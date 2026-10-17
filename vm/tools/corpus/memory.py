import json
import os


def space(path):
    s = os.statvfs(path)
    return s.f_blocks * s.f_frsize // 1024


print(json.dumps({
    "shm_kb": space("/dev/shm"),
    "tmp_kb": space("/tmp"),
    "home_kb": space("/home/student"),
    "cgroup": open("/proc/self/cgroup").read().strip(),
}), flush=True)
mib = b"x" * (1 << 20)
for mount in ["/dev/shm", "/tmp", "/home/student"]:
    n = 0
    try:
        while True:
            with open(f"{mount}/fill{n}", "wb") as f:
                f.write(mib)
            n += 1
    except OSError as error:
        print(json.dumps({"mount": mount, "mib": n, "error": type(error).__name__}), flush=True)
blocks = []
while True:
    blocks.append(b"x" * (1 << 20))
    print(json.dumps({"memory_mib": len(blocks)}), flush=True)
