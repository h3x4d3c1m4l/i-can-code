//! Messages: what a frame's type and payload mean. vm/protocol/README.md sections 4 to 6.
//!
//! Both directions are here, so the fixtures can hold every message to its bytes, and so the agent
//! can refuse to send a message the host would drop.

use crate::frame::{self, Frame};
use serde::Serialize;
use serde_json::{Map, Value};
use std::borrow::Cow;
use std::fmt;

/// Who sent a frame. Bit 7 of the type code says which.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Side {
    Host,
    Agent,
}

impl Side {
    pub fn of(type_code: u8) -> Side {
        if type_code & 0x80 == 0 { Side::Host } else { Side::Agent }
    }

    /// The largest payload this side may send.
    fn max_payload(self) -> usize {
        match self {
            Side::Host => frame::MAX_PAYLOAD_TO_AGENT,
            Side::Agent => frame::MAX_PAYLOAD_TO_HOST,
        }
    }
}

pub const HELLO: u8 = 0x01;
pub const RUN: u8 = 0x02;
pub const STDIN: u8 = 0x03;
pub const STOP: u8 = 0x04;
pub const PING: u8 = 0x05;
pub const CLOSE: u8 = 0x06;
pub const PREPARE: u8 = 0x10;
pub const READY: u8 = 0x81;
pub const STARTED: u8 = 0x82;
pub const STDOUT: u8 = 0x83;
pub const STDERR: u8 = 0x84;
pub const EXIT: u8 = 0x85;
pub const WINDOW: u8 = 0x86;
pub const ERROR: u8 = 0x87;
pub const PONG: u8 = 0x88;
pub const CREDIT: u8 = 0x89;
pub const HINT: u8 = 0x8A;
pub const LOG: u8 = 0x8F;
pub const PARKED: u8 = 0x90;

/// Payloads are JSON objects except for these, which are raw bytes.
fn carries_data(type_code: u8) -> bool {
    matches!(type_code, STDIN | STDOUT | STDERR)
}

/// The message's name in the protocol, or `None` for a code no row of the table has.
pub fn type_name(type_code: u8) -> Option<&'static str> {
    Some(match type_code {
        HELLO => "HELLO",
        RUN => "RUN",
        STDIN => "STDIN",
        STOP => "STOP",
        PING => "PING",
        CLOSE => "CLOSE",
        PREPARE => "PREPARE",
        READY => "READY",
        STARTED => "STARTED",
        STDOUT => "STDOUT",
        STDERR => "STDERR",
        EXIT => "EXIT",
        WINDOW => "WINDOW",
        ERROR => "ERROR",
        PONG => "PONG",
        CREDIT => "CREDIT",
        HINT => "HINT",
        LOG => "LOG",
        PARKED => "PARKED",
        _ => return None,
    })
}

pub const MAX_FILES: usize = 64;
pub const MAX_ARGV: usize = 64;
pub const MAX_WINDOWS: usize = 32;
pub const MAX_RESIDENT: usize = 1024;
pub const MAX_RESERVE_MIB: u32 = 1024;
pub const MAX_OUTPUT_CAP: u32 = 16 * 1024 * 1024;
/// Bytes the host may have in flight to the agent. README section 7.
pub const CREDIT_WINDOW: usize = 16384;
/// The agent owes the host a CREDIT once this many bytes are unreported.
pub const CREDIT_STEP: usize = 4096;
/// JavaScript's `Number.MAX_SAFE_INTEGER`: the host reads every integer as a double.
const MAX_SAFE_INTEGER: u64 = (1 << 53) - 1;

#[derive(Debug, Clone, PartialEq)]
pub enum Message {
    Hello(Hello),
    Run(Run),
    Stdin(Vec<u8>),
    Stop,
    Ping,
    Close(Close),
    Prepare(Prepare),
    Ready(Ready),
    Started(Started),
    Stdout(Vec<u8>),
    Stderr(Vec<u8>),
    Exit(Exit),
    Window(Window),
    Error(ErrorBody),
    Pong,
    Credit(Credit),
    Hint(Hint),
    Log(Log),
    Parked(Parked),
}

/// Why a good frame is not a message this receiver can use. README section 5.3.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Invalid {
    /// The type code is from the receiver's own side.
    Direction,
    UnknownType,
    /// The payload is not UTF-8, or not JSON.
    BadJson,
    NotObject,
    /// This top-level field is missing, of the wrong type or out of range, or a rule between fields
    /// that names it fails.
    Field(&'static str),
}

impl fmt::Display for Invalid {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Invalid::Direction => f.write_str("sent in the wrong direction"),
            Invalid::UnknownType => f.write_str("unknown message type"),
            Invalid::BadJson => f.write_str("payload is not UTF-8 JSON"),
            Invalid::NotObject => f.write_str("payload is not a JSON object"),
            Invalid::Field(name) => write!(f, "field {name} is missing or invalid"),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EncodeError {
    /// The receiver would refuse the message for this field.
    Field(&'static str),
    /// The payload is over the limit of the direction, by this many bytes.
    TooLong(usize),
}

impl fmt::Display for EncodeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EncodeError::Field(name) => write!(f, "field {name} is invalid"),
            EncodeError::TooLong(over) => write!(f, "payload is {over} bytes over the limit"),
        }
    }
}

impl Message {
    pub fn type_code(&self) -> u8 {
        match self {
            Message::Hello(_) => HELLO,
            Message::Run(_) => RUN,
            Message::Stdin(_) => STDIN,
            Message::Stop => STOP,
            Message::Ping => PING,
            Message::Close(_) => CLOSE,
            Message::Prepare(_) => PREPARE,
            Message::Ready(_) => READY,
            Message::Started(_) => STARTED,
            Message::Stdout(_) => STDOUT,
            Message::Stderr(_) => STDERR,
            Message::Exit(_) => EXIT,
            Message::Window(_) => WINDOW,
            Message::Error(_) => ERROR,
            Message::Pong => PONG,
            Message::Credit(_) => CREDIT,
            Message::Hint(_) => HINT,
            Message::Log(_) => LOG,
            Message::Parked(_) => PARKED,
        }
    }

    pub fn name(&self) -> &'static str {
        type_name(self.type_code()).unwrap_or("?")
    }

    /// Reads a frame that `from` is expected to have sent. Unknown keys are ignored, and a nullable
    /// field that is left out reads as null.
    pub fn decode(frame: &Frame, from: Side) -> Result<Message, Invalid> {
        let code = frame.type_code;
        if Side::of(code) != from {
            return Err(Invalid::Direction);
        }
        if type_name(code).is_none() {
            return Err(Invalid::UnknownType);
        }
        if carries_data(code) {
            let data = frame.payload.clone();
            return Ok(match code {
                STDIN => Message::Stdin(data),
                STDOUT => Message::Stdout(data),
                STDERR => Message::Stderr(data),
                _ => unreachable!("carries_data names three types"),
            });
        }

        let value: Value = serde_json::from_slice(&frame.payload).map_err(|_| Invalid::BadJson)?;
        // A derived Deserialize would also take an array, filling the fields by position.
        let Value::Object(object) = value else {
            return Err(Invalid::NotObject);
        };
        let fields = Fields(&object);
        Ok(match code {
            HELLO => Message::Hello(read(&fields)?),
            RUN => Message::Run(read(&fields)?),
            STOP => Message::Stop,
            PING => Message::Ping,
            CLOSE => Message::Close(read(&fields)?),
            PREPARE => Message::Prepare(read(&fields)?),
            READY => Message::Ready(read(&fields)?),
            STARTED => Message::Started(read(&fields)?),
            EXIT => Message::Exit(read(&fields)?),
            WINDOW => Message::Window(read(&fields)?),
            ERROR => Message::Error(read(&fields)?),
            PONG => Message::Pong,
            CREDIT => Message::Credit(read(&fields)?),
            HINT => Message::Hint(read(&fields)?),
            LOG => Message::Log(read(&fields)?),
            PARKED => Message::Parked(read(&fields)?),
            _ => unreachable!("type_name knows no other JSON type"),
        })
    }

    /// Returns the wire bytes, delimiter included, or why the receiver would refuse them.
    pub fn encode(&self, id: u32) -> Result<Vec<u8>, EncodeError> {
        let payload = self.payload()?;
        let max = Side::of(self.type_code()).max_payload();
        if payload.len() > max {
            return Err(EncodeError::TooLong(payload.len() - max));
        }
        Ok(frame::encode(self.type_code(), id, &payload))
    }

    /// The payload in canonical form: fields in table order, nulls written out, no whitespace.
    pub fn payload(&self) -> Result<Cow<'_, [u8]>, EncodeError> {
        Ok(match self {
            Message::Stdin(data) | Message::Stdout(data) | Message::Stderr(data) => Cow::Borrowed(data),
            Message::Stop | Message::Ping | Message::Pong => Cow::Borrowed(b"{}"),
            Message::Hello(body) => json(body)?,
            Message::Run(body) => json(body)?,
            Message::Close(body) => json(body)?,
            Message::Prepare(body) => json(body)?,
            Message::Ready(body) => json(body)?,
            Message::Started(body) => json(body)?,
            Message::Exit(body) => json(body)?,
            Message::Window(body) => json(body)?,
            Message::Error(body) => json(body)?,
            Message::Credit(body) => json(body)?,
            Message::Hint(body) => json(body)?,
            Message::Log(body) => json(body)?,
            Message::Parked(body) => json(body)?,
        })
    }
}

/// A JSON body. Its struct declares the fields in table order, which is what makes serde_json's
/// output canonical.
trait Body: Serialize + Sized {
    /// Reads each field as its type. What the type does not hold is [`Body::check`]'s.
    fn read(fields: &Fields<'_>) -> Result<Self, &'static str>;

    /// Ranges, patterns and the rules between fields, each naming the field it is about.
    fn check(&self) -> Result<(), &'static str> {
        Ok(())
    }
}

fn read<T: Body>(fields: &Fields<'_>) -> Result<T, Invalid> {
    let body = T::read(fields).map_err(Invalid::Field)?;
    body.check().map_err(Invalid::Field)?;
    Ok(body)
}

fn json<T: Body>(body: &T) -> Result<Cow<'static, [u8]>, EncodeError> {
    body.check().map_err(EncodeError::Field)?;
    let bytes = serde_json::to_vec(body).expect("a body of strings, integers and booleans always serialises");
    Ok(Cow::Owned(bytes))
}

/// Typed access to the members of a payload object, failing with the member's name.
struct Fields<'a>(&'a Map<String, Value>);

impl<'a> Fields<'a> {
    fn get(&self, name: &'static str) -> Result<&'a Value, &'static str> {
        self.0.get(name).ok_or(name)
    }

    /// A member that is null reads the same as one that is left out.
    fn nullable(&self, name: &'static str) -> Option<&'a Value> {
        self.0.get(name).filter(|value| !value.is_null())
    }

    fn int<T: TryFrom<i64>>(&self, name: &'static str) -> Result<T, &'static str> {
        integer(self.get(name)?).ok_or(name)
    }

    fn nullable_int<T: TryFrom<i64>>(&self, name: &'static str) -> Result<Option<T>, &'static str> {
        self.nullable(name).map(|value| integer(value).ok_or(name)).transpose()
    }

    fn bool(&self, name: &'static str) -> Result<bool, &'static str> {
        self.get(name)?.as_bool().ok_or(name)
    }

    fn string(&self, name: &'static str) -> Result<String, &'static str> {
        self.get(name)?.as_str().map(str::to_owned).ok_or(name)
    }

    fn nullable_string(&self, name: &'static str) -> Result<Option<String>, &'static str> {
        self.nullable(name)
            .map(|value| value.as_str().map(str::to_owned).ok_or(name))
            .transpose()
    }

    fn strings(&self, name: &'static str) -> Result<Vec<String>, &'static str> {
        let items = self.get(name)?.as_array().ok_or(name)?;
        items
            .iter()
            .map(|item| item.as_str().map(str::to_owned).ok_or(name))
            .collect()
    }
}

/// An integer that fits `T`. `1.0` and `1e3` are refused, which README section 5.1 allows.
fn integer<T: TryFrom<i64>>(value: &Value) -> Option<T> {
    value.as_i64().and_then(|n| T::try_from(n).ok())
}

/// `^[a-z][a-z0-9_]{0,63}$`
fn is_token(text: &str) -> bool {
    let bytes = text.as_bytes();
    (1..=64).contains(&bytes.len())
        && bytes[0].is_ascii_lowercase()
        && bytes
            .iter()
            .all(|&b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_')
}

/// `^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}$`. No leading dot: those names are the protocol's.
pub fn is_file_name(text: &str) -> bool {
    let bytes = text.as_bytes();
    (1..=64).contains(&bytes.len())
        && (bytes[0].is_ascii_alphanumeric() || bytes[0] == b'_')
        && bytes
            .iter()
            .all(|&b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-'))
}

/// An IANA zone name: at most 64 characters, `^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$`. With no dot
/// allowed it cannot climb out of the zoneinfo directory it is looked up in.
pub fn is_zone(text: &str) -> bool {
    (1..=64).contains(&text.len())
        && text.split('/').all(|part| {
            !part.is_empty()
                && part
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'_' | b'+' | b'-'))
        })
}

fn is_entropy(text: &str) -> bool {
    text.len() == 128 && text.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Hello {
    pub now_ms: u64,
    pub tz: String,
    /// 64 bytes as 128 lower-case hex digits.
    pub entropy: String,
}

impl Body for Hello {
    fn read(f: &Fields<'_>) -> Result<Self, &'static str> {
        Ok(Hello {
            now_ms: f.int("now_ms")?,
            tz: f.string("tz")?,
            entropy: f.string("entropy")?,
        })
    }

    fn check(&self) -> Result<(), &'static str> {
        rule(self.now_ms <= MAX_SAFE_INTEGER, "now_ms")?;
        rule(is_zone(&self.tz), "tz")?;
        rule(is_entropy(&self.entropy), "entropy")
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Run {
    pub entry: String,
    pub files: Vec<String>,
    pub argv: Vec<String>,
    pub stdin: bool,
    pub output_cap: u32,
}

impl Body for Run {
    fn read(f: &Fields<'_>) -> Result<Self, &'static str> {
        Ok(Run {
            entry: f.string("entry")?,
            files: f.strings("files")?,
            argv: f.strings("argv")?,
            stdin: f.bool("stdin")?,
            output_cap: f.int("output_cap")?,
        })
    }

    fn check(&self) -> Result<(), &'static str> {
        rule(is_file_name(&self.entry), "entry")?;
        rule(
            (1..=MAX_FILES).contains(&self.files.len()) && self.files.iter().all(|name| is_file_name(name)),
            "files",
        )?;
        rule(
            self.argv.len() <= MAX_ARGV && self.argv.iter().all(|arg| !arg.contains('\0')),
            "argv",
        )?;
        rule(self.output_cap <= MAX_OUTPUT_CAP, "output_cap")?;
        let distinct = self
            .files
            .iter()
            .enumerate()
            .all(|(i, name)| !self.files[..i].contains(name));
        rule(distinct, "files")?;
        rule(self.files.contains(&self.entry), "entry")
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Close {
    pub xid: u32,
}

impl Body for Close {
    fn read(f: &Fields<'_>) -> Result<Self, &'static str> {
        Ok(Close { xid: f.int("xid")? })
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Prepare {
    pub resident: Vec<String>,
    pub reserve_mib: u32,
}

impl Body for Prepare {
    fn read(f: &Fields<'_>) -> Result<Self, &'static str> {
        Ok(Prepare {
            resident: f.strings("resident")?,
            reserve_mib: f.int("reserve_mib")?,
        })
    }

    fn check(&self) -> Result<(), &'static str> {
        let absolute = |path: &String| path.starts_with('/') && !path.contains('\0');
        rule(
            self.resident.len() <= MAX_RESIDENT && self.resident.iter().all(absolute),
            "resident",
        )?;
        rule(self.reserve_mib <= MAX_RESERVE_MIB, "reserve_mib")
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Ready {
    pub agent: String,
    pub python: Option<String>,
    pub tk: Option<String>,
    pub tz: String,
    pub warm: bool,
}

impl Body for Ready {
    fn read(f: &Fields<'_>) -> Result<Self, &'static str> {
        Ok(Ready {
            agent: f.string("agent")?,
            python: f.nullable_string("python")?,
            tk: f.nullable_string("tk")?,
            tz: f.string("tz")?,
            warm: f.bool("warm")?,
        })
    }

    fn check(&self) -> Result<(), &'static str> {
        rule(is_zone(&self.tz), "tz")
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Started {
    pub pid: u32,
    pub warm: bool,
}

impl Body for Started {
    fn read(f: &Fields<'_>) -> Result<Self, &'static str> {
        Ok(Started {
            pid: f.int("pid")?,
            warm: f.bool("warm")?,
        })
    }

    fn check(&self) -> Result<(), &'static str> {
        rule((1..=i32::MAX as u32).contains(&self.pid), "pid")
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ExitReason {
    Exit,
    Stopped,
    Closed,
    Oom,
}

impl ExitReason {
    fn from_name(name: &str) -> Option<ExitReason> {
        Some(match name {
            "exit" => ExitReason::Exit,
            "stopped" => ExitReason::Stopped,
            "closed" => ExitReason::Closed,
            "oom" => ExitReason::Oom,
            _ => return None,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Exit {
    /// Exactly one of `code` and `signal` is set.
    pub code: Option<u8>,
    pub signal: Option<u8>,
    pub reason: ExitReason,
    pub truncated: bool,
    pub ms: u64,
}

impl Body for Exit {
    fn read(f: &Fields<'_>) -> Result<Self, &'static str> {
        Ok(Exit {
            code: f.nullable_int("code")?,
            signal: f.nullable_int("signal")?,
            reason: ExitReason::from_name(&f.string("reason")?).ok_or("reason")?,
            truncated: f.bool("truncated")?,
            ms: f.int("ms")?,
        })
    }

    fn check(&self) -> Result<(), &'static str> {
        rule(self.signal.is_none_or(|signal| (1..=64).contains(&signal)), "signal")?;
        rule(self.ms <= MAX_SAFE_INTEGER, "ms")?;
        rule(self.code.is_some() != self.signal.is_some(), "code")
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Window {
    /// Bottom to top in the X stacking order.
    pub windows: Vec<WindowEntry>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct WindowEntry {
    pub xid: u32,
    pub title: String,
    pub x: i32,
    pub y: i32,
    pub w: u16,
    pub h: u16,
    pub mapped: bool,
    pub root: bool,
    pub transient_for: Option<u32>,
}

impl WindowEntry {
    fn read(f: &Fields<'_>) -> Result<Self, &'static str> {
        Ok(WindowEntry {
            xid: f.int("xid")?,
            title: f.string("title")?,
            x: f.int("x")?,
            y: f.int("y")?,
            w: f.int("w")?,
            h: f.int("h")?,
            mapped: f.bool("mapped")?,
            root: f.bool("root")?,
            transient_for: f.nullable_int("transient_for")?,
        })
    }
}

impl Body for Window {
    fn read(f: &Fields<'_>) -> Result<Self, &'static str> {
        let items = f.get("windows")?.as_array().ok_or("windows")?;
        let windows = items
            .iter()
            .map(|item| {
                item.as_object()
                    .ok_or("windows")
                    .and_then(|o| WindowEntry::read(&Fields(o)))
            })
            .collect::<Result<_, _>>()
            .map_err(|_| "windows")?;
        Ok(Window { windows })
    }

    fn check(&self) -> Result<(), &'static str> {
        rule(self.windows.len() <= MAX_WINDOWS, "windows")?;
        rule(self.windows.iter().filter(|w| w.root).count() <= 1, "windows")
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ErrorBody {
    pub code: String,
    /// English, for developers.
    pub message: String,
}

impl Body for ErrorBody {
    fn read(f: &Fields<'_>) -> Result<Self, &'static str> {
        Ok(ErrorBody {
            code: f.string("code")?,
            message: f.string("message")?,
        })
    }

    fn check(&self) -> Result<(), &'static str> {
        rule(is_token(&self.code), "code")
    }
}

/// The ERROR codes the agent sends. A host treats a code it does not know as `internal`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorCode {
    BadRequest,
    UnknownType,
    Busy,
    BadFiles,
    Unsupported,
    SpawnFailed,
    Refused,
    Internal,
}

impl ErrorCode {
    pub fn as_str(self) -> &'static str {
        match self {
            ErrorCode::BadRequest => "bad_request",
            ErrorCode::UnknownType => "unknown_type",
            ErrorCode::Busy => "busy",
            ErrorCode::BadFiles => "bad_files",
            ErrorCode::Unsupported => "unsupported",
            ErrorCode::SpawnFailed => "spawn_failed",
            ErrorCode::Refused => "refused",
            ErrorCode::Internal => "internal",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Credit {
    pub bytes: u32,
}

impl Body for Credit {
    fn read(f: &Fields<'_>) -> Result<Self, &'static str> {
        Ok(Credit { bytes: f.int("bytes")? })
    }

    fn check(&self) -> Result<(), &'static str> {
        rule((1..=CREDIT_WINDOW as u32).contains(&self.bytes), "bytes")
    }
}

/// README 6.8: the HINT kinds of this version. A host ignores kinds it does not know, but the agent
/// sends no other, whatever reaches it from the prelude's pipe.
pub const HINT_KINDS: [&str; 1] = ["tk_no_mainloop"];

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Hint {
    pub kind: String,
}

impl Body for Hint {
    fn read(f: &Fields<'_>) -> Result<Self, &'static str> {
        Ok(Hint {
            kind: f.string("kind")?,
        })
    }

    fn check(&self) -> Result<(), &'static str> {
        rule(is_token(&self.kind), "kind")
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Level {
    Debug,
    Info,
    Warn,
    Error,
}

impl Level {
    fn from_name(name: &str) -> Option<Level> {
        Some(match name {
            "debug" => Level::Debug,
            "info" => Level::Info,
            "warn" => Level::Warn,
            "error" => Level::Error,
            _ => return None,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Log {
    pub level: Level,
    /// English, for developers.
    pub message: String,
}

impl Body for Log {
    fn read(f: &Fields<'_>) -> Result<Self, &'static str> {
        Ok(Log {
            level: Level::from_name(&f.string("level")?).ok_or("level")?,
            message: f.string("message")?,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Parked {
    pub warm: bool,
    pub mem_total_kb: u32,
    pub mem_available_kb: u32,
    pub zeroed_kb: u32,
    pub resident_kb: u32,
}

impl Body for Parked {
    fn read(f: &Fields<'_>) -> Result<Self, &'static str> {
        Ok(Parked {
            warm: f.bool("warm")?,
            mem_total_kb: f.int("mem_total_kb")?,
            mem_available_kb: f.int("mem_available_kb")?,
            zeroed_kb: f.int("zeroed_kb")?,
            resident_kb: f.int("resident_kb")?,
        })
    }
}

fn rule(holds: bool, field: &'static str) -> Result<(), &'static str> {
    if holds { Ok(()) } else { Err(field) }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fixtures::{hex, load, to_hex};
    use serde_json::json;

    fn side(name: &str) -> Side {
        match name {
            "host" => Side::Host,
            "agent" => Side::Agent,
            _ => panic!("unknown side {name}"),
        }
    }

    fn frame_of(wire_hex: &str) -> Frame {
        let wire = hex(wire_hex);
        assert_eq!(wire.last(), Some(&0), "{wire_hex} lacks its delimiter");
        frame::decode(&wire[..wire.len() - 1], frame::MAX_PAYLOAD_TO_HOST).expect("fixture frames are good frames")
    }

    fn type_code_of(name: &str) -> u8 {
        (0..=u8::MAX)
            .find(|&code| type_name(code) == Some(name))
            .unwrap_or_else(|| panic!("no type {name}"))
    }

    /// The fixtures' notation for a message: `{type, id, body}`, or `{type, id, data_hex}`.
    fn to_fixture(message: &Message, id: u32) -> Value {
        let payload = message.payload().unwrap();
        if carries_data(message.type_code()) {
            json!({"type": message.name(), "id": id, "data_hex": to_hex(&payload)})
        } else {
            let body: Value = serde_json::from_slice(&payload).unwrap();
            json!({"type": message.name(), "id": id, "body": body})
        }
    }

    /// Builds the message the fixture describes, through the decoder, from a payload that is valid
    /// JSON but not canonical: serde_json writes the fixture's keys in sorted order.
    fn from_fixture(fixture: &Value) -> (Message, u32) {
        let type_code = type_code_of(fixture["type"].as_str().unwrap());
        let id = fixture["id"].as_u64().unwrap() as u32;
        let payload = match fixture.get("data_hex") {
            Some(data) => hex(data.as_str().unwrap()),
            None => serde_json::to_vec(&fixture["body"]).unwrap(),
        };
        let frame = Frame { type_code, id, payload };
        (Message::decode(&frame, Side::of(type_code)).unwrap(), id)
    }

    #[test]
    fn type_table_matches_the_protocol() {
        let protocol = load("protocol.json");
        let types = protocol["types"].as_array().unwrap();
        for entry in types {
            let code = entry["code"].as_u64().unwrap() as u8;
            let name = entry["name"].as_str().unwrap();
            assert_eq!(type_name(code), Some(name));
            assert_eq!(Side::of(code), side(entry["from"].as_str().unwrap()), "{name}");
            assert_eq!(carries_data(code), entry["payload"] == "data", "{name}");
        }
        let known = (0..=u8::MAX).filter(|&code| type_name(code).is_some()).count();
        assert_eq!(known, types.len());
        assert_eq!(protocol["max_files"], MAX_FILES);
        assert_eq!(protocol["max_windows"], MAX_WINDOWS);
        assert_eq!(protocol["credit_window"], CREDIT_WINDOW);
        assert_eq!(protocol["credit_step"], CREDIT_STEP);
    }

    #[test]
    fn every_message_decodes_and_encodes_byte_exactly() {
        for fixture in load("messages.json")["frames"].as_array().unwrap() {
            let name = &fixture["name"];
            let frame = frame_of(fixture["frame_hex"].as_str().unwrap());
            assert_eq!(
                to_hex(&frame::encode(frame.type_code, frame.id, &frame.payload)),
                fixture["frame_hex"]
            );

            let decoded = Message::decode(&frame, side(fixture["from"].as_str().unwrap()))
                .unwrap_or_else(|e| panic!("{name}: {e}"));
            assert_eq!(to_fixture(&decoded, frame.id), fixture["message"], "decode {name}");

            let (built, id) = from_fixture(&fixture["message"]);
            assert_eq!(built, decoded, "{name}");
            let wire = built.encode(id).unwrap_or_else(|e| panic!("{name}: {e}"));
            assert_eq!(to_hex(&wire), fixture["frame_hex"], "encode {name}");

            let raw = frame::cobs_decode(&wire[..wire.len() - 1]).unwrap();
            assert_eq!(to_hex(&raw), fixture["raw_hex"], "raw {name}");
        }
    }

    #[test]
    fn every_tolerated_payload_decodes_and_encodes_canonically() {
        for fixture in load("messages-tolerated.json")["frames"].as_array().unwrap() {
            let name = &fixture["name"];
            let frame = frame_of(fixture["frame_hex"].as_str().unwrap());
            let decoded = Message::decode(&frame, side(fixture["from"].as_str().unwrap()))
                .unwrap_or_else(|e| panic!("{name}: {e}"));
            assert_eq!(to_fixture(&decoded, frame.id), fixture["message"], "decode {name}");
            assert_eq!(
                to_hex(&decoded.encode(frame.id).unwrap()),
                fixture["canonical_frame_hex"],
                "encode {name}"
            );
        }
    }

    #[test]
    fn every_invalid_message_is_refused_for_the_right_reason() {
        for fixture in load("messages-invalid.json")["frames"].as_array().unwrap() {
            let name = &fixture["name"];
            let frame = frame_of(fixture["frame_hex"].as_str().unwrap());
            let error = Message::decode(&frame, side(fixture["from"].as_str().unwrap()))
                .expect_err(&format!("{name} was accepted"));
            let (kind, field) = match error {
                Invalid::Direction => ("direction", None),
                Invalid::UnknownType => ("unknown_type", None),
                Invalid::BadJson => ("bad_json", None),
                Invalid::NotObject => ("not_object", None),
                Invalid::Field(field) => ("field", Some(field)),
            };
            assert_eq!(kind, fixture["error"], "{name}");
            assert_eq!(field, fixture["field"].as_str(), "{name}");
        }
    }

    #[test]
    fn encode_refuses_what_the_host_would_drop() {
        let exit = |code, signal| {
            Message::Exit(Exit {
                code,
                signal,
                reason: ExitReason::Exit,
                truncated: false,
                ms: 1,
            })
        };
        assert_eq!(exit(None, None).encode(2), Err(EncodeError::Field("code")));
        assert_eq!(exit(Some(0), Some(9)).encode(2), Err(EncodeError::Field("code")));
        assert_eq!(exit(None, Some(65)).encode(2), Err(EncodeError::Field("signal")));
        assert!(exit(None, Some(9)).encode(2).is_ok());

        assert_eq!(
            Message::Credit(Credit { bytes: 0 }).encode(0),
            Err(EncodeError::Field("bytes"))
        );
        let error = ErrorBody {
            code: "Busy".into(),
            message: String::new(),
        };
        assert_eq!(Message::Error(error).encode(0), Err(EncodeError::Field("code")));

        let entry = |root| WindowEntry {
            xid: 1,
            title: String::new(),
            x: 0,
            y: 0,
            w: 1,
            h: 1,
            mapped: true,
            root,
            transient_for: None,
        };
        let two_roots = Window {
            windows: vec![entry(true), entry(true)],
        };
        assert_eq!(Message::Window(two_roots).encode(2), Err(EncodeError::Field("windows")));
        let too_many = Window {
            windows: vec![entry(false); MAX_WINDOWS + 1],
        };
        assert_eq!(Message::Window(too_many).encode(2), Err(EncodeError::Field("windows")));

        assert!(
            Message::Stdout(vec![b'x'; frame::MAX_PAYLOAD_TO_HOST])
                .encode(2)
                .is_ok()
        );
        assert_eq!(
            Message::Stdout(vec![b'x'; frame::MAX_PAYLOAD_TO_HOST + 1]).encode(2),
            Err(EncodeError::TooLong(1))
        );
        assert_eq!(
            Message::Stdin(vec![b'x'; frame::MAX_PAYLOAD_TO_AGENT + 1]).encode(2),
            Err(EncodeError::TooLong(1))
        );
    }

    #[test]
    fn patterns_hold_their_edges() {
        assert!(is_token("tk_no_mainloop"));
        assert!(!is_token("_x") && !is_token("") && !is_token("a-b") && !is_token(&"a".repeat(65)));
        assert!(is_token(&"a".repeat(64)));

        assert!(is_file_name("main.py") && is_file_name("_x") && is_file_name(&"a".repeat(64)));
        assert!(!is_file_name(".stdin") && !is_file_name("a/b") && !is_file_name("") && !is_file_name(&"a".repeat(65)));
        assert!(!is_file_name("..") && !is_file_name("é.py"));

        assert!(is_zone("UTC") && is_zone("America/Argentina/Buenos_Aires") && is_zone("Etc/GMT+1"));
        assert!(!is_zone("") && !is_zone("/UTC") && !is_zone("UTC/") && !is_zone("a//b") && !is_zone("../x"));
        assert!(!is_zone(&"a".repeat(65)) && is_zone(&"a".repeat(64)));
    }
}
