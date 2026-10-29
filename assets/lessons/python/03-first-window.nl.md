# Een eerste venster

Een programma met een eigen venster, gemaakt met Tkinter.

```metadata
id: first-window
icon: window
runtime: tkinter
```

## Een venster openen

```metadata
type: info
id: opening-a-window
emoji: "🪟"
```

Tot nu toe schreven je programma's alleen tekst in de uitvoer. Met de module `tkinter` opent een programma een eigen venster, met knoppen en tekst erin.

```python
import tkinter as tk

root = tk.Tk()
root.title("Mijn venster")
root.mainloop()
```

`tk.Tk()` maakt het venster en `root.title(...)` zet de tekst in de titelbalk. `root.mainloop()` houdt het venster open tot je het sluit. Zonder die laatste regel is het programma meteen klaar en verdwijnt het venster weer.

## Tekst in het venster

```metadata
type: exercise
id: text-in-a-window
emoji: "🏷️"
```

Een stuk tekst in een venster heet een label. Je maakt het met `tk.Label` en zet het met `pack()` in het venster:

```python
label = tk.Label(root, text="Welkom")
label.pack()
```

Geef het venster hieronder de titel `Begroeting` en zet er een label in met de tekst `Hallo!`.

```python-assignment
import tkinter as tk

root = tk.Tk()

root.mainloop()
```

```python-validator
if not program.calls(".title"):
    raise Exception("Geef het venster een titel met `root.title(...)`.")
if not program.calls(".title").with_args("Begroeting"):
    raise Exception("De titel moet `Begroeting` zijn.")
if not program.calls("tk.Label"):
    raise Exception("Maak een label met `tk.Label(...)`.")
if not program.calls("tk.Label").with_args(anything, text="Hallo!"):
    raise Exception("Het label moet de tekst `Hallo!` hebben.")
if not program.calls(".pack"):
    raise Exception("Zet het label in het venster met `pack()`.")
if not program.calls(".mainloop"):
    raise Exception("Zonder `root.mainloop()` gaat het venster meteen weer dicht.")
```
