import tkinter as tk

root = tk.Tk()
root.title("Canvas")
canvas = tk.Canvas(root, width=400, height=300, bg="white")
canvas.pack()
canvas.create_rectangle(20, 20, 180, 120, fill="#22aa44", outline="")
canvas.create_oval(250, 30, 350, 130, fill="orange", outline="")
canvas.create_text(200, 220, text="Bold", font=("Helvetica", 28, "bold"), fill="navy")
canvas.create_text(200, 270, text="and italic", font=("Times", 18, "italic"))
root.mainloop()
