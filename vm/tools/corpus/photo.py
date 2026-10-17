import json
import tkinter as tk

root = tk.Tk()
root.title("Picture")
photo = tk.PhotoImage(file="picture.png")
label = tk.Label(root, image=photo, borderwidth=0)
label.pack()
root.update()
print(json.dumps({"size": [photo.width(), photo.height()], "at": [label.winfo_rootx(), label.winfo_rooty()]}), flush=True)
root.mainloop()
