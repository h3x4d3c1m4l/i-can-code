import json
import tkinter as tk

root = tk.Tk()
root.title("Button")
counter = tk.IntVar(root, 0)


def click():
    counter.set(counter.get() + 1)
    print("clicked", counter.get(), flush=True)


button = tk.Button(root, text="Click me", command=click, font=("Arial", 16))
button.pack(padx=40, pady=40)
tk.Label(root, textvariable=counter).pack()
root.update()
print(json.dumps({"button": [button.winfo_rootx(), button.winfo_rooty(), button.winfo_width(), button.winfo_height()]}), flush=True)
root.mainloop()
