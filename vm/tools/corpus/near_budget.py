import json
import tkinter as tk

# Fills the run's memory budget to within MARGIN_KB of memory.max, then has Xorg allocate a
# 1920 x 1080 Canvas's pixmap. Xorg's room lies outside the budget, so neither may take the
# other's memory by evicting a file the guest maps.
MARGIN_KB = 1536


def group_kb(file):
    return int(open(f"/sys/fs/cgroup/run/{file}").read()) // 1024


def memory():
    fields = dict(line.split(":", 1) for line in open("/proc/meminfo"))
    return {name: int(fields[name].split()[0]) for name in ("MemFree", "Cached", "Mapped")}


max_kb = group_kb("memory.max")
before = {"current_kb": group_kb("memory.current"), **memory()}
ballast = bytearray((max_kb - before["current_kb"] - MARGIN_KB) * 1024)
print(json.dumps({"max_kb": max_kb, "ballast_kb": len(ballast) // 1024, "before": before,
                  "after_ballast": {"current_kb": group_kb("memory.current"), **memory()}}), flush=True)

root = tk.Tk()
root.title("Full")
root.geometry("1920x1080+0+0")
canvas = tk.Canvas(root, width=1920, height=1080, bg="#00ffff", highlightthickness=0)
canvas.pack()
root.update()
print(json.dumps({"drawn": {"current_kb": group_kb("memory.current"), **memory()}}), flush=True)
root.after(1000, root.destroy)
root.mainloop()
