// Check the WebAssembly host interface (patch 0006) under Node.
//
//   node tests/run-wasm-host.mjs dist/wasm/qemu-system-arm.js tests/hello/hello.elf
//
// Runs tests/hello with -serial none, so SCI9 is connected to the rings in
// the wasm heap, and talks to it the way a browser page would: reads its
// output from the output ring, types a line into the input ring (hello
// echoes it back), and reads D13 from the port output latches.
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const [qemuJs, elfPath, timeoutSec = '120'] = process.argv.slice(2);
if (!qemuJs || !elfPath) {
  console.error('usage: node run-wasm-host.mjs <qemu-system-arm.js> <hello.elf> [timeout-s]');
  process.exit(2);
}

const LINE = 'typed into the input ring\r\n';
const D13_PORT = 1;
const D13_BIT = 1 << 2;
const POLL_MS = 10;
const OUT_HEAD = 0, OUT_TAIL = 1, IN_HEAD = 2, IN_TAIL = 3, OUT_DROPPED = 4;

const createModule = (await import(pathToFileURL(path.resolve(qemuJs)).href)).default;
const elf = fs.readFileSync(elfPath);

function fail(why) {
  console.error(`host interface test FAILED: ${why}`);
  process.exit(1);
}

setTimeout(() => fail(`not done within ${timeoutSec}s`), Number(timeoutSec) * 1000);

function attach(info) {
  for (const key of ['sram', 'podr', 'rings', 'outOffset', 'outSize', 'inOffset', 'inSize']) {
    if (typeof info[key] !== 'number') fail(`info.${key} is ${typeof info[key]}, not a number`);
  }
  if (info.sramBase !== 0x20000000 || info.sramSize !== 32 * 1024) {
    fail(`unexpected SRAM ${info.sramBase.toString(16)}+${info.sramSize}`);
  }
  const words = () => new Int32Array(info.heap().buffer);
  const r = info.rings >>> 2;
  let out = '';
  let typed = false;

  setInterval(() => {
    const w = words();
    const h = info.heap();
    const head = Atomics.load(w, r + OUT_HEAD) >>> 0;
    let tail = Atomics.load(w, r + OUT_TAIL) >>> 0;
    for (; tail !== head; tail = (tail + 1) >>> 0) {
      out += String.fromCharCode(h[info.rings + info.outOffset + (tail % info.outSize)]);
    }
    Atomics.store(w, r + OUT_TAIL, tail | 0);

    if (!typed && out.includes('D13: high')) {
      const podr = h[info.podr + 2 * D13_PORT] | (h[info.podr + 2 * D13_PORT + 1] << 8);
      if (!(podr & D13_BIT)) fail(`D13 reads low in PODR (0x${podr.toString(16)})`);
      let inHead = Atomics.load(w, r + IN_HEAD) >>> 0;
      for (const c of Buffer.from(LINE)) {
        h[info.rings + info.inOffset + (inHead % info.inSize)] = c;
        inHead = (inHead + 1) >>> 0;
      }
      Atomics.store(w, r + IN_HEAD, inHead | 0);
      typed = true;
    }
    if (typed && out.includes(LINE)) {
      const dropped = Atomics.load(w, r + OUT_DROPPED);
      if (dropped !== 0) fail(`${dropped} output bytes dropped`);
      process.stdout.write(out);
      console.log('host interface test passed');
      process.exit(0);
    }
  }, POLL_MS);
}

await createModule({
  arguments: ['-M', 'arduino-uno-r4', '-kernel', '/fw.elf',
              '-display', 'none', '-serial', 'none', '-monitor', 'none'],
  preRun: [(m) => { m.FS.writeFile('/fw.elf', elf); }],
  print: (line) => console.log(line),
  printErr: (line) => {
    if (!line.includes('unsupported syscall')) console.error(line);
  },
  unor4Attach: attach,
});
