import tkinter as tk
from tkinter import messagebox

root = tk.Tk()
root.withdraw()
messagebox.showinfo("Notice", "Only this window should appear.")
print("closed")
