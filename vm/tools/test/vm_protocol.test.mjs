// Holds web/vm/vm_protocol.js to the golden fixtures in vm/protocol/fixtures/,
// which the Rust agent is held to as well.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, test } from 'node:test';

import * as protocol from '../../../web/vm/vm_protocol.js';

const {
  CreditedSender,
  FrameDecoder,
  cobsDecode,
  cobsEncode,
  crc32,
  decodeFrame,
  decodeMessage,
  encodeFrame,
  encodeMessage,
  maxEncodedLength,
} = protocol;

function fixture(name) {
  const url = new URL(`../../protocol/fixtures/${name}`, import.meta.url);
  return JSON.parse(readFileSync(url, 'utf8'));
}

function fromHex(text) {
  return new Uint8Array(Buffer.from(text, 'hex'));
}

function toHex(bytes) {
  return Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength).toString('hex');
}

function concat(parts) {
  return new Uint8Array(Buffer.concat(parts.map((p) => Buffer.from(p))));
}

/** Decodes one wire frame, delimiter included, as a receiver would. */
function frameOf(wireHex, maxPayload = protocol.MAX_PAYLOAD_TO_HOST) {
  const wire = fromHex(wireHex);
  assert.equal(wire.at(-1), 0, 'a wire frame ends in its delimiter');
  const result = decodeFrame(wire.subarray(0, -1), maxPayload);
  assert.ok(result.frame, `frame did not decode: ${result.error}`);
  return result.frame;
}

/** A message in the fixtures' shape, so it can be compared with deepEqual. */
function asFixtureMessage(message) {
  if (message.data) return { type: message.type, id: message.id, data_hex: toHex(message.data) };
  return message;
}

function fromFixtureMessage(message) {
  if (message.data_hex !== undefined) {
    return { type: message.type, id: message.id, data: fromHex(message.data_hex) };
  }
  return message;
}

function asFixtureEvent(event) {
  if (event.error) return { error: event.error };
  const { version, type, id, payload } = event.frame;
  return { frame: { version, type, id, payload_hex: toHex(payload) } };
}

describe('protocol.json', () => {
  const doc = fixture('protocol.json');

  test('constants match', () => {
    assert.equal(protocol.VERSION, doc.version);
    assert.equal(protocol.FRAME_OVERHEAD, doc.header_bytes + doc.crc_bytes);
    assert.equal(protocol.MAX_PAYLOAD_TO_AGENT, doc.max_payload_to_agent);
    assert.equal(protocol.MAX_PAYLOAD_TO_HOST, doc.max_payload_to_host);
    assert.equal(maxEncodedLength(doc.max_payload_to_agent), doc.max_encoded_to_agent);
    assert.equal(maxEncodedLength(doc.max_payload_to_host), doc.max_encoded_to_host);
    assert.equal(protocol.CREDIT_WINDOW, doc.credit_window);
    assert.equal(protocol.CREDIT_STEP, doc.credit_step);
    assert.equal(protocol.OUTPUT_CAP, doc.output_cap);
    assert.equal(protocol.MAX_FILES, doc.max_files);
    assert.equal(protocol.MAX_FILES_BYTES, doc.max_files_bytes);
    assert.equal(protocol.MAX_WINDOWS, doc.max_windows);
    assert.equal(protocol.FILE_NAME.source, doc.file_name_pattern);
    assert.equal(protocol.IN_DIR, doc.in_dir);
    assert.equal(protocol.inFilePath(7, 'main.py'), doc.in_file.replace('{id}', '7').replace('{name}', 'main.py'));
  });

  test('type table matches', () => {
    assert.deepEqual(
      Object.entries(protocol.TYPES),
      doc.types.map((t) => [t.name, t.code]),
    );
    for (const t of doc.types) assert.equal(protocol.senderOf(t.code), t.from, t.name);
  });
});

describe('crc32.json', () => {
  for (const v of fixture('crc32.json').vectors) {
    test(v.name, () => {
      assert.equal(crc32(fromHex(v.input_hex)).toString(16).padStart(8, '0'), v.crc);
    });
  }
});

describe('cobs.json', () => {
  const doc = fixture('cobs.json');

  for (const v of doc.vectors) {
    test(`round trip: ${v.name}`, () => {
      assert.equal(toHex(cobsEncode(fromHex(v.decoded_hex))), v.encoded_hex);
      assert.equal(toHex(cobsDecode(fromHex(v.encoded_hex))), v.decoded_hex);
    });
  }

  for (const v of doc.decode_only) {
    test(`decode only: ${v.name}`, () => {
      assert.equal(toHex(cobsDecode(fromHex(v.encoded_hex))), v.decoded_hex);
      assert.notEqual(toHex(cobsEncode(fromHex(v.decoded_hex))), v.encoded_hex);
    });
  }

  for (const v of doc.invalid) {
    test(`invalid: ${v.name}`, () => {
      assert.equal(cobsDecode(fromHex(v.encoded_hex)), null);
    });
  }

  test('random data round-trips within the length bound and never encodes a zero', () => {
    const random = seeded(1);
    for (let round = 0; round < 500; round++) {
      const length = Math.floor(random() * 1200);
      const zeroRate = [0, 0.01, 0.2, 0.9][round % 4];
      const data = new Uint8Array(length);
      for (let i = 0; i < length; i++) data[i] = random() < zeroRate ? 0 : 1 + Math.floor(random() * 255);
      const encoded = cobsEncode(data);
      assert.ok(encoded.length <= length + 1 + Math.floor(length / 254));
      assert.equal(encoded.indexOf(0), -1);
      assert.deepEqual(cobsDecode(encoded), data);
    }
  });
});

describe('messages.json', () => {
  const doc = fixture('messages.json');

  for (const f of doc.frames) {
    test(f.name, () => {
      assert.equal(toHex(cobsDecode(fromHex(f.frame_hex).subarray(0, -1))), f.raw_hex);

      const frame = frameOf(f.frame_hex);
      assert.equal(frame.version, protocol.VERSION);
      assert.equal(frame.type, protocol.TYPES[f.message.type]);
      assert.equal(frame.id, f.message.id);

      const decoded = decodeMessage(frame, { from: f.from });
      assert.ok(decoded.message, `rejected: ${decoded.error} ${decoded.field ?? ''}`);
      assert.deepEqual(asFixtureMessage(decoded.message), f.message);

      assert.equal(toHex(encodeMessage(fromFixtureMessage(f.message))), f.frame_hex);
      assert.equal(toHex(encodeMessage(decoded.message)), f.frame_hex);
    });
  }

  test('every type has a fixture', () => {
    const covered = new Set(doc.frames.map((f) => f.message.type));
    for (const name of Object.keys(protocol.TYPES)) assert.ok(covered.has(name), name);
  });
});

describe('messages-invalid.json', () => {
  for (const f of fixture('messages-invalid.json').frames) {
    test(f.name, () => {
      const frame = frameOf(f.frame_hex);
      const decoded = decodeMessage(frame, { from: f.from });
      assert.equal(decoded.message, undefined);
      assert.equal(decoded.error, f.error);
      assert.equal(decoded.field, f.field);

      if (f.error === 'field') {
        const name = Object.entries(protocol.TYPES).find(([, code]) => code === frame.type)[0];
        const body = JSON.parse(Buffer.from(frame.payload).toString('utf8'));
        assert.throws(() => encodeMessage({ type: name, id: frame.id, body }), TypeError);
      }
    });
  }
});

describe('messages-tolerated.json', () => {
  for (const f of fixture('messages-tolerated.json').frames) {
    test(f.name, () => {
      const decoded = decodeMessage(frameOf(f.frame_hex), { from: f.from });
      assert.ok(decoded.message, `rejected: ${decoded.error} ${decoded.field ?? ''}`);
      assert.deepEqual(decoded.message, f.message);
      assert.equal(toHex(encodeMessage(decoded.message)), f.canonical_frame_hex);
    });
  }
});

describe('stream.json', () => {
  const doc = fixture('stream.json');

  function run(maxPayload, chunks) {
    const decoder = new FrameDecoder({ maxPayload });
    return chunks.flatMap((chunk) => decoder.push(chunk)).map(asFixtureEvent);
  }

  /** The same bytes without FrameDecoder, so decodeFrame's own checks are held
   *  to the fixtures too. */
  function decodeChunks(maxPayload, bytes) {
    const events = [];
    let at = 0;
    for (let i = 0; i < bytes.length; i++) {
      if (bytes[i] !== 0) continue;
      if (i > at) events.push(asFixtureEvent(decodeFrame(bytes.subarray(at, i), maxPayload)));
      at = i + 1;
    }
    return events;
  }

  for (const c of doc.cases) {
    test(c.name, () => {
      const chunks = c.chunks_hex.map(fromHex);
      const all = concat(chunks);

      assert.deepEqual(run(c.max_payload, chunks), c.events, 'as given');
      assert.deepEqual(decodeChunks(c.max_payload, all), c.events, 'chunk by chunk through decodeFrame');
      assert.deepEqual(run(c.max_payload, [all]), c.events, 'in one read');

      if (all.length <= 2048) {
        const bytes = Array.from(all, (b) => Uint8Array.of(b));
        assert.deepEqual(run(c.max_payload, bytes), c.events, 'byte by byte');
        for (let at = 1; at < all.length; at++) {
          const split = [all.subarray(0, at), all.subarray(at)];
          assert.deepEqual(run(c.max_payload, split), c.events, `split at ${at}`);
        }
      } else {
        const random = seeded(all.length);
        for (let round = 0; round < 40; round++) {
          assert.deepEqual(run(c.max_payload, splitRandomly(all, random)), c.events, `random split ${round}`);
        }
      }

      // Re-encoding a decoded frame gives the bytes it came from, except for
      // the one case that exists to show a non-canonical encoding is accepted.
      const canonical = !c.name.includes('without its final empty block');
      for (const event of run(c.max_payload, [all])) {
        if (!event.frame) continue;
        const { type, id, payload_hex: payload } = event.frame;
        const wire = Buffer.from(encodeFrame({ type, id, payload: fromHex(payload) }));
        const found = Buffer.from(all).includes(wire);
        if (canonical) assert.ok(found, `frame ${type}/${id} re-encodes to other bytes`);
      }
    });
  }

  test('reset drops a partial frame', () => {
    const wire = encodeMessage({ type: 'PING', id: 1, body: {} });
    const decoder = new FrameDecoder({ maxPayload: protocol.MAX_PAYLOAD_TO_AGENT });
    assert.deepEqual(decoder.push(wire.subarray(0, 4)), []);
    decoder.reset();
    const events = decoder.push(wire);
    assert.equal(events.length, 1);
    assert.equal(events[0].frame.id, 1);
  });

  test('stats count frames and drops by reason', () => {
    const decoder = new FrameDecoder({ maxPayload: protocol.MAX_PAYLOAD_TO_AGENT });
    for (const c of doc.cases.filter((x) => x.max_payload === protocol.MAX_PAYLOAD_TO_AGENT)) {
      for (const chunk of c.chunks_hex) decoder.push(fromHex(chunk));
      decoder.reset();
    }
    const expected = { frames: 0, errors: { oversize: 0, cobs: 0, short: 0, crc: 0, version: 0 } };
    for (const c of doc.cases.filter((x) => x.max_payload === protocol.MAX_PAYLOAD_TO_AGENT)) {
      for (const e of c.events) {
        if (e.frame) expected.frames++;
        else expected.errors[e.error]++;
      }
    }
    assert.deepEqual(decoder.stats, expected);
  });
});

describe('encodeMessage', () => {
  test('refuses a host payload over 4096 bytes', () => {
    const files = Array.from({ length: 64 }, (_, i) => `${'f'.repeat(58)}${String(i).padStart(2, '0')}.py`);
    const body = { entry: files[0], files, argv: ['x'.repeat(200)], stdin: false, output_cap: 262144 };
    assert.throws(() => encodeMessage({ type: 'RUN', id: 1, body }), RangeError);
  });

  test('refuses a second root window', () => {
    const w = { xid: 1, title: '', x: 0, y: 0, w: 1, h: 1, mapped: true, root: true, transient_for: null };
    assert.throws(
      () => encodeMessage({ type: 'WINDOW', id: 1, body: { windows: [w, { ...w, xid: 2 }] } }),
      /WINDOW\.windows/,
    );
  });

  test('refuses an unknown type', () => {
    assert.throws(() => encodeMessage({ type: 'NOPE', id: 1, body: {} }), TypeError);
  });
});

describe('CreditedSender', () => {
  const frameOfSize = (n) => new Uint8Array(n);

  test('holds what the window cannot take, in order, until credit arrives', () => {
    const written = [];
    const sender = new CreditedSender((bytes) => written.push(bytes.length));
    sender.send(frameOfSize(10000));
    sender.send(frameOfSize(4000));
    sender.send(frameOfSize(4000));
    sender.send(frameOfSize(100));
    assert.deepEqual(written, [10000, 4000]);
    assert.equal(sender.queued, 2);

    sender.grant(1000);
    assert.deepEqual(written, [10000, 4000], 'the 100-byte frame does not overtake');
    sender.grant(1000);
    assert.deepEqual(written, [10000, 4000, 4000, 100]);
    assert.equal(sender.available, protocol.CREDIT_WINDOW - 18100 + 2000);
  });

  test('never opens wider than the window', () => {
    const sender = new CreditedSender(() => {});
    sender.grant(50000);
    assert.equal(sender.available, protocol.CREDIT_WINDOW);
  });

  test('reset refills the window and forgets the queue', () => {
    const written = [];
    const sender = new CreditedSender((bytes) => written.push(bytes.length));
    sender.send(frameOfSize(16000));
    sender.send(frameOfSize(1000));
    sender.reset();
    assert.equal(sender.available, protocol.CREDIT_WINDOW);
    assert.equal(sender.queued, 0);
    sender.grant(16000);
    assert.deepEqual(written, [16000]);
  });
});

/** Mulberry32, so a failing split can be reproduced. */
function seeded(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function splitRandomly(bytes, random) {
  const parts = [];
  let at = 0;
  while (at < bytes.length) {
    const size = 1 + Math.floor(random() * 700);
    parts.push(bytes.subarray(at, at + size));
    at += size;
  }
  return parts;
}
