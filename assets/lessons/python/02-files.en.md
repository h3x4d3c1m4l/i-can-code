# Files

Read a CSV file, and write one.

```metadata
id: files
emoji: "📄"
```

## The average grade

```metadata
type: exercise
id: average-grade
emoji: "📊"
```

Next to your program is a file called `grades.csv`. Every line is a student with
a grade, and the first line names the columns. Press its button to see what is
in it.

The `csv` module reads a file like this line by line. `csv.reader` gives you a
list for every line, with one element per column.

Show the average grade of all students.

```file grades.csv
{{#include data/grades.csv}}
```

```python-assignment
import csv

with open("grades.csv") as file:
    rows = list(csv.reader(file))
```

```python-validator
import re

if not program.calls("open"):
    raise Exception('Open the file with `open("grades.csv")`.')
if program.calls("print").with_args(7.25) or program.calls("print").with_args("7.25"):
    raise Exception("Work the average out from the grades in the file instead of typing it.")
numbers = re.findall(r"-?\d+(?:\.\d+)?", output)
if not numbers:
    raise Exception("Show the average with `print`.")
if float(numbers[-1]) != 7.25:
    raise Exception(
        "Add the grades up and divide by the number of students. The first line holds the "
        "headings, so leave it out."
    )
```

## Who passed?

```metadata
type: exercise
id: who-passed
emoji: "✍️"
```

`csv.writer` writes a file like this. `writerow` adds one line, which you hand
it as a list.

Write the name of everyone with a 5.5 or higher to `passed.csv`. Start with the
heading `name`, as the program already does. Once your program has run, the file
is under the output.

```file grades.csv
{{#include data/grades.csv}}
```

```python-assignment
import csv

with open("grades.csv") as file:
    rows = list(csv.reader(file))

with open("passed.csv", "w", newline="") as out:
    writer = csv.writer(out)
    writer.writerow(["name"])
```

```python-validator
import csv

if not program.calls(".writerow"):
    raise Exception("Write the lines with `writerow`.")
try:
    with open("passed.csv", newline="") as _file:
        lines = list(csv.reader(_file))
except FileNotFoundError:
    raise Exception("Write to `passed.csv`, with exactly that name.")
if not lines or lines[0] != ["name"]:
    raise Exception("Start the file with the line `name`, the column's heading.")
if lines[1:] != [["Sanne"], ["Mohammed"], ["Fatima"]]:
    raise Exception(
        "Under the heading, put the name of everyone with a 5.5 or higher, one per line, "
        "in the order of `grades.csv`."
    )
```

## Two grades added up

```metadata
type: predict-output
id: two-grades
emoji: "🔮"
```

This program reads the same file and adds up the grades of Sanne and Mohammed.
What does it show?

```file grades.csv
{{#include data/grades.csv}}
```

```python-predict
import csv

with open("grades.csv") as file:
    rows = list(csv.reader(file))

print(rows[1][1] + rows[2][1])
```

```explanation
A CSV file only holds text, and `csv.reader` gives you that text as it is in the
file. `"7.5" + "8.0"` puts two pieces of text one after the other. To calculate
with a grade, turn it into a number with `float` first.
```
