import tkinter as tk
from tkinter import messagebox

root = tk.Tk()
root.withdraw()
answer = messagebox.askokcancel("Question", "Do you want to continue?")
print("answer:", answer)
