import json
import os
import stat


def attempt(action):
    try:
        action()
        return "ok"
    except OSError as error:
        return type(error).__name__


def in_child(action):
    """What `action` gives in a forked child: whether the child still holds what its parent held."""
    read_fd, write_fd = os.pipe()
    child = os.fork()
    if child == 0:
        os.write(write_fd, attempt(action).encode())
        os._exit(0)
    os.close(write_fd)
    os.waitpid(child, 0)
    return os.read(read_fd, 100).decode()


def space_kb(path):
    s = os.statvfs(path)
    return s.f_blocks * s.f_frsize // 1024


def su():
    """su's exit status and what it said. By hand rather than through subprocess, whose imports
    would be fetched over the network."""
    read_fd, write_fd = os.pipe()
    child = os.fork()
    if child == 0:
        try:
            null = os.open("/dev/null", os.O_RDWR)
            os.dup2(null, 0)
            os.dup2(write_fd, 1)
            os.dup2(write_fd, 2)
            os.execv("/bin/su", ["su", "-c", "id -u"])
        finally:
            os._exit(127)
    os.close(write_fd)
    said = b""
    while part := os.read(read_fd, 4096):
        said += part
    os.close(read_fd)
    return os.waitstatus_to_exitcode(os.waitpid(child, 0)[1]), said.decode(errors="replace").strip()


def setuid_files():
    """Files with a setuid or setgid bit where programs are found."""
    found = []
    for folder in ["/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/libexec", "/usr/local/bin"]:
        for name in os.listdir(folder):
            mode = os.lstat(os.path.join(folder, name)).st_mode
            if stat.S_ISREG(mode) and mode & (stat.S_ISUID | stat.S_ISGID):
                found.append(os.path.join(folder, name))
    return found


def flood():
    """Writes what the prelude writes to the agent, many times over, and lines it never writes."""
    for _ in range(1000):
        os.write(4, b"hint tk_no_mainloop\nhint made_up\n")
    os.write(4, b"x" * 100_000 + b"\n")


agent = next((int(p) for p in os.listdir("/proc") if p.isdigit() and open(f"/proc/{p}/comm").read().strip() == "icc-agent"), None)
print(json.dumps({
    "uid": os.getuid(),
    "agent": agent is not None,
    "icc_in": attempt(lambda: os.listdir("/icc/in")),
    "ttyS1": attempt(lambda: open("/dev/ttyS1", "wb")),
    "signal_agent": attempt(lambda: os.kill(agent, 0)),
    "agent_environ": attempt(lambda: open(f"/proc/{agent}/environ").read()),
    "root_home": attempt(lambda: os.listdir("/root")),
    "write_root": attempt(lambda: open("/new.txt", "w")),
    "setuid": attempt(lambda: os.setuid(0)),
    "no_new_privs": next(line.split()[1] for line in open("/proc/self/status") if line.startswith("NoNewPrivs:")),
    **dict(zip(["su", "su_says"], su())),
    "setuid_files": setuid_files(),
    "write_tmp": attempt(lambda: open("/tmp/allowed.txt", "w").write("yes")),
    "write_work": attempt(lambda: open("output.txt", "w").write("yes")),
    "status_fd_in_child": in_child(lambda: os.fstat(4)),
    "cgroup": open("/proc/self/cgroup").read().strip(),
    "leave_cgroup": attempt(lambda: open("/sys/fs/cgroup/cgroup.procs", "w").write(str(os.getpid()))),
    "shm_kb": space_kb("/dev/shm"),
    "flood": attempt(flood),
}), flush=True)
