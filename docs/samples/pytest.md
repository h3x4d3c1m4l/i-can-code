# Sample: unit tests with pytest

Two `exercise` sections with `run: pytest`. In the first the student writes the
tests; in the second, the code the tests are for.

```metadata
id: sample-pytest
icon: magnifier
```

## Tests that catch a bug

```metadata
type: exercise
id: tests-for-deel
emoji: "🧪"
run: pytest
file: test_rekenmachine.py
```

`run: pytest` runs the tests instead of the program. The editor holds the file
`file:` names. Each `file` block with a `.py` name gives one more module, shown
as code above the editor.

Write tests for `deel` in `rekenmachine.py`. Mark each test's three parts with
`# Arrange`, `# Act` and `# Assert`.

```file rekenmachine.py
def deel(a, b):
    if b == 0:
        raise ValueError("delen door nul")
    return a / b
```

```python-assignment
import pytest
from rekenmachine import deel


def test_deel():
    # Arrange
    a, b = 7, 2
    # Act
    uitkomst = deel(a, b)
    # Assert
    assert uitkomst == 3.5


def test_deel_door_nul():
    # Arrange
    a = 1
    # Act / Assert
    with pytest.raises(ValueError):
        deel(a, 0)
```

```python-validator
program.require_aaa()
for old, new, hint in [
    ("if b == 0", "if b == 1", "Test ook wat er gebeurt als je door 0 deelt."),
    ("return a / b", "return a // b", "Test een deling die niet precies uitkomt, zoals 7 / 2."),
]:
    if run_tests(replace={"rekenmachine.py": (old, new)}).passed:
        raise Exception(hint)
```

## Code that passes the tests

```metadata
type: exercise
id: korting-for-tests
emoji: "🎯"
run: pytest
file: korting.py
optional: true
```

The other way round: the tests are given, and the student writes the function
until they all pass. No validator block is needed: a section with `run: pytest`
only passes once every test does.

```file test_korting.py
from korting import met_korting


def test_tien_procent():
    # Arrange
    prijs = 50.0
    # Act
    nieuw = met_korting(prijs, 10)
    # Assert
    assert nieuw == 45.0


def test_geen_korting():
    # Arrange
    prijs = 20.0
    # Act
    nieuw = met_korting(prijs, 0)
    # Assert
    assert nieuw == 20.0
```

```python-assignment
def met_korting(prijs, procent):
    ...
```
