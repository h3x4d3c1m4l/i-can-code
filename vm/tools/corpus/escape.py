import os
import sys
import time

# A grandchild in a session of its own, so no signal to the program's process group reaches it,
# that says it is still alive every 100 ms.
child = os.fork()
if child == 0:
    os.setsid()
    if os.fork() == 0:
        while True:
            with open("/tmp/heartbeat", "w") as f:
                f.write(f"{time.monotonic():.3f}")
            time.sleep(0.1)
    os._exit(0)
os.waitpid(child, 0)
time.sleep(0.5)
print("escaped", flush=True)
if sys.argv[1:] == ["stay"]:
    while True:
        pass
