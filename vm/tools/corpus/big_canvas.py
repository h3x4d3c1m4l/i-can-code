import tkinter as tk

# Tk draws a canvas through a pixmap the size of the part it redraws: here 3000 x 3000 at four
# bytes a pixel, more than the whole guest has.
root = tk.Tk()
root.title("Big canvas")
root.geometry("3000x3000+0+0")
canvas = tk.Canvas(root, width=3000, height=3000, bg="red", highlightthickness=0)
canvas.pack()
print("started", flush=True)
root.update()
print("drawn", flush=True)
root.after(1000, root.destroy)
root.mainloop()
