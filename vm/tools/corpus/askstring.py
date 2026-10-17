import tkinter as tk
from tkinter import simpledialog

root = tk.Tk()
root.withdraw()
name = simpledialog.askstring("Name", "What is your name?")
print("Hello", name)
