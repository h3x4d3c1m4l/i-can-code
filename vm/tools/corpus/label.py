import tkinter as tk

root = tk.Tk()
root.title("Label")
tk.Label(root, text="Hello world!", font=("Arial", 24, "bold"), bg="#3366cc", fg="white", padx=40, pady=30).pack()
root.mainloop()
print("mainloop is done")
