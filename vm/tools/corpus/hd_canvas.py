import json
import os
import tkinter as tk

# Tk redraws a Canvas through a pixmap the size of the part it redraws, and Xorg allocates it:
# 7.9 MiB at 1920 x 1080 and 9.8 MiB at 1600 x 1600, both larger than the 800 x 600 screen.


def xorg_kb():
    """Xorg's VmData and VmHWM: its /proc status is as readable to the student as anyone's."""
    for pid in filter(str.isdigit, os.listdir("/proc")):
        try:
            if open(f"/proc/{pid}/comm").read().strip() != "Xorg":
                continue
            fields = dict(line.split(":", 1) for line in open(f"/proc/{pid}/status"))
            return {name: int(fields[name].split()[0]) for name in ("VmData", "VmHWM")}
        except OSError:
            pass
    return None


def bigger():
    root.geometry("1600x1600+0+0")
    canvas.config(width=1600, height=1600, bg="#ff00ff")
    root.update()
    print(json.dumps({"drawn": "1600x1600", "xorg_kb": xorg_kb()}), flush=True)
    root.after(1000, root.destroy)


print(json.dumps({"before": xorg_kb()}), flush=True)
root = tk.Tk()
root.title("Full HD")
root.geometry("1920x1080+0+0")
canvas = tk.Canvas(root, width=1920, height=1080, bg="#00ff00", highlightthickness=0)
canvas.pack()
canvas.create_rectangle(100, 100, 300, 300, fill="#0000ff", outline="")
root.update()
print(json.dumps({"drawn": "1920x1080", "xorg_kb": xorg_kb()}), flush=True)
root.after(1000, bigger)
root.mainloop()
