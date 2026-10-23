# A first window

A program with a window of its own, made with Tkinter.

```metadata
id: first-window
icon: window
runtime: tkinter
feature: tkinter
```

## Opening a window

```metadata
type: info
id: opening-a-window
emoji: "🪟"
```

So far your programs only wrote text to the output. With the `tkinter` module a program opens a window of its own, with buttons and text in it.

```python
import tkinter as tk

root = tk.Tk()
root.title("My window")
root.mainloop()
```

`tk.Tk()` makes the window and `root.title(...)` sets the text in its title bar. `root.mainloop()` keeps the window open until you close it. Without that last line the program is done straight away and the window disappears again.

## Text in the window

```metadata
type: exercise
id: text-in-a-window
emoji: "🏷️"
```

A piece of text in a window is called a label. You make one with `tk.Label` and put it in the window with `pack()`:

```python
label = tk.Label(root, text="Welcome")
label.pack()
```

Give the window below the title `Greeting` and put a label in it with the text `Hello!`.

```python-assignment
import tkinter as tk

root = tk.Tk()

root.mainloop()
```

```python-validator
if not program.calls(".title"):
    raise Exception("Give the window a title with `root.title(...)`.")
if not program.calls(".title").with_args("Greeting"):
    raise Exception("The title should be `Greeting`.")
if not program.calls("tk.Label"):
    raise Exception("Make a label with `tk.Label(...)`.")
if not program.calls("tk.Label").with_args(anything, text="Hello!"):
    raise Exception("The label should have the text `Hello!`.")
if not program.calls(".pack"):
    raise Exception("Put the label in the window with `pack()`.")
if not program.calls(".mainloop"):
    raise Exception("Without `root.mainloop()` the window closes straight away.")
```
