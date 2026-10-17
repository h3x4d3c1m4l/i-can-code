//! The agent's half of the contract with /usr/lib/icc/prelude.py, the warm interpreter's own code.
//!
//! The prelude reads one go-line from fd 3 and writes status lines to fd 4. Both are plain lines,
//! and neither is part of the host protocol: they never leave the guest. The program runs in the
//! prelude's own process and can write to fd 4 as well, so a status line is a claim, not a fact.

use serde::Serialize;

/// Longest status line the agent keeps. The prelude's lines are well under it, so a longer one is
/// a broken prelude, and is cut rather than buffered without bound.
const MAX_LINE: usize = 256;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Status {
    /// The warm-up is done. `xid` is the X window of the root `.` the program will be handed; its
    /// parent, once Tk first maps it, is the top-level window the X server lists.
    Warm { python: String, tk: String, xid: u32 },
    /// Sent before the program exits, for the run's HINT.
    Hint(String),
    /// The program is done: its code returned, and its threads and atexit handlers finished.
    Done,
}

/// Reads one status line, without its newline. `None` for a line this agent does not know.
pub fn parse_status(line: &[u8]) -> Option<Status> {
    let line = std::str::from_utf8(line).ok()?;
    let mut words = line.split(' ');
    match (words.next()?, words.next(), words.next(), words.next(), words.next()) {
        ("warm", Some(python), Some(tk), Some(xid), None) => Some(Status::Warm {
            python: format!("Python {python}"),
            tk: tk.to_owned(),
            xid: xid.parse().ok()?,
        }),
        ("hint", Some(kind), None, None, None) => Some(Status::Hint(kind.to_owned())),
        ("done", None, None, None, None) => Some(Status::Done),
        _ => None,
    }
}

/// The program the warm interpreter runs, as the line it reads from fd 3.
#[derive(Debug, Serialize)]
pub struct Go<'a> {
    pub dir: &'a str,
    pub entry: &'a str,
    pub argv: &'a [String],
    pub tz: &'a str,
}

impl Go<'_> {
    pub fn line(&self) -> Vec<u8> {
        let mut line = serde_json::to_vec(self).expect("strings always serialise");
        line.push(b'\n');
        line
    }
}

/// Splits a byte stream into lines.
#[derive(Default)]
pub struct Lines {
    partial: Vec<u8>,
}

impl Lines {
    pub fn push(&mut self, bytes: &[u8]) -> Vec<Vec<u8>> {
        let mut lines = Vec::new();
        for &byte in bytes {
            if byte == b'\n' {
                lines.push(std::mem::take(&mut self.partial));
            } else if self.partial.len() < MAX_LINE {
                self.partial.push(byte);
            }
        }
        lines
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_warm_line_and_hints() {
        assert_eq!(
            parse_status(b"warm 3.12.14 8.6.16 2097416"),
            Some(Status::Warm {
                python: "Python 3.12.14".into(),
                tk: "8.6.16".into(),
                xid: 2_097_416
            })
        );
        assert_eq!(
            parse_status(b"hint tk_no_mainloop"),
            Some(Status::Hint("tk_no_mainloop".into()))
        );
        assert_eq!(parse_status(b"done"), Some(Status::Done));
        assert_eq!(parse_status(b"done 0"), None);
        assert_eq!(parse_status(b"warm 3.12.14 8.6.16"), None);
        assert_eq!(parse_status(b"warm 3.12.14 8.6.16 0x20 extra"), None);
        assert_eq!(parse_status(b"hello"), None);
        assert_eq!(parse_status(b"\xff"), None);
    }

    #[test]
    fn writes_one_json_line() {
        let argv = ["een".to_owned(), "t\"wee".to_owned()];
        let go = Go {
            dir: "/run/icc/work",
            entry: "main.py",
            argv: &argv,
            tz: "Europe/Amsterdam",
        };
        assert_eq!(
            String::from_utf8(go.line()).unwrap(),
            "{\"dir\":\"/run/icc/work\",\"entry\":\"main.py\",\"argv\":[\"een\",\"t\\\"wee\"],\"tz\":\"Europe/Amsterdam\"}\n"
        );
    }

    #[test]
    fn splits_lines_across_reads_and_bounds_them() {
        let mut lines = Lines::default();
        assert!(lines.push(b"warm 3.12").is_empty());
        assert_eq!(
            lines.push(b".14 8.6.16 1\nhint a\nhi"),
            vec![b"warm 3.12.14 8.6.16 1".to_vec(), b"hint a".to_vec()]
        );
        let long = vec![b'x'; 10_000];
        assert!(lines.push(&long).is_empty());
        let cut = lines.push(b"\n");
        assert_eq!(cut[0].len(), MAX_LINE);
        assert!(cut[0].starts_with(b"hi"));
    }
}
