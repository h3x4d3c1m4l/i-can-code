// The codec for the control line between the host (vm_host.js) and the agent in
// the guest (vm/agent/). vm/protocol/README.md is the spec; the fixtures in
// vm/protocol/fixtures/ hold this file and the agent to the same bytes.
//
// No DOM and no dependencies: the page and the Node tools under vm/tools/ import
// the same file, so the build pipeline tests the codec the app ships.

export const VERSION = 1;

const HEADER_BYTES = 6;
const CRC_BYTES = 4;
export const FRAME_OVERHEAD = HEADER_BYTES + CRC_BYTES;

export const MAX_PAYLOAD_TO_AGENT = 4096;
export const MAX_PAYLOAD_TO_HOST = 16384;

/** Bytes the host may have in flight to the agent. The guest tty lost a 256 KiB
 *  burst and kept a 64 KiB one, so this stays well under the smaller. */
export const CREDIT_WINDOW = 16384;
export const CREDIT_STEP = 4096;

export const OUTPUT_CAP = 262144;
export const MAX_FILES = 64;
export const MAX_FILES_BYTES = 8 * 1024 * 1024;
export const MAX_WINDOWS = 32;

export const IN_DIR = '/icc/in';

/** No leading dot: names that start with one are reserved for the protocol. */
export const FILE_NAME = /^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}$/;

/** Where the host writes a run's file before RUN names it. The run id makes the
 *  name one the guest's cache=loose mount has never looked up. */
export function inFilePath(runId, name) {
  return `${IN_DIR}/r${runId}-${name}`;
}

/** The longest encoding of a frame with [maxPayload] bytes of payload, without
 *  its delimiter. A receiver stops buffering past this. */
export function maxEncodedLength(maxPayload) {
  const n = FRAME_OVERHEAD + maxPayload;
  return n + 1 + Math.floor(n / 254);
}

const TYPE_TABLE = [
  ['HELLO', 0x01, 'json'],
  ['RUN', 0x02, 'json'],
  ['STDIN', 0x03, 'data'],
  ['STOP', 0x04, 'json'],
  ['PING', 0x05, 'json'],
  ['CLOSE', 0x06, 'json'],
  ['PREPARE', 0x10, 'json'],
  ['READY', 0x81, 'json'],
  ['STARTED', 0x82, 'json'],
  ['STDOUT', 0x83, 'data'],
  ['STDERR', 0x84, 'data'],
  ['EXIT', 0x85, 'json'],
  ['WINDOW', 0x86, 'json'],
  ['ERROR', 0x87, 'json'],
  ['PONG', 0x88, 'json'],
  ['CREDIT', 0x89, 'json'],
  ['HINT', 0x8a, 'json'],
  ['LOG', 0x8f, 'json'],
  ['PARKED', 0x90, 'json'],
];

/** Message name to type code. */
export const TYPES = Object.freeze(Object.fromEntries(TYPE_TABLE.map(([name, code]) => [name, code])));

const TYPE_BY_CODE = new Map(TYPE_TABLE.map(([name, code, payload]) => [code, { name, code, payload }]));
const TYPE_BY_NAME = new Map(TYPE_TABLE.map(([name, code, payload]) => [name, { name, code, payload }]));

/** 'host' or 'agent': bit 7 of the type code is the direction. */
export function senderOf(code) {
  return code & 0x80 ? 'agent' : 'host';
}

// CRC-32/ISO-HDLC, the one crc32fast and zlib compute.

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

export function crc32(bytes) {
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

// COBS.

/** Encodes without the delimiter. The final block is written even when empty,
 *  so 254 non-zero bytes end in `01`: that is what makes the encoding unique,
 *  and the fixtures pin it. */
export function cobsEncode(data) {
  const out = new Uint8Array(data.length + 1 + Math.floor(data.length / 254));
  let codeAt = 0;
  let o = 1;
  let code = 1;
  for (let i = 0; i < data.length; i++) {
    const b = data[i];
    if (b === 0) {
      out[codeAt] = code;
      codeAt = o++;
      code = 1;
    } else {
      out[o++] = b;
      code++;
      if (code === 0xff) {
        out[codeAt] = code;
        codeAt = o++;
        code = 1;
      }
    }
  }
  out[codeAt] = code;
  return out.subarray(0, o);
}

/** Decodes one chunk (no delimiter), or returns null when it is not COBS. Also
 *  accepts the form that leaves out an empty final block. */
export function cobsDecode(encoded) {
  const n = encoded.length;
  if (n === 0) return null;
  const out = new Uint8Array(n);
  let i = 0;
  let o = 0;
  while (i < n) {
    const code = encoded[i++];
    const end = i + code - 1;
    if (code === 0 || end > n) return null;
    for (; i < end; i++) {
      const b = encoded[i];
      if (b === 0) return null;
      out[o++] = b;
    }
    if (code !== 0xff && i < n) out[o++] = 0;
  }
  return out.slice(0, o);
}

// Frames.

const EMPTY = new Uint8Array(0);

/** Returns the wire bytes of one frame, delimiter included. Checks no size
 *  limit; encodeMessage does. */
export function encodeFrame({ type, id, payload = EMPTY, version = VERSION }) {
  if (!isInt(type, 0, 0xff)) throw new RangeError(`frame type ${type} is not a byte`);
  if (!isInt(id, 0, 0xffffffff)) throw new RangeError(`frame id ${id} is not a u32`);
  if (!isInt(version, 0, 0xff)) throw new RangeError(`frame version ${version} is not a byte`);

  const raw = new Uint8Array(FRAME_OVERHEAD + payload.length);
  const view = new DataView(raw.buffer);
  raw[0] = version;
  raw[1] = type;
  view.setUint32(2, id, true);
  raw.set(payload, HEADER_BYTES);
  const crcAt = raw.length - CRC_BYTES;
  view.setUint32(crcAt, crc32(raw.subarray(0, crcAt)), true);

  const encoded = cobsEncode(raw);
  const wire = new Uint8Array(encoded.length + 1);
  wire.set(encoded);
  return wire;
}

/** Decodes one chunk, the bytes between two delimiters. Returns `{frame}` or
 *  `{error}`, the error naming the first check that failed, in the spec's order. */
export function decodeFrame(chunk, maxPayload) {
  if (chunk.length > maxEncodedLength(maxPayload)) return { error: 'oversize' };
  const raw = cobsDecode(chunk);
  if (raw === null) return { error: 'cobs' };
  if (raw.length < FRAME_OVERHEAD) return { error: 'short' };

  const view = new DataView(raw.buffer, raw.byteOffset, raw.byteLength);
  const crcAt = raw.length - CRC_BYTES;
  if (crc32(raw.subarray(0, crcAt)) !== view.getUint32(crcAt, true)) return { error: 'crc' };
  if (raw[0] !== VERSION) return { error: 'version' };

  const payload = raw.subarray(HEADER_BYTES, crcAt);
  if (payload.length > maxPayload) return { error: 'oversize' };
  return { frame: { version: raw[0], type: raw[1], id: view.getUint32(2, true), payload } };
}

/** Turns a byte stream split anywhere into frames, and resyncs at the next zero
 *  after anything it cannot decode. Memory stays within one maximum frame
 *  whatever the peer sends. */
export class FrameDecoder {

  #maxPayload;
  #buffer;
  #length = 0;
  #overflowed = false;

  /** Drops by reason, for diagnostics. */
  stats = { frames: 0, errors: { oversize: 0, cobs: 0, short: 0, crc: 0, version: 0 } };

  constructor({ maxPayload }) {
    this.#maxPayload = maxPayload;
    this.#buffer = new Uint8Array(maxEncodedLength(maxPayload));
  }

  /** Returns the `{frame}` and `{error}` events the bytes completed, in order. */
  push(bytes) {
    const events = [];
    let start = 0;
    while (start < bytes.length) {
      const zero = bytes.indexOf(0, start);
      const end = zero === -1 ? bytes.length : zero;
      this.#append(bytes.subarray(start, end));
      if (zero === -1) break;
      this.#finish(events);
      start = zero + 1;
    }
    return events;
  }

  /** Forgets a partial frame, as the host MUST after every restore. */
  reset() {
    this.#length = 0;
    this.#overflowed = false;
  }

  #append(part) {
    if (this.#overflowed || part.length === 0) return;
    if (this.#length + part.length > this.#buffer.length) {
      this.#overflowed = true;
      return;
    }
    this.#buffer.set(part, this.#length);
    this.#length += part.length;
  }

  #finish(events) {
    let event;
    if (this.#overflowed) {
      event = { error: 'oversize' };
    } else if (this.#length > 0) {
      event = decodeFrame(this.#buffer.subarray(0, this.#length), this.#maxPayload);
    }
    this.reset();
    if (!event) return;
    if (event.frame) this.stats.frames++;
    else this.stats.errors[event.error]++;
    events.push(event);
  }

}

// Message bodies. Each spec returns the value in canonical form (known fields
// only, in table order) or INVALID, so encoding what was decoded is canonical.

const INVALID = Symbol('invalid');
const MAX_SAFE = Number.MAX_SAFE_INTEGER;

function isInt(value, min, max) {
  return Number.isInteger(value) && value >= min && value <= max;
}

function isRecord(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

const accept = (test) => (value) => (test(value) ? value : INVALID);
const int = (min, max) => accept((v) => isInt(v, min, max));
const bool = accept((v) => typeof v === 'boolean');
const string = accept((v) => typeof v === 'string');
const pattern = (re) => accept((v) => typeof v === 'string' && re.test(v));
const oneOf = (...values) => accept((v) => values.includes(v));
/** A nullable field may also be left out, and reads as null then. serde's
 *  derive does the same for an `Option`, so both sides agree without either
 *  needing a special case. */
const nullable = (spec) => Object.assign((v) => (v === null ? null : spec(v)), { nullable: true });

function fieldOf(value, name, spec) {
  if (Object.hasOwn(value, name)) return spec(value[name]);
  return spec.nullable ? null : INVALID;
}

const u32 = int(0, 0xffffffff);
const i32 = int(-0x80000000, 0x7fffffff);
const token = pattern(/^[a-z][a-z0-9_]{0,63}$/);
const zone = pattern(/^(?=.{1,64}$)[A-Za-z0-9_+-]+(?:\/[A-Za-z0-9_+-]+)*$/);
const fileName = pattern(FILE_NAME);
const argument = accept((v) => typeof v === 'string' && !v.includes('\0'));
const absolutePath = accept((v) => typeof v === 'string' && v.startsWith('/') && !v.includes('\0'));

function listOf(item, min, max) {
  return (value) => {
    if (!Array.isArray(value) || value.length < min || value.length > max) return INVALID;
    const out = [];
    for (const element of value) {
      const checked = item(element);
      if (checked === INVALID) return INVALID;
      out.push(checked);
    }
    return out;
  };
}

function record(fields) {
  return (value) => {
    if (!isRecord(value)) return INVALID;
    const out = {};
    for (const [name, spec] of fields) {
      const checked = fieldOf(value, name, spec);
      if (checked === INVALID) return INVALID;
      out[name] = checked;
    }
    return out;
  };
}

/** A top-level body: reports the first field at fault, then the cross-field
 *  rules, each of which also names a field. */
function body(fields, rules = []) {
  return (value) => {
    const out = {};
    for (const [name, spec] of fields) {
      const checked = fieldOf(value, name, spec);
      if (checked === INVALID) return { field: name };
      out[name] = checked;
    }
    for (const [name, rule] of rules) {
      if (!rule(out)) return { field: name };
    }
    return { body: out };
  };
}

const windowEntry = record([
  ['xid', u32],
  ['title', string],
  ['x', i32],
  ['y', i32],
  ['w', int(0, 0xffff)],
  ['h', int(0, 0xffff)],
  ['mapped', bool],
  ['root', bool],
  ['transient_for', nullable(u32)],
]);

const BODIES = {
  HELLO: body([
    ['now_ms', int(0, MAX_SAFE)],
    ['tz', zone],
    ['entropy', pattern(/^[0-9a-f]{128}$/)],
  ]),
  RUN: body(
    [
      ['entry', fileName],
      ['files', listOf(fileName, 1, MAX_FILES)],
      ['argv', listOf(argument, 0, 64)],
      ['stdin', bool],
      ['output_cap', int(0, 16 * 1024 * 1024)],
    ],
    [
      ['files', (b) => new Set(b.files).size === b.files.length],
      ['entry', (b) => b.files.includes(b.entry)],
    ],
  ),
  STOP: body([]),
  PING: body([]),
  CLOSE: body([['xid', u32]]),
  PREPARE: body([
    ['resident', listOf(absolutePath, 0, 1024)],
    ['reserve_mib', int(0, 1024)],
  ]),
  READY: body([
    ['agent', string],
    ['python', nullable(string)],
    ['tk', nullable(string)],
    ['tz', zone],
    ['warm', bool],
  ]),
  STARTED: body([
    ['pid', int(1, 0x7fffffff)],
    ['warm', bool],
  ]),
  EXIT: body(
    [
      ['code', nullable(int(0, 255))],
      ['signal', nullable(int(1, 64))],
      ['reason', oneOf('exit', 'stopped', 'closed', 'oom')],
      ['truncated', bool],
      ['ms', int(0, MAX_SAFE)],
    ],
    [['code', (b) => (b.code === null) !== (b.signal === null)]],
  ),
  WINDOW: body(
    [['windows', listOf(windowEntry, 0, MAX_WINDOWS)]],
    [['windows', (b) => b.windows.filter((w) => w.root).length <= 1]],
  ),
  ERROR: body([
    ['code', token],
    ['message', string],
  ]),
  PONG: body([]),
  CREDIT: body([['bytes', int(1, CREDIT_WINDOW)]]),
  HINT: body([['kind', token]]),
  LOG: body([
    ['level', oneOf('debug', 'info', 'warn', 'error')],
    ['message', string],
  ]),
  PARKED: body([
    ['warm', bool],
    ['mem_total_kb', u32],
    ['mem_available_kb', u32],
    ['zeroed_kb', u32],
    ['resident_kb', u32],
  ]),
};

// fatal: invalid UTF-8 is bad_json, as it is for serde_json. ignoreBOM keeps a
// BOM in the text, where JSON.parse rejects it, again as serde_json does.
const UTF8_DECODER = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });
const UTF8_ENCODER = new TextEncoder();

/** Turns a frame into a message, checking it came from [from] ('host' or
 *  'agent'). Returns `{message}` or `{error, field?}`: see README section 5.3. */
export function decodeMessage(frame, { from }) {
  if (senderOf(frame.type) !== from) return { error: 'direction' };
  const type = TYPE_BY_CODE.get(frame.type);
  if (!type) return { error: 'unknown_type' };

  if (type.payload === 'data') {
    return { message: { type: type.name, id: frame.id, data: frame.payload } };
  }

  let value;
  try {
    value = JSON.parse(UTF8_DECODER.decode(frame.payload));
  } catch {
    return { error: 'bad_json' };
  }
  if (!isRecord(value)) return { error: 'not_object' };

  const checked = BODIES[type.name](value);
  if (checked.field) return { error: 'field', field: checked.field };
  return { message: { type: type.name, id: frame.id, body: checked.body } };
}

/** Returns the wire bytes of `{type, id, body}` or, for STDOUT, STDERR and
 *  STDIN, `{type, id, data}`. Throws on a message the receiver would refuse. */
export function encodeMessage({ type, id, body: value, data }) {
  const spec = TYPE_BY_NAME.get(type);
  if (!spec) throw new TypeError(`unknown message type ${type}`);

  let payload;
  if (spec.payload === 'data') {
    if (!(data instanceof Uint8Array)) throw new TypeError(`${type} needs data as a Uint8Array`);
    payload = data;
  } else {
    if (!isRecord(value)) throw new TypeError(`${type} needs a body object`);
    const checked = BODIES[type](value);
    if (checked.field) throw new TypeError(`${type}.${checked.field} is missing or invalid`);
    payload = UTF8_ENCODER.encode(JSON.stringify(checked.body));
  }

  const max = senderOf(spec.code) === 'host' ? MAX_PAYLOAD_TO_AGENT : MAX_PAYLOAD_TO_HOST;
  if (payload.length > max) throw new RangeError(`${type} payload is ${payload.length} bytes, over ${max}`);
  return encodeFrame({ type: spec.code, id, payload });
}

/** Holds frames to the agent until it has room for them (README section 7).
 *  [write] takes wire bytes, in practice `bytes => emulator.serial_send_bytes(1, bytes)`. */
export class CreditedSender {

  #write;
  #available = CREDIT_WINDOW;
  #queue = [];

  constructor(write) {
    this.#write = write;
  }

  get available() {
    return this.#available;
  }

  get queued() {
    return this.#queue.length;
  }

  /** Writes [frame] now if the credit covers it, else after the frames ahead of
   *  it. Nothing overtakes. */
  send(frame) {
    this.#queue.push(frame);
    this.#drain();
  }

  /** Applies a CREDIT. Capped at the window, so an agent that over-reports
   *  cannot open it wider than the guest tty can hold. */
  grant(bytes) {
    this.#available = Math.min(CREDIT_WINDOW, this.#available + bytes);
    this.#drain();
  }

  /** After a restore: the restored agent owes nothing, and whatever was queued
   *  was addressed to a machine that no longer exists. */
  reset() {
    this.#available = CREDIT_WINDOW;
    this.#queue.length = 0;
  }

  #drain() {
    while (this.#queue.length > 0 && this.#queue[0].length <= this.#available) {
      const frame = this.#queue.shift();
      this.#available -= frame.length;
      this.#write(frame);
    }
  }

}
