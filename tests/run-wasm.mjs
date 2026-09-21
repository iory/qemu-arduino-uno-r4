// Boot tests/hello on the WebAssembly build under Node and check its output.
//
//   node tests/run-wasm.mjs dist/wasm/qemu-system-arm.js tests/hello/hello.elf
//
// The build is ES6 (EXPORT_ES6) and exposes FS, so the firmware is written
// into the in-memory filesystem before QEMU starts.
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const [qemuJs, elfPath, timeoutSec = '120'] = process.argv.slice(2);
if (!qemuJs || !elfPath) {
  console.error('usage: node run-wasm.mjs <qemu-system-arm.js> <firmware.elf> [timeout-s]');
  process.exit(2);
}

const createModule = (await import(pathToFileURL(path.resolve(qemuJs)).href)).default;
const elf = fs.readFileSync(elfPath);
const seen = [];

setTimeout(() => {
  console.error(`smoke test FAILED: no expected output within ${timeoutSec}s`);
  process.exit(1);
}, Number(timeoutSec) * 1000);

await createModule({
  arguments: ['-M', 'arduino-uno-r4', '-kernel', '/fw.elf',
              '-nographic', '-monitor', 'none'],
  preRun: [(m) => { m.FS.writeFile('/fw.elf', elf); }],
  print: (line) => {
    console.log(line);
    seen.push(line);
    if (seen.some((l) => l.includes('hello from 0x4000')) &&
        seen.some((l) => l.includes('D13: high'))) {
      console.log('smoke test passed');
      process.exit(0);
    }
  },
  printErr: (line) => {
    if (!line.includes('unsupported syscall')) console.error(line);
  },
});
