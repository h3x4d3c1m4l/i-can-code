import time
import tkinter as tk

root = tk.Tk()
root.title("Animation")
canvas = tk.Canvas(root, width=300, height=100, bg="white")
canvas.pack()
ball = canvas.create_oval(0, 40, 20, 60, fill="red", outline="")
steps = 0
start = time.monotonic()


def step():
    global steps
    steps += 1
    canvas.move(ball, 2, 0)
    if canvas.coords(ball)[0] > 280:
        canvas.move(ball, -280, 0)
    if steps % 10 == 0:
        print(f"{steps} {time.monotonic() - start:.3f} {time.time():.3f}", flush=True)
    root.after(50, step)


root.after(50, step)
root.mainloop()
