import json
import tkinter as tk

root = tk.Tk()
root.title("Input")
name = tk.Entry(root, font=("Arial", 14))
name.pack(padx=20, pady=20)
name.focus_set()

window = tk.Toplevel(root)
window.title("Second window")
window.geometry("+420+200")
city = tk.Entry(window, font=("Arial", 14))
city.pack(padx=20, pady=20)
city.focus_set()


def done(event):
    print(json.dumps({"name": name.get(), "city": city.get()}), flush=True)


root.bind_all("<Return>", done)
root.update()
print(json.dumps({"name": [name.winfo_rootx(), name.winfo_rooty(), name.winfo_width(), name.winfo_height()]}), flush=True)
root.mainloop()
