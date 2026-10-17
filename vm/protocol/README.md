# VM control protocol

The line between the JS host (`web/vm/vm_host.js`) and the agent in the guest
(`icc-agent`, crate `vm/agent/`). This document is normative. MUST, SHOULD and
MAY are used as in RFC 2119.

Two codecs implement it: `web/vm/vm_protocol.js`, and the agent's frame and
message modules. Both are held to the byte-exact vectors in `fixtures/`, which
`gen_fixtures.py` writes from this document (section 11).

**Protocol version: 1.**

Each part has a status:

- **v1**: in the first release.
- **build**: v1, but only the image pipeline (`vm/tools/`) sends it.
- **later**: not implemented. The number and the shape are fixed here so that
  nothing else takes them.

## 1. Channel

- The line is the guest's second UART. v86 creates it with `uart1: true`: a
  16550A at 0x2F8, IRQ 3, which the guest sees as `/dev/ttyS1`. The host writes
  with `serial_send_bytes(1, bytes)` and reads the `serial1-output-byte` event.
- The agent owns ttyS1. It MUST put the port in raw mode (`cfmakeraw`: no echo,
  no line editing, no CR/LF translation, 8 data bits) before it sends anything.
  It does this at boot, so the saved snapshot, and every machine restored from
  it, is raw already.
- Files do not travel on this line. The host writes them into the guest's 9p
  tree with `create_file`, and RUN names them (section 6.3).
- ttyS0 is the kernel console and not part of the protocol. The host keeps its
  last 16 KiB for failure reports.
- Agent to host is lossless: v86 hands every byte to the listener. Host to
  agent is not: the guest's tty drops input it has no room for. In the spike a
  64 KiB burst arrived intact and a 256 KiB burst did not. Section 7 keeps the
  host well inside that.

## 2. Frames

### 2.1 Layout

Before encoding, a frame is:

| Offset | Size | Field | Contents |
| ---: | ---: | --- | --- |
| 0 | 1 | version | `0x01` |
| 1 | 1 | type | The message type (section 4). |
| 2 | 4 | id | u32, little-endian (section 3). |
| 6 | n | payload | A JSON object or raw bytes, by type (section 5). |
| 6 + n | 4 | crc | CRC-32 of bytes 0 to 5 + n, u32 little-endian. |

On the wire the frame is COBS-encoded (2.3) and followed by one `0x00`, the
delimiter.

A later version MUST keep the version byte first and the CRC last. That is what
lets a receiver of any version tell an incompatible peer (good CRC, other
version) from line noise (bad CRC).

### 2.2 CRC

CRC-32/ISO-HDLC, the CRC of zlib, PNG and Ethernet: reflected polynomial
`0xEDB88320`, initial value `0xFFFFFFFF`, final XOR `0xFFFFFFFF`. The check
value for the ASCII string `123456789` is `0xCBF43926`, which a frame stores as
`26 39 f4 cb`. It is what `crc32fast::hash` and Python's `zlib.crc32` return.
It covers version, type, id and payload. Vectors: `fixtures/crc32.json`.

### 2.3 COBS

Consistent Overhead Byte Stuffing (Cheshire and Baker, 1999) removes every zero
byte from the frame, so on the wire `0x00` can only be the delimiter.

**Encoding.** Split the data into blocks. A block ends at a zero byte, after 254
non-zero bytes, or at the end of the data. Write each block as a code byte
followed by its non-zero bytes. The code is 1 plus the number of non-zero bytes:

- A block that ended at a zero has a code from `0x01` to `0xFE`. The zero itself
  is not written.
- A block of 254 non-zero bytes has code `0xFF`, and no zero follows it.
- The block at the end of the data is always written, even when it is empty.

The last rule makes the encoding unique, and it is the rule encoders disagree
on. 254 non-zero bytes encode as `FF <254 bytes> 01`, not as `FF <254 bytes>`.
An encoder MUST produce the first form. A decoder MUST accept both.

```text
encode(data):
    out = [0]; code_at = 0; code = 1
    for b in data:
        if b == 0:
            out[code_at] = code; code_at = len(out); out.append(0); code = 1
        else:
            out.append(b); code += 1
            if code == 0xFF:
                out[code_at] = code; code_at = len(out); out.append(0); code = 1
    out[code_at] = code
    return out
```

**Decoding** one chunk, the bytes between two delimiters:

```text
decode(chunk):
    if chunk is empty: fail
    out = []; i = 0
    while i < len(chunk):
        code = chunk[i]; i += 1
        if code == 0 or i + code - 1 > len(chunk): fail
        append chunk[i : i + code - 1] to out       # fail if any of them is 0
        i += code - 1
        if code != 0xFF and i < len(chunk): out.append(0)
    return out
```

n bytes encode to at most n + 1 + floor(n / 254) bytes. Vectors, the 254-byte
cases included: `fixtures/cobs.json`.

### 2.4 Size limits

| Direction | Max payload | Max frame before encoding | Max encoded, no delimiter |
| --- | ---: | ---: | ---: |
| host to agent | 4,096 | 4,106 | 4,123 |
| agent to host | 16,384 | 16,394 | 16,459 |

A sender MUST NOT exceed them. Each receiver enforces the limit of the
direction it receives. The host's is the one that matters: everything the guest
sends is untrusted input to the page, and this limit is what bounds the host's
buffer.

### 2.5 Receiving and resync

A receiver collects bytes up to a `0x00` and then judges the chunk. The checks
run in this order, and the first that fails names the drop:

1. The chunk is empty: ignore it. No event and no count. A sender MAY write
   extra `0x00` bytes between frames.
2. The chunk is longer than the maximum encoded length: `oversize`. The receiver
   stops storing bytes as soon as a chunk passes the limit and discards the rest
   up to the delimiter, so its memory stays bounded whatever arrives.
3. COBS decoding fails: `cobs`.
4. The decoded frame is shorter than 10 bytes: `short`.
5. The CRC does not match: `crc`.
6. The version is not 1: `version`.
7. The payload is longer than the maximum payload: `oversize`.
8. Otherwise the frame is good and goes to the message layer (5.3).

A dropped frame is counted by its reason and never acted on: not answered, not
partly applied.

Resync needs no step of its own. No zero byte can occur inside an encoded frame,
so the next `0x00` ends whatever was damaged, and the frame after it decodes
normally. Garbage that ends in a `0x00` costs only itself. Garbage without one
runs into the next frame and costs that frame too.

A receiver starts, and restarts after a reset, as if at the start of a frame. If
it was not, the first chunk fails and the one after it is good.

- The agent MUST write one `0x00` when it opens ttyS1, before its first frame.
  When init respawns an agent that died mid-frame, that zero ends the
  half-written frame instead of merging it with the new agent's READY.
- The host MUST reset its decoder on every restore, because the guest side of
  the line has just gone back to the snapshot.
- The host counts drops by reason and keeps the counts for diagnostics. The
  agent reports its own drops in a LOG `warn`, at most once a second.

Stream vectors (splits, garbage, every drop reason, both size limits):
`fixtures/stream.json`.

## 3. Ids

- The id is a u32. `0` means "part of no conversation" and only the agent uses
  it, for frames nobody asked for.
- The host takes ids from one counter. It starts at 1 and advances for every
  HELLO, PING, PREPARE and RUN the host sends. Nothing resets it, not a restore
  and not a failure, so an id never names two conversations while the page
  lives. It MUST NOT wrap. The one frame the host sends twice is a RUN retried
  after a park (9.7): the same run, sent to a machine that never saw the first.
- It is one counter rather than one per kind so that an id alone names the
  conversation. ERROR carries the id it answers, and with two counters request 7
  and run 7 would be the same number.
- A RUN's id is the **run id**. STOP, CLOSE and STDIN open no conversation: they
  carry the run id of the run they are about.
- An agent frame that answers a request carries the request's id. An agent frame
  about a run carries the run id.
- The agent MUST treat ids as opaque and MUST NOT assume they increase. The
  snapshot holds the ids the build pipeline used, and every new page starts
  again at 1.
- The host drops every agent frame whose id is neither 0 nor one it is waiting
  on: the current run, or an unanswered HELLO, PING or PREPARE. That is what
  keeps output or an EXIT from a stopped run off the next run.

## 4. Message types

Bit 7 of the type code is the direction. `0x01` to `0x7F` go from host to agent,
`0x81` to `0xFF` from agent to host. `0x10` to `0x1F` and `0x90` to `0x9F` hold
the build-pipeline messages. `0x00` and `0x80` are never used, and every code
not in the table is unassigned.

| Code | Name | From | id | Payload | Status | Answered by |
| --- | --- | --- | --- | --- | --- | --- |
| 0x01 | HELLO | host | new | JSON | v1 | READY |
| 0x02 | RUN | host | new: the run id | JSON | v1 | STARTED, then EXIT; or ERROR |
| 0x03 | STDIN | host | run id | data | later | |
| 0x04 | STOP | host | run id | JSON `{}` | v1 | EXIT |
| 0x05 | PING | host | new | JSON `{}` | v1 | PONG |
| 0x06 | CLOSE | host | run id | JSON | v1 | nothing direct |
| 0x10 | PREPARE | host | new | JSON | build | PARKED; or ERROR |
| 0x81 | READY | agent | HELLO's, or 0 | JSON | v1 | |
| 0x82 | STARTED | agent | run id | JSON | v1 | |
| 0x83 | STDOUT | agent | run id | data | v1 | |
| 0x84 | STDERR | agent | run id | data | v1 | |
| 0x85 | EXIT | agent | run id | JSON | v1 | |
| 0x86 | WINDOW | agent | run id | JSON | v1 | |
| 0x87 | ERROR | agent | the frame it answers, or 0 | JSON | v1 | |
| 0x88 | PONG | agent | PING's | JSON `{}` | v1 | |
| 0x89 | CREDIT | agent | 0 | JSON | v1 | |
| 0x8A | HINT | agent | run id | JSON | v1 | |
| 0x8F | LOG | agent | 0, or a run id | JSON | v1 | |
| 0x90 | PARKED | agent | PREPARE's | JSON | build | |

## 5. Payloads

### 5.1 JSON

- A control payload is one JSON object (RFC 8259) in UTF-8, without a byte-order
  mark.
- Senders SHOULD write the **canonical form**, which the fixtures use:
  - no whitespace;
  - keys in the order this document lists them;
  - every field present, with an absent value written as `null`, not left out;
  - integers as plain digits, with no fraction and no exponent;
  - strings escaped only where JSON requires it (`\"`, `\\`, `\b`, `\f`, `\n`,
    `\r`, `\t`, and other control characters as `\u00xx` in lower case), every
    other character as raw UTF-8.

  `JSON.stringify` on an object built in table order produces exactly this, and
  so does serde_json on a struct whose fields are declared in table order.
- Receivers MUST accept any valid JSON: whitespace, keys in any order, and keys
  they do not know, which they ignore. That is how a field is added within a
  version.
- A missing field, a value of the wrong type or one out of range makes the
  message invalid. The exception is a field whose type allows null: left out,
  it reads as null, which is also what serde's derive does with an `Option`.
  A sender MUST NOT repeat a key, and a receiver MAY reject a payload that does.
  A receiver MAY reject an integer written as `1.0` or `1e3`.
- An empty payload is not an empty object: it is invalid. PING, PONG and STOP
  carry the two bytes `{}`.

Types in the tables below:

| Type | Values |
| --- | --- |
| u32 | integer 0 to 4,294,967,295 |
| i32 | integer -2,147,483,648 to 2,147,483,647 |
| ms | integer 0 to 2^53 - 1 |
| bool | `true` or `false` |
| token | string matching `^[a-z][a-z0-9_]{0,63}$` |
| name | string matching `^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}$` |
| zone | IANA time zone name, at most 64 characters, matching `^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$` |

### 5.2 Data

STDOUT, STDERR and STDIN carry raw bytes, with no JSON and no text encoding of
their own. The bytes MAY include `0x00` (COBS takes care of it) and need not be
valid UTF-8 or end on a character boundary. The host decodes each stream of a
run with its own streaming `TextDecoder`.

### 5.3 Invalid messages

A good frame can still carry a message the receiver cannot use. The message
layer checks, in order:

1. **`direction`**: the type code is from the wrong side, a code below `0x80`
   reaching the host or one above it reaching the agent. Counted and dropped,
   never answered. On the host it nearly always means the guest's tty echoes:
   the agent did not make ttyS1 raw, and the image is broken.
2. **`unknown_type`**: no row in section 4 has the code. The agent answers ERROR
   `unknown_type` with the frame's id. The host counts it and drops it.
3. **`bad_json`** (the payload is not UTF-8, or not JSON), **`not_object`** (it
   is JSON but not an object), **`field`** (a field is missing, of the wrong
   type or out of range, or a rule between fields fails). The agent answers all
   three with ERROR `bad_request` and the frame's id. The host drops the
   message, and when the id is its current run's, it ends that run as `broken`
   (9.3).

`fixtures/messages-invalid.json` has a case for each rule, and
`fixtures/messages-tolerated.json` has the non-canonical payloads a receiver
MUST still accept.

## 6. Messages

### 6.1 HELLO (0x01, host to agent, v1)

The host sends HELLO after every resume from a park, before anything else. A
restored machine has the clock and the random pool of the moment the snapshot
was taken (measured: the guest showed the build's time of day). The agent
answers READY with the same id.

| Field | Type | Meaning |
| --- | --- | --- |
| `now_ms` | ms | The host's wall clock in Unix epoch milliseconds, when the frame is sent. The agent sets `CLOCK_REALTIME` to it. |
| `tz` | zone | The host's time zone, from `Intl.DateTimeFormat().resolvedOptions().timeZone`. The agent looks it up under `/usr/share/zoneinfo` and gives it to the next run as `TZ`. A zone the image lacks falls back to `UTC`, and READY says which zone the agent kept. |
| `entropy` | string | 64 bytes from `crypto.getRandomValues`, as exactly 128 lower-case hex digits. The agent adds them to the kernel pool with `RNDADDENTROPY` and forces a reseed with `RNDRESEEDCRNG`. |

`entropy` is hex rather than base64 so the agent needs no decoder beyond a few
lines. HELLO is valid in any state, a run included: it changes the clock, the
pool and the zone for later runs, never a program that is running.

### 6.2 READY (0x81, agent to host, v1)

| Field | Type | Meaning |
| --- | --- | --- |
| `agent` | string | The agent's version: its Cargo package version. |
| `python` | string or null | What the interpreter calls itself, as `python3 -V` prints it: `"Python 3.12.12"`. This is the same wording `PythonRuntime.version` gives for the lesson runtime. null while the agent does not know it: at boot, before PREPARE. |
| `tk` | string or null | Tk's patch level, such as `"8.6.16"`. null when `python` is. |
| `tz` | zone | The zone the next run will get. |
| `warm` | bool | A warm interpreter is waiting for a program. false at boot, and after the warm interpreter was lost. |

READY answers HELLO with HELLO's id. The agent also sends one READY with id 0,
unasked, right after its opening `0x00` when it starts, so the build pipeline
knows it is up. On a page, an unasked READY means the agent process restarted
(init respawns it after a crash): the host ends the current run as `broken` and
parks. A READY with `warm: false` during starting is not an error: the run goes
ahead on a cold interpreter, and STARTED says so.

### 6.3 RUN (0x02, host to agent, v1)

| Field | Type | Meaning |
| --- | --- | --- |
| `entry` | name | The file run as `__main__`. MUST be one of `files`. |
| `files` | array of name | 1 to 64 distinct names. Each file MUST already be in the 9p tree at `/icc/in/r<id>-<name>`, `<id>` being this RUN's id in decimal. The host writes them with `create_file` before it sends RUN. |
| `argv` | array of string | 0 to 64 arguments after the script name, none containing U+0000. The program sees `sys.argv == [entry, *argv]`. |
| `stdin` | bool | v1: MUST be false. The program's stdin is `/dev/null`, so `input()` raises `EOFError`. true is **later** (6.13), and a v1 agent answers it with ERROR `unsupported`. |
| `output_cap` | integer 0 to 16,777,216 | Bytes of STDOUT and STDERR together that the agent forwards for this run. A v1 host sends 262,144, the `MAX_OUTPUT_BYTES` of the lesson runtime. The agent MUST honour any value up to 1 MiB and MAY lower a larger one to 1 MiB. |

The whole payload MUST fit in 4,096 bytes, which is what bounds `argv`.

- A name that starts with a dot is reserved for the protocol (the later stdin
  file is `r<id>-.stdin`), so no student file can take it.
- The run id is in the path because the guest mounts its root with
  `cache=loose`, which answers a name it has looked up before from its own
  cache. A name with a new run id in it has never been looked up.
- The files may add up to 8 MiB. The agent checks that, and that each file
  exists.

The agent copies the files into the run's working directory (a tmpfs owned by
the student user), takes what they occupy there off the run's memory budget
(6.6), hands the program to the warm interpreter, or to a cold `python3` when
none is waiting, and answers STARTED. When it cannot start the
run it answers ERROR with the run id instead, and no STARTED or EXIT follows:

| ERROR code | When |
| --- | --- |
| `busy` | Another run is current. |
| `bad_request` | The payload is invalid (5.3). |
| `bad_files` | A file is missing from `/icc/in`, or the files add up to more than 8 MiB. |
| `unsupported` | `stdin` is true. |
| `spawn_failed` | The program could not be started. |

Once STARTED is sent, the run ends with exactly one EXIT. In between, STDOUT,
STDERR, WINDOW, HINT and LOG frames come in any order. EXIT is the last frame of
a run: the agent sends nothing about a run after its EXIT.

### 6.4 STARTED (0x82, agent to host, v1)

| Field | Type | Meaning |
| --- | --- | --- |
| `pid` | integer 1 to 2^31 - 1 | The program's process, leader of its process group. |
| `warm` | bool | The warm interpreter took the run. false means a cold `python3`, 5 to 7 s to a first Tk window (measured). That only happens after a park failed to bring the warm one back. |

### 6.5 STDOUT (0x83) and STDERR (0x84), agent to host, v1

Raw bytes, in the order the program wrote them to that stream. The two streams
are two pipes, so the order between them is the order the agent read them. That
is close to the order they were written, but not always the same.

- The agent SHOULD flush a stream when 4,096 bytes are pending, or 16 ms after
  its first pending byte, whichever comes first. A print loop then costs about
  60 frames a second rather than one frame per line.
- The agent MUST flush both streams before EXIT.
- `output_cap` counts the payload bytes of both streams together. Once the cap
  is reached the agent forwards nothing more for either stream. It keeps reading
  and discarding both pipes, so the program never blocks on a full pipe, and it
  sets `truncated` in EXIT. The cut MAY fall inside a UTF-8 character.

### 6.6 EXIT (0x85, agent to host, v1)

| Field | Type | Meaning |
| --- | --- | --- |
| `code` | integer 0 to 255, or null | The exit status, or null when a signal ended the process. |
| `signal` | integer 1 to 64, or null | The signal that ended the process, or null. Exactly one of `code` and `signal` is non-null. |
| `reason` | `"exit"`, `"stopped"`, `"closed"` or `"oom"` | Why it ended; see below. |
| `truncated` | bool | Output passed `output_cap`, and the rest was discarded. |
| `ms` | ms | Guest `CLOCK_MONOTONIC` milliseconds from handing over the program to reaping it, or to killing it (below). It leaves out time the CPU was stopped for a hidden tab: the host stops the guest's clock with its CPU (9.6). |

| reason | Meaning |
| --- | --- |
| `exit` | The program ended by itself. That includes an uncaught exception (code 1, the traceback on STDERR) and a signal the program brought on itself. |
| `stopped` | STOP killed it. |
| `closed` | CLOSE had to kill it, because the window did not take `WM_DELETE_WINDOW` (6.10). |
| `oom` | The kernel's OOM killer took it, inside the run's memory budget or the guest's. The agent compares the `oom_kill` counters of the run's cgroup (`memory.events`) and of `/proc/vmstat` before and after. |

The run ends when the process named in STARTED has been reaped. Anything the run
started is then killed with SIGKILL: every process in the run's cgroup, which a
process cannot leave the way setsid(2) leaves a process group, and the process
group besides. A program that crashes is not a harness failure: it is an EXIT
with reason `exit`. ERROR is for harness failures only.

Every process of a run is in one cgroup v2 group, and so shares one memory
budget, its `memory.max`, which tmpfs pages written by the run count against too.
The run's files are written by the agent, so their pages are not charged to the
group; the agent lowers `memory.max` by what they occupy instead, since they come
out of the same memory. Running out of it is an OOM inside the group, which kills
all of the run and ends it as `oom`; the rest of the guest keeps its memory.
`docs/vm-build.md` has the size and how it is chosen.

A warm run's program is done before its process has exited. The prelude does
what `python3` does after a script up to its own teardown: it waits for the
program's threads and runs its atexit handlers, and then tells the agent. The
agent kills every other process of the run at that point, so the teardown that
is left does not share the CPU with processes the program left spinning; EXIT
still follows the reap. Measured: with 40 busy children left behind, a program's
EXIT came 15.7 s after its last line before this; with 10 it now comes 0.8 to
1.4 s after.

A run the agent kills itself, for STOP or for CLOSE, ends the moment the SIGKILL
is sent, with `signal` 9: it cannot be caught, so the outcome is already known.
The agent first forwards what the pipes hold, and reaps the process afterwards
without reporting it. The kernel's teardown of a Tk program takes 70 to 230 ms
in v86 (measured), and the park that follows a stop discards the process however
far that teardown has got, so waiting for it would only hold the park up.

### 6.7 WINDOW (0x86, agent to host, v1)

The run's top-level X windows, as the complete list every time, bottom to top in
the X stacking order. A full list rather than a change keeps the host free of
per-window state, and makes the stacking order the array order.

| Field | Type | Meaning |
| --- | --- | --- |
| `windows` | array of window | 0 to 32 entries. |

Each window:

| Field | Type | Meaning |
| --- | --- | --- |
| `xid` | u32 | The X window id. CLOSE names a window by it. |
| `title` | string | `_NET_WM_NAME` (UTF-8) if set, else `WM_NAME` (Latin-1 when its type is STRING), else `""`. Control characters are left out and the title is cut to 80 characters, which keeps 32 windows within one frame. |
| `x`, `y` | i32 | Position on the 800 x 600 screen, in guest pixels. |
| `w`, `h` | integer 0 to 65,535 | Inside size in guest pixels. With no window manager there is no decoration around it. |
| `mapped` | bool | true while the window is viewable; false while it is withdrawn or iconified. |
| `root` | bool | This is the program's main window (below). At most one entry has it. |
| `transient_for` | u32 or null | `WM_TRANSIENT_FOR`: a dialog names the window it belongs to. |

- **Which windows.** Every child of the X root window that has been mapped at
  least once during this run and still exists, except override-redirect windows
  (menus, combobox lists, tooltips), which a window manager would not manage
  either. A destroyed window leaves the list. Past 32, the list keeps the 32
  highest in the stacking order.
- **`root`** marks the Tk root the warm interpreter handed to the program. The
  prelude tells the agent the xid of that root's own window `.` during warm-up.
  The top-level the X server lists is Tk's wrapper around it, which only exists
  once Tk first maps the root, so the agent finds it as that window's parent.
  With a cold interpreter it marks the first top-level the run mapped.
- **No window manager** (decision 3). Windows sit where the program put them: a
  Tk toplevel at +0+0, a dialog centred on its parent. Flutter draws the frame,
  a title and a close button, from these frames; which windows get one is the
  host's decision, not the agent's.
- **When.** The agent keeps the list from X events, which carry each window's
  geometry and its place in the stacking order, and asks the X server only for
  titles and `WM_TRANSIENT_FOR`. It sends the list when an event changes it and
  it differs from the last one it sent for this run. The first change after a
  quiet spell goes out at once, since the window's pixels are on screen already
  and Flutter frames the window from this frame; after that the agent sends at
  most one WINDOW every 16 ms, so a burst of X events becomes one frame at the
  end of that interval. A window mapped and withdrawn inside such a burst is
  never reported as mapped. The agent reads X on a thread of its own: a server
  that does not answer, because another client grabbed it or is drawing
  something huge, holds WINDOW up until it answers, and never holds up a PONG.
  Measured: a window mapped while the agent waited on the server is listed
  within 100 ms of it answering, where it used to wait for the agent's next
  wakeup, up to a PING later. The root the warm interpreter hands over has never
  been mapped (F1): like a cold `Tk()`'s, it maps at the program's first idle
  unless the program withdraws it first, so `root = Tk(); root.withdraw()` never
  shows it at all.
- **Focus.** With no window manager the agent sets X input focus itself (F4): to
  each top-level as it is mapped, back to the most recently mapped one still
  showing when the focused one goes, and to any top-level the pointer clicks
  into. The clicks come to the agent through a passive button grab on each
  top-level, which it answers with `AllowEvents(ReplayPointer)`, so the program
  still gets the click as if nothing had seen it first. v1 does not report focus.

### 6.8 HINT (0x8A, agent to host, v1)

| Field | Type | Meaning |
| --- | --- | --- |
| `kind` | token | What happened. The host ignores kinds it does not know. |

v1 has one kind, and the agent sends each kind at most once per run. The prelude
decides a hint in the program's own process, where the program can write the
same line; the agent therefore drops any kind this section does not list, and
any second one.

- `tk_no_mainloop`: the program created a Tk root and ended without entering
  `mainloop()`, and neither destroyed nor withdrew that root, so its window closed
  when it exited or never appeared at all (decision 4). The host tells the
  student why. The prelude decides it, so a cold interpreter never sends it.

A HINT about a run comes before its EXIT. **later** kinds: `stdin_unavailable`
(the program read stdin with none given) and `output_truncated` (sent the moment
the cap is reached, not only in EXIT).

### 6.9 STOP (0x04, host to agent, v1)

Payload `{}`. The agent kills the run, its cgroup and its process group, with
SIGKILL and sends EXIT with reason `stopped` at once (6.6). Measured: EXIT 2.1 to 3.7 ms
after STOP with `while True: pass` running.

A STOP for a run that is not current, because it has ended or never started, is
ignored without an answer: the EXIT it wants is already on its way, or was never
due. The host never waits for the answer (9.5).

### 6.10 CLOSE (0x06, host to agent, v1)

| Field | Type | Meaning |
| --- | --- | --- |
| `xid` | u32 | A window from the run's last WINDOW. |

This is what the close button on a frame Flutter draws does, and it does what a
window manager would:

- If the window lists `WM_DELETE_WINDOW` in `WM_PROTOCOLS`, the agent sends it a
  `WM_PROTOCOLS` ClientMessage carrying `WM_DELETE_WINDOW`. The program decides
  what happens. Tk's default destroys the window, and destroying the root ends
  `mainloop()`, so a typical program ends normally with an EXIT reason `exit`. A
  program with its own handler may ask "are you sure?" or ignore it.
- Otherwise the agent kills the run as STOP would, and the EXIT has reason
  `closed`. Tk always lists `WM_DELETE_WINDOW`, so this is for other X clients.
- A message box or simple dialog closed this way answers as its Cancel button
  would; one with no Cancel ignores it, as it would under a window manager.

CLOSE has no answer of its own. The result shows as a WINDOW without that
window, as an EXIT, or not at all. A CLOSE for an xid the run does not have, or
for a run that is not current, is ignored.

### 6.11 PING (0x05) and PONG (0x88), v1

Payload `{}` both ways. PONG carries PING's id. The agent answers PING in any
state, ahead of other work pending in its poll loop. Nothing a program does to the
X server can delay it, since the agent's X connection has a thread of its own.

### 6.12 CREDIT (0x89, agent to host, v1)

| Field | Type | Meaning |
| --- | --- | --- |
| `bytes` | integer 1 to 16,384 | Bytes the agent has read from ttyS1 since its last CREDIT. |

id 0. See section 7.

### 6.13 STDIN (0x03, host to agent, later)

Raw bytes for the program's stdin, for a RUN with `stdin: true`. An empty
payload closes it. It is credit-gated like every host frame, and it is the only
host message that could fill the credit window. A v1 host never sends it, and a
v1 agent answers it with ERROR `unsupported`.

### 6.14 LOG (0x8F, agent to host, v1)

| Field | Type | Meaning |
| --- | --- | --- |
| `level` | `"debug"`, `"info"`, `"warn"` or `"error"` | |
| `message` | string | English, for developers. |

id 0, or a run id when it is about a run that has not had its EXIT (6.3): a LOG
about a run after that, such as the background reap of a killed program, carries
id 0 and names the run in its message. The host writes LOG to the developer
console; it never reaches the student. The agent sends at most 20 a second and
folds the rest into a count in the next one.

### 6.15 ERROR (0x87, agent to host, v1)

| Field | Type | Meaning |
| --- | --- | --- |
| `code` | token | See below. A host MUST treat a code it does not know as `internal`. |
| `message` | string | English, for developers. |

The agent could not do what a frame asked. ERROR is always a harness failure,
never the student's mistake. Its id is the frame it answers, or 0 when it
answers none.

| code | Meaning |
| --- | --- |
| `bad_request` | The payload is invalid (5.3). |
| `unknown_type` | No such message type. |
| `busy` | RUN or PREPARE while a run is current. |
| `bad_files` | A RUN file is missing, or the files exceed 8 MiB. |
| `unsupported` | Valid, but not in this version: RUN with `stdin: true`, and STDIN. |
| `spawn_failed` | The program could not be started. |
| `refused` | PREPARE on an agent that has prepared already. |
| `internal` | Anything else. |

### 6.16 PREPARE (0x10, host to agent, build)

| Field | Type | Meaning |
| --- | --- | --- |
| `resident` | array of string | 0 to 1,024 absolute paths, read back into the page cache last. |
| `reserve_mib` | integer 0 to 1,024 | Free memory in MiB left unzeroed. |

Turns a freshly booted guest into the machine that ships. The agent sets up its
tmpfs mounts, starts Xorg, spawns and warms the interpreter, remounts `/`
read-only, drops caches, zero-fills free memory except `reserve_mib`, reads back
whole every file Xorg and the warm interpreter map and then the `resident` files,
creates the run's cgroup with a memory budget of what is left (6.6), flushes its
credit (section 7) and sends PARKED. It also LOGs what it measured on
the way, at level `info`.

A second PREPARE gets ERROR `refused`, and one during a run gets `busy`. It takes
seconds (the spike's warm-up alone took 7.7 s), and the agent may answer PING
late while it zero-fills memory, so the pipeline waits for PARKED on a long
deadline of its own instead of the watchdog's.

### 6.17 PARKED (0x90, agent to host, build)

| Field | Type | Meaning |
| --- | --- | --- |
| `warm` | bool | The warm interpreter is waiting. The pipeline MUST NOT save a state without it. |
| `mem_total_kb` | u32 | `MemTotal`. |
| `mem_available_kb` | u32 | `MemAvailable` after zeroing and read-back. |
| `zeroed_kb` | u32 | Memory zero-filled. |
| `resident_kb` | u32 | Bytes of `resident` read back. |

PREPARE is done and the machine can be saved. The pipeline MUST NOT send
anything between PARKED and `save_state()`, so the snapshot holds an agent with
an empty receive buffer that owes no credit. Section 7 depends on it.

## 7. Flow control

Host to agent is credit-based, because the guest's tty drops what it has no room
for.

- The host has 16,384 bytes of credit when the emulator is constructed and after
  every restore.
- Every byte the host writes to ttyS1 costs one credit: the encoded frame, its
  delimiter, and any extra `0x00`.
- The host writes a frame only when its credit covers all of it, and always
  writes it whole. Otherwise the frame waits in a queue, and frames leave the
  queue in order; nothing overtakes.
- The agent counts every byte it reads from ttyS1, garbage and delimiters
  included. It sends CREDIT once 4,096 bytes are unreported, and MAY send it
  sooner. It MUST report everything it has read before it sends PARKED.
- The host adds `bytes` to its credit, never going past 16,384, and writes what
  now fits.
- On a restore the host resets its credit to 16,384 and discards its queue. The
  agent it was talking to no longer exists, and the restored one owes nothing,
  by the PARKED rule.

16 KiB is a quarter of the 64 KiB burst that arrived intact. In v1 only small
control frames go this way, so the window never fills; it is there for STDIN.
`CreditedSender` in `vm_protocol.js` is the host's side.

Agent to host needs no credit, since v86 delivers every byte to the listener.
The agent bounds its own output instead: output batching, the output cap, WINDOW
coalescing and the LOG rate limit. The host collects the bytes of one v86 slice
and decodes them in one call, so Dart hears about each frame once rather than
about each byte.

## 8. Sequences

`#n` is the frame's id.

Build (the image pipeline, once per image):

```text
agent starts              <- 00, READY#0 {warm:false, python:null, tk:null}
HELLO#1 ->                <- READY#1
PREPARE#2 ->              <- CREDIT#0 (the flush), PARKED#2 {warm:true}
save_state(), with nothing sent after PARKED
```

Load (every page):

```text
construct v86 with no BIOS and no kernel; restoreSnapshot(); run()
HELLO#n ->                <- READY#n {warm:true}      warm:false is a broken image
emulator.stop()           parked; the host reports ready, with python and tk
```

Run:

```text
resume
HELLO#a ->                <- READY#a
create_file("/icc/in/r<b>-main.py"), one per file
RUN#b ->                  <- STARTED#b
                          <- STDOUT#b, STDERR#b, WINDOW#b, HINT#b, in any order
                          <- EXIT#b
park: restoreSnapshot(), then emulator.stop()
```

Stop:

```text
stop(): the run has ended, as far as the caller knows
STOP#b ->                 <- EXIT#b {reason:"stopped"}, or nothing within 500 ms
park
```

## 9. Host state machine

This section binds the host, `web/vm/vm_run.js` behind `vm_host.js`. The agent
sees none of it.

### 9.1 States

| State | CPU | Meaning |
| --- | --- | --- |
| `unloaded` | none | Nothing constructed yet. |
| `loading` | varies | Manifest, assets, construction, the first restore and the load-time HELLO. |
| `parked` | stopped | Restored and waiting. No run. |
| `starting(r)` | running | Run r was asked for. HELLO, the files and RUN are under way; STARTED has not arrived. |
| `running(r)` | running | STARTED arrived. |
| `stopping(r)` | running | r has ended for the caller. STOP was sent, and the host is waiting for its EXIT. |
| `parking` | stopped after | Restoring the snapshot, then stopping the CPU. |
| `failed(reason)` | stopped | The host cannot run programs. A failed load is tried again on the next `load()` or `run()`; after the machine was ready, only a new host leaves this state. |
| `destroyed` | none | `destroy()` was called. |

Visibility is not a state. The CPU also stops while the page is hidden (9.6).

### 9.2 Transitions

| From | Event | Action | To |
| --- | --- | --- | --- |
| unloaded | `load()` | Fetch the manifest and check its versions, fetch the assets, construct, `restoreSnapshot()`, `run()`, send HELLO. | loading |
| loading | READY `{warm: true}` | `stop()`; report ready with `python` and `tk`. | parked |
| loading | READY `{warm: false}` | | failed(`broken`) |
| loading | the manifest names another protocol or state version | Checked before anything else downloads. | failed(`incompatible`) |
| loading | an asset fails to load, or fails the manifest's size or sha256 | Cache nothing that failed; delete a cached copy that failed, and fetch it once more. | failed(`network`) |
| loading | the restore throws | Drop the state, cached copy included. | failed(`broken`) |
| loading | a rootfs load fails (9.8) | | failed(`fetch`) |
| loading | HELLO deadline, first | Restore, send HELLO again. | loading |
| loading | HELLO deadline, second | Drop the state, cached copy included. | failed(`unresponsive`) |
| parked | `run(r)` | Resume, send HELLO. | starting(r) |
| starting(r) | READY | `create_file` for each file, then send RUN. | starting(r) |
| starting(r) | STARTED | Report started. | running(r) |
| starting(r) | ERROR with r's id | End r as `broken`. | parking |
| starting(r) | HELLO or RUN deadline, first | Park, then start r again with the same run id. The restore removed its files, so they are written again. | parking |
| starting(r) | HELLO or RUN deadline, second | End r as `unresponsive`. | parking, then failed(`unresponsive`) |
| running(r) | STDOUT, STDERR, WINDOW, HINT | Report them. | running(r) |
| running(r) | EXIT | End r with the EXIT's reason, code, signal, truncated and ms. | parking |
| running(r) | PONG deadline | End r as `unresponsive`. | parking |
| starting(r), running(r) | `stop()` | End r as `stopped` at once. Send STOP if RUN was sent. | stopping(r) if RUN was sent, else parking |
| starting(r), running(r) | `run(s)` | As `stop()`, and queue s. | stopping(r) or parking |
| stopping(r), parking | `run(s)` | Queue s. A run queued already ends as `stopped` without starting. | unchanged |
| stopping(r) | EXIT for r, or 500 ms after STOP | Drop the EXIT. | parking |
| starting, running, stopping | a rootfs load fails (9.8) | End the run as `fetch`, unless it has ended. | parking |
| starting, running | READY with id 0 | End the run as `broken`: the agent restarted. | parking |
| parking | restore done | Reset the decoder, the credit, the open conversations and the run's text decoders; `stop()`. Start the queued run, if any. | parked, or starting(s) |
| parking | the restore throws | Destroy the emulator, construct a new one from the cached assets and restore. If that fails too, failed(`broken`). | parked |
| any | `destroy()` | End the current run and any queued run as `stopped`, destroy the emulator. | destroyed |
| any | a newer `openVm()` on the page | As `destroy()`, then report failed(`replaced`). | destroyed |

`closeWindow(xid)` in running(r) sends CLOSE and changes nothing else; in any
other state it does nothing. `stop()` outside starting and running does nothing
either, apart from ending a queued run as `stopped`. `run()` in unloaded or
loading queues the run and loads first, so a Run pressed during the download
starts once the machine is ready. A load that failed is tried again by the next
`load()` or `run()`; in failed after the machine was ready, or in destroyed, the
run ends at once as `broken`.

### 9.3 How a run ends

The host reports every run it accepted as ended exactly once, with one of these
reasons:

| Reason | Source | code and signal |
| --- | --- | --- |
| `exit` | EXIT | from EXIT |
| `closed` | EXIT | from EXIT |
| `oom` | EXIT | from EXIT |
| `stopped` | the host: `stop()`, a newer `run()`, `destroy()` | null |
| `unresponsive` | the host's watchdog (9.7) | null |
| `fetch` | the host: a rootfs file could not be loaded (9.8) | null |
| `broken` | the host: the agent refused the run with ERROR, restarted, or sent an invalid message about it | null |

An EXIT with reason `stopped` never reaches the caller: the host ended the run
itself when it sent STOP.

A failed host has one of `network`, `incompatible`, `fetch`, `unresponsive` and
`broken` as its reason, and one that a newer `openVm()` destroyed has `replaced`.

### 9.4 Park

A park is `restoreSnapshot()` followed by `emulator.stop()`. Every run ends in a
park, however it ended, because the warm interpreter is single-use and a restore
is what brings it back. Nothing in the guest can block a restore: it is JS
replacing the machine's memory and devices.

A restore is a synchronous main-thread task. v86 decompresses a zstd state
inside it, which took 115 to 150 ms at 1× and 481 to 536 ms at 4× CPU
throttling in Chrome. The host therefore decompresses the state once per page,
in a worker, and restores the raw state: 19 to 50 ms at 1×, 89 to 132 ms at 4×
and 155 to 191 ms at 6× (docs/vm-build.md, "Measurements"). The host SHOULD
start a park only after the caller has heard that the run ended and a frame has
painted, so the Run button's change is on screen before the page freezes.

### 9.5 Stop

- `stop()` ends the run for the caller at once. The UI never waits on the guest.
- If RUN was sent, the host sends STOP and parks on the run's EXIT or 500 ms
  after STOP, whichever is first. The 500 ms is wall-clock time, not watchdog
  time: running out of it is no failure, since a park needs nothing from the
  guest.
- If RUN was not sent yet, the host sends neither RUN nor any remaining file,
  and parks.

The restore would end the program regardless. STOP is still sent so that the
agent's kill path is exercised on every stop and measured by the corpus, and
because a later version may keep a machine whose program ended cleanly instead
of restoring it.

### 9.6 Visibility (F2)

- The page is visible when `document.visibilityState` is `visible`. Under Node
  there is no document, and the tool calls `setVisible(false)` and
  `setVisible(true)` itself.
- When the page is hidden in starting, running or stopping, the host stops the
  CPU. When it is visible again, the host resumes it. The run is untouched:
  nothing is sent and nothing ends.
- A parked machine's CPU is stopped already, and visibility changes nothing.
- The host stops the guest's clock with its CPU: every stop records the TSC and
  every start writes it back, the way QEMU stops kvmclock across a stop. Left
  running, v86's TSC would count the whole hidden time at once on the resume,
  and every `after()` and `time.sleep()` in flight would end at that moment.
- `CLOCK_MONOTONIC` therefore leaves the hidden time out, and `CLOCK_REALTIME`
  falls behind by it. The host sends HELLO after a resume from hidden in
  starting, running or stopping, without a deadline, and the agent puts the wall
  clock right. A Tcl `after()` counts on the wall clock, so one that was waiting
  fires at once, as it would after a laptop's sleep.
- A parked machine is always resumed with a HELLO (8), so F6's long park needs
  nothing more: the corpus checks that a run after 15 minutes parked has the
  right time, working timers, and no soft-lockup or RCU stall on the console.

### 9.7 Watchdog (F2)

| Deadline | Duration |
| --- | --- |
| HELLO to READY | 1,000 ms |
| RUN to STARTED | 2,000 ms |
| PING, sent while running, every | 2,000 ms |
| PING to PONG | 1,000 ms |

Deadlines run on **active time**, never on wall-clock time. The host samples
every 100 ms. A sample adds the time since the sample before it, capped at
100 ms, and only if at that moment:

- the page is visible, and
- the CPU is running (`emulator.is_running()`).

Otherwise it adds nothing. When the last of the two holds goes, the armed
deadline starts again from zero: a guest that has just got its CPU back gets the
whole allowance to answer.

A rootfs load in flight (9.8) suspends the count instead. Samples taken while one
is in flight add nothing, and once the last one lands the count goes on from
where it stood; it does not start again. Were every load to restart it, an agent
that has hung while its guest goes on reading files, one every half second say,
would never run out of time. One deadline is suspended for at most
30 s of loads in all, as long as one fetch attempt may take; past that, time
with a load in flight counts like any other. Every newly armed deadline, the one
a PONG arms included, gets 30 s of its own.

A stopped CPU, for a hidden tab or a park, adds nothing, so a backgrounded tab
cannot produce `unresponsive`: F2 follows from how active time is defined, with
no special case for it. The 100 ms cap on a sample covers the other way a guest
can lose time that is not its fault. While the page's main thread is busy with something else
(Flutter's layout, a GC, a restore), timers do not fire and v86 does not run
either; the sample that finally fires late adds 100 ms, not the length of the
gap.

Strikes:

- In loading and starting, the first expiry parks and tries again: the same
  HELLO, or the same run. A second expiry in a row is failed(`unresponsive`),
  and a run in progress ends as `unresponsive`.
- In running, a PONG expiry ends the run as `unresponsive` and parks. It counts
  as a strike: if the next deadline expires too, the host fails.
- Any answer in time resets the count.

### 9.8 Rootfs load failures (F3)

v86 loads a rootfs file the first time the guest reads it: `lib/filesystem.js`
calls `ServerFileStorageWrapper.load_from_server` in
`src/browser/filestorage.js`. On a 4xx status that load never settles: v86 logs
it and stops. On a 5xx or a network error it retries forever with a growing
delay (`src/lib.js`). Under Node a missing file rejects inside `load_file`, and
the load again never settles. Every time, the guest's 9p read never returns. The
program hangs inside it while the agent, which is not blocked, keeps answering
PING, so the watchdog cannot see it.

The host therefore replaces `load_from_server` on the storage instance,
`emulator.fs9p.storage`, before the first restore:

- It fetches `<baseurl><sha256>.zst` itself.
- A failure is any status but 200, a network error, a body that does not
  decompress, or no complete response within 30 s.
- It keeps up to 16 MiB of files the guest has closed, where v86 would drop each
  one on close, so a run does not fetch again what an earlier run of the page
  fetched.
- A network error or a 5xx is retried once, 1 s later. A 4xx is not: a deploy
  that replaced the image will not bring the file back.
- Every final failure goes to the state machine: failed(`fetch`) in loading;
  otherwise the run ends as `fetch` 50 ms later and the host parks. The 50 ms
  lets through what the program printed before the read, which can wait 16 ms
  in the agent's output batch. The host stays usable after that park, since the
  next run may not need the file, or the network may be back.
- **Stale loads.** A load that settles after a restore MUST NOT resolve into the
  restored machine. v86's 9p handler would send the reply to a request the
  restored guest never made (`lib/9p.js`: `await this.fs.Read(...)`, then
  `SendReply`). The host tags each load with the restore it started under, and
  leaves the promise of a load from an earlier one unsettled. It may keep the
  data.
- While any load is in flight the watchdog's count is suspended, for at most
  30 s per deadline (9.7). A slow network is not an unresponsive guest; the cap
  bounds how long an unresponsive one can pass for a slow network.

Like `restoreSnapshot()`, this reaches into v86 internals, so it is pinned to
the bundled v86 build and held in place by the pipeline's tests.

## 10. Versions, and what comes later

The version byte in every frame is the only protocol version; HELLO and READY
carry none. The image manifest records it as `agentProto`, and the host refuses
an image with another one before it constructs anything (failed(`incompatible`)).
A frame with another version is dropped as `version` (2.5). A host that sees
such frames from the agent reports the image as incompatible rather than waiting
for a deadline.

Within a version a field may be added, because receivers ignore keys they do
not know. Anything else is a new version: a new required field, a new EXIT
reason, a new meaning for an existing field.

**later:**

- STDIN and RUN with `stdin: true`, with HINT `stdin_unavailable` for a program
  that reads stdin when none was given.
- HINT `output_truncated`, sent the moment the cap is reached.
- A `focused` field on WINDOW entries.
- Files in subdirectories, and reading back the files a program wrote.
- A keyboard layout in HELLO. v1 is US only (decision 6).
- The clipboard, both ways.
- Screen sizes other than 800 x 600.
- Keeping a machine whose program ended cleanly instead of restoring it.

## 11. Fixtures

`fixtures/` holds the vectors both codecs are tested against. `gen_fixtures.py`
writes them from this document with its own COBS and zlib's CRC, and shares no
code with either codec. To change the protocol: change this document and the
generator, run `just gen-vm-fixtures`, then make both codecs pass.

| File | Contents |
| --- | --- |
| `protocol.json` | Version, limits, credit numbers, file-name pattern and the type table. |
| `crc32.json` | CRC-32 vectors, as a number and as the bytes in a frame. |
| `cobs.json` | Round trips, the 254-byte boundary included; encodings a decoder MUST accept and an encoder MUST NOT produce; invalid encodings. |
| `messages.json` | One canonical frame per message, every type included: the message, the frame before COBS (`raw_hex`) and the wire bytes (`frame_hex`). Decoding `frame_hex` MUST give the message, and encoding the message MUST give `frame_hex`. |
| `messages-invalid.json` | Good frames that are invalid messages, with the error (5.3) and the field at fault. |
| `messages-tolerated.json` | Non-canonical payloads a receiver MUST accept, and the canonical frame each one encodes back to. |
| `stream.json` | Byte streams in chunks, and the events a receiver MUST produce for them: splits, several frames in one read, empty chunks, garbage, every drop reason, and both size limits exactly at the edge and one byte past it. The same bytes split anywhere else MUST give the same events. |

The JS codec runs them with `just test-vm`, from
`vm/tools/test/vm_protocol.test.mjs` beside the host's own tests, so that no
test ships under `web/`. The agent runs them from its own tests, reading
`../protocol/fixtures/` relative to its crate. CI runs both.

## 12. Notes for implementers

Rust:

- Declare serde struct fields in table order, so the output is canonical. Give
  `Option<T>` fields no `skip_serializing_if`, so `None` goes out as `null`.
  Give an empty body a braced struct, `struct Ping {}`: a unit struct
  serializes as `null`, not `{}`. Do not use `deny_unknown_fields`.
- `serde_json::from_slice` already rejects invalid UTF-8 and a byte-order mark,
  as the JS decoder does, so both call those `bad_json`.
- A derived `Deserialize` also accepts a JSON array for a struct: `[]` becomes
  `Ping {}`, and `[1, true]` fills fields by position. Check that the payload is
  an object first (`not_object`). Types alone also miss every range, pattern and
  cross-field rule: `entry` among `files`, file-name and zone patterns, hex
  `entropy`, exactly one of `code` and `signal`, the enum strings, `bytes` of at
  least 1, at most one `root`, the list lengths. `messages-invalid.json` has a
  case for each.
- The CRC check is `crc32fast::hash(&raw[..raw.len() - 4])` against
  `u32::from_le_bytes` of the last four bytes.
- COBS is about twenty lines, and the pseudocode in 2.3 is all it needs. A crate
  is fine if it passes `cobs.json`: the 254-byte vector is where encoders
  differ.
- The crate is built with Alpine 3.22's Rust 1.87 inside the image build, so it
  has to stay within that version.

JS:

- `vm_protocol.js` exports `FrameDecoder` (reset it on every restore),
  `decodeMessage(frame, {from: 'agent'})`, `encodeMessage(message)`,
  `CreditedSender`, `inFilePath(runId, name)` and the constants.
- `encodeMessage` throws on anything the agent would refuse, so a host bug shows
  up as an exception on the page rather than as an ERROR from the guest.
