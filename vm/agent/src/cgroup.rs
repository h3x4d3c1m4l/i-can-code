//! The run's control group (cgroup v2, README 6.6). Everything the student's processes allocate is
//! charged to it, tmpfs pages included, so one `memory.max` bounds a run, and running out of it is
//! an OOM inside the group rather than the whole guest's. It is also the kill: a process can leave
//! its process group with setsid(2), but not its cgroup.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

/// Where PREPARE mounts cgroup2. The kernel creates the directory in sysfs.
pub const MOUNT: &str = "/sys/fs/cgroup";
/// The run's group, under [`MOUNT`].
pub const RUN: &str = "run";

/// A kill pass that finds new processes each time is chasing a fork loop; RLIMIT_NPROC ends that
/// well within this many passes.
const KILL_PASSES: usize = 16;

#[derive(Debug, Clone)]
pub struct Group {
    dir: PathBuf,
    /// What a run may have when its files take no memory, from PREPARE.
    budget_kb: u64,
}

impl Group {
    pub fn at(dir: impl Into<PathBuf>, budget_kb: u64) -> Group {
        Group {
            dir: dir.into(),
            budget_kb,
        }
    }

    /// The run's group in the guest.
    pub fn run(budget_kb: u64) -> Group {
        Group::at(Path::new(MOUNT).join(RUN), budget_kb)
    }

    /// Sets `memory.max` for a run whose files take `files_kb` of tmpfs, and returns it in kB.
    ///
    /// The agent writes those files, so their pages are charged to the agent's group, and yet
    /// they come out of the memory the budget was measured from. Without this, a run with 8 MiB of
    /// files could use its whole budget besides, and the kernel found the difference by evicting
    /// pages Xorg and the interpreter map. It SHOULD be called while the group is empty: below what
    /// the group holds, the write makes the kernel reclaim from it, or kill in it, first.
    pub fn limit_for_files(&self, files_kb: u64) -> io::Result<u64> {
        let kb = self.budget_kb.saturating_sub(files_kb);
        fs::write(self.dir.join("memory.max"), (kb * 1024).to_string())?;
        Ok(kb)
    }

    /// The file a process writes `0` to, to move itself in.
    pub fn procs(&self) -> PathBuf {
        self.dir.join("cgroup.procs")
    }

    /// Moves process `pid`, with all its threads. Only memory it allocates from now on is charged
    /// to the group: what the warm interpreter already holds stays with the group it came from.
    pub fn enter(&self, pid: u32) -> io::Result<()> {
        fs::write(self.procs(), pid.to_string())
    }

    /// SIGKILL to every process in the group, from the kernel, which no fork can race.
    pub fn kill(&self) -> io::Result<()> {
        fs::write(self.dir.join("cgroup.kill"), "1")
    }

    pub fn pids(&self) -> io::Result<Vec<libc::pid_t>> {
        Ok(fs::read_to_string(self.procs())?
            .lines()
            .filter_map(|line| line.trim().parse().ok())
            .collect())
    }

    /// SIGKILL to every process in the group but `keep`, until none is left. Returns how many it
    /// signalled.
    pub fn kill_all_but(&self, keep: libc::pid_t) -> io::Result<usize> {
        let mut killed = Vec::new();
        for _ in 0..KILL_PASSES {
            let others: Vec<libc::pid_t> = self
                .pids()?
                .into_iter()
                .filter(|&pid| pid != keep && !killed.contains(&pid))
                .collect();
            if others.is_empty() {
                break;
            }
            for pid in others {
                // SAFETY: kill takes a pid and a signal.
                unsafe { libc::kill(pid, libc::SIGKILL) };
                killed.push(pid);
            }
        }
        Ok(killed.len())
    }

    /// How often the kernel's OOM killer has killed in this group: `memory.events`' `oom_kill`.
    pub fn oom_kills(&self) -> Option<u64> {
        let events = fs::read_to_string(self.dir.join("memory.events")).ok()?;
        crate::procfs::counter(&events, "oom_kill")
    }

    /// The most memory the group has held, in kB.
    pub fn peak_kb(&self) -> Option<u64> {
        let bytes: u64 = fs::read_to_string(self.dir.join("memory.peak"))
            .ok()?
            .trim()
            .parse()
            .ok()?;
        Some(bytes / 1024)
    }
}

/// PREPARE: mounts cgroup2 where it is not yet, hands the memory controller down to the run's group
/// and sets that group's budget.
pub fn create(memory_max_kb: u64) -> Result<Group, String> {
    let root = Path::new(MOUNT);
    if !root.join("cgroup.controllers").exists() {
        crate::sys::mount_cgroup2(root).map_err(|error| format!("mounting cgroup2 on {MOUNT}: {error}"))?;
    }
    let write = |path: PathBuf, value: &str| {
        fs::write(&path, value).map_err(|error| format!("{} = {value}: {error}", path.display()))
    };
    write(root.join("cgroup.subtree_control"), "+memory")?;
    let group = Group::run(memory_max_kb);
    fs::create_dir_all(&group.dir).map_err(|error| format!("{}: {error}", group.dir.display()))?;
    write(group.dir.join("memory.max"), &(memory_max_kb * 1024).to_string())?;
    // An OOM inside the group ends all of the run, not one process of it, which is how it ends
    // anyway: the run's leader is the one the kernel would pick first.
    write(group.dir.join("memory.oom.group"), "1")?;
    Ok(group)
}

/// The least budget PREPARE saves a machine with, in kB. A run with the most files it may have,
/// [`crate::files::MAX_FILES_BYTES`], still gets about 8 MiB of it: a corpus program that draws
/// takes under 256 kB, and `sandbox.py` 1.7 MB.
pub const MIN_BUDGET_KB: u64 = 16 * 1024;

/// The run's memory budget, from `/proc/meminfo` once PREPARE has read everything back.
///
/// Free memory plus the page cache nothing maps, less the kernel's high watermarks and
/// `reserved_kb`, what Xorg and the kernel may take besides. Beyond it the kernel would reclaim
/// pages that Xorg, the agent and the warm interpreter map, and fetch them again over the network
/// while the run goes on.
///
/// Errs when `meminfo` lacks a field, and under [`MIN_BUDGET_KB`]: a machine saved with less still
/// builds and restores, and then every run on it ends `oom`.
pub fn budget_kb(meminfo: &str, high_watermarks_kb: u64, reserved_kb: u64) -> Result<u64, String> {
    let field = |key| crate::procfs::kb_field(meminfo, key).ok_or_else(|| format!("/proc/meminfo lacks {key}"));
    let available = field("MemFree")? + field("Cached")?.saturating_sub(field("Mapped")?);
    let budget = available.saturating_sub(high_watermarks_kb + reserved_kb);
    if budget < MIN_BUDGET_KB {
        return Err(format!(
            "the run's memory.max would be {budget} kB, under the {MIN_BUDGET_KB} kB floor: {available} kB of free memory and unmapped page cache, less {high_watermarks_kb} kB of high watermarks and the {reserved_kb} kB reserved for Xorg and the kernel. Give the guest more memory, or reserve less"
        ));
    }
    Ok(budget)
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Scratch(PathBuf);

    impl Scratch {
        fn new(name: &str) -> Scratch {
            let dir = std::env::temp_dir().join(format!("icc-cgroup-{name}-{}", std::process::id()));
            let _ = fs::remove_dir_all(&dir);
            fs::create_dir_all(&dir).unwrap();
            Scratch(dir)
        }
    }

    impl Drop for Scratch {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn reads_the_groups_counters() {
        let scratch = Scratch::new("counters");
        let group = Group::at(&scratch.0, 0);
        assert_eq!(group.oom_kills(), None);
        fs::write(
            scratch.0.join("memory.events"),
            "low 0\nhigh 0\nmax 12\noom 1\noom_kill 1\noom_group_kill 1\n",
        )
        .unwrap();
        fs::write(scratch.0.join("memory.peak"), "3145728\n").unwrap();
        fs::write(scratch.0.join("cgroup.procs"), "12\n345\n").unwrap();
        assert_eq!(group.oom_kills(), Some(1));
        assert_eq!(group.peak_kb(), Some(3072));
        assert_eq!(group.pids().unwrap(), [12, 345]);
    }

    #[test]
    fn kills_nothing_it_is_told_to_keep() {
        let scratch = Scratch::new("keep");
        let group = Group::at(&scratch.0, 0);
        // SAFETY: getpid cannot fail.
        let me = unsafe { libc::getpid() };
        fs::write(scratch.0.join("cgroup.procs"), format!("{me}\n")).unwrap();
        assert_eq!(group.kill_all_but(me).unwrap(), 0);
    }

    #[test]
    fn a_runs_files_come_out_of_its_budget() {
        let scratch = Scratch::new("files");
        let group = Group::at(&scratch.0, 10_192);
        assert_eq!(group.limit_for_files(8_196).unwrap(), 1_996);
        assert_eq!(fs::read_to_string(scratch.0.join("memory.max")).unwrap(), "2043904");
        assert_eq!(group.limit_for_files(20_000).unwrap(), 0);
    }

    #[test]
    fn budgets_what_can_go_without_touching_mapped_pages() {
        let meminfo =
            "MemTotal: 124648 kB\nMemFree: 38636 kB\nMemAvailable: 59212 kB\nCached: 23200 kB\nMapped: 15840 kB\n";
        assert_eq!(budget_kb(meminfo, 1488, 18_432), Ok(38_636 + 7_360 - 1_488 - 18_432));
        assert!(budget_kb("MemFree: 1 kB\n", 0, 0).unwrap_err().contains("lacks Cached"));
    }

    #[test]
    fn refuses_a_budget_under_the_floor_and_names_the_reserve() {
        // The 96 MiB build: 12,204 kB above the high watermarks, which the 18 MiB reserve took all of.
        let meminfo =
            "MemTotal: 92392 kB\nMemFree: 6636 kB\nMemAvailable: 27212 kB\nCached: 23200 kB\nMapped: 15840 kB\n";
        let error = budget_kb(meminfo, 1_792, 18_432).unwrap_err();
        assert!(error.contains("would be 0 kB"), "{error}");
        assert!(
            error.contains("the 18432 kB reserved for Xorg and the kernel"),
            "{error}"
        );

        let at_floor = format!("MemFree: {MIN_BUDGET_KB} kB\nCached: 0 kB\nMapped: 0 kB\n");
        assert_eq!(budget_kb(&at_floor, 0, 0), Ok(MIN_BUDGET_KB));
        assert!(budget_kb(&at_floor, 1, 0).is_err());
    }
}
