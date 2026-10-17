//! Frames waiting for the line. They leave whole and in order, except that an urgent frame overtakes
//! every frame that has not started.

use std::collections::VecDeque;

#[derive(Default)]
pub struct Outbox {
    frames: VecDeque<Queued>,
    /// Bytes of the front frame already written.
    written: usize,
}

struct Queued {
    bytes: Vec<u8>,
    urgent: bool,
}

impl Outbox {
    pub fn push(&mut self, bytes: Vec<u8>) {
        self.frames.push_back(Queued { bytes, urgent: false });
    }

    /// Queues `bytes` behind the other urgent frames and ahead of the rest.
    pub fn push_urgent(&mut self, bytes: Vec<u8>) {
        // A frame part-way out cannot be overtaken: the bytes after it would land inside it.
        let first = usize::from(self.written > 0);
        let at = (first..self.frames.len())
            .find(|&i| !self.frames[i].urgent)
            .unwrap_or(self.frames.len());
        self.frames.insert(at, Queued { bytes, urgent: true });
    }

    pub fn is_empty(&self) -> bool {
        self.frames.is_empty()
    }

    /// What is left of the front frame.
    pub fn pending(&self) -> &[u8] {
        self.frames.front().map_or(&[], |front| &front.bytes[self.written..])
    }

    /// Records that the first `n` bytes of [`Outbox::pending`] were written.
    pub fn consume(&mut self, n: usize) {
        let Some(front) = self.frames.front() else {
            assert_eq!(n, 0, "consumed bytes from an empty outbox");
            return;
        };
        self.written += n;
        assert!(self.written <= front.bytes.len(), "consumed past the front frame");
        if self.written == front.bytes.len() {
            self.frames.pop_front();
            self.written = 0;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn drain(outbox: &mut Outbox) -> Vec<u8> {
        let mut out = Vec::new();
        while !outbox.is_empty() {
            let pending = outbox.pending().to_vec();
            out.extend_from_slice(&pending);
            outbox.consume(pending.len());
        }
        out
    }

    #[test]
    fn urgent_frames_overtake_in_their_own_order() {
        let mut outbox = Outbox::default();
        outbox.push(b"a".to_vec());
        outbox.push(b"b".to_vec());
        outbox.push_urgent(b"1".to_vec());
        outbox.push_urgent(b"2".to_vec());
        assert_eq!(drain(&mut outbox), b"12ab");
    }

    #[test]
    fn a_frame_part_way_out_is_finished_first() {
        let mut outbox = Outbox::default();
        outbox.push(b"abc".to_vec());
        outbox.push(b"d".to_vec());
        outbox.consume(1);
        outbox.push_urgent(b"1".to_vec());
        assert_eq!(outbox.pending(), b"bc");
        assert_eq!(drain(&mut outbox), b"bc1d");
    }
}
