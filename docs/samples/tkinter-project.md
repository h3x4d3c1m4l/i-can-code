# Sample: a project with a window

One program with a window, built up over its tasks and run on the machine behind the Tkinter page.

```metadata
id: sample-tkinter-project
emoji: "🪟"
layout: project
runtime: tkinter
feature: tkinter
```

## What you will build

```metadata
type: info
id: what-you-build
emoji: "🪟"
```

A window with a line of text in it, and then a button that changes that text. Press **Run** and your program's window opens over the page. The cross in its title bar ends the program.

## A window with a label

```metadata
type: task
id: window-with-label
emoji: "🏷️"
```

The editor already holds an empty window. Put a label in it that says `Hello!`, and run it.

```done-when
A window opens with `Hello!` in it.
```

### 💡 Hint {collapsed}

`tk.Label(root, text="...")` makes the label, and `.pack()` puts it in the window.

```python-assignment
import tkinter as tk

root = tk.Tk()
root.title("My window")

root.mainloop()
```

## A button that changes it

```metadata
type: task
id: button-changes-label
emoji: "🔘"
```

Add a button under the label. When it is pressed, the label says `You pressed it!` instead.

```done-when
Pressing the button changes the text in the window.
```

### 💡 Hint {collapsed}

A button runs the function you give it as `command`, and `label.config(text="...")` changes what the label says.
