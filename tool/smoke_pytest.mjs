// Runs pytest on the shipped python.wasm, through the same WASI shim the
// browser uses, and fails unless it reports one failed and one passed test.
// tool/bake_pytest.py runs it after baking; it also prints how long a run takes.
//
//   node tool/smoke_pytest.mjs [assets/python]

import { readFileSync } from 'node:fs';
import { basename, resolve } from 'node:path';
import { Wasi, WasiExit } from '../web/python/wasi.js';
import { STDLIB_DIRECTORIES, STDLIB_ZIP } from '../web/python/stdlib_layout.js';

const dir = resolve(process.argv[2] ?? 'assets/python');
const compiled = await WebAssembly.compile(readFileSync(`${dir}/python.wasm`));
const stdlib = new Uint8Array(readFileSync(`${dir}/${basename(STDLIB_ZIP)}`));
const encode = (text) => new TextEncoder().encode(text);

const TESTS = `
def kwadraat(x):
    return x * x

def test_goed():
    assert kwadraat(3) == 9

def test_fout():
    assert kwadraat(3) == 6
`;

// The flags lib/services/python/python_pytest_library.dart passes, minus its
// plugin. The logging plugin stays on: it is what needs /dev/null.
const PYTEST = `
import os, pytest
os.makedirs("/tmp/smoke")
with open("/tmp/smoke/test_smoke.py", "w") as f:
    f.write(${JSON.stringify(TESTS)})
pytest.main(["/tmp/smoke", "--rootdir", "/tmp/smoke", "-q", "--tb=short", "--color=no",
             "--capture=sys", "-p", "no:faulthandler", "-p", "no:cacheprovider"])
`;

function run(code) {
  let stdout = '';
  let stderr = '';
  const decoder = new TextDecoder();
  // The environment web/python/python_worker.js starts every run with.
  const wasi = new Wasi({
    args: ['python', '/main.py'],
    env: { PYTHONHOME: '/', PYTHONDONTWRITEBYTECODE: '1', PYTHONUNBUFFERED: '1' },
    files: new Map([[STDLIB_ZIP, stdlib], ['/main.py', encode(code)]]),
    readOnlyPaths: [STDLIB_ZIP],
    directories: STDLIB_DIRECTORIES,
    stdin: new Uint8Array(0),
    onOutput: (kind, bytes) => {
      if (kind === 'stdout') stdout += decoder.decode(bytes);
      else stderr += decoder.decode(bytes);
    },
  });
  const started = performance.now();
  return WebAssembly.instantiate(compiled, wasi.imports()).then((instance) => {
    wasi.memory = instance.exports.memory;
    try {
      instance.exports._start();
    } catch (error) {
      if (!(error instanceof WasiExit)) throw error;
    }
    return { stdout, stderr, ms: performance.now() - started };
  });
}

async function median(code, times = 5) {
  const all = [];
  for (let i = 0; i < times; i++) all.push((await run(code)).ms);
  return all.sort((a, b) => a - b)[times >> 1].toFixed(0);
}

const result = await run(PYTEST);
const problems = [];
if (!result.stdout.includes('1 failed, 1 passed')) problems.push('expected "1 failed, 1 passed"');
// pytest hides its own frames by their path; one showing means the bytecode
// was compiled under another name than the zip it is imported from.
if (result.stdout.includes('/_pytest/')) problems.push('pytest internals in the traceback');
if (problems.length > 0) {
  console.error(`smoke test failed: ${problems.join(', ')}\n--- stdout\n${result.stdout}\n--- stderr\n${result.stderr}`);
  process.exit(1);
}
console.log(`==> smoke test passed: print ${await median('print(1)')} ms, pytest ${await median(PYTEST)} ms (median of 5)`);
