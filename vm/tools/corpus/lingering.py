import os

# Ten children that never end, and a program that does. Each fork of the warm interpreter costs
# the run about 665 kB, so ten stay well inside its memory budget.
for _ in range(10):
    if os.fork() == 0:
        while True:
            pass
print("done", flush=True)
