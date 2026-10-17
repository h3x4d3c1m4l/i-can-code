import json
import os

# The run's files take 8 MiB of the guest's memory before the program starts, and then it
# allocates until it runs out. Its budget has to have shrunk by what the files take.
print(json.dumps({
    "size": os.path.getsize("data.bin"),
    "max_kb": int(open("/sys/fs/cgroup/run/memory.max").read()) // 1024,
}), flush=True)
blocks = []
while True:
    blocks.append(b"x" * (1 << 20))
    print(json.dumps({"memory_mib": len(blocks)}), flush=True)
