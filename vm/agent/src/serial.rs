//! The control line's port. README section 1: the agent owns it and makes it raw before it sends
//! anything.

use std::fs::{File, OpenOptions};
use std::io;
use std::os::fd::AsRawFd;
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;

/// Opens `path` non-blocking and raw, with anything that arrived before discarded.
pub fn open(path: &Path) -> io::Result<File> {
    // O_NOCTTY: the port must not become the agent's controlling terminal, or a hangup on it
    // would signal the agent.
    let port = OpenOptions::new()
        .read(true)
        .write(true)
        .custom_flags(libc::O_NOCTTY | libc::O_NONBLOCK)
        .open(path)?;
    make_raw(&port)?;
    Ok(port)
}

fn make_raw(port: &File) -> io::Result<()> {
    let fd = port.as_raw_fd();
    // SAFETY: fd stays open for the life of `port`, termios is plain data that tcgetattr fills
    // before anything reads it, and every pointer is to that local.
    unsafe {
        let mut termios: libc::termios = std::mem::zeroed();
        check(libc::tcgetattr(fd, &mut termios))?;
        // Echo would send every host frame straight back, and line editing would hold bytes until
        // a newline that COBS never sends.
        libc::cfmakeraw(&mut termios);
        // v86's UART reports no carrier, its modem status starts at zero; CLOCAL makes the tty
        // ignore that line.
        termios.c_cflag |= libc::CLOCAL | libc::CREAD;
        termios.c_cc[libc::VMIN] = 1;
        termios.c_cc[libc::VTIME] = 0;
        check(libc::tcsetattr(fd, libc::TCSANOW, &termios))?;
        // Bytes that arrived before the port was raw went through the line discipline and are
        // not a frame's bytes any more.
        check(libc::tcflush(fd, libc::TCIFLUSH))
    }
}

fn check(result: libc::c_int) -> io::Result<()> {
    if result == -1 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}
