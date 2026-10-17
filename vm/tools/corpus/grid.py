import json
import tkinter as tk

root = tk.Tk()
root.title("Grid")
colours = ["#cc0000", "#00aa00", "#0000cc", "#cccc00", "#00cccc", "#cc00cc", "#888888", "#ff8800", "#004400"]
cells = {}
for row in range(3):
    for column in range(3):
        cell = tk.Label(root, text=f"{row},{column}", width=8, height=3, bg=colours[row * 3 + column])
        cell.grid(row=row, column=column, padx=2, pady=2)
        cells[f"{row},{column}"] = cell
root.update()
print(json.dumps({k: [v.winfo_rootx() + v.winfo_width() // 2, v.winfo_rooty() + 5] for k, v in cells.items()}), flush=True)
root.mainloop()
