//! The agent's main thread: a poll(2) over its file descriptors, with the agent's next deadline as
//! the timeout. It never waits on the X server, which has a thread of its own (`x11.rs`), so a
//! PING is answered whatever a program does to X.

use crate::agent::Agent;
use crate::outbox::Outbox;
use crate::serial;
use crate::supervisor::Supervisor;
use std::convert::Infallible;
use std::fs::File;
use std::io::{self, Read, Write};
use std::os::fd::AsRawFd;
use std::path::Path;
use std::time::Instant;

/// Serves the control line on the port at `path` until the port fails.
pub fn serve(path: &Path) -> io::Result<Infallible> {
    let mut port = serial::open(path)?;
    let mut agent = Agent::new(Instant::now());
    let mut supervisor = Supervisor::default();
    // One read per wakeup, answered before the next: a PING in a burst is not held up by the rest
    // of the burst.
    let mut buffer = [0u8; 4096];
    let mut fds = Vec::new();
    loop {
        // PREPARE blocks here for its whole length. The host sends nothing while it waits for
        // PARKED, and README 6.16 allows a late PONG meanwhile.
        while let Some(action) = agent.take_action() {
            supervisor.perform(action, &mut agent);
        }
        write_pending(&mut port, agent.outbox())?;

        let mut events = libc::POLLIN;
        if !agent.outbox().is_empty() {
            events |= libc::POLLOUT;
        }
        fds.clear();
        fds.push(libc::pollfd {
            fd: port.as_raw_fd(),
            events,
            revents: 0,
        });
        supervisor.watch(&mut fds);
        poll(&mut fds, timeout_ms(agent.next_deadline(), Instant::now()))?;

        let revents = fds[0].revents;
        if revents & libc::POLLNVAL != 0 {
            return Err(io::Error::other("the serial port is not open"));
        }
        if revents & (libc::POLLIN | libc::POLLHUP | libc::POLLERR) != 0 {
            match port.read(&mut buffer) {
                Ok(0) => return Err(io::Error::new(io::ErrorKind::UnexpectedEof, "the serial port hung up")),
                Ok(n) => agent.on_serial(&buffer[..n], Instant::now()),
                Err(e) if matches!(e.kind(), io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted) => {}
                Err(e) => return Err(e),
            }
        }
        supervisor.on_poll(&fds[1..], &mut agent);
        agent.on_tick(Instant::now());
    }
}

/// Writes until the outbox is empty or the port has no room.
fn write_pending(port: &mut File, outbox: &mut Outbox) -> io::Result<()> {
    while !outbox.is_empty() {
        match port.write(outbox.pending()) {
            Ok(0) => return Err(io::ErrorKind::WriteZero.into()),
            Ok(n) => outbox.consume(n),
            Err(e) if e.kind() == io::ErrorKind::WouldBlock => return Ok(()),
            Err(e) if e.kind() == io::ErrorKind::Interrupted => {}
            Err(e) => return Err(e),
        }
    }
    Ok(())
}

/// A signal leaves every `revents` zero, which the loop reads as nothing to do.
fn poll(fds: &mut [libc::pollfd], timeout_ms: libc::c_int) -> io::Result<()> {
    // SAFETY: the pointer and length describe `fds`, which outlives the call.
    let result = unsafe { libc::poll(fds.as_mut_ptr(), fds.len() as libc::nfds_t, timeout_ms) };
    if result == -1 {
        let error = io::Error::last_os_error();
        if error.kind() != io::ErrorKind::Interrupted {
            return Err(error);
        }
    }
    Ok(())
}

/// poll(2)'s timeout for `deadline`: -1 without one.
fn timeout_ms(deadline: Option<Instant>, now: Instant) -> libc::c_int {
    let Some(deadline) = deadline else {
        return -1;
    };
    // Rounded up, so the loop does not wake just short of the deadline and poll again for zero.
    let ms = deadline.saturating_duration_since(now).as_micros().div_ceil(1000);
    libc::c_int::try_from(ms).unwrap_or(libc::c_int::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::frame::{self, Decoder};
    use crate::proto::{Hello, Message, Side};
    use std::ffi::CStr;
    use std::os::fd::FromRawFd;
    use std::path::PathBuf;
    use std::sync::mpsc;
    use std::thread;
    use std::time::Duration;

    const TIMEOUT: Duration = Duration::from_secs(5);

    /// A pseudo-terminal pair. The agent opens the slave as its serial port, and the test plays the
    /// host on the master.
    fn open_pty() -> (File, PathBuf) {
        // SAFETY: each call gets the fd posix_openpt returned, and ptsname's string is copied out
        // before anything else could overwrite it.
        unsafe {
            let master = libc::posix_openpt(libc::O_RDWR | libc::O_NOCTTY);
            assert!(master >= 0, "posix_openpt: {}", io::Error::last_os_error());
            assert_eq!(libc::grantpt(master), 0, "grantpt: {}", io::Error::last_os_error());
            assert_eq!(libc::unlockpt(master), 0, "unlockpt: {}", io::Error::last_os_error());
            let name = libc::ptsname(master);
            assert!(!name.is_null(), "ptsname: {}", io::Error::last_os_error());
            let path = PathBuf::from(CStr::from_ptr(name).to_str().unwrap());
            (File::from_raw_fd(master), path)
        }
    }

    /// Reads from the master until a message arrives, skipping CREDIT and LOG.
    fn next_message(master: &mut File, decoder: &mut Decoder, queue: &mut Vec<(u32, Message)>) -> (u32, Message) {
        let until = Instant::now() + TIMEOUT;
        loop {
            if let Some(i) = queue
                .iter()
                .position(|(_, m)| !matches!(m, Message::Credit(_) | Message::Log(_)))
            {
                return queue.remove(i);
            }
            let mut fds = [libc::pollfd {
                fd: master.as_raw_fd(),
                events: libc::POLLIN,
                revents: 0,
            }];
            let left = until.saturating_duration_since(Instant::now());
            assert!(!left.is_zero(), "no message from the agent within {TIMEOUT:?}");
            poll(&mut fds, timeout_ms(Some(until), Instant::now())).unwrap();
            if fds[0].revents & libc::POLLIN == 0 {
                continue;
            }
            let mut buffer = [0u8; 4096];
            let n = master.read(&mut buffer).unwrap();
            for event in decoder.push(&buffer[..n]) {
                let frame = event.expect("the agent writes good frames");
                queue.push((frame.id, Message::decode(&frame, Side::Agent).unwrap()));
            }
        }
    }

    #[test]
    fn serves_a_pty_until_it_hangs_up() {
        let (mut master, path) = open_pty();
        let (done, finished) = mpsc::channel();
        thread::spawn(move || {
            let Err(error) = serve(&path);
            done.send(error).unwrap();
        });

        let mut decoder = Decoder::new(frame::MAX_PAYLOAD_TO_HOST);
        let mut queue = Vec::new();
        let (id, ready) = next_message(&mut master, &mut decoder, &mut queue);
        assert_eq!(id, 0);
        assert!(matches!(ready, Message::Ready(ref r) if !r.warm), "{ready:?}");

        master.write_all(&Message::Ping.encode(42).unwrap()).unwrap();
        assert_eq!(next_message(&mut master, &mut decoder, &mut queue), (42, Message::Pong));

        let hello = Message::Hello(Hello {
            now_ms: 1,
            tz: "UTC".into(),
            entropy: "ab".repeat(64),
        });
        master.write_all(&hello.encode(43).unwrap()).unwrap();
        let (id, ready) = next_message(&mut master, &mut decoder, &mut queue);
        assert_eq!(id, 43);
        assert!(matches!(ready, Message::Ready(_)), "{ready:?}");

        drop(master);
        finished.recv_timeout(TIMEOUT).expect("serve returned after the hangup");
    }

    #[test]
    fn timeout_rounds_up_to_the_deadline() {
        let now = Instant::now();
        assert_eq!(timeout_ms(None, now), -1);
        assert_eq!(timeout_ms(Some(now), now), 0);
        assert_eq!(timeout_ms(Some(now + Duration::from_micros(1)), now), 1);
        assert_eq!(timeout_ms(Some(now + Duration::from_millis(16)), now), 16);
        assert_eq!(timeout_ms(Some(now - Duration::from_millis(5)), now), 0);
    }
}
