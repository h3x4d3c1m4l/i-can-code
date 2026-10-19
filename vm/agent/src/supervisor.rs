//! The guest side of the agent's work: PREPARE, and each run from its files to its EXIT.

use crate::agent::{Action, Agent, Stream};
use crate::cgroup::Group;
use crate::prelude::{Go, Lines, Status, parse_status};
use crate::prepare::{self, STUDENT_UID};
use crate::proto::{ErrorCode, ExitReason, Level, Run};
use crate::x11::{self, Note};
use crate::{clock, entropy, files, procfs, sys};
use std::fs::{self, File};
use std::io::{self, Read, Write};
use std::os::fd::{AsRawFd, OwnedFd};
use std::path::Path;
use std::time::Instant;

/// The run's working directory, in the tmpfs PREPARE mounted on /run/icc.
const WORK_DIR: &str = "/run/icc/work";

/// The warm interpreter from PREPARE, blocked on its go pipe until a program arrives.
pub struct Warm {
    pub pid: u32,
    pub go: File,
    pub status: File,
    pub stdout: File,
    pub stderr: File,
    /// The X window of the root the program will be handed; see [`Status::Warm`].
    pub xid: u32,
}

struct Running {
    id: u32,
    pid: libc::pid_t,
    exited: OwnedFd,
    stdout: Option<File>,
    stderr: Option<File>,
    /// The prelude's status pipe. A cold interpreter has no prelude.
    status: Option<File>,
    lines: Lines,
    started: Instant,
    /// The kernel's OOM kill count when the run started, over the whole guest and in the run's
    /// cgroup.
    oom_kills: (Option<u64>, Option<u64>),
    /// The prelude said the program is done: its code has returned, and its threads and atexit
    /// handlers have finished. What is left is the interpreter's own teardown.
    done: bool,
}

/// A program the agent killed and has reported, whose teardown the kernel has not finished.
struct Dying {
    run: u32,
    pid: libc::pid_t,
    exited: OwnedFd,
    killed_at: Instant,
}

#[derive(Default)]
pub struct Supervisor {
    warm: Option<Warm>,
    run: Option<Running>,
    dying: Vec<Dying>,
    windows: Option<x11::Windows>,
    /// The run's cgroup, from PREPARE. Without it, a run is killed by its process group only.
    group: Option<Group>,
}

impl Supervisor {
    pub fn perform(&mut self, action: Action, agent: &mut Agent) {
        match action {
            Action::Prepare { id, request } => match prepare::prepare(&request) {
                Ok(outcome) => {
                    for note in outcome.notes {
                        agent.log(0, Level::Info, note);
                    }
                    self.warm = Some(outcome.warm);
                    self.windows = Some(outcome.windows);
                    self.group = Some(outcome.group);
                    agent.on_prepared(id, Ok(outcome.prepared));
                }
                Err(message) => agent.on_prepared(id, Err(message)),
            },
            Action::Greet { now_ms, entropy } => {
                if let Err(error) = clock::set_realtime(now_ms) {
                    agent.log(0, Level::Warn, format!("setting the clock: {error}"));
                }
                if let Err(error) = entropy::add(&entropy) {
                    agent.log(0, Level::Warn, format!("adding entropy: {error}"));
                }
            }
            Action::Run { id, request, tz } => match self.start(id, &request, &tz, agent) {
                Ok((pid, warm)) => agent.on_started(id, pid, warm),
                Err((code, message)) => agent.on_refused(id, code, message),
            },
            Action::Stop { run } => self.kill(run, ExitReason::Stopped, agent),
            Action::Close { run, xid } => {
                if let (Some(windows), Some(_)) = (&self.windows, self.run.as_ref().filter(|running| running.id == run))
                {
                    windows.close(run, xid);
                }
            }
        }
    }

    /// Adds what the supervisor waits on to the poll set. [`Supervisor::on_poll`] MUST get the
    /// same entries back, before anything else changes the supervisor.
    pub fn watch(&self, fds: &mut Vec<libc::pollfd>) {
        if let Some(windows) = &self.windows {
            fds.push(pollfd(windows.fd()));
        }
        for dying in &self.dying {
            fds.push(pollfd(dying.exited.as_raw_fd()));
        }
        let Some(running) = &self.run else {
            return;
        };
        let pipes = [&running.stdout, &running.stderr, &running.status];
        for fd in pipes.map(|pipe| pipe.as_ref().map_or(-1, AsRawFd::as_raw_fd)) {
            fds.push(pollfd(fd));
        }
        fds.push(pollfd(running.exited.as_raw_fd()));
    }

    pub fn on_poll(&mut self, fds: &[libc::pollfd], agent: &mut Agent) {
        let ready = |i: usize| fds.get(i).is_some_and(|fd| fd.revents != 0);
        let mut at = 0;
        if self.windows.is_some() {
            if ready(at) {
                self.on_notes(agent);
            }
            at = 1;
        }
        let exited: Vec<usize> = (0..self.dying.len()).filter(|&i| ready(at + i)).collect();
        at += self.dying.len();
        for index in exited.into_iter().rev() {
            let dying = self.dying.remove(index);
            let mut status = 0;
            // SAFETY: waitpid writes the status into the local it is given.
            unsafe { libc::waitpid(dying.pid, &mut status, libc::WNOHANG) };
            let ms = dying.killed_at.elapsed().as_secs_f64() * 1000.0;
            // Id 0: the run's EXIT has gone already, and nothing about a run follows its EXIT.
            agent.log(
                0,
                Level::Debug,
                format!("run {}: reaped {ms:.1} ms after the kill", dying.run),
            );
        }
        let Some(running) = &mut self.run else {
            return;
        };
        if ready(at) {
            running.forward(Stream::Stdout, agent);
        }
        if ready(at + 1) {
            running.forward(Stream::Stderr, agent);
        }
        if ready(at + 2) && running.read_status(agent) {
            self.on_done(agent);
        }
        if ready(at + 3) {
            self.reap(agent);
        }
    }

    fn on_notes(&mut self, agent: &mut Agent) {
        let Some(windows) = &self.windows else {
            return;
        };
        for note in windows.notes() {
            match note {
                // The agent drops a list for a run that is not current.
                Note::Windows { run, windows } => agent.on_windows(run, windows),
                Note::CloseRefused { run } => self.kill(run, ExitReason::Closed, agent),
                // Without its X connection the agent can still run programs; it only stops
                // reporting and focusing their windows.
                Note::Lost(error) => {
                    self.windows = None;
                    agent.log(0, Level::Error, format!("lost the X connection: {error}"));
                }
            }
        }
    }

    /// The program has finished, and only the interpreter's teardown is left: whatever else the run
    /// started goes now, so the teardown has the CPU to itself. Forty spinning children once held
    /// a finished program's EXIT up for 16 s.
    fn on_done(&mut self, agent: &mut Agent) {
        let (Some(running), Some(group)) = (&self.run, &self.group) else {
            return;
        };
        match group.kill_all_but(running.pid) {
            Ok(0) => {}
            Ok(killed) => agent.log(
                running.id,
                Level::Debug,
                format!("the program is done; killed {killed} processes it left"),
            ),
            Err(error) => agent.log(
                running.id,
                Level::Warn,
                format!("killing what the program left: {error}"),
            ),
        }
    }

    /// Starts the run: on the warm interpreter if one is waiting, otherwise on a new python3.
    /// Returns the program's pid and whether it was warm.
    fn start(
        &mut self,
        id: u32,
        request: &Run,
        tz: &str,
        agent: &mut Agent,
    ) -> Result<(u32, bool), (ErrorCode, String)> {
        let files_bytes = files::stage(
            Path::new(files::IN_DIR),
            id,
            &request.files,
            Path::new(WORK_DIR),
            (STUDENT_UID, STUDENT_UID),
        )
        .map_err(|message| (ErrorCode::BadFiles, message))?;
        if let Some(group) = &self.group {
            let files_kb = files_bytes.div_ceil(1024);
            match group.limit_for_files(files_kb) {
                Ok(kb) => agent.log(
                    id,
                    Level::Debug,
                    format!("memory.max {kb} kB: the budget less {files_kb} kB for the run's files"),
                ),
                Err(error) => agent.log(id, Level::Warn, format!("the run's memory.max: {error}")),
            }
        }
        let oom_kills = (oom_kills(), self.group.as_ref().and_then(Group::oom_kills));
        let started = Instant::now();
        if let Some(warm) = self.warm.take() {
            // Both before the program can run: its first window is the run's, and its first
            // allocation counts against the run's budget.
            if let Some(windows) = &self.windows {
                windows.begin_run(id, Some(warm.xid));
            }
            if let Some(group) = &self.group
                && let Err(error) = group.enter(warm.pid)
            {
                agent.log(
                    id,
                    Level::Warn,
                    format!("moving the warm interpreter into the run's cgroup: {error}"),
                );
            }
            match hand_over(warm, request, tz) {
                Ok(child) => {
                    let pid = child.pid as u32;
                    self.begin(id, child, oom_kills, started)?;
                    return Ok((pid, true));
                }
                Err(message) => {
                    agent.log(
                        id,
                        Level::Warn,
                        format!("the warm interpreter is gone, starting a cold one: {message}"),
                    );
                }
            }
        }
        if let Some(windows) = &self.windows {
            windows.begin_run(id, None);
        }
        let child = prepare::spawn_cold(
            Path::new(WORK_DIR),
            &request.entry,
            &request.argv,
            tz,
            self.group.as_ref(),
        )
        .map_err(|error| (ErrorCode::SpawnFailed, format!("python3: {error}")))?;
        let pid = child.pid as u32;
        self.begin(id, child, oom_kills, started)?;
        Ok((pid, false))
    }

    fn begin(
        &mut self,
        id: u32,
        child: prepare::Child,
        oom_kills: (Option<u64>, Option<u64>),
        started: Instant,
    ) -> Result<(), (ErrorCode, String)> {
        let exited = sys::pidfd_open(child.pid)
            .map_err(|error| (ErrorCode::SpawnFailed, format!("watching the program: {error}")))?;
        self.run = Some(Running {
            id,
            pid: child.pid,
            exited,
            stdout: Some(child.stdout),
            stderr: Some(child.stderr),
            status: child.status,
            lines: Lines::default(),
            started,
            oom_kills,
            done: false,
        });
        Ok(())
    }

    /// SIGKILL to everything the run started. The process group as well as the cgroup: a leader
    /// that could not be moved into the cgroup is still in its own group.
    fn kill_all(&self, running: &Running, agent: &mut Agent) {
        if let Some(group) = &self.group
            && let Err(error) = group.kill()
        {
            agent.log(running.id, Level::Warn, format!("cgroup.kill: {error}"));
        }
        // SAFETY: kill takes a process group and a signal.
        unsafe { libc::kill(-running.pid, libc::SIGKILL) };
    }

    /// What the run's cgroup held at most, for the developer console.
    fn log_peak(&self, running: &Running, agent: &mut Agent) {
        if let Some(kb) = self.group.as_ref().and_then(Group::peak_kb) {
            agent.log(running.id, Level::Debug, format!("memory.peak {kb} kB"));
        }
    }

    /// Kills the run's whole process group and ends the run with its EXIT at once.
    ///
    /// SIGKILL cannot be caught, so the outcome is known the moment it is sent, while the kernel's
    /// teardown of a Tk program takes 70 to 230 ms in v86 (measured). Waiting for it would hold
    /// the host's park for nothing: the restore that follows discards the process however far its
    /// teardown has got. It is reaped in the background.
    fn kill(&mut self, run: u32, reason: ExitReason, agent: &mut Agent) {
        let Some(mut running) = self.run.take_if(|running| running.id == run) else {
            return;
        };
        let killed_at = Instant::now();
        self.kill_all(&running, agent);
        // What the program wrote before it died still belongs to the run.
        running.forward(Stream::Stdout, agent);
        running.forward(Stream::Stderr, agent);
        self.log_peak(&running, agent);
        if let Some(windows) = &self.windows {
            windows.end_run();
        }
        let mut status = 0;
        // SAFETY: waitpid writes the status into the local it is given.
        let (code, signal) = if unsafe { libc::waitpid(running.pid, &mut status, libc::WNOHANG) } == running.pid {
            // It had ended by itself already.
            exit_status(status)
        } else {
            self.dying.push(Dying {
                run,
                pid: running.pid,
                exited: running.exited,
                killed_at,
            });
            (None, Some(libc::SIGKILL as u8))
        };
        let ms = running.started.elapsed().as_millis() as u64;
        agent.on_exit(run, code, signal, reason, ms);
    }

    /// Ends the run once its process has exited: the output it left, then HINT, then EXIT.
    fn reap(&mut self, agent: &mut Agent) {
        let Some(mut running) = self.run.take() else {
            return;
        };
        let mut status = 0;
        // SAFETY: waitpid writes the status into the local it is given.
        if unsafe { libc::waitpid(running.pid, &mut status, libc::WNOHANG) } != running.pid {
            self.run = Some(running);
            return;
        }
        running.forward(Stream::Stdout, agent);
        running.forward(Stream::Stderr, agent);
        running.read_status(agent);
        // Whatever the program started goes with it (README 6.6).
        self.kill_all(&running, agent);
        let (code, signal) = exit_status(status);
        let (before, before_in_group) = running.oom_kills;
        let moved = |before: Option<u64>, after: Option<u64>| before.zip(after).is_some_and(|(b, a)| a > b);
        let in_group = moved(before_in_group, self.group.as_ref().and_then(Group::oom_kills));
        let oom = signal == Some(libc::SIGKILL as u8) && (in_group || moved(before, oom_kills()));
        if oom {
            let whose = if in_group { "the run's cgroup" } else { "the guest" };
            agent.log(running.id, Level::Info, format!("out of memory: {whose}"));
        }
        let reason = if oom { ExitReason::Oom } else { ExitReason::Exit };
        let ms = running.started.elapsed().as_millis() as u64;
        self.log_peak(&running, agent);
        if let Some(windows) = &self.windows {
            windows.end_run();
        }
        agent.on_exit(running.id, code, signal, reason, ms);
    }
}

impl Running {
    /// Forwards what the pipe holds now. Called on exit too, when a writer the program started may
    /// hold the pipe open, so it stops at the first empty read rather than at the end.
    fn forward(&mut self, stream: Stream, agent: &mut Agent) {
        let pipe = match stream {
            Stream::Stdout => &mut self.stdout,
            Stream::Stderr => &mut self.stderr,
        };
        let mut buffer = [0u8; 16384];
        while let Some(file) = pipe {
            match file.read(&mut buffer) {
                Ok(0) => *pipe = None,
                Ok(n) => agent.on_output(self.id, stream, &buffer[..n], Instant::now()),
                Err(error) if error.kind() == io::ErrorKind::Interrupted => {}
                Err(error) => {
                    if error.kind() != io::ErrorKind::WouldBlock {
                        agent.log(self.id, Level::Warn, format!("reading the program's output: {error}"));
                        *pipe = None;
                    }
                    return;
                }
            }
        }
    }

    /// Reads the prelude's status lines. Returns whether the program has just become done.
    ///
    /// The program runs in the prelude's own process, so it can write these lines too: the agent
    /// believes only what one run can say once (README 6.8).
    fn read_status(&mut self, agent: &mut Agent) -> bool {
        let mut buffer = [0u8; 4096];
        let mut done = false;
        while let Some(file) = &mut self.status {
            let n = match file.read(&mut buffer) {
                Ok(0) => {
                    self.status = None;
                    break;
                }
                Ok(n) => n,
                Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                Err(_) => break,
            };
            for line in self.lines.push(&buffer[..n]) {
                match parse_status(&line) {
                    Some(Status::Hint(kind)) => agent.on_hint(self.id, &kind),
                    Some(Status::Done) if !self.done => {
                        self.done = true;
                        done = true;
                    }
                    _ => {}
                }
            }
        }
        done
    }
}

/// Gives the program to the warm interpreter. Fails when the interpreter is no longer there to
/// read it, which the caller answers with a cold one.
fn hand_over(warm: Warm, request: &Run, tz: &str) -> Result<prepare::Child, String> {
    let go = Go {
        dir: WORK_DIR,
        entry: &request.entry,
        argv: &request.argv,
        tz,
    };
    let mut pipe = warm.go;
    // SIGPIPE is ignored in a Rust program, so a reader that is gone is an EPIPE here.
    pipe.write_all(&go.line())
        .map_err(|error| format!("the go pipe: {error}"))?;
    let child = prepare::Child {
        pid: warm.pid as libc::pid_t,
        stdout: warm.stdout,
        stderr: warm.stderr,
        status: Some(warm.status),
    };
    Ok(child)
}

/// A wait status as EXIT's `code` and `signal`, exactly one of them set.
fn exit_status(status: libc::c_int) -> (Option<u8>, Option<u8>) {
    if libc::WIFSIGNALED(status) {
        (None, u8::try_from(libc::WTERMSIG(status)).ok())
    } else {
        (u8::try_from(libc::WEXITSTATUS(status)).ok(), None)
    }
}

/// `/proc/vmstat`'s `oom_kill`: how often the OOM killer has struck since boot.
fn oom_kills() -> Option<u64> {
    procfs::counter(&fs::read_to_string("/proc/vmstat").ok()?, "oom_kill")
}

fn pollfd(fd: libc::c_int) -> libc::pollfd {
    libc::pollfd {
        fd,
        events: libc::POLLIN,
        revents: 0,
    }
}
