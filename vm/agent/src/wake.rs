//! A channel whose receiver waits in poll(2) beside file descriptors: every send also writes a byte
//! to a pipe that the receiver polls. It is how the X watcher's thread and the event loop reach each
//! other without either one blocking on the other.

use std::fs::File;
use std::io::{self, Read, Write};
use std::os::fd::{AsRawFd, OwnedFd, RawFd};
use std::sync::mpsc::{self, TryRecvError};

pub struct Sender<T> {
    values: mpsc::Sender<T>,
    pipe: File,
}

pub struct Receiver<T> {
    values: mpsc::Receiver<T>,
    pipe: File,
}

/// The other end is gone.
#[derive(Debug, PartialEq, Eq)]
pub struct Gone;

pub fn channel<T>() -> io::Result<(Sender<T>, Receiver<T>)> {
    let (reader, writer) = io::pipe()?;
    let (reader, writer) = (File::from(OwnedFd::from(reader)), File::from(OwnedFd::from(writer)));
    for pipe in [&reader, &writer] {
        set_nonblocking(pipe.as_raw_fd())?;
    }
    let (sender, receiver) = mpsc::channel();
    Ok((
        Sender {
            values: sender,
            pipe: writer,
        },
        Receiver {
            values: receiver,
            pipe: reader,
        },
    ))
}

impl<T> Sender<T> {
    pub fn send(&self, value: T) -> Result<(), Gone> {
        self.values.send(value).map_err(|_| Gone)?;
        // The value goes first: a receiver that drains the pipe and then the channel cannot miss
        // it. A full pipe already holds a wakeup the receiver has not read, so EAGAIN is no loss.
        let _ = (&self.pipe).write(&[1]);
        Ok(())
    }
}

impl<T> Receiver<T> {
    /// Polls readable when something may have been sent.
    pub fn fd(&self) -> RawFd {
        self.pipe.as_raw_fd()
    }

    /// Everything sent so far, in order. [`Gone`] once the sender is dropped and nothing is left.
    pub fn drain(&self) -> Result<Vec<T>, Gone> {
        let mut bytes = [0u8; 64];
        while matches!((&self.pipe).read(&mut bytes), Ok(n) if n > 0) {}
        let mut values = Vec::new();
        loop {
            match self.values.try_recv() {
                Ok(value) => values.push(value),
                Err(TryRecvError::Empty) => return Ok(values),
                Err(TryRecvError::Disconnected) if values.is_empty() => return Err(Gone),
                Err(TryRecvError::Disconnected) => return Ok(values),
            }
        }
    }
}

fn set_nonblocking(fd: RawFd) -> io::Result<()> {
    // SAFETY: fcntl on an fd the caller owns.
    unsafe {
        let flags = libc::fcntl(fd, libc::F_GETFL);
        if flags == -1 || libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK) == -1 {
            return Err(io::Error::last_os_error());
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::thread;
    use std::time::Duration;

    fn readable(fd: RawFd, timeout_ms: libc::c_int) -> bool {
        let mut fds = [libc::pollfd {
            fd,
            events: libc::POLLIN,
            revents: 0,
        }];
        // SAFETY: the pointer and length describe `fds`, which outlives the call.
        unsafe { libc::poll(fds.as_mut_ptr(), 1, timeout_ms) };
        fds[0].revents & libc::POLLIN != 0
    }

    #[test]
    fn a_send_wakes_a_poll_and_arrives_in_order() {
        let (sender, receiver) = channel().unwrap();
        assert!(!readable(receiver.fd(), 0));
        let worker = thread::spawn(move || {
            thread::sleep(Duration::from_millis(20));
            for i in 0..3 {
                sender.send(i).unwrap();
            }
            sender
        });
        assert!(readable(receiver.fd(), 5_000));
        let mut got = Vec::new();
        while got.len() < 3 {
            got.extend(receiver.drain().unwrap());
        }
        assert_eq!(got, [0, 1, 2]);
        assert!(!readable(receiver.fd(), 0), "drain empties the pipe");
        let sender = worker.join().unwrap();
        drop(sender);
        assert!(readable(receiver.fd(), 0), "a closed pipe polls readable");
        assert_eq!(receiver.drain(), Err(Gone));
    }

    #[test]
    fn more_sends_than_the_pipe_holds_lose_nothing() {
        let (sender, receiver) = channel().unwrap();
        for i in 0..100_000 {
            sender.send(i).unwrap();
        }
        let got = receiver.drain().unwrap();
        assert_eq!(got.len(), 100_000);
        assert_eq!(got.last(), Some(&99_999));
    }

    #[test]
    fn a_send_to_a_dropped_receiver_fails() {
        let (sender, receiver) = channel::<u8>().unwrap();
        drop(receiver);
        assert_eq!(sender.send(1), Err(Gone));
    }
}
