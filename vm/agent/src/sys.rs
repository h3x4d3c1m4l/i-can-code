//! The system calls that exist only on Linux. Elsewhere each fails with `Unsupported`, so that the
//! rest of the agent builds, lints and tests on any Unix, a developer's Mac included.

use std::io;
use std::path::Path;

#[cfg(target_os = "linux")]
mod linux {
    use std::ffi::CString;
    use std::io;
    use std::os::fd::{FromRawFd, OwnedFd};
    use std::os::unix::ffi::OsStrExt;
    use std::path::Path;
    use std::ptr;

    fn c_path(path: &Path) -> io::Result<CString> {
        CString::new(path.as_os_str().as_bytes()).map_err(|_| io::ErrorKind::InvalidInput.into())
    }

    fn check(result: libc::c_int) -> io::Result<()> {
        if result == -1 {
            Err(io::Error::last_os_error())
        } else {
            Ok(())
        }
    }

    pub fn mount_tmpfs(target: &Path, options: &str) -> io::Result<()> {
        let target = c_path(target)?;
        let options = CString::new(options).map_err(|_| io::ErrorKind::InvalidInput)?;
        // SAFETY: every pointer is to a NUL-terminated string that outlives the call.
        check(unsafe {
            libc::mount(
                c"tmpfs".as_ptr(),
                target.as_ptr(),
                c"tmpfs".as_ptr(),
                libc::MS_NOSUID | libc::MS_NODEV,
                options.as_ptr().cast(),
            )
        })
    }

    pub fn mount_cgroup2(target: &Path) -> io::Result<()> {
        let target = c_path(target)?;
        // SAFETY: every pointer is to a NUL-terminated string that outlives the call.
        check(unsafe {
            libc::mount(
                c"cgroup2".as_ptr(),
                target.as_ptr(),
                c"cgroup2".as_ptr(),
                libc::MS_NOSUID | libc::MS_NODEV | libc::MS_NOEXEC,
                ptr::null(),
            )
        })
    }

    /// Caps `pid`'s RLIMIT_DATA, which counts its heap and private anonymous mappings.
    pub fn limit_data(pid: libc::pid_t, bytes: u64) -> io::Result<()> {
        let limit = libc::rlimit {
            rlim_cur: bytes,
            rlim_max: bytes,
        };
        // SAFETY: prlimit reads the limit it is given and writes no old limit.
        check(unsafe { libc::prlimit(pid, libc::RLIMIT_DATA, &limit, ptr::null_mut()) })
    }

    /// Sets no_new_privs: from now on no exec gains privileges from a setuid bit or a capability.
    ///
    /// Children inherit it. A bare prctl(2), so a forked child MAY call it before exec.
    pub fn forbid_new_privileges() -> io::Result<()> {
        // SAFETY: prctl with PR_SET_NO_NEW_PRIVS reads only its integer arguments.
        check(unsafe { libc::prctl(libc::PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) })
    }

    /// Sets the calling thread's nice value, which threads and processes it starts inherit.
    pub fn set_nice(nice: libc::c_int) -> io::Result<()> {
        // SAFETY: setpriority takes plain integers.
        check(unsafe { libc::setpriority(libc::PRIO_PROCESS, 0, nice) })
    }

    /// Keeps every page of this process in RAM, now and later.
    pub fn lock_memory() -> io::Result<()> {
        // SAFETY: mlockall takes flags only.
        check(unsafe { libc::mlockall(libc::MCL_CURRENT | libc::MCL_FUTURE) })
    }

    pub fn remount_read_only(target: &Path, bind: bool) -> io::Result<()> {
        let target = c_path(target)?;
        let bind = if bind { libc::MS_BIND } else { 0 };
        // SAFETY: a remount reads no source, type or data; the target outlives the call.
        check(unsafe {
            libc::mount(
                ptr::null(),
                target.as_ptr(),
                ptr::null(),
                libc::MS_REMOUNT | libc::MS_RDONLY | bind,
                ptr::null(),
            )
        })
    }

    /// An fd that turns readable once the process has exited, so poll(2) can wait for it beside
    /// the process's pipes.
    pub fn pidfd_open(pid: libc::pid_t) -> io::Result<OwnedFd> {
        // SAFETY: pidfd_open takes a pid and flags and returns a new fd or -1.
        let fd = unsafe { libc::syscall(libc::SYS_pidfd_open, pid, 0) };
        if fd == -1 {
            return Err(io::Error::last_os_error());
        }
        // SAFETY: the kernel just returned this fd, and nothing else owns it.
        Ok(unsafe { OwnedFd::from_raw_fd(fd as libc::c_int) })
    }
}

#[cfg(target_os = "linux")]
pub use linux::{
    forbid_new_privileges, limit_data, lock_memory, mount_cgroup2, mount_tmpfs, pidfd_open, remount_read_only, set_nice,
};

#[cfg(not(target_os = "linux"))]
pub fn mount_tmpfs(_: &Path, _: &str) -> io::Result<()> {
    Err(io::ErrorKind::Unsupported.into())
}

#[cfg(not(target_os = "linux"))]
pub fn limit_data(_: libc::pid_t, _: u64) -> io::Result<()> {
    Err(io::ErrorKind::Unsupported.into())
}

#[cfg(not(target_os = "linux"))]
pub fn forbid_new_privileges() -> io::Result<()> {
    Err(io::ErrorKind::Unsupported.into())
}

#[cfg(not(target_os = "linux"))]
pub fn set_nice(_: libc::c_int) -> io::Result<()> {
    Err(io::ErrorKind::Unsupported.into())
}

#[cfg(not(target_os = "linux"))]
pub fn lock_memory() -> io::Result<()> {
    Err(io::ErrorKind::Unsupported.into())
}

#[cfg(not(target_os = "linux"))]
pub fn mount_cgroup2(_: &Path) -> io::Result<()> {
    Err(io::ErrorKind::Unsupported.into())
}

#[cfg(not(target_os = "linux"))]
pub fn remount_read_only(_: &Path, _: bool) -> io::Result<()> {
    Err(io::ErrorKind::Unsupported.into())
}

#[cfg(not(target_os = "linux"))]
pub fn pidfd_open(_: libc::pid_t) -> io::Result<std::os::fd::OwnedFd> {
    Err(io::ErrorKind::Unsupported.into())
}

/// Whether the filesystem holding `path` is mounted read-only, as statvfs(3) reports it.
pub fn is_read_only(path: &Path) -> io::Result<bool> {
    use std::os::unix::ffi::OsStrExt;
    let path = std::ffi::CString::new(path.as_os_str().as_bytes()).map_err(|_| io::ErrorKind::InvalidInput)?;
    // SAFETY: statvfs fills the struct it is given, and the path outlives the call.
    unsafe {
        let mut stat: libc::statvfs = std::mem::zeroed();
        if libc::statvfs(path.as_ptr(), &mut stat) == -1 {
            return Err(io::Error::last_os_error());
        }
        Ok(stat.f_flag & libc::ST_RDONLY != 0)
    }
}
