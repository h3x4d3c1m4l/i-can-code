# Sample: a quick exercise

One `quick-exercise` section: prose and a two-line editor, stacked.

```metadata
id: sample-quick-exercise
icon: keyboard
```

## Print something yourself

```metadata
type: quick-exercise
id: print-yourself
emoji: "✍️"
```

A `quick-exercise` is a question of a sentence or two whose answer runs one line
past its starter, so the prose and the editor stack in a single column and the
editor is sized to exactly that. An empty starter counts as one line, so the
least is two: storing something and then showing it is the smallest exercise
worth setting. A step that needs more says `lines:` in its metadata. The editor
holds the student to the limit, so a line past it is joined onto the last one
rather than accepted.

Write a line of code that prints a piece of text.

```python-assignment
```

```python-validator
program.allow_only("call")

if not program.calls("print"):
    raise Exception("Use the `print` function to show a piece of text.")
if not program.calls("print").with_args(a_string):
    raise Exception("Put your text between quotation marks.")
```
