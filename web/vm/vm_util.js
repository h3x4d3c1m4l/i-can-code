// Small helpers the VM's modules share.

export function isNode() {
  return typeof process !== 'undefined' && Boolean(process.versions?.node);
}

/** Whether `url` names a file on disk: under Node, a path rather than a URL. */
export function isLocalPath(url) {
  return isNode() && !/^[a-z][a-z0-9+.-]+:/i.test(url);
}

/** restore_state starts with `new Uint8Array(state)`, which wraps an
 *  ArrayBuffer but copies a typed array: tens of MiB on every park. */
export function toArrayBuffer(bytes) {
  if (bytes instanceof ArrayBuffer) return bytes;
  if (bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength) return bytes.buffer;
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
}

/** A promise that never settles, created per call so that whatever awaits it
 *  can be collected once nothing else refers to it. */
export function never() {
  return new Promise(() => {});
}

export function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

export function withTimeout(promise, ms, message) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${message} within ${ms} ms.`)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}
