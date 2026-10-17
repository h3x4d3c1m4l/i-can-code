//! The guest's wall clock. A restored machine starts with the clock of the moment the snapshot was
//! saved, and the host stops the guest's TSC while it is parked, so HELLO carries the host's time.

use std::io;

/// Sets `CLOCK_REALTIME` to `now_ms`, Unix epoch milliseconds.
#[cfg(target_os = "linux")]
pub fn set_realtime(now_ms: u64) -> io::Result<()> {
    // SAFETY: timespec is plain data; zeroed covers the padding some 32-bit ABIs add to it.
    let mut time: libc::timespec = unsafe { std::mem::zeroed() };
    // Whatever width tv_sec has here: 32 bits in the libc crate's view of 32-bit musl.
    time.tv_sec = (now_ms / 1000).try_into().map_err(|_| io::ErrorKind::InvalidInput)?;
    time.tv_nsec = ((now_ms % 1000) * 1_000_000) as libc::c_long;
    // SAFETY: clock_settime reads the timespec it is given.
    if unsafe { libc::clock_settime(libc::CLOCK_REALTIME, &time) } == -1 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

#[cfg(not(target_os = "linux"))]
pub fn set_realtime(_: u64) -> io::Result<()> {
    Err(io::ErrorKind::Unsupported.into())
}
