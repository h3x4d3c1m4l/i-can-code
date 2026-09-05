# Input and output

Enable user interaction through text input and output.

```metadata
id: input-and-output
emoji: "⌨️"
```

## Introduction

```metadata
type: info
id: introduction
emoji: "👋"
```

Welcome to the first module about Python!

When programmers first start exploring a new programming language, showing a short text message is often the first thing they try.

The message most commonly used for this, and one that is very well known among programmers, is 'Hello, world'. You will come across that same message in this and other tutorials.

The line of code that shows the text 'Hello, world' in Python is:

```python
print("Hello, world")
```

This calls Python's `print` function and tells it what to 'print'. The term printing dates back to the time when computers had no screens. Input was done with physical switches on the computer itself, and output went through a printer. So although the term is a leftover from the past, it is still the standard in many programming languages.

## Printing yourself

```metadata
type: quick-exercise
id: print-yourself
emoji: "✍️"
```

Now write a line of code yourself to "print" a piece of text. Choose your own message.

```python-assignment
```

```python-validator
if "print(" not in code:
    raise Exception("Use the `print` function to output text.")
if not output:
    raise Exception("Use the `print` function with a non-empty text.")
```

## Printing different things

```metadata
type: exercise
id: printing-values
emoji: "📦"
```

You have now seen and experienced how to use the `print` function for text. You can use that same function for other types of values too.

You will find more about the different types of values Python knows in a later chapter. For now we will limit ourselves to whole numbers and decimal numbers.

Change the code below so that it first prints the number `42` and then the number Pi to 2 decimal places (2 digits after the decimal point).

Unlike text, numbers are written without quotation marks in Python. Note as well that Python uses a dot as the decimal separator, not a comma: write `3.14`, not `3,14`.

```python-assignment
print(...)
print(...)
```

```python-validator
if "print(" not in code:
    raise Exception("Use the `print` function.")
if '"42"' in code or "'42'" in code or '"3.14"' in code or "'3.14'" in code:
    raise Exception("Numbers are written without quotation marks.")
if "3,14" in code.replace(" ", ""):
    raise Exception("Python uses a dot as the decimal separator, not a comma: write 3.14.")
if output != "42\n3.14":
    raise Exception("`print` 42 first, then 3.14. Use 2 separate `print` lines for this.")
```

## What belongs together?

```metadata
type: match-pairs
id: printing-pairs
emoji: "🧩"
```

You now know what `print` does with text and with numbers. Put together the parts that form one sentence that is true.

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
