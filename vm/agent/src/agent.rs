//! What the agent does with what reaches it over the line, without doing the I/O itself: bytes and
//! the time go in, the frames to write wait in the outbox, and work that needs the guest waits as
//! an [`Action`] until the event loop reports how it went.

use crate::entropy;
use crate::frame::{self, DropCounts, DropReason, Frame};
use crate::log_limit::LogLimit;
use crate::outbox::Outbox;
pub use crate::output::Stream;
use crate::output::{Chunk, Output};
use crate::proto::{
    self, Credit, ErrorBody, ErrorCode, Exit, ExitReason, Hello, Hint, Invalid, Level, Log, Message, Parked, Prepare,
    Ready, Run, Side, Started, Window, WindowEntry,
};
use std::collections::VecDeque;
use std::path::Path;
use std::time::{Duration, Instant};

/// README section 2.5: the agent reports its own drops at most once a second.
const DROP_REPORT_INTERVAL: Duration = Duration::from_secs(1);

const ZONEINFO: &str = "/usr/share/zoneinfo";
const FALLBACK_ZONE: &str = "UTC";

/// Work that needs the guest. The event loop takes it with [`Agent::take_action`] and reports back
/// through the `on_*` methods.
#[derive(Debug, Clone, PartialEq)]
pub enum Action {
    /// Answered by [`Agent::on_prepared`].
    Prepare { id: u32, request: Prepare },
    /// Answered by [`Agent::on_started`] or [`Agent::on_refused`], and once started by
    /// [`Agent::on_exit`].
    Run { id: u32, request: Run, tz: String },
    /// Kill the run's process group. Its EXIT still comes from [`Agent::on_exit`].
    Stop { run: u32 },
    /// A close button: WM_DELETE_WINDOW to window `xid`, or the run killed if it does not take it.
    Close { run: u32, xid: u32 },
    /// HELLO's clock and random bytes, for the guest.
    Greet { now_ms: u64, entropy: [u8; entropy::BYTES] },
}

/// What PREPARE left behind.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Prepared {
    pub python: String,
    pub tk: String,
    pub parked: Parked,
}

struct CurrentRun {
    id: u32,
    output: Output,
    /// The last WINDOW sent for the run.
    windows: Vec<WindowEntry>,
    /// The HINT kinds sent for the run.
    hinted: Vec<&'static str>,
}

pub struct Agent {
    decoder: frame::Decoder,
    outbox: Outbox,
    actions: VecDeque<Action>,
    /// PREPARE was accepted once. A second one is refused, whatever became of the first.
    prepared: bool,
    preparing: bool,
    /// What the interpreter calls itself, from PREPARE; `None` before.
    interpreter: Option<(String, String)>,
    /// A warm interpreter is waiting for a program.
    warm: bool,
    run: Option<CurrentRun>,
    /// Bytes read from the line that no CREDIT has reported yet.
    unreported: usize,
    drops: Drops,
    reported_drops: Drops,
    last_drop_report: Option<Instant>,
    log_limit: LogLimit,
    /// The zone the next run gets, as READY reports it.
    tz: String,
    now: Instant,
}

/// Frames the agent could not use and does not answer.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
struct Drops {
    frames: DropCounts,
    /// Frames from the agent's own side. The host's line does not echo, so this is noise that
    /// happened to pass the CRC, or a host bug.
    direction: u64,
}

impl Agent {
    /// Queues the zero that opens the line and the unasked READY.
    pub fn new(now: Instant) -> Agent {
        let mut agent = Agent {
            decoder: frame::Decoder::new(frame::MAX_PAYLOAD_TO_AGENT),
            outbox: Outbox::default(),
            actions: VecDeque::new(),
            prepared: false,
            preparing: false,
            interpreter: None,
            warm: false,
            run: None,
            unreported: 0,
            drops: Drops::default(),
            reported_drops: Drops::default(),
            last_drop_report: None,
            log_limit: LogLimit::default(),
            tz: FALLBACK_ZONE.to_owned(),
            now,
        };
        // When init respawns an agent that died mid-frame, this zero ends the half-written frame
        // instead of merging it with the READY below.
        agent.outbox.push(vec![0]);
        let ready = agent.ready();
        agent.send(0, Message::Ready(ready));
        agent
    }

    pub fn outbox(&mut self) -> &mut Outbox {
        &mut self.outbox
    }

    pub fn take_action(&mut self) -> Option<Action> {
        self.actions.pop_front()
    }

    /// Answers PREPARE: PARKED, after a CREDIT for every byte read so far, or ERROR `internal`.
    pub fn on_prepared(&mut self, id: u32, outcome: Result<Prepared, String>) {
        self.preparing = false;
        match outcome {
            Ok(prepared) => {
                self.warm = prepared.parked.warm;
                self.interpreter = Some((prepared.python, prepared.tk));
                // README section 7: the snapshot is saved right after PARKED, and the agent in it
                // must owe the host nothing.
                self.flush_credit();
                self.send(id, Message::Parked(prepared.parked));
            }
            Err(message) => self.refuse(id, ErrorCode::Internal, message),
        }
    }

    pub fn on_started(&mut self, run: u32, pid: u32, warm: bool) {
        if warm {
            self.warm = false;
        }
        self.send(run, Message::Started(Started { pid, warm }));
    }

    /// The run could not start. It is over, with this ERROR in place of STARTED and EXIT.
    pub fn on_refused(&mut self, run: u32, code: ErrorCode, message: String) {
        self.run = None;
        self.refuse(run, code, message);
    }

    /// Takes output as it was read. It leaves in batches (README 6.5), within the run's
    /// `output_cap`; the rest is dropped.
    pub fn on_output(&mut self, run: u32, stream: Stream, bytes: &[u8], now: Instant) {
        self.now = now;
        let Some(current) = self.run.as_mut().filter(|current| current.id == run) else {
            return;
        };
        let chunks = current.output.push(stream, bytes, now);
        self.send_output(run, chunks);
    }

    /// Sends HINT `kind` for the run, once, if the protocol has such a kind. The student's code can
    /// write the prelude's hint lines as well as the prelude can, so anything else is dropped.
    pub fn on_hint(&mut self, run: u32, kind: &str) {
        let Some(current) = self.run.as_mut().filter(|current| current.id == run) else {
            return;
        };
        let Some(&kind) = proto::HINT_KINDS.iter().find(|&&known| known == kind) else {
            return;
        };
        if current.hinted.contains(&kind) {
            return;
        }
        current.hinted.push(kind);
        // After the output that came before it, so the host can show it in its place.
        let chunks = current.output.flush();
        self.send_output(run, chunks);
        self.send(run, Message::Hint(Hint { kind: kind.to_owned() }));
    }

    /// Sends the run's windows, unless they are what was sent last.
    pub fn on_windows(&mut self, run: u32, windows: Vec<WindowEntry>) {
        let Some(current) = self.run.as_mut().filter(|current| current.id == run) else {
            return;
        };
        if current.windows == windows {
            return;
        }
        current.windows = windows.clone();
        self.send(run, Message::Window(Window { windows }));
    }

    /// Ends the run with its EXIT, after its pending output. The caller MUST have read all the
    /// output the program left first.
    pub fn on_exit(&mut self, run: u32, code: Option<u8>, signal: Option<u8>, reason: ExitReason, ms: u64) {
        let Some(mut current) = self.run.take_if(|current| current.id == run) else {
            return;
        };
        let chunks = current.output.flush();
        self.send_output(run, chunks);
        let exit = Exit {
            code,
            signal,
            reason,
            truncated: current.output.truncated(),
            ms,
        };
        self.send(run, Message::Exit(exit));
    }

    /// A LOG from the side that does the guest's work, under the same rate limit as the agent's own.
    pub fn log(&mut self, id: u32, level: Level, message: String) {
        self.send_log(id, level, message);
    }

    /// Takes bytes as they were read from the line, split anywhere.
    pub fn on_serial(&mut self, bytes: &[u8], now: Instant) {
        self.now = now;
        self.unreported += bytes.len();
        // Chunks that were no frame are counted by the decoder, and answered by nothing.
        for frame in self.decoder.push(bytes).into_iter().flatten() {
            self.on_frame(frame);
        }
        self.drops.frames = self.decoder.drops();
        self.report_credit();
        self.report_drops();
    }

    /// Runs whatever is due at `now`. The caller MUST call it by [`Agent::next_deadline`].
    pub fn on_tick(&mut self, now: Instant) {
        self.now = now;
        if let Some(current) = &mut self.run {
            let id = current.id;
            let chunks = current.output.due(now);
            self.send_output(id, chunks);
        }
        self.report_drops();
        self.report_suppressed();
    }

    pub fn next_deadline(&self) -> Option<Instant> {
        let drops = (self.drops != self.reported_drops)
            .then_some(self.last_drop_report)
            .flatten()
            .map(|last| last + DROP_REPORT_INTERVAL);
        let output = self.run.as_ref().and_then(|current| current.output.deadline());
        [drops, self.log_limit.deadline(), output].into_iter().flatten().min()
    }

    fn on_frame(&mut self, frame: Frame) {
        let id = frame.id;
        let name = proto::type_name(frame.type_code).unwrap_or("?");
        match Message::decode(&frame, Side::Host) {
            Ok(message) => self.on_message(id, message),
            Err(Invalid::Direction) => self.drops.direction += 1,
            Err(Invalid::UnknownType) => {
                let message = format!("unknown message type {:#04x}", frame.type_code);
                self.refuse(id, ErrorCode::UnknownType, message);
            }
            Err(invalid) => self.refuse(id, ErrorCode::BadRequest, format!("{name}: {invalid}")),
        }
    }

    fn on_message(&mut self, id: u32, message: Message) {
        let name = message.name();
        match message {
            Message::Ping => self.send_urgent(id, Message::Pong),
            Message::Hello(hello) => {
                self.on_hello(hello);
                let ready = self.ready();
                self.send(id, Message::Ready(ready));
            }
            Message::Prepare(request) => {
                if self.prepared {
                    self.refuse(id, ErrorCode::Refused, "PREPARE was already sent".into());
                } else if self.run.is_some() {
                    self.refuse(id, ErrorCode::Busy, "a run is current".into());
                } else {
                    self.prepared = true;
                    self.preparing = true;
                    self.actions.push_back(Action::Prepare { id, request });
                }
            }
            Message::Run(request) => {
                if self.run.is_some() || self.preparing {
                    self.refuse(
                        id,
                        ErrorCode::Busy,
                        format!("{name} while another run or PREPARE is current"),
                    );
                } else if request.stdin {
                    self.refuse(id, ErrorCode::Unsupported, "stdin is not in protocol 1".into());
                } else {
                    self.run = Some(CurrentRun {
                        id,
                        output: Output::new(request.output_cap),
                        windows: Vec::new(),
                        hinted: Vec::new(),
                    });
                    let tz = self.tz.clone();
                    self.actions.push_back(Action::Run { id, request, tz });
                }
            }
            Message::Stdin(_) => self.refuse(id, ErrorCode::Unsupported, "STDIN is not in protocol 1".into()),
            // README 6.9: a STOP for a run that is not current is ignored.
            Message::Stop => {
                if self.run.as_ref().is_some_and(|current| current.id == id) {
                    self.actions.push_back(Action::Stop { run: id });
                }
            }
            // README 6.10: a CLOSE for a run that is not current is ignored.
            Message::Close(close) => {
                if self.run.as_ref().is_some_and(|current| current.id == id) {
                    self.actions.push_back(Action::Close {
                        run: id,
                        xid: close.xid,
                    });
                }
            }
            Message::Ready(_)
            | Message::Started(_)
            | Message::Stdout(_)
            | Message::Stderr(_)
            | Message::Exit(_)
            | Message::Window(_)
            | Message::Error(_)
            | Message::Pong
            | Message::Credit(_)
            | Message::Hint(_)
            | Message::Log(_)
            | Message::Parked(_) => unreachable!("decode refuses agent messages as Direction"),
        }
    }

    fn on_hello(&mut self, hello: Hello) {
        self.tz = if zone_is_installed(&hello.tz) {
            hello.tz
        } else {
            FALLBACK_ZONE.to_owned()
        };
        // The message layer has checked the digits already.
        if let Some(entropy) = entropy::decode_hex(&hello.entropy) {
            self.actions.push_back(Action::Greet {
                now_ms: hello.now_ms,
                entropy,
            });
        }
    }

    fn ready(&self) -> Ready {
        let (python, tk) = self.interpreter.clone().unzip();
        Ready {
            agent: env!("CARGO_PKG_VERSION").to_owned(),
            python,
            tk,
            tz: self.tz.clone(),
            warm: self.warm,
        }
    }

    /// Credit is flow control, so it overtakes queued output: a host waiting for room would
    /// otherwise wait on the output ahead of it.
    fn report_credit(&mut self) {
        while self.unreported >= proto::CREDIT_STEP {
            let bytes = self.unreported.min(proto::CREDIT_WINDOW);
            self.unreported -= bytes;
            let credit = Credit { bytes: bytes as u32 };
            self.send_urgent(0, Message::Credit(credit));
        }
    }

    /// Reports every byte read so far, even under a step.
    fn flush_credit(&mut self) {
        self.report_credit();
        if self.unreported > 0 {
            let credit = Credit {
                bytes: self.unreported as u32,
            };
            self.unreported = 0;
            self.send_urgent(0, Message::Credit(credit));
        }
    }

    fn report_drops(&mut self) {
        if self.drops == self.reported_drops {
            return;
        }
        if self
            .last_drop_report
            .is_some_and(|last| self.now < last + DROP_REPORT_INTERVAL)
        {
            return;
        }
        let message = describe_drops(&self.reported_drops, &self.drops);
        self.reported_drops = self.drops;
        self.last_drop_report = Some(self.now);
        self.send_log(0, Level::Warn, message);
    }

    fn refuse(&mut self, id: u32, code: ErrorCode, message: String) {
        let body = ErrorBody {
            code: code.as_str().to_owned(),
            message,
        };
        self.send(id, Message::Error(body));
    }

    fn send_log(&mut self, id: u32, level: Level, message: String) {
        self.report_suppressed();
        if self.log_limit.admit(self.now) {
            self.send(id, log(level, message));
        }
    }

    fn report_suppressed(&mut self) {
        if let Some(suppressed) = self.log_limit.take_suppressed(self.now) {
            self.send(0, log(Level::Warn, format!("suppressed {suppressed} log messages")));
        }
    }

    fn send_output(&mut self, id: u32, chunks: Vec<Chunk>) {
        for chunk in chunks {
            let message = match chunk.stream {
                Stream::Stdout => Message::Stdout(chunk.bytes),
                Stream::Stderr => Message::Stderr(chunk.bytes),
            };
            self.send(id, message);
        }
    }

    fn send(&mut self, id: u32, message: Message) {
        if let Some(bytes) = self.encode(id, &message) {
            self.outbox.push(bytes);
        }
    }

    fn send_urgent(&mut self, id: u32, message: Message) {
        if let Some(bytes) = self.encode(id, &message) {
            self.outbox.push_urgent(bytes);
        }
    }

    /// Never lets out a message the host would drop: it would read as a guest that stopped
    /// answering, far from the bug that caused it.
    fn encode(&mut self, id: u32, message: &Message) -> Option<Vec<u8>> {
        match message.encode(id) {
            Ok(bytes) => Some(bytes),
            Err(error) => {
                // A LOG about a LOG that cannot be sent would recurse.
                if !matches!(message, Message::Log(_)) {
                    self.send_log(id, Level::Error, format!("did not send {}: {error}", message.name()));
                }
                None
            }
        }
    }
}

fn log(level: Level, message: String) -> Message {
    Message::Log(Log { level, message })
}

/// `tz` has passed the zone pattern, which allows no dot, so the path stays under ZONEINFO.
fn zone_is_installed(tz: &str) -> bool {
    Path::new(ZONEINFO).join(tz).is_file()
}

/// "dropped 2 frames (crc)", or with more than one reason "dropped 3 frames (crc 2, cobs 1)".
fn describe_drops(before: &Drops, after: &Drops) -> String {
    let mut reasons: Vec<(&str, u64)> = DropReason::ALL
        .iter()
        .map(|&reason| (reason.as_str(), after.frames.get(reason) - before.frames.get(reason)))
        .collect();
    reasons.push(("direction", after.direction - before.direction));
    reasons.retain(|&(_, count)| count > 0);

    let total: u64 = reasons.iter().map(|&(_, count)| count).sum();
    let noun = if total == 1 { "frame" } else { "frames" };
    let detail = match reasons.as_slice() {
        [(reason, _)] => (*reason).to_owned(),
        _ => reasons
            .iter()
            .map(|(reason, count)| format!("{reason} {count}"))
            .collect::<Vec<_>>()
            .join(", "),
    };
    format!("dropped {total} {noun} ({detail})")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fixtures::{hex, load};
    use crate::proto::Close;

    const ENTROPY: &str = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\
                           202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f";

    /// Reads what the agent queued the way the host would, and checks every frame is valid.
    fn replies(agent: &mut Agent) -> Vec<(u32, Message)> {
        let mut wire = Vec::new();
        let outbox = agent.outbox();
        while !outbox.is_empty() {
            let pending = outbox.pending().to_vec();
            wire.extend_from_slice(&pending);
            outbox.consume(pending.len());
        }
        frame::Decoder::new(frame::MAX_PAYLOAD_TO_HOST)
            .push(&wire)
            .into_iter()
            .map(|event| {
                let frame = event.expect("the agent writes good frames");
                let message = Message::decode(&frame, Side::Agent).expect("the agent writes valid messages");
                (frame.id, message)
            })
            .collect()
    }

    fn started() -> (Agent, Instant) {
        let t0 = Instant::now();
        let mut agent = Agent::new(t0);
        replies(&mut agent);
        (agent, t0)
    }

    fn hello(tz: &str) -> Message {
        Message::Hello(Hello {
            now_ms: 1_789_999_999_123,
            tz: tz.into(),
            entropy: ENTROPY.into(),
        })
    }

    fn error_code(message: &Message) -> &str {
        match message {
            Message::Error(error) => &error.code,
            other => panic!("expected ERROR, got {other:?}"),
        }
    }

    fn log_text(message: &Message) -> &str {
        match message {
            Message::Log(log) => &log.message,
            other => panic!("expected LOG, got {other:?}"),
        }
    }

    #[test]
    fn opens_with_a_zero_and_an_unasked_ready() {
        let mut agent = Agent::new(Instant::now());
        assert_eq!(agent.outbox().pending(), &[0]);
        let expected = Ready {
            agent: env!("CARGO_PKG_VERSION").into(),
            python: None,
            tk: None,
            tz: "UTC".into(),
            warm: false,
        };
        assert_eq!(replies(&mut agent), vec![(0, Message::Ready(expected))]);
    }

    #[test]
    fn answers_ping_with_its_id() {
        let (mut agent, t0) = started();
        agent.on_serial(&Message::Ping.encode(0x1234_5678).unwrap(), t0);
        assert_eq!(replies(&mut agent), vec![(0x1234_5678, Message::Pong)]);
    }

    #[test]
    fn answers_hello_with_the_zone_it_kept() {
        let (mut agent, t0) = started();
        agent.on_serial(&hello("Europe/Amsterdam").encode(1).unwrap(), t0);
        agent.on_serial(&hello("Nowhere/Atlantis").encode(2).unwrap(), t0);
        let zones: Vec<(u32, String)> = replies(&mut agent)
            .into_iter()
            .map(|(id, message)| match message {
                Message::Ready(ready) => (id, ready.tz),
                other => panic!("expected READY, got {other:?}"),
            })
            .collect();
        // The host running these tests has zoneinfo too; the guest image ships it from tzdata.
        assert_eq!(zones, vec![(1, "Europe/Amsterdam".into()), (2, "UTC".into())]);
    }

    #[test]
    fn a_ping_overtakes_what_is_queued() {
        let (mut agent, t0) = started();
        let mut bytes = hello("UTC").encode(1).unwrap();
        bytes.extend(Message::Ping.encode(2).unwrap());
        agent.on_serial(&bytes, t0);
        let ids: Vec<u32> = replies(&mut agent).into_iter().map(|(id, _)| id).collect();
        assert_eq!(ids, vec![2, 1]);
    }

    fn run_request(stdin: bool, output_cap: u32) -> Run {
        Run {
            entry: "main.py".into(),
            files: vec!["main.py".into()],
            argv: vec![],
            stdin,
            output_cap,
        }
    }

    fn prepare_request() -> Prepare {
        Prepare {
            resident: vec!["/usr/share/fonts/dejavu/DejaVuSans.ttf".into()],
            reserve_mib: 4,
        }
    }

    fn parked() -> Parked {
        Parked {
            warm: true,
            mem_total_kb: 93_000,
            mem_available_kb: 30_000,
            zeroed_kb: 40_000,
            resident_kb: 20_000,
        }
    }

    fn prepared() -> Prepared {
        Prepared {
            python: "Python 3.12.14".into(),
            tk: "8.6.16".into(),
            parked: parked(),
        }
    }

    #[test]
    fn answers_stdin_as_unsupported_and_ignores_what_is_not_current() {
        let (mut agent, t0) = started();
        agent.on_serial(&Message::Run(run_request(true, 262_144)).encode(5).unwrap(), t0);
        agent.on_serial(&Message::Stdin(b"42\n".to_vec()).encode(5).unwrap(), t0);
        agent.on_serial(&Message::Stop.encode(5).unwrap(), t0);
        agent.on_serial(&Message::Close(Close { xid: 7 }).encode(5).unwrap(), t0);
        let replies = replies(&mut agent);
        assert_eq!(replies.len(), 2, "{replies:?}");
        for (id, message) in &replies {
            assert_eq!((*id, error_code(message)), (5, "unsupported"));
        }
        assert_eq!(agent.take_action(), None);
    }

    #[test]
    fn prepares_once_and_parks_owing_no_credit() {
        let (mut agent, t0) = started();
        let hello = hello("UTC").encode(1).unwrap();
        let prepare = Message::Prepare(prepare_request()).encode(2).unwrap();
        agent.on_serial(&hello, t0);
        agent.on_serial(&prepare, t0);
        assert!(matches!(agent.take_action(), Some(Action::Greet { .. })));
        assert_eq!(
            agent.take_action(),
            Some(Action::Prepare {
                id: 2,
                request: prepare_request()
            })
        );
        let run = Message::Run(run_request(false, 100)).encode(3).unwrap();
        agent.on_serial(&run, t0);
        agent.on_prepared(2, Ok(prepared()));
        agent.on_serial(&Message::Prepare(prepare_request()).encode(4).unwrap(), t0);

        let replies = replies(&mut agent);
        let credited: u32 = replies
            .iter()
            .filter_map(|(_, message)| match message {
                Message::Credit(credit) => Some(credit.bytes),
                _ => None,
            })
            .sum();
        let parked_at = replies.iter().position(|(id, _)| *id == 2).unwrap();
        let credited_before: u32 = replies[..parked_at]
            .iter()
            .filter_map(|(_, message)| match message {
                Message::Credit(credit) => Some(credit.bytes),
                _ => None,
            })
            .sum();
        assert_eq!(
            credited_before as usize,
            hello.len() + prepare.len() + run.len(),
            "{replies:?}"
        );
        assert!(credited >= credited_before);
        let answers: Vec<(u32, &Message)> = replies
            .iter()
            .filter(|(_, message)| !matches!(message, Message::Credit(_)))
            .map(|(id, message)| (*id, message))
            .collect();
        assert!(matches!(answers[0], (1, Message::Ready(_))));
        assert_eq!((answers[1].0, error_code(answers[1].1)), (3, "busy"));
        assert_eq!(answers[2], (2, &Message::Parked(parked())));
        assert_eq!((answers[3].0, error_code(answers[3].1)), (4, "refused"));
    }

    #[test]
    fn ready_names_the_interpreter_once_prepared() {
        let (mut agent, t0) = started();
        agent.on_serial(&Message::Prepare(prepare_request()).encode(2).unwrap(), t0);
        agent.take_action();
        agent.on_prepared(2, Ok(prepared()));
        agent.on_serial(&hello("UTC").encode(3).unwrap(), t0);
        let ready = replies(&mut agent).into_iter().find_map(|(id, message)| match message {
            Message::Ready(ready) if id == 3 => Some(ready),
            _ => None,
        });
        let ready = ready.expect("READY#3");
        assert_eq!(ready.python.as_deref(), Some("Python 3.12.14"));
        assert_eq!(ready.tk.as_deref(), Some("8.6.16"));
        assert!(ready.warm);
    }

    #[test]
    fn a_failed_prepare_is_an_internal_error() {
        let (mut agent, t0) = started();
        agent.on_serial(&Message::Prepare(prepare_request()).encode(2).unwrap(), t0);
        agent.take_action();
        agent.on_prepared(2, Err("Xorg did not start".into()));
        let replies = replies(&mut agent);
        let (id, message) = replies.iter().find(|(_, m)| matches!(m, Message::Error(_))).unwrap();
        assert_eq!((*id, error_code(message)), (2, "internal"));
    }

    #[test]
    fn a_run_goes_started_output_hint_exit() {
        let (mut agent, t0) = started();
        agent.on_serial(&hello("UTC").encode(1).unwrap(), t0);
        agent.on_serial(&Message::Run(run_request(false, 10)).encode(7).unwrap(), t0);
        assert!(matches!(agent.take_action(), Some(Action::Greet { .. })));
        assert_eq!(
            agent.take_action(),
            Some(Action::Run {
                id: 7,
                request: run_request(false, 10),
                tz: "UTC".into()
            })
        );
        agent.on_serial(&Message::Run(run_request(false, 10)).encode(8).unwrap(), t0);
        agent.on_started(7, 1234, true);
        agent.on_output(7, Stream::Stdout, b"hello\n", t0);
        agent.on_output(8, Stream::Stdout, b"not this run", t0);
        agent.on_output(7, Stream::Stderr, b"world\n", t0);
        agent.on_hint(7, "tk_no_mainloop");
        agent.on_serial(&Message::Stop.encode(7).unwrap(), t0);
        assert_eq!(agent.take_action(), Some(Action::Stop { run: 7 }));
        agent.on_exit(7, None, Some(9), ExitReason::Stopped, 42);
        agent.on_output(7, Stream::Stdout, b"after the exit", t0);

        let messages: Vec<(u32, Message)> = replies(&mut agent)
            .into_iter()
            .filter(|(_, message)| !matches!(message, Message::Credit(_) | Message::Ready(_)))
            .collect();
        assert_eq!(
            messages,
            vec![
                (
                    8,
                    Message::Error(ErrorBody {
                        code: "busy".into(),
                        message: "RUN while another run or PREPARE is current".into()
                    })
                ),
                (7, Message::Started(Started { pid: 1234, warm: true })),
                (7, Message::Stdout(b"hello\n".to_vec())),
                (7, Message::Stderr(b"worl".to_vec())),
                (
                    7,
                    Message::Hint(Hint {
                        kind: "tk_no_mainloop".into()
                    })
                ),
                (
                    7,
                    Message::Exit(Exit {
                        code: None,
                        signal: Some(9),
                        reason: ExitReason::Stopped,
                        truncated: true,
                        ms: 42
                    })
                ),
            ]
        );
    }

    #[test]
    fn sends_each_known_hint_once_and_nothing_else() {
        let (mut agent, t0) = started();
        agent.on_serial(&Message::Run(run_request(false, 1000)).encode(7).unwrap(), t0);
        agent.take_action();
        agent.on_started(7, 1234, true);
        for _ in 0..1000 {
            agent.on_hint(7, "tk_no_mainloop");
            agent.on_hint(7, "made_up");
            agent.on_hint(7, "Tk_No_Mainloop");
        }
        agent.on_hint(8, "tk_no_mainloop");
        let hints: Vec<(u32, Message)> = replies(&mut agent)
            .into_iter()
            .filter(|(_, message)| matches!(message, Message::Hint(_)))
            .collect();
        assert_eq!(
            hints,
            vec![(
                7,
                Message::Hint(Hint {
                    kind: "tk_no_mainloop".into()
                })
            )]
        );
    }

    #[test]
    fn hello_hands_the_clock_and_the_bytes_to_the_guest() {
        let (mut agent, t0) = started();
        agent.on_serial(&hello("UTC").encode(1).unwrap(), t0);
        let Some(Action::Greet { now_ms, entropy }) = agent.take_action() else {
            panic!("no Greet");
        };
        assert_eq!(now_ms, 1_789_999_999_123);
        assert_eq!(entropy[..4], [0, 1, 2, 3]);
        assert_eq!(entropy[63], 63);
    }

    #[test]
    fn output_waits_for_its_batch_and_leaves_before_the_exit() {
        let (mut agent, t0) = started();
        agent.on_serial(&Message::Run(run_request(false, 1000)).encode(7).unwrap(), t0);
        agent.take_action();
        agent.on_started(7, 1234, true);
        replies(&mut agent);
        agent.on_output(7, Stream::Stdout, b"een\n", t0);
        agent.on_output(7, Stream::Stdout, b"twee\n", t0 + Duration::from_millis(5));
        assert!(replies(&mut agent).is_empty());
        assert_eq!(agent.next_deadline(), Some(t0 + crate::output::FLUSH_AFTER));
        agent.on_tick(t0 + crate::output::FLUSH_AFTER);
        assert_eq!(replies(&mut agent), vec![(7, Message::Stdout(b"een\ntwee\n".to_vec()))]);

        agent.on_output(7, Stream::Stdout, b"drie\n", t0 + Duration::from_millis(20));
        agent.on_exit(7, Some(0), None, ExitReason::Exit, 30);
        let messages = replies(&mut agent);
        assert_eq!(messages[0], (7, Message::Stdout(b"drie\n".to_vec())));
        assert!(matches!(messages[1], (7, Message::Exit(ref exit)) if !exit.truncated));
        assert_eq!(agent.next_deadline(), None);
    }

    #[test]
    fn sends_a_window_list_only_when_it_changes() {
        let (mut agent, t0) = started();
        agent.on_serial(&Message::Run(run_request(false, 1000)).encode(7).unwrap(), t0);
        agent.take_action();
        let window = WindowEntry {
            xid: 0x0020_0003,
            title: "tk".into(),
            x: 0,
            y: 0,
            w: 200,
            h: 100,
            mapped: true,
            root: true,
            transient_for: None,
        };
        agent.on_windows(7, vec![window.clone()]);
        agent.on_windows(7, vec![window.clone()]);
        agent.on_windows(8, vec![]);
        agent.on_windows(7, vec![]);
        let windows: Vec<usize> = replies(&mut agent)
            .into_iter()
            .filter_map(|(id, message)| match message {
                Message::Window(list) if id == 7 => Some(list.windows.len()),
                _ => None,
            })
            .collect();
        assert_eq!(windows, vec![1, 0]);
    }

    #[test]
    fn close_is_for_the_current_run_only() {
        let (mut agent, t0) = started();
        agent.on_serial(&Message::Run(run_request(false, 1000)).encode(7).unwrap(), t0);
        agent.take_action();
        agent.on_serial(&Message::Close(Close { xid: 5 }).encode(6).unwrap(), t0);
        assert_eq!(agent.take_action(), None);
        agent.on_serial(&Message::Close(Close { xid: 5 }).encode(7).unwrap(), t0);
        assert_eq!(agent.take_action(), Some(Action::Close { run: 7, xid: 5 }));
    }

    #[test]
    fn a_refused_run_frees_the_agent_for_the_next() {
        let (mut agent, t0) = started();
        agent.on_serial(&Message::Run(run_request(false, 10)).encode(7).unwrap(), t0);
        agent.take_action();
        agent.on_refused(7, ErrorCode::BadFiles, "main.py: missing".into());
        agent.on_serial(&Message::Run(run_request(false, 10)).encode(8).unwrap(), t0);
        assert!(matches!(agent.take_action(), Some(Action::Run { id: 8, .. })));
        let (id, message) = replies(&mut agent)
            .into_iter()
            .find(|(_, m)| matches!(m, Message::Error(_)))
            .unwrap();
        assert_eq!((id, error_code(&message)), (7, "bad_files"));
    }

    #[test]
    fn answers_every_invalid_host_frame_as_the_spec_says() {
        for fixture in load("messages-invalid.json")["frames"].as_array().unwrap() {
            if fixture["from"] != "host" {
                continue;
            }
            let (mut agent, t0) = started();
            let wire = hex(fixture["frame_hex"].as_str().unwrap());
            let id = frame::decode(&wire[..wire.len() - 1], frame::MAX_PAYLOAD_TO_AGENT)
                .unwrap()
                .id;
            agent.on_serial(&wire, t0);
            let replies = replies(&mut agent);
            let name = &fixture["name"];
            match fixture["error"].as_str().unwrap() {
                "direction" => {
                    assert_eq!(replies.len(), 1, "{name}: {replies:?}");
                    assert_eq!(log_text(&replies[0].1), "dropped 1 frame (direction)", "{name}");
                }
                expected => {
                    let code = if expected == "unknown_type" {
                        "unknown_type"
                    } else {
                        "bad_request"
                    };
                    assert_eq!(replies.len(), 1, "{name}: {replies:?}");
                    assert_eq!((replies[0].0, error_code(&replies[0].1)), (id, code), "{name}");
                }
            }
        }
    }

    #[test]
    fn reports_drops_at_most_once_a_second() {
        let (mut agent, t0) = started();
        agent.on_serial(&[0x05, 0x11, 0x00], t0);
        let first = replies(&mut agent);
        assert_eq!(first.len(), 1);
        assert_eq!(log_text(&first[0].1), "dropped 1 frame (cobs)");
        assert_eq!(agent.next_deadline(), None);

        let later = t0 + Duration::from_millis(300);
        agent.on_serial(&[&[0x05, 0x11, 0x00][..], &[0x03, 0x11, 0x00]].concat(), later);
        assert!(replies(&mut agent).is_empty());
        assert_eq!(agent.next_deadline(), Some(t0 + DROP_REPORT_INTERVAL));

        agent.on_tick(t0 + DROP_REPORT_INTERVAL);
        let second = replies(&mut agent);
        assert_eq!(log_text(&second[0].1), "dropped 2 frames (cobs)");
        assert_eq!(agent.next_deadline(), None);
    }

    #[test]
    fn a_frame_after_garbage_is_still_answered() {
        let (mut agent, t0) = started();
        let mut bytes = vec![0x7F, 0x7F, 0x00];
        bytes.extend(Message::Ping.encode(9).unwrap());
        agent.on_serial(&bytes, t0);
        let replies = replies(&mut agent);
        assert_eq!(replies[0], (9, Message::Pong));
        assert_eq!(log_text(&replies[1].1), "dropped 1 frame (cobs)");
    }

    #[test]
    fn credits_every_byte_it_reads_in_steps() {
        let (mut agent, t0) = started();
        let ping = Message::Ping.encode(1).unwrap();
        let count = 1000;
        let stream = ping.repeat(count);
        let mut credited = 0;
        let mut pongs = 0;
        for chunk in stream.chunks(777) {
            agent.on_serial(chunk, t0);
            for (_, message) in replies(&mut agent) {
                match message {
                    Message::Credit(credit) => {
                        assert!(credit.bytes as usize >= proto::CREDIT_STEP);
                        credited += credit.bytes as usize;
                    }
                    Message::Pong => pongs += 1,
                    other => panic!("unexpected {other:?}"),
                }
            }
        }
        assert_eq!(pongs, count);
        assert!(stream.len() - credited < proto::CREDIT_STEP);
        assert_eq!(agent.unreported, stream.len() - credited);
    }

    #[test]
    fn describes_several_reasons_with_counts() {
        let before = Drops::default();
        let mut decoder = frame::Decoder::new(frame::MAX_PAYLOAD_TO_AGENT);
        decoder.push(&[0x05, 0x11, 0x00, 0x03, 0x11, 0x00, 0x01, 0x00]);
        let after = Drops {
            frames: decoder.drops(),
            direction: 1,
        };
        assert_eq!(
            describe_drops(&before, &after),
            "dropped 4 frames (cobs 2, short 1, direction 1)"
        );
    }
}
