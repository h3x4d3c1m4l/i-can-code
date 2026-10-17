//! Holds LOG to 20 frames a second. The ones over the limit become a count, sent once the second is
//! over.

use std::time::{Duration, Instant};

const WINDOW: Duration = Duration::from_secs(1);
const PER_WINDOW: u32 = 20;

#[derive(Default)]
pub struct LogLimit {
    window_start: Option<Instant>,
    sent: u32,
    suppressed: u32,
}

impl LogLimit {
    /// Whether one more LOG may go out at `now`. A refused one is counted.
    ///
    /// Call [`LogLimit::take_suppressed`] first, or the count of an earlier second waits a second
    /// longer.
    pub fn admit(&mut self, now: Instant) -> bool {
        self.roll(now);
        if self.sent < PER_WINDOW {
            self.sent += 1;
            true
        } else {
            self.suppressed += 1;
            false
        }
    }

    /// How many LOGs the second that has just ended refused. The caller MUST send the count as a
    /// LOG, which this already counts against the new second.
    pub fn take_suppressed(&mut self, now: Instant) -> Option<u32> {
        if self.suppressed == 0 || self.window_start.is_some_and(|start| now < start + WINDOW) {
            return None;
        }
        let suppressed = std::mem::take(&mut self.suppressed);
        self.roll(now);
        self.sent += 1;
        Some(suppressed)
    }

    /// When [`LogLimit::take_suppressed`] will have a count to give.
    pub fn deadline(&self) -> Option<Instant> {
        if self.suppressed == 0 {
            return None;
        }
        self.window_start.map(|start| start + WINDOW)
    }

    fn roll(&mut self, now: Instant) {
        if self.window_start.is_none_or(|start| now >= start + WINDOW) {
            self.window_start = Some(now);
            self.sent = 0;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn twenty_a_second_then_one_count() {
        let t0 = Instant::now();
        let mut limit = LogLimit::default();
        let admitted = (0..25).filter(|_| limit.admit(t0)).count();
        assert_eq!(admitted, 20);
        assert_eq!(limit.deadline(), Some(t0 + WINDOW));
        assert_eq!(limit.take_suppressed(t0 + WINDOW / 2), None);

        let t1 = t0 + WINDOW;
        assert_eq!(limit.take_suppressed(t1), Some(5));
        assert_eq!(limit.take_suppressed(t1), None);
        assert_eq!(limit.deadline(), None);
        assert_eq!((0..25).filter(|_| limit.admit(t1)).count(), 19);
    }
}
