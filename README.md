# qemu-arduino-uno-r4

QEMU with an **Arduino UNO R4** machine (Renesas RA4M1, Cortex-M4F).

It runs the very same firmware the Arduino / PlatformIO toolchain produces
for the board — the Arduino core, the Renesas FSP and your sketch — without
any change to the code. It was written for the book
*『つくりながら学ぶ！リアルタイムOS自作入門』*, which builds a preemptive RTOS on
the UNO R4 WiFi, so that readers can follow along without the board and so
that every chapter can be checked in CI.

This repository only holds a patch series against a pinned QEMU release,
the scripts that build it, and the release workflow. Prebuilt binaries are
on the [Releases](../../releases) page.

## What is modelled

| Block | Model | Notes |
| --- | --- | --- |
| CPU | Cortex-M4F, 32 NVIC IRQs, 4 priority bits | QEMU's armv7m, including MPU, divide-by-zero trap and precise bus faults |
| ICU | IELSRn event routing to the NVIC | IR latch cleared by software, as the FSP does in every ISR |
| SCI0/1/2/9 | Asynchronous mode (UART), no FIFO | TXI/TEI/RXI generated the way FSP `r_sci_uart` expects |
| AGT0/1 | Timer mode | Drives `millis()` in the Arduino core |
| PORT0..9, PFS | Output/direction/input, set/reset | Registers decoded by access width (see below) |
| Clock generator | Always "stable" | Enough for the FSP start-up code |
| Everything else | Unimplemented (reads as zero) | Logged with `-d unimp` |

Not modelled: USB, GPT, ADC, I²C, SPI, DMA, the ESP32 on the WiFi board.

Things worth knowing when reading the code:

- **16-bit register aliases do not follow little-endian byte lanes.** In the
  32-bit `PCNTR1`, `PDR` is bits 15:0 and `PODR` bits 31:16, yet the 16-bit
  alias at offset +0 is `PODR` and the one at +2 is `PDR`. `PmnPFS` has a
  16-bit alias at +2 and an 8-bit one at +3, both meaning its low bits. The
  port model therefore decodes accesses by width, not by byte offset.
- **The FSP polls several "done" bits.** `OSCSF` must report the oscillators
  as stable, and `FCACHEIV` must clear itself after being set to 1; a plain
  register there hangs the boot before `main()`.
- **The reset vector is at 0x4000.** Sketches are linked after the 16 KiB
  bootloader, so the board sets the reset VTOR there.

## Usage

Build your sketch with USB disabled (the machine has no USB, so `Serial`
must go to a UART), for example in `platformio.ini`:

```ini
[env:sim]
extends = env:uno_r4_wifi
build_flags = ${env:uno_r4_wifi.build_flags} -D NO_USB
```

Then run it:

```sh
qemu-system-arm -M arduino-uno-r4 -kernel .pio/build/sim/firmware.elf \
    -nographic -icount shift=4,sleep=on
```

- `serial0` is **SCI9**, where `Serial` goes when the core is built with
  `-DNO_USB`. `serial1` is SCI2 (`Serial1`, pins D0/D1).
- `-icount shift=4,sleep=on` makes the CPU run at roughly 48 MHz (16 ns per
  instruction), like the real board. Without it the guest runs at host speed,
  which is much faster than the hardware and changes the timing of anything
  that races (for example two tasks printing at once).
- Guest state can be inspected with QMP/HMP, e.g. `xp /1wx 0x40040020` reads
  `PORT1.PCNTR1`, whose bit 18 is the on-board LED (D13, P102).

## Building

### Native (Linux, macOS)

```sh
# Debian/Ubuntu
sudo apt install build-essential ninja-build pkg-config \
                 libglib2.0-dev python3-venv python3-tomli curl git
# macOS
brew install ninja pkgconf glib

./build.sh                     # -> dist/bin/qemu-system-arm
tests/smoke.sh                 # boots tests/hello and checks its output
```

`build.sh` downloads the QEMU release pinned in `QEMU_VERSION`, checks its
SHA-256, applies `patches/` and builds only `qemu-system-arm`, with none of
QEMU's optional host features (no display, audio, network back ends, …).
The only library it needs at run time is glib; libfdt comes from the copy
QEMU pins and is linked in statically.

On macOS, `scripts/bundle-macos.sh dist` copies glib and its dependencies
into `dist/lib` and points the binary there, so it runs without Homebrew.

### Native (Windows)

In an [MSYS2](https://www.msys2.org/) **UCRT64** shell (on ARM64, use
**CLANGARM64** and `mingw-w64-clang-aarch64-{clang,…}` instead):

```sh
pacman -S git curl patch tar xz diffutils \
          mingw-w64-ucrt-x86_64-{gcc,glib2,ninja,pkgconf,python}

./build.sh                     # -> dist/bin/qemu-system-arm.exe
scripts/bundle-windows.sh dist # copies the DLLs it needs next to it
tests/smoke.sh dist/bin/qemu-system-arm.exe
```

### WebAssembly

```sh
./build-wasm.sh                # -> dist/wasm/qemu-system-arm.{js,wasm}
node tests/run-wasm.mjs dist/wasm/qemu-system-arm.js tests/hello/hello.elf
```

This uses QEMU's own Emscripten cross-build container, so Docker is the only
host requirement. QEMU's WebAssembly host is wasm64 with the TCG interpreter
(there is no WebAssembly JIT upstream). We build with
`--wasm64-32bit-address-limit`, which lowers the module to wasm32, so it also
runs in browsers without Memory64 support.

Running in a browser needs `SharedArrayBuffer`, i.e. a cross-origin isolated
page (`Cross-Origin-Opener-Policy: same-origin` and
`Cross-Origin-Embedder-Policy: require-corp`) served from `https` or
`localhost`.

Performance is the limit: the interpreter executes far fewer instructions per
second than the real 48 MHz part. With `-icount shift=auto` timers and
blinking stay close to real time but computation is very slow; with
`shift=4` everything runs at about a tenth of real time.

## Tests

- `tests/hello/` is a tiny bare-metal program linked at 0x4000. It prints a
  line on SCI9 and drives D13 through `PCNTR3`, reading it back through
  `PCNTR1`. Rebuild it with `make -C tests/hello` (needs
  `arm-none-eabi-gcc`); the ELF is committed so the tests do not need a
  cross compiler.
- `tests/smoke.sh` and `tests/run-wasm.mjs` boot it on the native and the
  WebAssembly builds.

The book's repository runs all its chapters on this machine and checks the
serial output against the text.

## Releases

Pushing a tag `v<qemu-version>-unor4.<n>` (e.g. `v11.1.1-unor4.2`) builds
and publishes:

| Asset | Contents | Needs |
| --- | --- | --- |
| `…-linux-x86_64.tar.gz`, `…-linux-arm64.tar.gz` | `bin/qemu-system-arm` | glib (`libglib2.0-0`), present on almost every distribution; glibc 2.35 or newer (Ubuntu 22.04+) |
| `…-macos-arm64.tar.gz` | `bin/qemu-system-arm` and `lib/` | Apple silicon, macOS 14 or newer |
| `…-windows-x86_64.zip` | `bin/qemu-system-arm.exe` and its DLLs | Windows 10/11 on x64 |
| `…-windows-arm64.zip` | the same, built for ARM64 | Windows 11 on ARM (the x64 build does not work under emulation there) |
| `…-wasm.tar.gz` | `qemu-system-arm.{js,wasm}` | see [WebAssembly](#webassembly) |
| `…-source.tar.xz` | the complete patched QEMU tree the binaries were built from, with these scripts | |

`SHA256SUMS` lists the checksums of all of them.

The macOS binary is signed ad hoc, not notarized. A tarball downloaded with a
browser is quarantined, and macOS then refuses to run it; clear the flag once
after unpacking:

```sh
xattr -dr com.apple.quarantine qemu-arduino-uno-r4-*-macos-arm64
```

(`curl` does not set the flag, so this is not needed for scripted downloads.)

## Upstreaming

The patches follow QEMU's layout (one per device) so they can be sent to
qemu-devel eventually. Before that they still need migration state
(`VMStateDescription`), qtests, documentation under `docs/system/arm/`, a
`MAINTAINERS` entry and a `Signed-off-by:` from the author on each patch.

## License

GPL-2.0-or-later, like the QEMU code it modifies. See `LICENSE`.
