# Talking to a micro:bit over USB

How the Rust core reaches a BBC micro:bit V2, and the hardware behaviour it has
to work around. The build itself is in [rust-core-build.md](rust-core-build.md).

The USB layer is ported from
[microbit-foundation/microbit-connection](https://github.com/microbit-foundation/microbit-connection)
(`packages/microbit-connection/src/usb/`, MIT), which is itself derived from
dapjs (Copyright Arm Limited 2018, Microsoft Corporation, MIT). Each Rust module
names the TypeScript file it came from.

## The layers

| Module | What it does |
|---|---|
| `transport/` | Opens the device and moves 64-byte packets. Knows no DAP commands. |
| `dap/cmsis.rs` | CMSIS-DAP framing: `DAP_Info`, `DAP_Transfer`, `DAP_TransferBlock`. |
| `dap/adi.rs` | SWD: the Debug Port, the Access Port, reading and writing target memory. |
| `dap/cortex_m.rs` | Halting, resuming and resetting the processor. |
| `daplink/` | DAPLink's own vendor commands: the unique id, the target's serial port. |
| `session/` | Holds one board open and serves a command queue. |

## Board ids

The first four hex characters of a DAPLink serial number are the board id.

| Version | Ids |
|---|---|
| V1 | `9900`, `9901` |
| V2 | `9903`, `9904`, `9905`, `9906` |

The micro:bit support docs list only `9903` and `9904`. Current V2.21 hardware
ships as `9906`, so a check written from those docs rejects a board bought
today.

The id is read over a DAPLink vendor command rather than off the USB descriptor,
because Chrome may anonymize `USBDevice.serialNumber` for anti-fingerprinting
([microbit-connection#57](https://github.com/microbit-foundation/microbit-connection/issues/57)).
The descriptor is the fallback. Which of the two answered is reported to the
screen, so the anonymization is visible when it happens.

## Two vendor-class interfaces, only one usable

A micro:bit V2 exposes six USB interfaces, two of them class `0xFF`:

```
#0 class=0x08 (mass storage)   #1 class=0x02 (CDC)   #2 class=0x0a (CDC data)
#3 class=0x03 (HID)            #4 class=0xff         #5 class=0xff
```

**Interface #4 has no endpoints.** Claiming it succeeds, so the mistake surfaces
later as transfers that go nowhere. The transport therefore selects the `0xFF`
interface that *has* bulk endpoints.

Upstream falls back to control transfers for an endpoint-less interface, which is
how a micro:bit V1 speaks CMSIS-DAP v1 over HID. That fallback is deliberately
not ported: a V1 cannot run the MicroPython this app flashes and is turned away
by board id first.

## CDC eats the first output after a physical connection

DAPLink offers the target's serial output two ways at once: as a CDC serial port,
and through a vendor read command. A browser cannot open a CDC port, so the app
uses the vendor command.

Both read from **one** UART ring buffer inside DAPLink. Whichever takes a byte
first has it; the other never sees it. DAPLink's CDC side drains that buffer on
its own, whether or not anything has the port open, so it eats the first bytes
after a physical connection and the app's reads come up short.
([ARMmbed/DAPLink#903](https://github.com/ARMmbed/DAPLink/issues/903))

Measured here on a V2.21: a 4-line MicroPython banner arrived with 58 bytes
missing from the front.

It stops once it cannot take any more. With nobody reading the CDC port its TX
buffer fills, `cdc_process_event()` then stops pulling from the UART ring buffer,
and that fills too. From there everything overflows past CDC and reaches the
vendor reads intact.

So the app fills both buffers on purpose, once, by sending 2048 bytes out of the
target's UART. Buffer sizes vary by interface chip: KL26/KL27 hold 64 + 64,
an nRF52820/nRF52833 1024 + 64. 2048 clears every known variant with room to
spare, and takes about 178 ms at 115200 baud.

The bytes are NUL, which a terminal ignores if something happens to be watching
the CDC port. They are sent by a UARTE DMA transfer set up over SWD, so the
halted processor is no obstacle.

## Why connecting halts and then hard-resets

`device::restart_for_serial` runs four steps, and the order is the whole point:

1. **Discard** whatever serial is already buffered. It was printed before anyone
   was watching.
2. **Halt** the processor. The next step writes over the running program's RAM.
3. **Saturate**, as above. The DMA buffer goes at `0x20000000`, the base of RAM.
4. **Hard reset.** The C startup runs again, which restores the initialised
   globals step 3 wrote over, and boots the board.

A *soft* reboot is not enough. MicroPython's soft reset reinitialises its heap
but not the C data section, so the corruption would survive it.

## Breaking into the REPL

After the reset the session waits 500 ms and sends `\x03`.

A board with a `main.py` boots straight into that program, and MicroPython prints
its banner only when the **REPL** starts. Without the interrupt a reader watches
an empty terminal indefinitely and has to know to press Ctrl-C themselves.

The interrupt is unconditional. Sending it only when no prompt appears would mean
recognising a prompt in the output, and a running program can print `>>> ` as
easily as anything else: the one time the guess is wrong is the one time the
interrupt was needed. The cost of being unconditional is one extra prompt line on
a board that had nothing to run.

The 500 ms covers the firmware coming up. The reset itself is already waited for;
a byte sent before MicroPython reads its UART is lost.

## The session holds the board, because a call cannot

flutter_rust_bridge hands every call to an arbitrary worker from a pool, and the
`JsValue` inside nusb's `Device` cannot be transferred between workers. A device
therefore cannot live in anything a call returns. It sits on the stack of
`session::run`, which does not return while a board is open, and everything else
reaches it through a queue.

The queue is polled rather than a channel. Waking a task from another worker
thread posts a microtask on the wrong queue, and the loop has to poll anyway
because DAPLink's serial read is itself a poll.

A generation counter stops two sessions fighting over one board when a screen is
opened twice.

## Serial reads drain

115200 baud is about 11.5 KB/s. One vendor read carries at most 62 bytes, so one
read per 15 ms poll retires only about 4 KB/s. A `print` in a loop would fall
further behind on every pass, so each poll reads until a read comes back short.

The read returns bytes, not text. MicroPython can split one UTF-8 sequence across
two reads, so decoding per read turns the second half into a replacement
character. Dart decodes the stream incrementally.

## No line discipline

The browser console needs one because CPython's basic REPL does no echo. The
micro:bit needs none: MicroPython echoes, edits and keeps history for itself, so
a second line discipline would double every character.

Only `cookOutput` is shared, which turns `\n` into `\r\n` the way a tty driver
would.

Ctrl-C reaches a real interpreter here and raises a real `KeyboardInterrupt`.
That is the opposite of the browser console, where wasm has no signals and Ctrl-C
can only restart the interpreter.
