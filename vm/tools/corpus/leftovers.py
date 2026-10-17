import json
import os
import time

# Run after another program on the same machine, without a restore in between: which of the
# student's processes are still there?
time.sleep(1)
remaining = []
for pid in os.listdir("/proc"):
    if not pid.isdigit() or int(pid) == os.getpid():
        continue
    try:
        with open(f"/proc/{pid}/status") as f:
            uid = next(line.split()[1] for line in f if line.startswith("Uid:"))
        if uid == "1000":
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                remaining.append(f.read().replace(b"\0", b" ").decode().strip())
    except (OSError, StopIteration):
        pass
try:
    heartbeat = time.monotonic() - float(open("/tmp/heartbeat").read())
except (OSError, ValueError):
    heartbeat = None
print(json.dumps({"remaining": remaining, "heartbeat": heartbeat}), flush=True)
