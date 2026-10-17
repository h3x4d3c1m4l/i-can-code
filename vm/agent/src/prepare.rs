//! PREPARE (README 6.16): turns the freshly booted guest into the machine the snapshot holds. It runs
//! once, at build time, and every page restores what it leaves behind.

use crate::agent::Prepared;
use crate::cgroup::{self, Group};
use crate::prelude::{self, Lines, Status};
use crate::procfs;
use crate::proto::{Parked, Prepare};
use crate::supervisor::Warm;
use crate::sys;
use crate::x11;
use std::collections::BTreeMap;
use std::ffi::CString;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read};
use std::os::fd::{AsRawFd, OwnedFd, RawFd};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::MetadataExt;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

pub const STUDENT_UID: u32 = 1000;

/// Each capped, because every page a guest writes into is a page of RAM and of the host's memory.
/// The run's memory budget bounds what a program writes into all of them together; the caps keep
/// one directory from taking all of it.
///
/// /run/icc holds a run's files, [`crate::files::MAX_FILES_BYTES`] at most and each rounded up to a
/// page, beside Xorg's log. /dev/shm is Alpine's, mounted with no size at all, so this mounts a capped one over it.
const TMPFS: [(&str, &str); 4] = [
    ("/run/icc", "size=12m,mode=0755"),
    ("/tmp", "size=8m,mode=1777"),
    ("/home/student", "size=8m,mode=0700,uid=1000,gid=1000"),
    ("/dev/shm", "size=8m,mode=1777"),
];

/// Memory the run's budget leaves for what the kernel allocates on a program's behalf outside its
/// group.
const SYSTEM_HEADROOM_KB: u64 = 2048;

/// How far Xorg's data segment may grow past its warm size: room the run's budget leaves free.
///
/// Xorg allocates a program's pixmaps outside the run's group. Tk redraws a Canvas through one the
/// size of the part it redraws, 7.9 MiB at 1920 x 1080, and a full-HD PhotoImage has Xorg peak
/// 16 MB above its warm size while Tk hands it over. Uncapped, a 3000 x 3000 Canvas made the kernel
/// evict every mapped page and the guest stopped answering; capped, it is a BadAlloc. Counted in
/// the budget as well, Xorg found its room by evicting mapped files, which the run fetched again.
const XORG_DATA_GROWTH_KB: u64 = 16384;

const XORG_LOG: &str = "/run/icc/xorg.log";
const PRELUDE: &str = "/usr/lib/icc/prelude.py";

/// Measured under v86 on an M1: Xorg answers after about 5 s and the warm-up takes about 8 s.
/// These allow for a build host that is several times slower.
const XORG_TIMEOUT: Duration = Duration::from_secs(120);
const WARM_TIMEOUT: Duration = Duration::from_secs(600);

const ZERO_CHUNKS: [usize; 2] = [1 << 20, 64 << 10];

/// The environment of the warm interpreter, and so of every program.
const STUDENT_ENV: [(&str, &str); 8] = [
    ("DISPLAY", ":0"),
    ("HOME", "/home/student"),
    ("LANG", "C.UTF-8"),
    ("LOGNAME", "student"),
    ("PATH", "/usr/local/bin:/usr/bin:/bin"),
    ("PYTHONDONTWRITEBYTECODE", "1"),
    ("PYTHONUNBUFFERED", "1"),
    ("USER", "student"),
];

/// What PREPARE hands the supervisor, and the measurements it LOGs.
pub struct Outcome {
    pub warm: Warm,
    pub windows: x11::Windows,
    pub group: Group,
    pub prepared: Prepared,
    pub notes: Vec<String>,
}

/// A program the student runs, with the pipes the agent reads it through.
pub struct Child {
    pub pid: libc::pid_t,
    pub stdout: File,
    pub stderr: File,
    /// The prelude's status pipe; `None` for a program started without the prelude.
    pub status: Option<File>,
}

pub fn prepare(request: &Prepare) -> Result<Outcome, String> {
    let mut notes = Vec::new();

    // Xorg and the warm interpreter inherit it; the interpreter raises its own to 1000 again.
    fs::write("/proc/self/oom_score_adj", "-1000").map_err(context("oom_score_adj"))?;
    for (path, options) in TMPFS {
        fs::create_dir_all(path).map_err(context(path))?;
        sys::mount_tmpfs(Path::new(path), options).map_err(context(path))?;
    }

    let started = Instant::now();
    let xorg = start_xorg()?;
    let xorg_ms = started.elapsed().as_millis();
    let started = Instant::now();
    let (warm, python, tk, printed) = start_interpreter()?;
    notes.push(format!(
        "Xorg answered after {xorg_ms} ms; the warm interpreter ({python}, Tk {tk}) after {} ms",
        started.elapsed().as_millis()
    ));
    if !printed.is_empty() {
        notes.push(format!("the warm-up printed: {printed}"));
    }
    // After the warm-up, whose windows it would otherwise hear about, and before the zero-fill, so
    // the memory the connection and its thread hold is not in the part of RAM the snapshot stores
    // as zeros.
    let windows = x11::Windows::spawn(x11::Watcher::connect(":0")?).map_err(context("the X watcher's thread"))?;

    notes.push(remount_root_read_only()?);

    // The agent's own binary too: a page of it that nothing touched before the save is a fetch
    // over the network the first time a run needs it.
    let processes = [("interpreter", warm.pid), ("Xorg", xorg), ("agent", std::process::id())];
    let mut memory = Memory::default();
    memory.sample("warm", &processes)?;

    // What boot read and nothing maps any more, so the zero-fill can reclaim its pages.
    // SAFETY: sync takes no arguments and cannot fail.
    unsafe { libc::sync() };
    fs::write("/proc/sys/vm/drop_caches", "3").map_err(context("drop_caches"))?;
    memory.sample("dropped", &processes)?;

    notes.push(describe_watermarks()?);
    let reserve_kb = u64::from(request.reserve_mib) * 1024;
    let zeroed_kb = zero_free_memory(reserve_kb)?;
    memory.sample("zeroed", &processes)?;

    let resident = resident_files(&processes, &request.resident, &mut notes)?;
    let resident_kb = read_back(&resident, &mut notes)?.div_ceil(1024);
    memory.sample("resident", &processes)?;
    notes.extend(memory.report());

    let high_kb: u64 = procfs::watermarks(&read("/proc/zoneinfo")?)
        .iter()
        .map(|(_, [_, _, high])| high * 4)
        .sum();
    let budget_kb = cgroup::budget_kb(
        &read("/proc/meminfo")?,
        high_kb,
        SYSTEM_HEADROOM_KB + XORG_DATA_GROWTH_KB,
    )?;
    let group = cgroup::create(budget_kb)?;
    notes.push(format!(
        "the run's cgroup {} has memory.max {budget_kb} kB: free memory and unmapped page cache, less {high_kb} kB of high watermarks, {XORG_DATA_GROWTH_KB} kB for Xorg and {SYSTEM_HEADROOM_KB} kB for the kernel",
        group.procs().parent().unwrap_or(Path::new("")).display()
    ));
    let xorg_data_kb =
        procfs::kb_field(&read(&format!("/proc/{xorg}/status"))?, "VmData").ok_or("Xorg has no VmData")?;
    let xorg_cap_kb = xorg_data_kb + XORG_DATA_GROWTH_KB;
    sys::limit_data(xorg as libc::pid_t, xorg_cap_kb * 1024).map_err(context("Xorg's RLIMIT_DATA"))?;
    notes.push(format!(
        "Xorg's RLIMIT_DATA is {xorg_cap_kb} kB, {XORG_DATA_GROWTH_KB} kB over its VmData"
    ));
    // Under memory pressure the kernel evicts the pages of mapped files, the agent's own binary
    // among them, and faulting them back in is a fetch over 9p that can take seconds. Locked, the
    // agent answers PING however short the guest runs.
    sys::lock_memory().map_err(context("mlockall"))?;

    let meminfo = read("/proc/meminfo")?;
    let field = |key| {
        procfs::kb_field(&meminfo, key)
            .and_then(|kb| u32::try_from(kb).ok())
            .unwrap_or(0)
    };
    let parked = Parked {
        warm: true,
        mem_total_kb: field("MemTotal"),
        mem_available_kb: field("MemAvailable"),
        zeroed_kb: u32::try_from(zeroed_kb).unwrap_or(u32::MAX),
        resident_kb: u32::try_from(resident_kb).unwrap_or(u32::MAX),
    };
    Ok(Outcome {
        warm,
        windows,
        group,
        prepared: Prepared { python, tk, parked },
        notes,
    })
}

/// Starts Xorg and waits until it accepts clients. Returns its pid.
fn start_xorg() -> Result<u32, String> {
    let (ready, ready_writer) = io::pipe().map_err(context("pipe"))?;
    let ready_fd = ready_writer.as_raw_fd();
    let mut command = Command::new("/usr/bin/Xorg");
    // -noreset: with its last client gone Xorg would reset, and the agent's own X connection
    // is not always there to be that client. -displayfd: the server writes its display number
    // there once it accepts connections.
    command
        .args([
            ":0",
            "-nolisten",
            "tcp",
            "-noreset",
            "-s",
            "0",
            "-dpms",
            "vt7",
            "-logfile",
            XORG_LOG,
        ])
        .args(["-displayfd", &ready_fd.to_string()])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    // SAFETY: the closure only makes async-signal-safe calls.
    unsafe {
        command.pre_exec(move || {
            // Its own session, so no signal meant for a run's process group can reach it.
            check(libc::setsid())?;
            // The agent's priority is the agent's alone.
            check(libc::setpriority(libc::PRIO_PROCESS, 0, 0))?;
            keep_across_exec(ready_fd)
        });
    }
    let child = command.spawn().map_err(context("Xorg"))?;
    drop(ready_writer);
    match read_line(File::from(OwnedFd::from(ready)), XORG_TIMEOUT) {
        Ok(Some(_)) => Ok(child.id()),
        Ok(None) => Err(format!("Xorg exited before it accepted clients; see {XORG_LOG}")),
        Err(error) => Err(format!("Xorg: {error}; see {XORG_LOG}")),
    }
}

/// Starts the warm interpreter as the student and waits until its warm-up is done.
fn start_interpreter() -> Result<(Warm, String, String, String), String> {
    let (go, go_writer) = io::pipe().map_err(context("pipe"))?;
    let (status, status_writer) = io::pipe().map_err(context("pipe"))?;
    let (go_fd, status_fd) = (go.as_raw_fd(), status_writer.as_raw_fd());
    let mut command = Command::new("/usr/bin/python3");
    command
        .arg(PRELUDE)
        .env_clear()
        .envs(STUDENT_ENV)
        .current_dir("/home/student")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    // It warms up outside the run's cgroup and is moved in when a program arrives, so the budget
    // counts what the program allocates and not what the warm-up already holds.
    // SAFETY: the closure only makes async-signal-safe calls.
    unsafe { command.pre_exec(move || become_student(Some((go_fd, status_fd)), None)) };
    let mut child = command.spawn().map_err(context("python3"))?;
    drop((go, status_writer));

    let stdout: File = OwnedFd::from(child.stdout.take().expect("piped")).into();
    let stderr: File = OwnedFd::from(child.stderr.take().expect("piped")).into();
    let status: File = OwnedFd::from(status).into();
    for file in [&stdout, &stderr, &status] {
        set_nonblocking(file.as_raw_fd()).map_err(context("O_NONBLOCK"))?;
    }
    let warm = Warm {
        pid: child.id(),
        go: OwnedFd::from(go_writer).into(),
        status,
        stdout,
        stderr,
        xid: 0,
    };
    wait_until_warm(warm)
}

/// Starts `entry` in `dir` on a python3 of its own, for a run with no warm interpreter waiting:
/// what `python3 main.py` does, 5 to 7 s to a first Tk window rather than 0.3 s. It starts inside
/// `group` when there is one.
pub fn spawn_cold(dir: &Path, entry: &str, argv: &[String], tz: &str, group: Option<&Group>) -> io::Result<Child> {
    let procs = group
        .map(|group| CString::new(group.procs().as_os_str().as_bytes()))
        .transpose()
        .map_err(|_| io::ErrorKind::InvalidInput)?;
    let mut command = Command::new("/usr/bin/python3");
    command
        .arg(entry)
        .args(argv)
        .env_clear()
        .envs(STUDENT_ENV)
        .env("TZ", tz)
        .current_dir(dir)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    // SAFETY: the closure only makes async-signal-safe calls.
    unsafe { command.pre_exec(move || become_student(None, procs.as_deref())) };
    let mut child = command.spawn()?;
    let stdout: File = OwnedFd::from(child.stdout.take().expect("piped")).into();
    let stderr: File = OwnedFd::from(child.stderr.take().expect("piped")).into();
    for file in [&stdout, &stderr] {
        set_nonblocking(file.as_raw_fd())?;
    }
    Ok(Child {
        pid: child.id() as libc::pid_t,
        stdout,
        stderr,
        status: None,
    })
}

/// Runs in the forked child before exec, so it MUST only make async-signal-safe calls. `pipes`
/// are the prelude's go and status pipes, which end up on fds 3 and 4. `cgroup_procs` is the
/// `cgroup.procs` of a group to move into, which only root may do.
fn become_student(pipes: Option<(RawFd, RawFd)>, cgroup_procs: Option<&std::ffi::CStr>) -> io::Result<()> {
    // SAFETY: plain system calls on fds, constants and strings this process owns.
    unsafe {
        // The agent runs at a higher priority, which the student's programs must not inherit.
        check(libc::setpriority(libc::PRIO_PROCESS, 0, 0))?;
        if let Some(procs) = cgroup_procs {
            let fd = libc::open(procs.as_ptr(), libc::O_WRONLY);
            check(fd)?;
            let written = libc::write(fd, b"0".as_ptr().cast(), 1);
            libc::close(fd);
            if written != 1 {
                return Err(io::Error::last_os_error());
            }
        }
        // Xorg and the agent run at -1000, so under memory pressure the kernel ends the student's
        // program and nothing else. Written before setuid, which makes the process undumpable and
        // its /proc files root's.
        let fd = libc::open(c"/proc/self/oom_score_adj".as_ptr(), libc::O_WRONLY);
        check(fd)?;
        let written = libc::write(fd, b"1000".as_ptr().cast(), 4);
        libc::close(fd);
        if written != 4 {
            return Err(io::Error::last_os_error());
        }
        let nproc = libc::rlimit {
            rlim_cur: 64,
            rlim_max: 64,
        };
        check(libc::setrlimit(libc::RLIMIT_NPROC, &nproc))?;
        // Its own session and process group, which is what STOP kills.
        check(libc::setsid())?;
        if let Some((go, status)) = pipes {
            // Either pipe may already sit on fd 3 or 4, so both move out of the way first. dup2
            // clears close-on-exec on the copy, which is how the two survive exec.
            let go = libc::fcntl(go, libc::F_DUPFD, 10);
            check(go)?;
            let status = libc::fcntl(status, libc::F_DUPFD, 10);
            check(status)?;
            check(libc::dup2(go, 3))?;
            check(libc::dup2(status, 4))?;
            libc::close(go);
            libc::close(status);
        }
        // Any setuid binary the image ever gains then runs without its privileges.
        sys::forbid_new_privileges()?;
        check(libc::setgroups(0, std::ptr::null()))?;
        check(libc::setgid(STUDENT_UID))?;
        check(libc::setuid(STUDENT_UID))
    }
}

/// Reads the warm interpreter's status pipe until its warm line. Returns what it printed on the
/// way, which a clean warm-up leaves empty.
fn wait_until_warm(mut warm: Warm) -> Result<(Warm, String, String, String), String> {
    let deadline = Instant::now() + WARM_TIMEOUT;
    let mut lines = Lines::default();
    let mut printed = Vec::new();
    let mut open = [true; 3];
    let mut buffer = [0u8; 4096];
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return Err(format!("no warm line within {WARM_TIMEOUT:?}: {}", tail(&printed)));
        }
        let files = [&warm.status, &warm.stdout, &warm.stderr];
        // poll(2) skips a negative fd, which is how a pipe at its end drops out.
        let mut fds: [libc::pollfd; 3] = std::array::from_fn(|i| libc::pollfd {
            fd: if open[i] { files[i].as_raw_fd() } else { -1 },
            events: libc::POLLIN,
            revents: 0,
        });
        poll(&mut fds, left)?;
        for index in 0..3 {
            if fds[index].revents == 0 {
                continue;
            }
            let file = match index {
                0 => &mut warm.status,
                1 => &mut warm.stdout,
                _ => &mut warm.stderr,
            };
            let n = match file.read(&mut buffer) {
                Ok(n) => n,
                Err(error) if error.kind() == io::ErrorKind::WouldBlock => continue,
                Err(error) => return Err(format!("warm interpreter: {error}")),
            };
            if n == 0 {
                if index == 0 {
                    return Err(format!(
                        "the warm interpreter exited during warm-up: {}",
                        tail(&printed)
                    ));
                }
                open[index] = false;
            } else if index > 0 {
                printed.extend_from_slice(&buffer[..n]);
            } else {
                for line in lines.push(&buffer[..n]) {
                    if let Some(Status::Warm { python, tk, xid }) = prelude::parse_status(&line) {
                        warm.xid = xid;
                        return Ok((warm, python, tk, tail(&printed)));
                    }
                }
            }
        }
    }
}

/// Every guest write afterwards lands in a size-capped tmpfs. Without this, a write into the 9p
/// root would go into v86's JS memory, and evict files from v86's file cache as well.
fn remount_root_read_only() -> Result<String, String> {
    let root = Path::new("/");
    // SAFETY: sync takes no arguments and cannot fail.
    unsafe { libc::sync() };
    // A bind remount marks only this mount read-only, which is the fallback for a filesystem
    // that refuses to change its superblock.
    let how = match sys::remount_read_only(root, false) {
        Ok(()) => "remount,ro".to_owned(),
        Err(first) => {
            sys::remount_read_only(root, true)
                .map_err(|second| format!("remounting / read-only failed: {first}; as a bind mount: {second}"))?;
            format!("remount,bind,ro, because remount,ro failed: {first}")
        }
    };
    if !sys::is_read_only(root).map_err(context("statvfs /"))? {
        return Err(format!("/ is still writable after {how}"));
    }
    let probe = root.join(".icc-read-only-probe");
    match OpenOptions::new().write(true).create_new(true).open(&probe) {
        Err(error) if error.raw_os_error() == Some(libc::EROFS) => Ok(format!(
            "/ is read-only ({how}); creating a file there fails with EROFS"
        )),
        Err(error) => Err(format!(
            "creating {} after {how} failed with {error}, not EROFS",
            probe.display()
        )),
        Ok(_) => {
            let _ = fs::remove_file(&probe);
            Err(format!("/ took a new file after {how}"))
        }
    }
}

/// Fills free memory with zero pages and gives it back, so the snapshot stores nothing for it.
///
/// It stops `reserve_kb` above zero free memory, rather than at MemAvailable: that counts page
/// cache the kernel would reclaim, and among it are the warm interpreter's own mapped libraries.
/// Returns the kB zeroed.
fn zero_free_memory(reserve_kb: u64) -> Result<u64, String> {
    // SAFETY: sysconf only reads a constant.
    let page = usize::try_from(unsafe { libc::sysconf(libc::_SC_PAGESIZE) }).unwrap_or(4096);
    let mut chunks = Vec::new();
    let mut failure = None;
    // Large steps first, then small ones, so the last step leaves less than 64 KiB unzeroed
    // above the reserve rather than up to 1 MiB.
    'sizes: for size in ZERO_CHUNKS {
        loop {
            let free = procfs::kb_field(&read("/proc/meminfo")?, "MemFree").ok_or("MemFree is missing")?;
            if free < reserve_kb + (size / 1024) as u64 {
                break;
            }
            // SAFETY: a fresh private anonymous mapping, written only within its length and
            // unmapped below before anything else could refer to it.
            let chunk = unsafe {
                libc::mmap(
                    std::ptr::null_mut(),
                    size,
                    libc::PROT_READ | libc::PROT_WRITE,
                    libc::MAP_PRIVATE | libc::MAP_ANONYMOUS,
                    -1,
                    0,
                )
            };
            if chunk == libc::MAP_FAILED {
                failure = Some(io::Error::last_os_error());
                break 'sizes;
            }
            // A write, not a read: a read fault would map the shared zero page and allocate nothing.
            for offset in (0..size).step_by(page) {
                // SAFETY: offset is within the mapping.
                unsafe { chunk.cast::<u8>().add(offset).write_volatile(0) };
            }
            chunks.push((chunk, size));
        }
    }
    let zeroed_kb = chunks.iter().map(|(_, size)| (size / 1024) as u64).sum();
    for (chunk, size) in chunks {
        // SAFETY: each chunk is a mapping of `size` bytes made above.
        unsafe { libc::munmap(chunk, size) };
    }
    match failure {
        Some(error) if zeroed_kb == 0 => Err(format!("zero-filling memory: {error}")),
        _ => Ok(zeroed_kb),
    }
}

/// The watermarks the reserve has to stay above, for the LOG.
fn describe_watermarks() -> Result<String, String> {
    let zones: Vec<String> = procfs::watermarks(&read("/proc/zoneinfo")?)
        .into_iter()
        .map(|(zone, [min, low, high])| format!("{zone} {} / {} / {}", min * 4, low * 4, high * 4))
        .collect();
    Ok(format!("zone watermarks min / low / high in kB: {}", zones.join(", ")))
}

/// The files to read back whole: everything Xorg and the warm interpreter map from the root
/// filesystem, then the pipeline's own list.
///
/// A page of a mapped library that nothing touched during the warm-up is not in the page cache,
/// and a program that later touches it has v86 fetch the whole file.
fn resident_files(
    processes: &[(&str, u32)],
    requested: &[String],
    notes: &mut Vec<String>,
) -> Result<Vec<String>, String> {
    let root_dev = fs::metadata("/").map_err(context("/"))?.dev();
    let mut files: Vec<String> = Vec::new();
    for (_, pid) in processes {
        for path in procfs::mapped_paths(&read(&format!("/proc/{pid}/maps"))?) {
            let on_root = fs::metadata(&path).is_ok_and(|meta| meta.is_file() && meta.dev() == root_dev);
            if on_root && !files.contains(&path) {
                files.push(path);
            }
        }
    }
    let mapped = files.len();
    for path in requested {
        if !files.contains(path) {
            files.push(path.clone());
        }
    }
    notes.push(format!(
        "reading back {} files: {mapped} mapped by Xorg and the interpreter, and the rest of the {} asked for",
        files.len(),
        requested.len()
    ));
    Ok(files)
}

/// Reads each file to its end, so the page cache holds all of it. Returns the bytes read.
fn read_back(paths: &[String], notes: &mut Vec<String>) -> Result<u64, String> {
    let mut buffer = vec![0u8; 256 * 1024];
    let mut total = 0;
    let mut sizes = Vec::new();
    let mut missing = Vec::new();
    for path in paths {
        let Ok(mut file) = File::open(path) else {
            missing.push(path.as_str());
            continue;
        };
        let mut size = 0;
        loop {
            match file.read(&mut buffer) {
                Ok(0) => break,
                Ok(n) => size += n as u64,
                Err(error) if error.kind() == io::ErrorKind::Interrupted => {}
                Err(error) => return Err(format!("reading back {path}: {error}")),
            }
        }
        total += size;
        sizes.push((size, path.as_str()));
    }
    sizes.sort_unstable_by(|a, b| b.cmp(a));
    let largest: Vec<String> = sizes
        .iter()
        .take(40)
        .map(|(size, path)| format!("{path} {}", size / 1024))
        .collect();
    notes.push(format!(
        "read back {} kB in {} files; kB by file, largest first: {}",
        total / 1024,
        sizes.len(),
        largest.join(", ")
    ));
    if !missing.is_empty() {
        notes.push(format!("resident files that do not exist: {}", missing.join(" ")));
    }
    Ok(total)
}

/// Memory at each step of PREPARE, for the LOG that says what the snapshot holds.
#[derive(Default)]
struct Memory {
    steps: Vec<(&'static str, BTreeMap<String, u64>)>,
}

impl Memory {
    const MEMINFO: [&'static str; 6] = ["MemFree", "MemAvailable", "Cached", "Mapped", "AnonPages", "Slab"];
    const VMSTAT: [&'static str; 5] = [
        "pgscan_kswapd",
        "pgscan_direct",
        "pgsteal_kswapd",
        "pgsteal_direct",
        "workingset_refault_file",
    ];

    fn sample(&mut self, step: &'static str, processes: &[(&str, u32)]) -> Result<(), String> {
        let mut values = BTreeMap::new();
        let meminfo = read("/proc/meminfo")?;
        for key in Self::MEMINFO {
            values.insert(key.to_owned(), procfs::kb_field(&meminfo, key).unwrap_or(0));
        }
        let vmstat = read("/proc/vmstat")?;
        for key in Self::VMSTAT {
            values.insert(key.to_owned(), procfs::counter(&vmstat, key).unwrap_or(0));
        }
        for (name, pid) in processes {
            let status = read(&format!("/proc/{pid}/status"))?;
            values.insert(
                format!("{name} RssFile"),
                procfs::kb_field(&status, "RssFile").unwrap_or(0),
            );
        }
        self.steps.push((step, values));
        Ok(())
    }

    /// One line per step: meminfo and RssFile in kB, and how far each vmstat counter moved since
    /// the step before. Reclaim during the zero-fill would show as pgscan and pgsteal.
    fn report(&self) -> Vec<String> {
        let mut lines = Vec::new();
        let mut previous: Option<&BTreeMap<String, u64>> = None;
        for (step, values) in &self.steps {
            let fields: Vec<String> = values
                .iter()
                .map(|(key, value)| match previous {
                    Some(before) if Self::VMSTAT.contains(&key.as_str()) => {
                        format!("{key} +{}", value.saturating_sub(before[key]))
                    }
                    _ => format!("{key} {value}"),
                })
                .collect();
            lines.push(format!("memory after {step}: {}", fields.join(", ")));
            previous = Some(values);
        }
        lines
    }
}

/// Reads one line from `file` within `timeout`. `None` when the writer closed it first.
fn read_line(file: File, timeout: Duration) -> io::Result<Option<Vec<u8>>> {
    let mut file = file;
    let deadline = Instant::now() + timeout;
    let mut lines = Lines::default();
    let mut buffer = [0u8; 256];
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return Err(io::Error::new(
                io::ErrorKind::TimedOut,
                format!("nothing within {timeout:?}"),
            ));
        }
        let mut fds = [libc::pollfd {
            fd: file.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        }];
        poll(&mut fds, left).map_err(io::Error::other)?;
        if fds[0].revents == 0 {
            continue;
        }
        let n = file.read(&mut buffer)?;
        if n == 0 {
            return Ok(None);
        }
        if let Some(line) = lines.push(&buffer[..n]).into_iter().next() {
            return Ok(Some(line));
        }
    }
}

fn poll(fds: &mut [libc::pollfd], timeout: Duration) -> Result<(), String> {
    let ms = libc::c_int::try_from(timeout.as_millis()).unwrap_or(libc::c_int::MAX);
    // SAFETY: the pointer and length describe `fds`, which outlives the call.
    let result = unsafe { libc::poll(fds.as_mut_ptr(), fds.len() as libc::nfds_t, ms) };
    if result == -1 {
        let error = io::Error::last_os_error();
        if error.kind() != io::ErrorKind::Interrupted {
            return Err(format!("poll: {error}"));
        }
    }
    Ok(())
}

/// Clears close-on-exec, in a forked child, on an fd the program being exec'd is meant to write.
fn keep_across_exec(fd: RawFd) -> io::Result<()> {
    // SAFETY: fcntl on an fd this process owns.
    unsafe {
        let flags = libc::fcntl(fd, libc::F_GETFD);
        check(flags)?;
        check(libc::fcntl(fd, libc::F_SETFD, flags & !libc::FD_CLOEXEC))
    }
}

pub fn set_nonblocking(fd: RawFd) -> io::Result<()> {
    // SAFETY: fcntl on an fd the caller owns.
    unsafe {
        let flags = libc::fcntl(fd, libc::F_GETFL);
        check(flags)?;
        check(libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK))
    }
}

fn check(result: libc::c_int) -> io::Result<()> {
    if result == -1 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

fn read(path: &str) -> Result<String, String> {
    fs::read_to_string(path).map_err(context(path))
}

fn context<E: std::fmt::Display>(what: &str) -> impl Fn(E) -> String + '_ {
    move |error| format!("{what}: {error}")
}

/// The last few hundred bytes a process printed, for an error message.
fn tail(printed: &[u8]) -> String {
    let start = printed.len().saturating_sub(800);
    String::from_utf8_lossy(&printed[start..]).trim().to_owned()
}
