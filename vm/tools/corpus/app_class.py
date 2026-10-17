import tkinter as tk


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("My app")
        self.geometry("320x200")
        tk.Label(self, text="A class", bg="#aa3355", fg="white").pack(fill="both", expand=True)


app = App()
app.mainloop()
