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

Every micro:bit is **VID `0x0D28`, PID `0x0204`**, whatever its version. What
tells the versions apart is the board id: the first four hex characters of the
DAPLink serial number.

| Board id | Version | |
|---|---|---|
| `9900` | v1.3 | V1 |
| `9901` | v1.5 | V1 |
| `9903` | v2.0 (reserved) | V2 |
| `9904` | v2.0 | V2 |
| `9905` | v2.20 | V2 |
| `9906` | v2.21 | V2 |

There is no `9902`.
([micro:bit support](https://support.microbit.org/support/solutions/articles/19000035697-what-are-the-usb-vid-pid-numbers-for-micro-bit))

Note that a *different* support article, 19000119055, stops at `9904`. A check
written from that one rejects current V2.21 hardware.

The filesystem library normalises a V2 to `0x9903` before it will work with a
hex, so a `9906` has to be translated on the way in.

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

## Breaking into the REPL, and not breaking into a program

`Connect` and `Restart` carry an `interrupt` flag. When it is set, the session
waits 500 ms after the reset and sends `\x03`.

A board with a `main.py` boots straight into that program, and MicroPython prints
its banner only when the **REPL** starts. So a screen that wants the prompt has
to ask for it: without the interrupt a reader watches an empty terminal
indefinitely and has to know to press Ctrl-C themselves. A screen that wants the
board's own program to run must not send it, or the program is stopped half a
second after it started. That is the whole difference between the two micro:bit
screens.

Within that choice the interrupt is unconditional. Sending it only when no prompt
appears would mean recognising a prompt in the output, and a running program can
print `>>> ` as easily as anything else: the one time the guess is wrong is the
one time the interrupt was needed. The cost is one extra prompt line on a board
that had nothing to run.

A flash never sends it. What was just written is meant to run.

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

## Which pages a flash would change is asked of the board

The board can hash its own flash far faster than we can read it out: 512 KB over
one vendor read at a time is minutes, while the target does it in its own RAM.
So `flash/blobs.rs` carries an ARM Thumb program that hashes every page, and
`dap/cortex_m.rs::execute` uploads it to 0x20000000, points the processor at it
and waits for the breakpoint it ends on. The answer, two words per page, is read
back from 0x20002000.

The hash is a murmur3 pair, not a choice: the blob computes it, so
`flash/util.rs` has to compute exactly the same thing or every page looks
changed. The seeds are asserted in both files.

Running it costs whatever was in the target's RAM, and the processor is left
halted. That is why the session only does it as the first step of a flash, which
overwrites everything anyway.

The blob only reads flash. Nothing in it touches NVMC, so a mistake in the
register setup costs a wrong answer rather than a damaged board.

## Code only runs on a target that was reset into a halted state

`CortexM::reset_and_halt` sets DEMCR's `VC_CORERESET` before the reset, so the
processor stops at the reset vector instead of running from it. Every blob starts
from there.

Halting a running program is not the same thing and does not work. Its
peripherals keep running, its interrupts stay enabled, and the vector table still
points at handlers in flash — so the first interrupt to fire lands in a handler
whose stack and data the blob has just overwritten, and the processor never
reaches the breakpoint the debugger is waiting for. It fails intermittently,
which is what makes it worth writing down: whether it works depends on whether an
interrupt happened to fire.

`flashAsync` upstream opens the same way, for the same stated reason.

## Two routes to the same flash

A flash first asks the board which pages it does not already hold, then takes
whichever route is cheaper:

- **Page by page**, when at most half the pages differ. The `FLASH_PAGE` blob
  runs on the target and copies one page at a time out of RAM; the host stages
  the next page while the target is still writing the current one, which is what
  the two slots at `DATA_ADDRESS` are for. Writing a changed `main.py` touches
  five pages of 128, and that is seconds rather than twenty of them.
- **The whole hex**, through DAPLink's own flash commands, otherwise.

Three things send a flash down the second route, and all three are deliberate:

- More than half the flash differs, where writing page by page costs more than
  letting DAPLink erase and program the lot.
- The survey failed. Not knowing what differs is not the same as knowing nothing
  does.
- The board's UICR does not already hold what the hex says it should. A partial
  flash writes flash and nothing else, so it would leave UICR behind. Upstream
  repairs UICR in place where the bits allow it and erases it where they do not;
  this falls back instead, which is slower and cannot get it wrong.

A partial flash that fails part way leaves the board holding some of the new
program and some of the old, so it falls back to writing the whole hex. The
reverse fallback upstream has, a full flash failing over to a partial one, is
left out: DAPLink's own flashing not working is not a thing driving the target
ourselves is likely to fix.

Nothing here can leave a board that cannot be flashed again. DAPLink does its own
flashing without the target's help, and the USB drive is there whatever the chip
holds.
