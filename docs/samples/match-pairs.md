# Sample: a match-the-pairs board

One `match-pairs` section: a board of tiles instead of an editor.

```metadata
id: sample-match-pairs
emoji: "🧩"
```

## What belongs together?

```metadata
type: match-pairs
id: printing-pairs
emoji: "🧩"
```

A `match-pairs` step carries a `pairs` block in place of an assignment and a
validator. **The board is the check**: the step passes the moment its last pair
lands, and there is nothing to run.

One pair per paragraph, two lines each, separated by a blank line. Every tile is
dealt into **one pool**, shuffled from the section's `id`, so which half you write
first changes nothing the student sees — and the order the file lists them in is
never the order they appear.

Both halves are inline markdown, and a tile is a square, so keep them short.

```pairs
`print("Hello")`
… shows the text Hello.

`print(42)`
… shows the number 42, with no quotation marks around it.

`print(3.14)`
… uses a dot as the decimal separator, not a comma.

Two `print` lines below one another
… produce two lines of output.
```
