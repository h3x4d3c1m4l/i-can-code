//! icc-agent: the process in the Tkinter VM's guest that the page talks to. It owns the serial port
//! it is given, and speaks the protocol of vm/protocol/README.md on it.

mod agent;
#[cfg(unix)]
mod cgroup;
#[cfg(unix)]
mod clock;
mod entropy;
#[cfg(unix)]
mod event_loop;
#[cfg(unix)]
mod files;
#[cfg(test)]
mod fixtures;
mod frame;
mod log_limit;
mod outbox;
mod output;
mod prelude;
#[cfg(unix)]
mod prepare;
mod procfs;
mod proto;
#[cfg(unix)]
mod serial;
#[cfg(unix)]
mod supervisor;
#[cfg(unix)]
mod sys;
#[cfg(unix)]
mod wake;
#[cfg(unix)]
mod x11;

use std::ffi::OsString;
use std::path::PathBuf;
use std::process::ExitCode;

const USAGE: &str = "usage: icc-agent --serial <device>";

#[derive(Debug, PartialEq, Eq)]
enum Command {
    Serve(PathBuf),
    Version,
}

fn main() -> ExitCode {
    match parse_args(std::env::args_os().skip(1)) {
        Ok(Command::Serve(port)) => serve(port),
        Ok(Command::Version) => {
            println!("icc-agent {}", env!("CARGO_PKG_VERSION"));
            ExitCode::SUCCESS
        }
        Err(problem) => {
            eprintln!("icc-agent: {problem}\n{USAGE}");
            ExitCode::from(2)
        }
    }
}

/// The agent's nice value. It is the page's only way into the guest: a program that keeps the CPU
/// busy, or Xorg and Tk drawing for it, must not put a PONG, a STOP or a WINDOW behind them.
#[cfg(unix)]
const NICE: libc::c_int = -10;

#[cfg(unix)]
fn serve(port: PathBuf) -> ExitCode {
    if let Err(error) = sys::set_nice(NICE) {
        eprintln!("icc-agent: nice {NICE}: {error}");
    }
    let Err(error) = event_loop::serve(&port);
    eprintln!("icc-agent: {}: {error}", port.display());
    // busybox init respawns the agent at once, so a port that keeps failing would otherwise keep
    // init busy.
    std::thread::sleep(std::time::Duration::from_secs(1));
    ExitCode::FAILURE
}

#[cfg(not(unix))]
fn serve(_: PathBuf) -> ExitCode {
    eprintln!("icc-agent: serial ports are only supported on Unix");
    ExitCode::FAILURE
}

fn parse_args(mut args: impl Iterator<Item = OsString>) -> Result<Command, String> {
    let mut port = None;
    while let Some(arg) = args.next() {
        if arg == "--version" {
            return Ok(Command::Version);
        }
        let value = if arg == "--serial" {
            args.next().ok_or("--serial needs a device")?
        } else if let Some(value) = arg.to_str().and_then(|a| a.strip_prefix("--serial=")) {
            value.into()
        } else {
            return Err(format!("unknown argument {}", arg.to_string_lossy()));
        };
        if port.replace(PathBuf::from(value)).is_some() {
            return Err("--serial given twice".into());
        }
    }
    port.map(Command::Serve).ok_or_else(|| "--serial is required".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(args: &[&str]) -> Result<Command, String> {
        parse_args(args.iter().map(OsString::from))
    }

    #[test]
    fn reads_the_serial_port_both_ways() {
        let expected = Ok(Command::Serve("/dev/ttyS1".into()));
        assert_eq!(parse(&["--serial", "/dev/ttyS1"]), expected);
        assert_eq!(parse(&["--serial=/dev/ttyS1"]), expected);
        assert_eq!(parse(&["--version"]), Ok(Command::Version));
    }

    #[test]
    fn refuses_what_it_does_not_know() {
        assert!(parse(&[]).is_err());
        assert!(parse(&["--serial"]).is_err());
        assert!(parse(&["--serial", "a", "--serial", "b"]).is_err());
        assert!(parse(&["/dev/ttyS1"]).is_err());
    }
}
