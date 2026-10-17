//! A run's files: from where the host wrote them over 9p into the working directory the program
//! runs in (README 6.3).

use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt, chown};
use std::path::{Path, PathBuf};

/// Where the host writes a run's files. Only root can read it, so a program cannot see the files
/// of a run that is not its own.
pub const IN_DIR: &str = "/icc/in";
pub const MAX_FILES_BYTES: u64 = 8 * 1024 * 1024;

/// tmpfs allocates whole pages.
const PAGE_BYTES: u64 = 4096;

/// A copy drops what it has read of the source from the page cache every this many bytes.
const COPY_CHUNK: usize = 256 * 1024;

/// The host's name for file `name` of run `run`. The run id makes it a name the guest's
/// `cache=loose` mount has never looked up.
pub fn in_path(dir: &Path, run: u32, name: &str) -> PathBuf {
    dir.join(format!("r{run}-{name}"))
}

/// Replaces `work` with a directory owned by `owner` (uid, gid) that holds the run's files.
/// Returns the bytes of memory they take there: `work` is a tmpfs, and its pages are charged to
/// the agent, not to the run.
///
/// `names` MUST have passed the protocol's file-name check, which allows no `/` and no leading
/// dot, so every path stays inside `work`.
pub fn stage(from: &Path, run: u32, names: &[String], work: &Path, owner: (u32, u32)) -> Result<u64, String> {
    let (uid, gid) = owner;
    let mut total = 0;
    // The directory's own page, and each file rounded up to whole pages.
    let mut needed = PAGE_BYTES;
    for name in names {
        let meta = fs::metadata(in_path(from, run, name)).map_err(|error| format!("{name}: {error}"))?;
        if !meta.is_file() {
            return Err(format!("{name}: not a regular file"));
        }
        total += meta.len();
        needed += meta.len().next_multiple_of(PAGE_BYTES);
    }
    if total > MAX_FILES_BYTES {
        return Err(format!("the files add up to {total} bytes, over {MAX_FILES_BYTES}"));
    }
    match fs::remove_dir_all(work) {
        Err(error) if error.kind() != io::ErrorKind::NotFound => return Err(context(work)(error)),
        _ => {}
    }
    // PREPARE sizes the tmpfs for the largest run, so this only fails if that is ever wrong, and
    // then it says so rather than leaving a copy half done with ENOSPC.
    let parent = work.parent().unwrap_or(Path::new("/"));
    let free = free_bytes(parent).map_err(context(parent))?;
    if needed > free {
        return Err(format!(
            "the files need {needed} bytes in {}, which has {free} free",
            parent.display()
        ));
    }
    fs::create_dir(work).map_err(context(work))?;
    fs::set_permissions(work, fs::Permissions::from_mode(0o700)).map_err(context(work))?;
    chown(work, Some(uid), Some(gid)).map_err(context(work))?;
    for name in names {
        let target = work.join(name);
        copy(&in_path(from, run, name), &target)?;
        fs::set_permissions(&target, fs::Permissions::from_mode(0o644)).map_err(context(&target))?;
        chown(&target, Some(uid), Some(gid)).map_err(context(&target))?;
    }
    Ok(needed)
}

/// Copies `from` to a new file `to` without keeping `from` in the page cache. The source is on
/// 9p, whose pages the guest caches, and a run's files may be 8 MiB: left there, they would compete
/// with the pages Xorg and the interpreter map, which a page fetches over the network if evicted.
fn copy(from: &Path, to: &Path) -> Result<(), String> {
    let mut source = File::open(from).map_err(context(from))?;
    let mut target = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o644)
        .open(to)
        .map_err(context(to))?;
    let mut buffer = vec![0u8; COPY_CHUNK];
    let mut offset = 0;
    loop {
        let n = match source.read(&mut buffer) {
            Ok(0) => return Ok(()),
            Ok(n) => n,
            Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
            Err(error) => return Err(context(from)(error)),
        };
        target.write_all(&buffer[..n]).map_err(context(to))?;
        forget(&source, offset, n);
        offset += n as u64;
    }
}

/// Drops `len` bytes of `file` from `offset` on out of the page cache. Only advice: a failure
/// costs memory, not the copy.
#[cfg(target_os = "linux")]
fn forget(file: &File, offset: u64, len: usize) {
    use std::os::fd::AsRawFd;
    let (Ok(offset), Ok(len)) = (libc::off_t::try_from(offset), libc::off_t::try_from(len)) else {
        return;
    };
    // SAFETY: posix_fadvise reads nothing but its arguments.
    unsafe { libc::posix_fadvise(file.as_raw_fd(), offset, len, libc::POSIX_FADV_DONTNEED) };
}

#[cfg(not(target_os = "linux"))]
fn forget(_file: &File, _offset: u64, _len: usize) {}

/// What an unprivileged writer may still put in the filesystem holding `path`.
fn free_bytes(path: &Path) -> io::Result<u64> {
    use std::os::unix::ffi::OsStrExt;
    let path = std::ffi::CString::new(path.as_os_str().as_bytes()).map_err(|_| io::ErrorKind::InvalidInput)?;
    // SAFETY: statvfs fills the struct it is given, and the path outlives the call.
    unsafe {
        let mut stat: libc::statvfs = std::mem::zeroed();
        if libc::statvfs(path.as_ptr(), &mut stat) == -1 {
            return Err(io::Error::last_os_error());
        }
        // Their widths differ between the guest's musl and a developer's Mac.
        #[allow(clippy::unnecessary_cast, clippy::useless_conversion)]
        let free = u64::from(stat.f_bavail) * stat.f_frsize as u64;
        Ok(free)
    }
}

fn context(path: &Path) -> impl Fn(io::Error) -> String + '_ {
    move |error| format!("{}: {error}", path.display())
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Scratch(PathBuf);

    impl Scratch {
        fn new(name: &str) -> Scratch {
            let dir = std::env::temp_dir().join(format!("icc-files-{name}-{}", std::process::id()));
            let _ = fs::remove_dir_all(&dir);
            fs::create_dir_all(dir.join("in")).unwrap();
            Scratch(dir)
        }
    }

    impl Drop for Scratch {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn me() -> (u32, u32) {
        // SAFETY: getuid and getgid cannot fail.
        unsafe { (libc::getuid(), libc::getgid()) }
    }

    #[test]
    fn copies_the_runs_files_and_nothing_else() {
        let scratch = Scratch::new("copy");
        let from = scratch.0.join("in");
        fs::write(in_path(&from, 7, "main.py"), b"print(1)").unwrap();
        fs::write(in_path(&from, 7, "picture.png"), b"png").unwrap();
        fs::write(in_path(&from, 6, "main.py"), b"old run").unwrap();
        let work = scratch.0.join("work");
        fs::create_dir(&work).unwrap();
        fs::write(work.join("left-over"), b"x").unwrap();

        let names = ["main.py".to_owned(), "picture.png".to_owned()];
        // The directory's page and one page for each file.
        assert_eq!(stage(&from, 7, &names, &work, me()).unwrap(), 3 * PAGE_BYTES);
        let mut listed: Vec<String> = fs::read_dir(&work)
            .unwrap()
            .map(|entry| entry.unwrap().file_name().into_string().unwrap())
            .collect();
        listed.sort();
        assert_eq!(listed, ["main.py", "picture.png"]);
        assert_eq!(fs::read(work.join("main.py")).unwrap(), b"print(1)");
    }

    #[test]
    fn copies_a_file_larger_than_a_chunk_whole() {
        let scratch = Scratch::new("large");
        let from = scratch.0.join("in");
        let data: Vec<u8> = (0..COPY_CHUNK * 2 + 17).map(|i| (i % 251) as u8).collect();
        fs::write(in_path(&from, 1, "data.bin"), &data).unwrap();
        let work = scratch.0.join("work");
        let taken = stage(&from, 1, &["data.bin".to_owned()], &work, me()).unwrap();
        assert_eq!(fs::read(work.join("data.bin")).unwrap(), data);
        assert_eq!(taken, PAGE_BYTES + (data.len() as u64).next_multiple_of(PAGE_BYTES));
        let mode = fs::metadata(work.join("data.bin")).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o644);
    }

    #[test]
    fn refuses_a_missing_file() {
        let scratch = Scratch::new("missing");
        let error = stage(
            &scratch.0.join("in"),
            3,
            &["main.py".to_owned()],
            &scratch.0.join("work"),
            me(),
        );
        assert!(error.unwrap_err().starts_with("main.py: "));
    }
}
