import json
import tkinter as tk

# Twelve windows mapped a few milliseconds apart, so some of them map while the agent is still
# reading the list the one before set off.
COLOURS = ["#aa0000", "#00aa00", "#0000aa", "#aaaa00", "#00aaaa", "#aa00aa",
           "#550000", "#005500", "#000055", "#555500", "#005555", "#550055"]
PAUSES = [5, 10, 15, 20, 25, 30, 35, 40, 50, 60, 80]

root = tk.Tk()
root.title("First")
root.geometry("120x80+0+0")
root.configure(bg="#ffffff")
places = {}


def open_window(i):
    x, y = 130 * (i % 6), 100 + 90 * (i // 6)
    window = tk.Toplevel(root)
    window.title(f"Window {i}")
    window.geometry(f"120x80+{x}+{y}")
    window.configure(bg=COLOURS[i])
    if i + 1 < len(COLOURS):
        root.after(PAUSES[i], open_window, i + 1)


def stack(attempts=0):
    """The server's own stacking order, which the agent's last list must match.

    Not the order the windows were opened in: Tk sometimes stacks the first two the other way.
    It lists mapped windows only, and on a busy host the last one can map after two seconds.
    """
    paths = root.tk.splitlist(root.tk.call("wm", "stackorder", "."))
    if len(paths) < len(COLOURS) + 1 and attempts < 40:
        root.after(250, stack, attempts + 1)
        return
    print(json.dumps({"stack": [root.nametowidget(path).title() for path in paths]}), flush=True)


for i, colour in enumerate(COLOURS):
    places[f"Window {i}"] = [130 * (i % 6) + 10, 100 + 90 * (i // 6) + 10, colour]
print(json.dumps({"places": places}), flush=True)
root.after(300, open_window, 0)
root.after(2000, stack)
root.mainloop()
