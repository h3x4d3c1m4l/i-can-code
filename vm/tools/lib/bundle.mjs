// An image bundle (web/vm/image/<imageId>/) opened the way a page opens it: its own v86 build,
// web/vm/vm_host.js, and the agent line on top.

import { randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

import { createVmHost } from '../../../web/vm/vm_host.js';
import { AgentLine } from './agent_line.mjs';

/** Reads a bundle's manifest, v86 build and state. */
export async function loadBundle(dir) {
  const manifest = JSON.parse(readFileSync(path.join(dir, 'manifest.json'), 'utf8'));
  const { V86 } = await import(pathToFileURL(path.join(dir, manifest.v86.lib)).href);
  const wasm = readFileSync(path.join(dir, manifest.v86.wasm));
  const file = readFileSync(path.join(dir, manifest.state.file));
  const state = file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength);
  return { dir, manifest, V86, wasm, state };
}

/**
 * Builds the page's host for `bundle`. `loadMs` runs from the constructor to emulator-loaded.
 * @returns {Promise<{host: object, line: AgentLine, loadMs: number}>}
 */
export async function openHost(bundle, { onEvent } = {}) {
  const { manifest } = bundle;
  const started = performance.now();
  const host = await createVmHost({
    V86: bundle.V86,
    wasm: bundle.wasm,
    memoryMiB: manifest.memoryMiB,
    vgaMiB: manifest.vgaMiB,
    uart1: manifest.uart1,
    rootfsUrl: path.join(bundle.dir, manifest.rootfs.dir) + path.sep,
    onEvent,
  });
  return { host, line: new AgentLine(host.emulator), loadMs: performance.now() - started };
}

/**
 * Restores the bundle's state, resumes it and says HELLO, as a page does before every run.
 * `readyMs` runs from the start of the restore to READY.
 */
export async function restoreAndGreet(bundle, host, line, { tz = 'UTC' } = {}) {
  const started = performance.now();
  line.reset();
  const { ms: restoreMs, syncMs } = await host.restoreSnapshot(bundle.state);
  await host.resume();
  const ready = await line.request('HELLO', {
    now_ms: Date.now(),
    tz,
    entropy: randomBytes(64).toString('hex'),
  }, { answers: ['READY'], timeoutMs: 10_000 });
  return { ready: ready.body, restoreMs, syncMs, readyMs: performance.now() - started };
}
