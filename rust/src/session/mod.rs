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
use crate::dap::cortex_m::CortexM;
use crate::dap::DapError;
use crate::daplink::flash::full_flash;
use crate::daplink::serial;
use crate::device::{read_board_report, restart_for_serial, BoardReport, FlashLayout};
use crate::flash::image::{flash_image, uicr_entries};
use crate::flash::partial::{plan_flash, write_pages, FlashPlan};
use crate::flash::util::Page;
use crate::hex::builder::build_map;
use crate::hex::intel::{write as write_hex, HexMap};
use crate::platform::sleep;
use crate::transport::usb::{list_microbits, UsbTransport};
use crate::transport::TransportError;

/// What a caller can ask the session to do.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SessionCommand {
    /// Open the first board this origin can see and report on it.
    ///
    /// `interrupt` sends Ctrl-C once the board is up, which breaks into
    /// MicroPython's prompt. A screen that wants the board's own program to run
    /// MUST leave it false.
    Connect { interrupt: bool },
    /// Let go of it. The session keeps running and can connect again.
    Disconnect,
    /// Start the board over: a hard reset, so it boots and runs `main.py` again.
    Restart { interrupt: bool },
    /// Send bytes to the target's UART, verbatim.
    Write(Vec<u8>),
    /// Put `main_py` on the board, built into a copy of `firmware`.
    Flash { firmware: String, main_py: String },
    /// End the session with this id. Another session's is ignored.
    ///
    /// Addressed, because the queue is shared: a screen being disposed of would
    /// otherwise stop the session of the screen that replaced it.
    Stop { session: u64 },
}

/// What the session tells whoever is listening.
#[derive(Debug, Clone, PartialEq)]
pub enum SessionEvent {
    Connected(Box<BoardReport>),
    /// Bytes the target printed, in order.
    ///
    /// Not text: MicroPython can split one UTF-8 sequence across two reads, so
    /// the caller decodes the stream.
    Serial(Vec<u8>),
    Disconnected,
    /// How much of the flash the board does not already hold, worked out before
    /// anything is written.
    FlashPlan {
        changed: u32,
        total: u32,
    },
    /// The board could not say which pages differ. The flash goes ahead and
    /// writes all of them.
    FlashPlanUnknown {
        message: String,
    },
    /// How far a flash has got, between 0 and 1.
    FlashProgress(f32),
    /// The board has been written and has restarted.
    Flashed,
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

/// Runs one session until it is stopped by id, or until a newer session takes
/// over.
///
/// `session` is the caller's own id, which is what [`SessionCommand::Stop`]
/// names. `emit` returns false once nobody is listening, which also ends it.
pub async fn run(session: u64, mut emit: impl FnMut(SessionEvent) -> bool) {
    let generation = GENERATION.fetch_add(1, Ordering::SeqCst) + 1;

    // Commands left by the previous session were meant for a board this one has
    // not opened.
    let _ = take_commands();

    let mut board: Option<ArmDebug<UsbTransport>> = None;
    // What the board said about its own flash when it was opened. A flash is
    // planned against these.
    let mut layout: Option<FlashLayout> = None;
    let mut interval = POLL_DISCONNECTED_MS;

    loop {
        if GENERATION.load(Ordering::SeqCst) != generation {
            return;
        }

        for command in take_commands() {
            match command {
                SessionCommand::Stop { session: stopped } => {
                    if stopped == session {
                        return;
                    }
                }
                SessionCommand::Disconnect => {
                    board = None;
                    layout = None;
                    interval = POLL_DISCONNECTED_MS;
                    if !emit(SessionEvent::Disconnected) {
                        return;
                    }
                }
                SessionCommand::Restart { interrupt } => {
                    if let Some(open) = &mut board {
                        start_board(open, interrupt).await;
                        interval = POLL_BUSY_MS;
                    }
                }
                SessionCommand::Connect { interrupt } => match open().await {
                    Ok((mut opened, report)) => {
                        layout = Some(report.layout);

                        // Before start_board, so the banner it produces
                        // arrives under the board it belongs to.
                        if !emit(SessionEvent::Connected(Box::new(report))) {
                            return;
                        }

                        start_board(&mut opened, interrupt).await;

                        board = Some(opened);
                        interval = POLL_BUSY_MS;
                    }
                    Err(error) => {
                        board = None;
                        layout = None;
                        interval = POLL_DISCONNECTED_MS;
                        if !emit(SessionEvent::Failed(error)) {
                            return;
                        }
                    }
                },
                SessionCommand::Flash { firmware, main_py } => {
                    if let (Some(open), Some(layout)) = (&mut board, layout) {
                        match flash(open, layout, &firmware, &main_py, &mut emit).await {
                            Ok(true) => {}
                            // The listener went away part way through.
                            Ok(false) => return,
                            Err(error) => {
                                if !emit(SessionEvent::Failed(error)) {
                                    return;
                                }
                            }
                        }
                        interval = POLL_BUSY_MS;
                    }
                }
                SessionCommand::Write(data) => {
                    if let Some(open) = &mut board {
                        if serial::write(open.dap(), &data).await.is_err() {
                            board = None;
                            layout = None;
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
                    layout = None;
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

/// Builds a hex around `main_py` and writes it to the board.
///
/// Returns false when the listener has gone away.
async fn flash(
    board: &mut ArmDebug<UsbTransport>,
    layout: FlashLayout,
    firmware: &str,
    main_py: &str,
    emit: &mut impl FnMut(SessionEvent) -> bool,
) -> Result<bool, TransportError> {
    let map = build_map(firmware, &[("main.py", main_py.as_bytes())])
        .map_err(|error| TransportError::Io(format!("{error:?}")))?;

    // Whatever the old program was still printing belongs to a board that is
    // about to be replaced.
    let _ = serial::discard_buffered(board.dap()).await;

    if !write_flash(board, &map, layout, emit).await? {
        return Ok(false);
    }

    // Nothing is sent to the board afterwards. What was just written is meant to
    // run, and a Ctrl-C would stop it a moment after it started.
    Ok(emit(SessionEvent::Flashed))
}

/// Puts what `map` describes on the board, by whichever route is cheaper.
///
/// Page by page when only a little has changed, and the whole hex through
/// DAPLink otherwise. The board is running the new program when this returns.
///
/// Returns false when the listener has gone away.
async fn write_flash(
    board: &mut ArmDebug<UsbTransport>,
    map: &HexMap,
    layout: FlashLayout,
    emit: &mut impl FnMut(SessionEvent) -> bool,
) -> Result<bool, TransportError> {
    let image = flash_image(map, layout.total_bytes());
    let uicr = uicr_entries(map);

    let survey = match survey(board, &image, &uicr, layout).await {
        Ok(survey) => {
            let event = SessionEvent::FlashPlan {
                changed: survey.plan.changed.len() as u32,
                total: survey.plan.total as u32,
            };
            if !emit(event) {
                return Ok(false);
            }
            Some(survey)
        }
        Err(error) => {
            let event = SessionEvent::FlashPlanUnknown {
                message: error.to_string(),
            };
            if !emit(event) {
                return Ok(false);
            }
            None
        }
    };

    if let Some(survey) = survey.filter(|survey| route(Some(survey)) == Route::Pages) {
        let mut listening = true;

        let written = write_partial(board, &survey.plan.changed, layout.page_size, &mut |fraction| {
            listening &= emit(SessionEvent::FlashProgress(fraction));
        })
        .await;

        match written {
            Ok(()) => return Ok(listening),
            // The board now holds some of the new program and some of the old,
            // which only writing all of it repairs. Needs a board to reach, so
            // no test covers it.
            Err(_) => {
                board.reset_state();
            }
        }
    }

    write_whole_hex(board, map, emit).await
}

/// Writes the whole hex through DAPLink's own flash commands.
async fn write_whole_hex(
    board: &mut ArmDebug<UsbTransport>,
    map: &HexMap,
    emit: &mut impl FnMut(SessionEvent) -> bool,
) -> Result<bool, TransportError> {
    let hex = write_hex(map);

    let mut listening = true;
    full_flash(board.dap(), &hex, |fraction| {
        listening &= emit(SessionEvent::FlashProgress(fraction));
    })
    .await
    .map_err(|error| TransportError::Io(error.to_string()))?;

    // DAPLink resets the board itself, so this layer's idea of the target is
    // stale and the new program is already starting.
    board.reset_state();

    Ok(listening)
}

/// What asking the board turns up before anything is written.
#[derive(Debug, Clone, PartialEq, Eq)]
struct Survey {
    plan: FlashPlan,
    /// Whether the board's UICR already holds what the hex says it should.
    uicr_matches: bool,
}

/// How a flash is written.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Route {
    /// Only the pages that differ, over SWD.
    Pages,
    /// The whole hex, through DAPLink's own flash commands.
    WholeHex,
}

/// Which route a flash takes, given what the board said.
///
/// Three things send it down the whole hex, and they differ in kind. Past half
/// the flash, writing page by page is slower than letting DAPLink erase and
/// program the lot. A UICR that does not match is something writing pages cannot
/// fix at all, because it writes flash and UICR is not flash. And a survey that
/// failed says nothing, which is not the same as saying nothing differs.
fn route(survey: Option<&Survey>) -> Route {
    match survey {
        Some(survey) if survey.plan.worth_partial() && survey.uicr_matches => Route::Pages,
        _ => Route::WholeHex,
    }
}

/// Asks the board which pages of `image` it does not already hold.
///
/// Halts the target and overwrites its RAM to do it, so the caller MUST be about
/// to flash. It leaves SWD disconnected again, which is what DAPLink's own flash
/// commands expect.
async fn survey(
    board: &mut ArmDebug<UsbTransport>,
    image: &[u8],
    uicr: &[(u32, u32)],
    layout: FlashLayout,
) -> Result<Survey, DapError> {
    board.connect().await?;

    let result = survey_connected(board, image, uicr, layout).await;

    let _ = board.disconnect().await;

    result
}

async fn survey_connected(
    board: &mut ArmDebug<UsbTransport>,
    image: &[u8],
    uicr: &[(u32, u32)],
    layout: FlashLayout,
) -> Result<Survey, DapError> {
    // The blob runs on the target, so the target has to be a clean machine
    // first. See `CortexM::reset_and_halt`.
    CortexM::new(board).reset_and_halt().await?;

    let plan = plan_flash(board, image, layout.page_size, layout.page_count).await?;

    let mut uicr_matches = true;
    for (address, value) in uicr {
        if board.read_mem32(*address).await? != *value {
            uicr_matches = false;
            break;
        }
    }

    Ok(Survey { plan, uicr_matches })
}

/// Writes only the pages the board does not already hold.
async fn write_partial(
    board: &mut ArmDebug<UsbTransport>,
    pages: &[Page],
    page_size: u32,
    on_progress: &mut impl FnMut(f32),
) -> Result<(), DapError> {
    board.connect().await?;

    let written = write_pages(board, pages, page_size, on_progress).await;

    // The last page left the processor at the blob's breakpoint, and nothing
    // else is going to start it.
    if written.is_ok() {
        CortexM::new(board).reset().await?;
    }

    let _ = board.disconnect().await;

    written
}

/// Restarts the board, and breaks into its MicroPython prompt if asked to.
///
/// The interrupt is the only place in this crate that assumes the target runs
/// MicroPython, and it is what a REPL wants and a program does not.
async fn start_board(board: &mut ArmDebug<UsbTransport>, interrupt: bool) {
    // MUST come before the restart, whose output is the point of it.
    let _ = serial::discard_buffered(board.dap()).await;
    let _ = restart_for_serial(board).await;

    if interrupt {
        // Unconditional. Sending Ctrl-C only when no prompt appears would mean
        // recognising one in the output, and a running program can print `>>> `.
        // See `docs/microbit-usb.md`.
        sleep(BOOT_MS).await;
        let _ = serial::write(board.dap(), b"\x03").await;
    }
}

/// How long a board that is still held is given to come free, and how often it
/// is asked. Four attempts is a little over two idle polls.
const BUSY_RETRY_MS: u32 = 150;
const BUSY_ATTEMPTS: usize = 4;

/// Opens the first board this origin can see.
///
/// A board that is held is retried. The session being replaced lets go on its
/// next poll and the screen that replaced it is already asking, which is one
/// poll interval, not a race. So is a hot restart, where the old session runs on
/// in the worker until it notices the new one. Another tab holding the board
/// still comes back as [`TransportError::Busy`], because no amount of waiting
/// fixes that.
async fn open() -> Result<(ArmDebug<UsbTransport>, BoardReport), TransportError> {
    for attempt in 0..BUSY_ATTEMPTS {
        match open_once().await {
            Err(TransportError::Busy) if attempt + 1 < BUSY_ATTEMPTS => sleep(BUSY_RETRY_MS).await,
            outcome => return outcome,
        }
    }

    Err(TransportError::Busy)
}

async fn open_once() -> Result<(ArmDebug<UsbTransport>, BoardReport), TransportError> {
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::flash::util::Page;

    fn survey(total: usize, changed: usize, uicr_matches: bool) -> Survey {
        Survey {
            plan: FlashPlan {
                total,
                changed: vec![
                    Page {
                        target_address: 0,
                        data: Vec::new(),
                    };
                    changed
                ],
            },
            uicr_matches,
        }
    }

    #[test]
    fn a_program_that_changed_a_little_is_written_page_by_page() {
        assert_eq!(route(Some(&survey(128, 5, true))), Route::Pages);
    }

    #[test]
    fn a_board_that_already_holds_it_is_written_page_by_page_too() {
        // Which writes no pages at all. Flashing the same thing twice should
        // cost nothing, not a whole hex.
        assert_eq!(route(Some(&survey(128, 0, true))), Route::Pages);
    }

    #[test]
    fn past_half_the_flash_daplink_does_it() {
        assert_eq!(route(Some(&survey(128, 64, true))), Route::Pages);
        assert_eq!(route(Some(&survey(128, 65, true))), Route::WholeHex);
    }

    #[test]
    fn a_uicr_that_does_not_match_takes_the_whole_hex_however_little_changed() {
        // Writing pages cannot repair UICR, and DAPLink writes it from the hex.
        assert_eq!(route(Some(&survey(128, 1, false))), Route::WholeHex);
    }

    #[test]
    fn a_board_that_could_not_be_asked_gets_the_whole_hex() {
        // Not knowing what differs is not the same as knowing nothing does.
        assert_eq!(route(None), Route::WholeHex);
    }
}
