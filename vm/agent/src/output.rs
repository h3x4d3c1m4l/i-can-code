//! A run's STDOUT and STDERR on their way to the host (README 6.5): batched, so a print loop costs
//! about 60 frames a second rather than one per line, and capped at the run's `output_cap`.

use crate::frame;
use std::time::{Duration, Instant};

/// A batch leaves once this much is pending.
pub const FLUSH_BYTES: usize = 4096;
/// ... or this long after its first byte, whichever comes first.
pub const FLUSH_AFTER: Duration = Duration::from_millis(16);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Stream {
    Stdout,
    Stderr,
}

/// Bytes ready to become one STDOUT or STDERR frame.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Chunk {
    pub stream: Stream,
    pub bytes: Vec<u8>,
}

/// One pending batch rather than one per stream: the host sees the two streams in the order the
/// agent read them, so a traceback cannot overtake the prints before it.
pub struct Output {
    /// Bytes of both streams together the run may still forward.
    budget: u64,
    truncated: bool,
    pending: Vec<u8>,
    stream: Stream,
    since: Option<Instant>,
}

impl Output {
    pub fn new(cap: u32) -> Output {
        Output {
            budget: cap.into(),
            truncated: false,
            pending: Vec::new(),
            stream: Stream::Stdout,
            since: None,
        }
    }

    /// Output past the cap was discarded.
    pub fn truncated(&self) -> bool {
        self.truncated
    }

    /// Takes bytes as they were read and returns what has to leave now, in order.
    pub fn push(&mut self, stream: Stream, bytes: &[u8], now: Instant) -> Vec<Chunk> {
        let allowed = bytes.len().min(usize::try_from(self.budget).unwrap_or(usize::MAX));
        self.budget -= allowed as u64;
        self.truncated |= allowed < bytes.len();
        if allowed == 0 {
            return Vec::new();
        }
        let mut chunks = Vec::new();
        if stream != self.stream {
            chunks.extend(self.flush());
            self.stream = stream;
        }
        self.pending.extend_from_slice(&bytes[..allowed]);
        self.since.get_or_insert(now);
        if self.pending.len() >= FLUSH_BYTES {
            chunks.extend(self.flush());
        }
        chunks
    }

    /// When the pending batch is due, if there is one.
    pub fn deadline(&self) -> Option<Instant> {
        self.since.map(|since| since + FLUSH_AFTER)
    }

    /// The pending batch, if it is due at `now`.
    pub fn due(&mut self, now: Instant) -> Vec<Chunk> {
        match self.deadline() {
            Some(deadline) if now >= deadline => self.flush(),
            _ => Vec::new(),
        }
    }

    /// Everything pending, due or not, in frames the host accepts.
    pub fn flush(&mut self) -> Vec<Chunk> {
        self.since = None;
        let pending = std::mem::take(&mut self.pending);
        pending
            .chunks(frame::MAX_PAYLOAD_TO_HOST)
            .map(|bytes| Chunk {
                stream: self.stream,
                bytes: bytes.to_vec(),
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn out(bytes: &[u8]) -> Chunk {
        Chunk {
            stream: Stream::Stdout,
            bytes: bytes.to_vec(),
        }
    }

    fn err(bytes: &[u8]) -> Chunk {
        Chunk {
            stream: Stream::Stderr,
            bytes: bytes.to_vec(),
        }
    }

    #[test]
    fn holds_small_writes_until_the_deadline() {
        let t0 = Instant::now();
        let mut output = Output::new(1000);
        assert!(output.push(Stream::Stdout, b"een\n", t0).is_empty());
        assert!(
            output
                .push(Stream::Stdout, b"twee\n", t0 + Duration::from_millis(10))
                .is_empty()
        );
        assert_eq!(output.deadline(), Some(t0 + FLUSH_AFTER));
        assert!(output.due(t0 + Duration::from_millis(15)).is_empty());
        assert_eq!(output.due(t0 + FLUSH_AFTER), vec![out(b"een\ntwee\n")]);
        assert_eq!(output.deadline(), None);
    }

    #[test]
    fn sends_at_once_when_a_batch_fills() {
        let t0 = Instant::now();
        let mut output = Output::new(1 << 20);
        let line = vec![b'x'; FLUSH_BYTES - 1];
        assert!(output.push(Stream::Stdout, &line, t0).is_empty());
        let sent = output.push(Stream::Stdout, b"yz", t0);
        assert_eq!(sent.len(), 1);
        assert_eq!(sent[0].bytes.len(), FLUSH_BYTES + 1);
        assert_eq!(output.deadline(), None);
    }

    #[test]
    fn a_large_read_leaves_in_frames_the_host_accepts() {
        let t0 = Instant::now();
        let mut output = Output::new(1 << 20);
        let sent = output.push(Stream::Stdout, &vec![b'x'; 40_000], t0);
        let sizes: Vec<usize> = sent.iter().map(|chunk| chunk.bytes.len()).collect();
        assert_eq!(sizes, vec![16384, 16384, 7232]);
    }

    #[test]
    fn keeps_the_order_between_the_streams() {
        let t0 = Instant::now();
        let mut output = Output::new(1000);
        assert!(output.push(Stream::Stdout, b"voor\n", t0).is_empty());
        assert_eq!(output.push(Stream::Stderr, b"Traceback\n", t0), vec![out(b"voor\n")]);
        assert_eq!(output.push(Stream::Stdout, b"na\n", t0), vec![err(b"Traceback\n")]);
        assert_eq!(output.flush(), vec![out(b"na\n")]);
    }

    #[test]
    fn stops_at_the_cap_across_both_streams() {
        let t0 = Instant::now();
        let mut output = Output::new(10);
        output.push(Stream::Stdout, b"123456", t0);
        let mut sent = output.push(Stream::Stderr, b"789012", t0);
        assert!(output.truncated());
        assert!(output.push(Stream::Stdout, b"more", t0).is_empty());
        sent.extend(output.flush());
        assert_eq!(sent, vec![out(b"123456"), err(b"7890")]);
    }

    #[test]
    fn a_cap_of_zero_forwards_nothing() {
        let mut output = Output::new(0);
        assert!(output.push(Stream::Stdout, b"x", Instant::now()).is_empty());
        assert!(output.flush().is_empty());
        assert!(output.truncated());
    }
}
