//! The one place a micro:bit is held open.
//!
//! A device cannot live in anything a flutter_rust_bridge call returns, so it
//! sits on [`run`]'s stack and everything else reaches it through a queue. See
//! `docs/microbit-usb.md`.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

use crate::dap::adi::ArmDebug;
use crate::dap::cmsis::CmsisDap;
use crate::daplink::serial;
use crate::device::{read_board_report, restart_for_serial, BoardReport};
use crate::platform::sleep;
use crate::transport::usb::{list_microbits, UsbTransport};
use crate::transport::TransportError;

/// What a caller can ask the session to do.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SessionCommand {
    /// Open the first board this origin can see and report on it.
    Connect,
    /// Let go of it. The session keeps running and can connect again.
    Disconnect,
    /// Start the board over: a hard reset, so it boots and runs `main.py` again.
    Restart,
    /// Send bytes to the target's UART, verbatim.
    Write(Vec<u8>),
    /// End the session. [`run`] returns after this.
    Stop,
}

/// What the session tells whoever is listening.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SessionEvent {
    Connected(Box<BoardReport>),
    /// Bytes the target printed, in order.
    ///
    /// Not text: MicroPython can split one UTF-8 sequence across two reads, so
    /// the caller decodes the stream.
    Serial(Vec<u8>),
    Disconnected,
    Failed(TransportError),
}

/// Commands waiting to be picked up.
///
/// Polled rather than a channel: waking a task from another worker thread posts
/// a microtask on the wrong queue.
static QUEUE: Mutex<VecDeque<SessionCommand>> = Mutex::new(VecDeque::new());

/// Which session is the live one.
///
/// A screen opened twice would otherwise leave two loops fighting over one
/// board. A loop stops once it no longer holds the highest number.
static GENERATION: AtomicU64 = AtomicU64::new(0);

/// How long the loop waits between polls: short while output is arriving,
/// longer once it stops.
const POLL_BUSY_MS: u32 = 15;
const POLL_IDLE_MS: u32 = 75;
/// Nothing is connected, so the only thing to watch for is a command.
const POLL_DISCONNECTED_MS: u32 = 150;

/// How long the firmware takes to start reading its UART after a reset. A byte
/// sent before that is lost.
const BOOT_MS: u32 = 500;

/// Puts a command in the queue. Returns as soon as it is in, not when it is done.
pub fn send(command: SessionCommand) {
    if let Ok(mut queue) = QUEUE.lock() {
        queue.push_back(command);
    }
}

/// Takes everything waiting, leaving the queue empty.
fn take_commands() -> Vec<SessionCommand> {
    match QUEUE.lock() {
        Ok(mut queue) => queue.drain(..).collect(),
        Err(_) => Vec::new(),
    }
}

/// Runs one session until [`SessionCommand::Stop`], or until a newer session
/// takes over.
///
/// `emit` returns false once nobody is listening, which ends the session.
pub async fn run(mut emit: impl FnMut(SessionEvent) -> bool) {
    let generation = GENERATION.fetch_add(1, Ordering::SeqCst) + 1;

    // Commands left by the previous session were meant for a board this one has
    // not opened.
    let _ = take_commands();

    let mut board: Option<ArmDebug<UsbTransport>> = None;
    let mut interval = POLL_DISCONNECTED_MS;

    loop {
        if GENERATION.load(Ordering::SeqCst) != generation {
            return;
        }

        for command in take_commands() {
            match command {
                SessionCommand::Stop => {
                    return;
                }
                SessionCommand::Disconnect => {
                    board = None;
                    interval = POLL_DISCONNECTED_MS;
                    if !emit(SessionEvent::Disconnected) {
                        return;
                    }
                }
                SessionCommand::Restart => {
                    if let Some(open) = &mut board {
                        start_board(open).await;
                        interval = POLL_BUSY_MS;
                    }
                }
                SessionCommand::Connect => match open().await {
                    Ok((mut opened, report)) => {
                        // Before start_board, so the banner it produces
                        // arrives under the board it belongs to.
                        if !emit(SessionEvent::Connected(Box::new(report))) {
                            return;
                        }

                        start_board(&mut opened).await;

                        board = Some(opened);
                        interval = POLL_BUSY_MS;
                    }
                    Err(error) => {
                        board = None;
                        interval = POLL_DISCONNECTED_MS;
                        if !emit(SessionEvent::Failed(error)) {
                            return;
                        }
                    }
                },
                SessionCommand::Write(data) => {
                    if let Some(open) = &mut board {
                        if serial::write(open.dap(), &data).await.is_err() {
                            board = None;
                            interval = POLL_DISCONNECTED_MS;
                            if !emit(SessionEvent::Disconnected) {
                                return;
                            }
                        } else {
                            // Something was typed, so an answer is coming.
                            interval = POLL_BUSY_MS;
                        }
                    }
                }
            }
        }

        if let Some(open) = &mut board {
            match serial::read_drain(open.dap()).await {
                Ok(bytes) if bytes.is_empty() => interval = POLL_IDLE_MS,
                Ok(bytes) => {
                    interval = POLL_BUSY_MS;
                    if !emit(SessionEvent::Serial(bytes)) {
                        return;
                    }
                }
                Err(_) => {
                    // The cable came out, or something else took the interface.
                    // The session stays up so the reader can plug in again.
                    board = None;
                    interval = POLL_DISCONNECTED_MS;
                    if !emit(SessionEvent::Disconnected) {
                        return;
                    }
                }
            }
        }

        sleep(interval).await;
    }
}

/// Restarts the board and breaks into its MicroPython prompt.
///
/// The only place in this crate that assumes the target runs MicroPython.
async fn start_board(board: &mut ArmDebug<UsbTransport>) {
    // MUST come before the restart, whose output is the point of it.
    let _ = serial::discard_buffered(board.dap()).await;
    let _ = restart_for_serial(board).await;

    // Unconditional. Sending Ctrl-C only when no prompt appears would mean
    // recognising one in the output, and a running program can print `>>> `.
    // See `docs/microbit-usb.md`.
    sleep(BOOT_MS).await;
    let _ = serial::write(board.dap(), b"\x03").await;
}

/// Opens the first board this origin can see.
async fn open() -> Result<(ArmDebug<UsbTransport>, BoardReport), TransportError> {
    let devices = list_microbits().await?;
    let device = devices.first().ok_or(TransportError::NoDevice)?;

    let usb_serial = device.serial_number().map(str::to_string);
    let transport = UsbTransport::open(device).await?;
    let mut debug = ArmDebug::new(CmsisDap::new(transport));

    let report = read_board_report(&mut debug, usb_serial.as_deref())
        .await
        .map_err(|error| TransportError::Io(error.to_string()))?;

    Ok((debug, report))
}
