#!/usr/bin/env python3
"""Writes the golden fixtures in vm/protocol/fixtures/ from the spec in README.md.

It shares no code with either codec: the CRC is zlib's (the same CRC-32/ISO-HDLC
that crc32fast computes) and COBS is written out again below. Run it after
changing the spec, then hold web/vm/vm_protocol.js and the agent to the result.

    python3 vm/protocol/gen_fixtures.py
"""

import json
import pathlib
import zlib

OUT = pathlib.Path(__file__).resolve().parent / "fixtures"

VERSION = 1
HEADER = 6
TRAILER = 4
MAX_PAYLOAD_TO_AGENT = 4096
MAX_PAYLOAD_TO_HOST = 16384

# name, code, sender, payload kind, status
TYPES = [
    ("HELLO", 0x01, "host", "json", "v1"),
    ("RUN", 0x02, "host", "json", "v1"),
    ("STDIN", 0x03, "host", "data", "later"),
    ("STOP", 0x04, "host", "json", "v1"),
    ("PING", 0x05, "host", "json", "v1"),
    ("CLOSE", 0x06, "host", "json", "v1"),
    ("PREPARE", 0x10, "host", "json", "build"),
    ("READY", 0x81, "agent", "json", "v1"),
    ("STARTED", 0x82, "agent", "json", "v1"),
    ("STDOUT", 0x83, "agent", "data", "v1"),
    ("STDERR", 0x84, "agent", "data", "v1"),
    ("EXIT", 0x85, "agent", "json", "v1"),
    ("WINDOW", 0x86, "agent", "json", "v1"),
    ("ERROR", 0x87, "agent", "json", "v1"),
    ("PONG", 0x88, "agent", "json", "v1"),
    ("CREDIT", 0x89, "agent", "json", "v1"),
    ("HINT", 0x8A, "agent", "json", "v1"),
    ("LOG", 0x8F, "agent", "json", "v1"),
    ("PARKED", 0x90, "agent", "json", "build"),
]
CODE = {name: code for name, code, *_ in TYPES}
SENDER = {name: sender for name, _, sender, *_ in TYPES}
KIND = {name: kind for name, _, _, kind, _ in TYPES}


def cobs_max(n):
    return n + 1 + n // 254


def cobs_encode(data):
    """The unique encoding: a block closes at every zero and after 254 non-zero
    bytes, and the final block is always written, even when it is empty."""
    out = bytearray([0])
    code_at = 0
    code = 1
    for b in data:
        if b == 0:
            out[code_at] = code
            code_at = len(out)
            out.append(0)
            code = 1
        else:
            out.append(b)
            code += 1
            if code == 0xFF:
                out[code_at] = code
                code_at = len(out)
                out.append(0)
                code = 1
    out[code_at] = code
    return bytes(out)


def cobs_decode(enc):
    if not enc:
        return None
    out = bytearray()
    i = 0
    while i < len(enc):
        code = enc[i]
        i += 1
        end = i + code - 1
        if code == 0 or end > len(enc) or 0 in enc[i:end]:
            return None
        out += enc[i:end]
        i = end
        if code != 0xFF and i < len(enc):
            out.append(0)
    return bytes(out)


def raw_frame(code, id_, payload, version=VERSION):
    body = bytes([version, code]) + id_.to_bytes(4, "little") + payload
    return body + zlib.crc32(body).to_bytes(4, "little")


def wire(raw):
    return cobs_encode(raw) + b"\x00"


def canonical(body):
    return json.dumps(body, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def decode_chunk(chunk, max_payload):
    """The receiver's checks, in the order the spec gives them."""
    if len(chunk) > cobs_max(HEADER + max_payload + TRAILER):
        return {"error": "oversize"}
    raw = cobs_decode(chunk)
    if raw is None:
        return {"error": "cobs"}
    if len(raw) < HEADER + TRAILER:
        return {"error": "short"}
    if zlib.crc32(raw[:-TRAILER]) != int.from_bytes(raw[-TRAILER:], "little"):
        return {"error": "crc"}
    if raw[0] != VERSION:
        return {"error": "version"}
    payload = raw[HEADER:-TRAILER]
    if len(payload) > max_payload:
        return {"error": "oversize"}
    return {
        "frame": {
            "version": raw[0],
            "type": raw[1],
            "id": int.from_bytes(raw[2:6], "little"),
            "payload_hex": payload.hex(),
        }
    }


def decode_stream(data, max_payload):
    events = []
    parts = data.split(b"\x00")
    for chunk in parts[:-1]:
        if chunk:
            events.append(decode_chunk(chunk, max_payload))
    return events


def zero_free_payload(code, id_, length, fill):
    """A payload of non-zero bytes whose whole raw frame, CRC included, has no
    zero byte, so the frame is one unbroken COBS run."""
    base = bytearray(fill(i) for i in range(length))
    for last in range(1, 256):
        base[-1] = last
        raw = raw_frame(code, id_, bytes(base))
        if 0 not in raw:
            return bytes(base)
    raise RuntimeError("no zero-free CRC found")


def pattern(i):
    return 1 + i % 255


def write(name, doc):
    OUT.mkdir(parents=True, exist_ok=True)
    text = json.dumps(doc, indent=2, ensure_ascii=False) + "\n"
    (OUT / name).write_text(text, encoding="utf-8")


# protocol.json

def protocol_doc():
    return {
        "description": "The constants of protocol version 1. Both codecs assert their tables against this file.",
        "version": VERSION,
        "header_bytes": HEADER,
        "crc_bytes": TRAILER,
        "max_payload_to_agent": MAX_PAYLOAD_TO_AGENT,
        "max_payload_to_host": MAX_PAYLOAD_TO_HOST,
        "max_encoded_to_agent": cobs_max(HEADER + MAX_PAYLOAD_TO_AGENT + TRAILER),
        "max_encoded_to_host": cobs_max(HEADER + MAX_PAYLOAD_TO_HOST + TRAILER),
        "credit_window": 16384,
        "credit_step": 4096,
        "output_cap": 262144,
        "output_flush_bytes": 4096,
        "output_flush_ms": 16,
        "max_files": 64,
        "max_files_bytes": 8 * 1024 * 1024,
        "max_windows": 32,
        "file_name_pattern": "^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}$",
        "in_dir": "/icc/in",
        "in_file": "/icc/in/r{id}-{name}",
        "types": [
            {"name": name, "code": code, "from": sender, "payload": kind, "status": status}
            for name, code, sender, kind, status in TYPES
        ],
    }


# crc32.json

def crc_doc():
    inputs = [
        ("empty", b""),
        ("check string '123456789'", b"123456789"),
        ("one zero byte", b"\x00"),
        ("four 0xff bytes", b"\xff\xff\xff\xff"),
        ("PING header, id 3", bytes([1, 0x05, 3, 0, 0, 0]) + b"{}"),
    ]
    vectors = []
    for name, data in inputs:
        crc = zlib.crc32(data)
        vectors.append({
            "name": name,
            "input_hex": data.hex(),
            "crc": f"{crc:08x}",
            "crc_le_hex": crc.to_bytes(4, "little").hex(),
        })
    return {
        "description": "CRC-32/ISO-HDLC: reflected polynomial 0xEDB88320, init 0xFFFFFFFF, final xor 0xFFFFFFFF. "
                       "'crc' is the value as a number; 'crc_le_hex' is how it sits in a frame.",
        "vectors": vectors,
    }


# cobs.json

def cobs_doc():
    run_254 = bytes(range(1, 255))
    run_253 = bytes(range(1, 254))
    cases = [
        ("empty", b""),
        ("one zero", b"\x00"),
        ("two zeros", b"\x00\x00"),
        ("zero, byte, zero", b"\x00\x11\x00"),
        ("zero in the middle", b"\x11\x22\x00\x33"),
        ("no zeros", b"\x11\x22\x33\x44"),
        ("trailing zeros", b"\x11\x00\x00\x00"),
        ("253 non-zero bytes", run_253),
        ("254 non-zero bytes: the final empty block is written", run_254),
        ("zero then 254 non-zero bytes", b"\x00" + run_254),
        ("255 non-zero bytes", bytes(range(1, 256))),
        ("254 non-zero bytes then a zero", bytes(range(2, 256)) + b"\x00"),
        ("253 non-zero bytes, zero, byte", bytes(range(3, 256)) + b"\x00\x01"),
        ("508 non-zero bytes", run_254 + run_254),
    ]
    vectors = []
    for name, data in cases:
        enc = cobs_encode(data)
        assert cobs_decode(enc) == data, name
        assert len(enc) <= cobs_max(len(data)), name
        vectors.append({"name": name, "decoded_hex": data.hex(), "encoded_hex": enc.hex()})

    decode_only = [
        ("254 non-zero bytes without the final empty block", b"\xff" + run_254, run_254),
        ("zero then 254 non-zero bytes without the final empty block", b"\x01\xff" + run_254, b"\x00" + run_254),
    ]
    for name, enc, data in decode_only:
        assert cobs_decode(enc) == data, name
    invalid = [
        ("empty input", b""),
        ("block runs past the end", b"\x05\x11\x22"),
        ("0xff block runs past the end", b"\xff\x11"),
        ("second block runs past the end", b"\x02\x11\x04\x22"),
    ]
    for name, enc in invalid:
        assert cobs_decode(enc) is None, name
    return {
        "description": "COBS without the delimiter. 'vectors' round-trip byte-exactly; 'decode_only' are "
                       "encodings another encoder may produce, which a decoder MUST accept but an encoder "
                       "MUST NOT produce; 'invalid' MUST be rejected.",
        "vectors": vectors,
        "decode_only": [
            {"name": name, "encoded_hex": enc.hex(), "decoded_hex": data.hex()}
            for name, enc, data in decode_only
        ],
        "invalid": [{"name": name, "encoded_hex": enc.hex()} for name, enc in invalid],
    }


# messages.json

ENTROPY = bytes(range(64)).hex()

MESSAGES = [
    ("HELLO", "HELLO", 1, {"now_ms": 1789999999123, "tz": "Europe/Amsterdam", "entropy": ENTROPY}),
    ("READY answering HELLO", "READY", 1,
     {"agent": "0.1.0", "python": "Python 3.12.12", "tk": "8.6.16", "tz": "Europe/Amsterdam", "warm": True}),
    ("READY at boot, unsolicited", "READY", 0,
     {"agent": "0.1.0", "python": None, "tk": None, "tz": "UTC", "warm": False}),
    ("RUN", "RUN", 2,
     {"entry": "main.py", "files": ["main.py", "picture.png"], "argv": [], "stdin": False, "output_cap": 262144}),
    ("RUN with argv", "RUN", 9,
     {"entry": "game.py", "files": ["game.py"], "argv": ["--level", "3", "naïve"], "stdin": False,
      "output_cap": 262144}),
    ("STARTED", "STARTED", 2, {"pid": 1234, "warm": True}),
    ("STARTED on a cold interpreter", "STARTED", 2, {"pid": 1301, "warm": False}),
    ("STDOUT", "STDOUT", 2, b"Hello\n"),
    ("STDOUT with zero bytes and invalid UTF-8", "STDOUT", 2, b"\x00\xff\x00A\n"),
    ("STDERR", "STDERR", 2, b'Traceback (most recent call last):\n  File "main.py", line 1\n'),
    ("WINDOW, one window", "WINDOW", 2,
     {"windows": [{"xid": 2097166, "title": "My app", "x": 0, "y": 0, "w": 320, "h": 200,
                   "mapped": True, "root": True, "transient_for": None}]}),
    ("WINDOW, withdrawn root under a dialog, title escapes", "WINDOW", 2,
     {"windows": [
         {"xid": 2097166, "title": "tk", "x": 0, "y": 0, "w": 200, "h": 200,
          "mapped": False, "root": True, "transient_for": None},
         {"xid": 2097201, "title": "Café \"naïve\"\t✓\\\u0001", "x": 280, "y": 250, "w": 240, "h": 100,
          "mapped": True, "root": False, "transient_for": 2097166},
     ]}),
    ("WINDOW, every window gone", "WINDOW", 2, {"windows": []}),
    ("HINT", "HINT", 2, {"kind": "tk_no_mainloop"}),
    ("EXIT, normal", "EXIT", 2, {"code": 0, "signal": None, "reason": "exit", "truncated": False, "ms": 1532}),
    ("EXIT, stopped and truncated", "EXIT", 2,
     {"code": None, "signal": 9, "reason": "stopped", "truncated": True, "ms": 20417}),
    ("EXIT, traceback", "EXIT", 9, {"code": 1, "signal": None, "reason": "exit", "truncated": False, "ms": 311}),
    ("STOP", "STOP", 2, {}),
    ("CLOSE", "CLOSE", 2, {"xid": 2097166}),
    ("PING", "PING", 3, {}),
    ("PONG", "PONG", 3, {}),
    ("PING, id bytes little-endian", "PING", 0x12345678, {}),
    ("CREDIT", "CREDIT", 0, {"bytes": 4096}),
    ("LOG", "LOG", 0, {"level": "warn", "message": "dropped 2 frames (crc)"}),
    ("ERROR answering a RUN", "ERROR", 4, {"code": "busy", "message": "run 2 is still active"}),
    ("ERROR about nothing in particular", "ERROR", 0, {"code": "internal", "message": "x11: connection lost"}),
    ("PREPARE", "PREPARE", 1,
     {"resident": ["/usr/lib/libpython3.12.so.1.0", "/usr/lib/libtk8.6.so"], "reserve_mib": 12}),
    ("PARKED", "PARKED", 1,
     {"warm": True, "mem_total_kb": 57344, "mem_available_kb": 21504, "zeroed_kb": 9216, "resident_kb": 12288}),
    ("STDIN (later)", "STDIN", 2, b"42\n"),
    ("STDIN end of input (later)", "STDIN", 2, b""),
]


def message_entry(name, type_, id_, content):
    code = CODE[type_]
    if KIND[type_] == "data":
        payload = content
        message = {"type": type_, "id": id_, "data_hex": content.hex()}
    else:
        payload = canonical(content)
        message = {"type": type_, "id": id_, "body": content}
    raw = raw_frame(code, id_, payload)
    return {
        "name": name,
        "from": SENDER[type_],
        "message": message,
        "raw_hex": raw.hex(),
        "frame_hex": wire(raw).hex(),
    }


def messages_doc():
    entries = [message_entry(*m) for m in MESSAGES]

    one_block_id = 0x01010101
    at_boundary = zero_free_payload(CODE["STDOUT"], one_block_id, 254 - HEADER - TRAILER,
                                    lambda i: 0x41)
    entries.append(message_entry("STDOUT whose raw frame is exactly one 254-byte block",
                                 "STDOUT", one_block_id, at_boundary))
    past_boundary = zero_free_payload(CODE["STDOUT"], one_block_id, 300 - HEADER - TRAILER, pattern)
    entries.append(message_entry("STDOUT whose raw frame spans a 254-byte block",
                                 "STDOUT", one_block_id, past_boundary))

    for e in entries:
        assert bytes.fromhex(e["frame_hex"]).count(0) == 1, e["name"]
    return {
        "description": "One frame per message, in canonical form. 'raw_hex' is the frame before COBS "
                       "(version | type | id LE | payload | CRC LE); 'frame_hex' is the bytes on the wire, "
                       "delimiter included. Decoding frame_hex MUST give 'message', and encoding 'message' "
                       "MUST give frame_hex.",
        "frames": entries,
    }


# messages-invalid.json and messages-tolerated.json

def invalid_entry(name, expect_from, code, id_, payload, error, field=None):
    entry = {
        "name": name,
        "from": expect_from,
        "frame_hex": wire(raw_frame(code, id_, payload)).hex(),
        "error": error,
    }
    if field is not None:
        entry["field"] = field
    return entry


def invalid_doc():
    run_ok = {"entry": "main.py", "files": ["main.py"], "argv": [], "stdin": False, "output_cap": 262144}

    def run_with(**changes):
        body = dict(run_ok)
        body.update(changes)
        return canonical(body)

    exit_ok = {"code": 0, "signal": None, "reason": "exit", "truncated": False, "ms": 5}

    def exit_with(**changes):
        body = dict(exit_ok)
        body.update(changes)
        return canonical(body)

    run_missing_entry = {k: v for k, v in run_ok.items() if k != "entry"}
    window = {"xid": 1, "title": "t", "x": 0, "y": 0, "w": 1, "h": 1, "mapped": True, "root": True,
              "transient_for": None}
    window_bad = dict(window, xid=-1)

    cases = [
        ("not JSON", "host", CODE["PING"], 3, b"{", "bad_json", None),
        ("not UTF-8", "host", CODE["PING"], 3, b"\xff", "bad_json", None),
        ("empty control payload", "host", CODE["PING"], 3, b"", "bad_json", None),
        ("JSON array", "host", CODE["PING"], 3, b"[]", "not_object", None),
        ("JSON null", "agent", CODE["PONG"], 3, b"null", "not_object", None),
        ("RUN without entry", "host", CODE["RUN"], 2, canonical(run_missing_entry), "field", "entry"),
        ("RUN entry not among the files", "host", CODE["RUN"], 2, run_with(entry="other.py"), "field", "entry"),
        ("RUN file name climbs out", "host", CODE["RUN"], 2,
         run_with(entry="main.py", files=["main.py", "../x"]), "field", "files"),
        ("RUN file name starts with a dot", "host", CODE["RUN"], 2,
         run_with(files=["main.py", ".stdin"]), "field", "files"),
        ("RUN file named twice", "host", CODE["RUN"], 2, run_with(files=["main.py", "main.py"]), "field", "files"),
        ("RUN with no files", "host", CODE["RUN"], 2, run_with(files=[]), "field", "files"),
        ("RUN argv with a NUL", "host", CODE["RUN"], 2, run_with(argv=["a\u0000b"]), "field", "argv"),
        ("RUN stdin not a boolean", "host", CODE["RUN"], 2, run_with(stdin=0), "field", "stdin"),
        ("HELLO entropy too short", "host", CODE["HELLO"], 1,
         canonical({"now_ms": 1, "tz": "UTC", "entropy": "00" * 32}), "field", "entropy"),
        ("HELLO entropy in capitals", "host", CODE["HELLO"], 1,
         canonical({"now_ms": 1, "tz": "UTC", "entropy": "AB" * 64}), "field", "entropy"),
        ("HELLO tz with a dot-dot", "host", CODE["HELLO"], 1,
         canonical({"now_ms": 1, "tz": "../etc/passwd", "entropy": ENTROPY}), "field", "tz"),
        ("HELLO now_ms negative", "host", CODE["HELLO"], 1,
         canonical({"now_ms": -1, "tz": "UTC", "entropy": ENTROPY}), "field", "now_ms"),
        ("CLOSE xid negative", "host", CODE["CLOSE"], 2, canonical({"xid": -1}), "field", "xid"),
        ("CLOSE xid past u32", "host", CODE["CLOSE"], 2, canonical({"xid": 4294967296}), "field", "xid"),
        ("CLOSE xid a string", "host", CODE["CLOSE"], 2, canonical({"xid": "1"}), "field", "xid"),
        ("EXIT code a string", "agent", CODE["EXIT"], 2, exit_with(code="0"), "field", "code"),
        ("EXIT code and signal both null", "agent", CODE["EXIT"], 2, exit_with(code=None), "field", "code"),
        ("EXIT code and signal both set", "agent", CODE["EXIT"], 2, exit_with(signal=9), "field", "code"),
        ("EXIT unknown reason", "agent", CODE["EXIT"], 2, exit_with(reason="crashed"), "field", "reason"),
        ("EXIT code past 255", "agent", CODE["EXIT"], 2, exit_with(code=256), "field", "code"),
        ("READY warm not a boolean", "agent", CODE["READY"], 1,
         canonical({"agent": "0.1.0", "python": None, "tk": None, "tz": "UTC", "warm": 1}), "field", "warm"),
        ("CREDIT of zero bytes", "agent", CODE["CREDIT"], 0, canonical({"bytes": 0}), "field", "bytes"),
        ("LOG unknown level", "agent", CODE["LOG"], 0,
         canonical({"level": "loud", "message": "x"}), "field", "level"),
        ("HINT kind not a token", "agent", CODE["HINT"], 2, canonical({"kind": "Tk No Mainloop"}), "field", "kind"),
        ("WINDOW with a negative xid", "agent", CODE["WINDOW"], 2,
         canonical({"windows": [window_bad]}), "field", "windows"),
        ("WINDOW with 33 windows", "agent", CODE["WINDOW"], 2,
         canonical({"windows": [dict(window, xid=i + 1, root=False) for i in range(33)]}), "field", "windows"),
        ("unknown host type", "host", 0x3E, 1, b"{}", "unknown_type", None),
        ("unknown agent type", "agent", 0xBE, 1, b"{}", "unknown_type", None),
        ("the host receives a host frame, as a tty that echoes would", "agent", CODE["PING"], 3, b"{}",
         "direction", None),
        ("the agent receives an agent frame", "host", CODE["PONG"], 3, b"{}", "direction", None),
    ]
    return {
        "description": "Frames that pass every framing check but MUST be rejected as messages. 'from' is the "
                       "sender the receiver expects. 'error' is one of bad_json, not_object, field, "
                       "unknown_type, direction; 'field' names the top-level field at fault. The agent "
                       "answers all of them with ERROR bad_request except unknown_type, which it answers "
                       "with ERROR unknown_type, and direction, which it only counts.",
        "frames": [invalid_entry(*c) for c in cases],
    }


def tolerated_doc():
    ready = {"agent": "0.1.0", "python": "Python 3.12.12", "tk": "8.6.16", "tz": "UTC", "warm": True}
    exit_ = {"code": 0, "signal": None, "reason": "exit", "truncated": False, "ms": 7}
    window = {"xid": 2097166, "title": "My app", "x": 0, "y": 0, "w": 320, "h": 200, "mapped": True,
              "root": True, "transient_for": None}
    cases = [
        ("READY with whitespace and its keys reordered", "READY", 1, ready,
         b'{ "warm": true,\n  "tz": "UTC", "tk": "8.6.16", "python": "Python 3.12.12", "agent": "0.1.0" }'),
        ("READY with keys this version does not know", "READY", 1, ready,
         b'{"agent":"0.1.0","python":"Python 3.12.12","tk":"8.6.16","tz":"UTC","warm":true,'
         b'"image":"a1b2","extra":{"nested":[1,2,{"x":null}]}}'),
        ("EXIT pretty-printed", "EXIT", 2, exit_,
         b'{\n  "code": 0,\n  "signal": null,\n  "reason": "exit",\n  "truncated": false,\n  "ms": 7\n}'),
        ("WINDOW entry with a key this version does not know", "WINDOW", 2, {"windows": [window]},
         b'{"windows":[{"focused":true,"xid":2097166,"title":"My app","x":0,"y":0,"w":320,"h":200,'
         b'"mapped":true,"root":true,"transient_for":null}]}'),
        ("PING with an escaped key", "PING", 3, {}, b'{"\\u0078":1}'),
        ("READY with its nullable fields left out", "READY", 0,
         {"agent": "0.1.0", "python": None, "tk": None, "tz": "UTC", "warm": False},
         b'{"agent":"0.1.0","tz":"UTC","warm":false}'),
        ("EXIT with signal left out", "EXIT", 2, exit_, b'{"code":0,"reason":"exit","truncated":false,"ms":7}'),
        ("WINDOW entry with transient_for left out", "WINDOW", 2, {"windows": [window]},
         b'{"windows":[{"xid":2097166,"title":"My app","x":0,"y":0,"w":320,"h":200,'
         b'"mapped":true,"root":true}]}'),
        ("STOP with a body this version does not know", "STOP", 2, {}, b'{"why":"student pressed Stop"}'),
    ]
    frames = []
    for name, type_, id_, body, payload in cases:
        code = CODE[type_]
        frames.append({
            "name": name,
            "from": SENDER[type_],
            "frame_hex": wire(raw_frame(code, id_, payload)).hex(),
            "message": {"type": type_, "id": id_, "body": body},
            "canonical_frame_hex": wire(raw_frame(code, id_, canonical(body))).hex(),
        })
    return {
        "description": "Non-canonical payloads a receiver MUST accept. Decoding 'frame_hex' MUST give "
                       "'message' (unknown keys dropped, nullable keys left out read as null); encoding "
                       "'message' gives 'canonical_frame_hex'.",
        "frames": frames,
    }


# stream.json

def stream_doc():
    ping = lambda id_: wire(raw_frame(CODE["PING"], id_, b"{}"))
    pong = lambda id_: wire(raw_frame(CODE["PONG"], id_, b"{}"))
    stdout = lambda id_, data: wire(raw_frame(CODE["STDOUT"], id_, data))
    ready_boot = wire(raw_frame(CODE["READY"], 0, canonical(
        {"agent": "0.1.0", "python": None, "tk": None, "tz": "UTC", "warm": False})))

    def flip_payload_bit(frame_wire):
        raw = bytearray(cobs_decode(frame_wire[:-1]))
        raw[HEADER] ^= 0x01
        return cobs_encode(bytes(raw)) + b"\x00"

    one_block_id = 0x01010101
    at_boundary_raw = raw_frame(CODE["STDOUT"], one_block_id,
                                zero_free_payload(CODE["STDOUT"], one_block_id, 244, lambda i: 0x41))
    at_boundary_wiki = b"\xff" + at_boundary_raw + b"\x00"

    def full_frame(code, max_payload):
        payload = zero_free_payload(code, one_block_id, max_payload, pattern)
        frame = wire(raw_frame(code, one_block_id, payload))
        assert len(frame) - 1 == cobs_max(HEADER + max_payload + TRAILER)
        return frame

    stdin_full = full_frame(CODE["STDIN"], MAX_PAYLOAD_TO_AGENT)
    stdout_full = full_frame(CODE["STDOUT"], MAX_PAYLOAD_TO_HOST)
    enc_agent = cobs_max(HEADER + MAX_PAYLOAD_TO_AGENT + TRAILER)
    enc_host = cobs_max(HEADER + MAX_PAYLOAD_TO_HOST + TRAILER)

    v2 = wire(raw_frame(CODE["PING"], 5, b"{}", version=2))
    short = cobs_encode(bytes([1, 0x05, 3, 0, 0, 0, 0x7B, 0x7D, 0])) + b"\x00"
    truncated_stdout = stdout(2, b"half a fram")[:9]

    cases = [
        ("two frames in one read", MAX_PAYLOAD_TO_AGENT, [ping(1) + ping(2)]),
        ("the delimiter alone in the next read", MAX_PAYLOAD_TO_AGENT, [ping(1)[:-1], b"\x00"]),
        ("one frame across three reads", MAX_PAYLOAD_TO_HOST,
         [stdout(2, b"Hello")[:3], stdout(2, b"Hello")[3:8], stdout(2, b"Hello")[8:]]),
        ("empty chunks are ignored", MAX_PAYLOAD_TO_AGENT, [b"\x00\x00" + ping(1) + b"\x00\x00\x00"]),
        ("garbage without a zero corrupts the frame it runs into", MAX_PAYLOAD_TO_HOST,
         [b"ABC" + pong(1) + pong(2)]),
        ("garbage ending in a zero is dropped on its own", MAX_PAYLOAD_TO_HOST, [b"\x11\x22\x00" + pong(1)]),
        ("a flipped bit fails the CRC", MAX_PAYLOAD_TO_AGENT, [flip_payload_bit(ping(1)) + ping(2)]),
        ("a lost byte in the middle", MAX_PAYLOAD_TO_HOST,
         [stdout(2, b"Hello")[:4] + stdout(2, b"Hello")[5:] + pong(3)]),
        ("a frame shorter than header and CRC", MAX_PAYLOAD_TO_AGENT, [short + ping(1)]),
        ("another protocol version", MAX_PAYLOAD_TO_AGENT, [v2 + ping(6)]),
        ("an agent that died mid-frame restarts with a zero and READY", MAX_PAYLOAD_TO_HOST,
         [truncated_stdout, b"\x00" + ready_boot]),
        ("a trailing partial frame emits nothing yet", MAX_PAYLOAD_TO_HOST, [pong(1) + pong(2)[:5]]),
        ("a frame encoded without its final empty block", MAX_PAYLOAD_TO_HOST, [at_boundary_wiki + pong(1)]),
        ("to the agent: a frame at the size limit", MAX_PAYLOAD_TO_AGENT, [stdin_full + ping(1)]),
        ("to the agent: one byte past the encoded limit", MAX_PAYLOAD_TO_AGENT,
         [b"\x41" * (enc_agent + 1) + b"\x00" + ping(1)]),
        ("to the agent: payload one byte too long, under the encoded limit", MAX_PAYLOAD_TO_AGENT,
         [wire(raw_frame(CODE["STDIN"], 2, b"\x00" * (MAX_PAYLOAD_TO_AGENT + 1))) + ping(1)]),
        ("to the host: a frame at the size limit", MAX_PAYLOAD_TO_HOST, [stdout_full + pong(1)]),
        ("to the host: one byte past the encoded limit", MAX_PAYLOAD_TO_HOST,
         [b"\x41" * (enc_host + 1) + b"\x00" + pong(1)]),
        ("to the host: payload one byte too long, under the encoded limit", MAX_PAYLOAD_TO_HOST,
         [wire(raw_frame(CODE["STDOUT"], 2, b"\x00" * (MAX_PAYLOAD_TO_HOST + 1))) + pong(1)]),
    ]

    out = []
    for name, max_payload, chunks in cases:
        events = decode_stream(b"".join(chunks), max_payload)
        out.append({
            "name": name,
            "max_payload": max_payload,
            "chunks_hex": [c.hex() for c in chunks],
            "events": events,
        })

    expected_errors = {
        "a flipped bit fails the CRC": "crc",
        "a frame shorter than header and CRC": "short",
        "another protocol version": "version",
        "garbage ending in a zero is dropped on its own": "cobs",
        "to the agent: one byte past the encoded limit": "oversize",
        "to the agent: payload one byte too long, under the encoded limit": "oversize",
        "to the host: one byte past the encoded limit": "oversize",
        "to the host: payload one byte too long, under the encoded limit": "oversize",
    }
    for case in out:
        want = expected_errors.get(case["name"])
        if want:
            assert case["events"][0] == {"error": want}, (case["name"], case["events"][0])
            assert "frame" in case["events"][1], case["name"]
    return {
        "description": "Byte streams as a receiver reads them. Feeding 'chunks_hex' in order, or the same bytes "
                       "split anywhere else, MUST produce 'events' in order. A frame event carries the header "
                       "fields and payload; an error event names the first check that failed: oversize, cobs, "
                       "short, crc, version, then oversize again for the decoded payload.",
        "cases": out,
    }


def main():
    write("protocol.json", protocol_doc())
    write("crc32.json", crc_doc())
    write("cobs.json", cobs_doc())
    write("messages.json", messages_doc())
    write("messages-invalid.json", invalid_doc())
    write("messages-tolerated.json", tolerated_doc())
    write("stream.json", stream_doc())


if __name__ == "__main__":
    main()
