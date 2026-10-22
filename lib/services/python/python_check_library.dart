/// The Python helper a validator is given for reading the student's own source.
///
/// It is carried into the run as base64 and exec'd into the validator's scope,
/// the same way the student's code is — see `PythonAttemptRunner.buildProgram`.
/// Keeping it here rather than under `assets/` is what lets `buildProgram` stay
/// static and synchronous, so `tool/try_lesson.dart` and the widget-free tests
/// drive the real thing without a `rootBundle`.
///
/// It leans on nothing outside the standard library. `ast` ships in
/// `assets/python/python315.zip`, and `_ast` is built into CPython itself, so
/// there is no asset to declare and no worker change behind this.
///
/// The names in its `__all__` are the contract with lesson authors, and
/// `docs/lesson-format.md` is where that contract is written down. Adding one
/// here means adding it there.
library;

// Raw, though nothing in it needs escaping today: this is Python source, and a
// `\n` or a `$` added to it later must reach CPython as written rather than be
// read by Dart on the way.
// ignore: unnecessary_raw_strings
const String kCheckLibrary = r'''
"""Static checks on the student's own source, for lesson validators.

Nothing here runs their code. It reads what they wrote, so it sees a branch that
never executed and never sees a value that was computed: `x = 40 + 2; print(x)`
is a call to `print` with a variable, not with 42.
"""
import ast
import io
import keyword
import re
import tokenize

__all__ = ["analyze", "anything", "a_string", "a_number", "a_variable", "a_call"]

#: What `disallow` and `allow_only` say when the author gave them no message.
#: English, and so wrong in every lesson not written in English — it is a
#: placeholder, and the `message` argument is the way out of it.
NOT_ALLOWED = "%s is not allowed in this exercise."

#: What `require_aaa` says when the author gave it no message. A placeholder in
#: English, for the same reason as `NOT_ALLOWED`.
AAA_MISSING = "`%s` needs the comments `# Arrange`, `# Act` and `# Assert`, once each and in that order."

#: The part markers `require_aaa` looks for. Text may follow the word, as in
#: `# Act: pay the bill`, but `# Actually` is no marker. One comment may mark
#: two parts, as `# Act / Assert` does around `pytest.raises`, where the call
#: and its check are the same `with` block.
_AAA_WORD = r"(?:arrange|act|assert)\b"
_AAA_MARKER = re.compile(r"#\s*%s(?:\s*(?:/|&|\+|,|and\b|en\b)\s*%s)*" % (_AAA_WORD, _AAA_WORD), re.IGNORECASE)


#: The constructs that are not a Python keyword, and so have no word to quote.
#: Spelled out rather than assembled, because "a assignment" is what a rule gives.
_PHRASES = {
    "call": "a function call",
    "assignment": "an assignment",
    "expression": "a bare expression",
    "comprehension": "a comprehension",
    "f-string": "an f-string",
    "type-alias": "a type alias",
}


def _is_keyword(construct):
    """Whether Python spells this construct with a word of its own.

    `match` is a **soft** keyword, so `iskeyword` says no about the one construct
    here that has a keyword and is not in that list.
    """
    return keyword.iskeyword(construct) or keyword.issoftkeyword(construct)


def _describe(construct):
    """A construct as it should be read. Only a keyword is set as code."""
    if _is_keyword(construct):
        return "`%s`" % construct
    return _PHRASES.get(construct, construct)


class NotAllowed(Exception):
    """What `disallow` and `allow_only` raise when the author wrote no message.

    The construct rides along so Dart can phrase it in the reader's own language
    — see `AppLocalizationsExtension.checkNotAllowed`. Its own text stays the
    English placeholder, so anything reading only the message still gets a
    sentence: `tool/try_lesson.dart` has no localizations to reach for.

    The attribute is prefixed because the harness finds it with `getattr` on
    whatever was raised, and must not mistake a validator's own exception for one
    of these.
    """

    def __init__(self, construct):
        super().__init__(NOT_ALLOWED % _describe(construct))
        self.icc_construct = construct


class AaaMissing(Exception):
    """What `require_aaa` raises when the author wrote no message.

    Carries the test's name as `icc_aaa`, so Dart can say it in the reader's own
    language, the same way `NotAllowed` carries its construct.
    """

    def __init__(self, test):
        super().__init__(AAA_MISSING % test)
        self.icc_aaa = test


def _types(*names):
    """AST classes by name, skipping any this CPython does not have.

    `ast.TryStar` arrived in 3.11 and `ast.TypeAlias` in 3.12. The app ships
    3.15, but `tool/try_lesson.dart` runs on whatever `python3` the machine has.
    """
    return tuple(getattr(ast, name) for name in names if hasattr(ast, name))


def _unwrap_sign(node):
    """`-1` is a unary minus over `1`, not the constant -1. Reads as the number."""
    if not isinstance(node, ast.UnaryOp) or not isinstance(node.op, (ast.UAdd, ast.USub)):
        return node
    if not isinstance(node.operand, ast.Constant):
        return node
    value = node.operand.value
    if isinstance(value, bool) or not isinstance(value, (int, float, complex)):
        return node
    return ast.Constant(value=-value if isinstance(node.op, ast.USub) else value)


def _matches(node, expected):
    """A matcher answers for itself; anything else is compared as a literal."""
    if hasattr(expected, "matches"):
        return expected.matches(node)
    node = _unwrap_sign(node)
    # `type(...) is type(...)` and not `==`, so 42 is not 42.0 and True is not 1.
    return (isinstance(node, ast.Constant)
            and type(node.value) is type(expected)
            and node.value == expected)


def _callee(call):
    """Every name a call answers to.

    `math.sqrt(x)` answers to both `math.sqrt` and `.sqrt`; `"hi".upper()` answers
    only to `.upper`, because its receiver is not a name to spell.
    """
    names = set()
    func = call.func
    if isinstance(func, ast.Attribute):
        names.add("." + func.attr)
    parts = []
    while isinstance(func, ast.Attribute):
        parts.append(func.attr)
        func = func.value
    if isinstance(func, ast.Name):
        parts.append(func.id)
        names.add(".".join(reversed(parts)))
    return names


class _Anything:

    def __repr__(self):
        return "anything"

    def matches(self, node):
        return True


class _Literal:
    """A literal of one of `types`. A bool is never a number."""

    def __init__(self, label, *types):
        self._label = label
        self._types = types

    def __repr__(self):
        return self._label

    def matches(self, node):
        node = _unwrap_sign(node)
        if not isinstance(node, ast.Constant):
            return False
        if isinstance(node.value, bool):
            return bool in self._types
        return isinstance(node.value, self._types)


class _Text(_Literal):
    """Text, f-string or not.

    An f-string parses to `ast.JoinedStr` rather than a constant, and a student
    who answered `print(f"Hallo {naam}")` has written text by the only reading
    that matters to a lesson.
    """

    def matches(self, node):
        return isinstance(node, ast.JoinedStr) or super().matches(node)


class a_variable:
    """Any name being read, or one particular name."""

    def __init__(self, name=None):
        self.name = name

    def __repr__(self):
        return "a_variable" if self.name is None else "a_variable(%r)" % self.name

    def matches(self, node):
        return isinstance(node, ast.Name) and (self.name is None or node.id == self.name)


class a_call:
    """A call used as an argument — the `round(...)` in `print(round(x, 2))`."""

    def __init__(self, name):
        self.name = name

    def __repr__(self):
        return "a_call(%r)" % self.name

    def matches(self, node):
        return isinstance(node, ast.Call) and self.name in _callee(node)


anything = _Anything()
a_string = _Text("a_string", str)
a_number = _Literal("a_number", int, float)


class _Query:
    """What still matches everything asked of it. Truthy while something does."""

    def __init__(self, nodes, label):
        self._nodes = nodes
        self._label = label

    def __bool__(self):
        return bool(self._nodes)

    def __len__(self):
        return len(self._nodes)

    def __repr__(self):
        return "<%d x %s>" % (len(self._nodes), self._label)

    def times(self, n):
        return len(self._nodes) == n

    def at_least(self, n):
        return len(self._nodes) >= n

    def at_most(self, n):
        return len(self._nodes) <= n


class CallQuery(_Query):

    def with_args(self, *expected, **keywords):
        """Exactly these positional arguments, and at least these keywords.

        Exactly, so `with_args(anything)` reads as "called with one thing" and
        not as "called with that among others" — which is `with_any_args`.
        """
        def ok(call):
            if len(call.args) != len(expected):
                return False
            if not all(_matches(a, e) for a, e in zip(call.args, expected)):
                return False
            # `**kwargs` in the call has arg None and cannot be named here.
            given = {k.arg: k.value for k in call.keywords if k.arg is not None}
            return all(name in given and _matches(given[name], value)
                       for name, value in keywords.items())

        shown = ", ".join([repr(e) for e in expected]
                          + ["%s=%r" % pair for pair in keywords.items()])
        return CallQuery([c for c in self._nodes if ok(c)],
                         "%s(%s)" % (self._label, shown))

    def with_any_args(self, *expected):
        """These arguments, in this order, among however many others."""
        def ok(call):
            rest = list(call.args)
            for e in expected:
                for i, arg in enumerate(rest):
                    if _matches(arg, e):
                        rest = rest[i + 1:]
                        break
                else:
                    return False
            return True

        return CallQuery([c for c in self._nodes if ok(c)], self._label)


class AssignQuery(_Query):

    def to(self, expected):
        """Assigned this value. An annotation with no value matches nothing."""
        return AssignQuery([n for n in self._nodes
                            if n.value is not None and _matches(n.value, expected)],
                           self._label)


def _assigns_to(node, name):
    if isinstance(node, ast.Assign):
        targets = node.targets
    elif isinstance(node, (ast.AnnAssign, ast.AugAssign)):
        targets = [node.target]
    else:
        return False
    if name is None:
        return True
    # Walked, not compared, so `a, b = 1, 2` counts as assigning both.
    return any(isinstance(inner, ast.Name) and inner.id == name
               for target in targets for inner in ast.walk(target))


class Program:
    """The student's source, read as a tree. Parsed once, on the first question."""

    _CONSTRUCTS = {
        "if": _types("If", "IfExp"),
        "match": _types("Match"),
        "for": _types("For", "AsyncFor"),
        "while": _types("While"),
        "break": _types("Break"),
        "continue": _types("Continue"),
        "comprehension": _types("ListComp", "SetComp", "DictComp", "GeneratorExp"),
        "try": _types("Try", "TryStar"),
        "raise": _types("Raise"),
        "assert": _types("Assert"),
        "def": _types("FunctionDef", "AsyncFunctionDef"),
        "lambda": _types("Lambda"),
        "return": _types("Return"),
        "yield": _types("Yield", "YieldFrom"),
        "class": _types("ClassDef"),
        "import": _types("Import", "ImportFrom"),
        "with": _types("With", "AsyncWith"),
        "global": _types("Global"),
        "nonlocal": _types("Nonlocal"),
        "del": _types("Delete"),
        "pass": _types("Pass"),
        "await": _types("Await"),
        "f-string": _types("JoinedStr"),
        "assignment": _types("Assign", "AnnAssign", "AugAssign"),
        "type-alias": _types("TypeAlias"),
    }

    # `ast.Expr` is a statement that is only an expression, so it carries no type
    # of its own to look up. It is the one a beginner's whole program is made of.
    _STATEMENTS = ("call", "expression")

    # A group stands for the constructs under it, so "no loops yet" is one word
    # rather than three an author has to remember to keep in step.
    _GROUPS = {
        "loops": ("for", "while", "comprehension"),
        "branches": ("if", "match"),
        "jumps": ("break", "continue", "return"),
        "functions": ("def", "lambda", "return"),
        "control-flow": ("if", "match", "for", "while", "comprehension",
                         "break", "continue", "try"),
    }

    _BY_TYPE = {t: name for name, types in _CONSTRUCTS.items() for t in types}

    def __init__(self, source):
        self.source = source
        self._tree = None

    @property
    def tree(self):
        if self._tree is None:
            self._tree = ast.parse(self.source)
        return self._tree

    def calls(self, name):
        """Every call to `name`, anywhere — inside a loop or a function included.

        The name is matched whole: `calls("math.sqrt")` finds `math.sqrt(x)`, and
        `calls("sqrt")` finds the bare `sqrt(x)` that `from math import sqrt`
        leaves. A leading dot is the method on any receiver, so `calls(".upper")`
        finds `naam.upper()` and `"hallo".upper()` alike.
        """
        return CallQuery([n for n in ast.walk(self.tree)
                          if isinstance(n, ast.Call) and name in _callee(n)], name)

    def assigns(self, name=None):
        """Every assignment with `=`, or every assignment to one name.

        A `for` target is not one of these: looping over something is not the
        same answer as naming it, and a lesson asking for either should say which.
        """
        return AssignQuery([n for n in ast.walk(self.tree) if _assigns_to(n, name)],
                           name or "an assignment")

    @classmethod
    def _construct_of(cls, node):
        """What a node is called, or None when it is a detail and not a construct.

        A `print(42)` line is a **call**; `x = input()` is an **assignment** and
        the call inside it is a detail, because what a lesson bans is the line a
        student wrote and not every node under it.
        """
        if isinstance(node, ast.Expr):
            return "call" if isinstance(node.value, ast.Call) else "expression"
        return cls._BY_TYPE.get(type(node))

    @classmethod
    def _names_of(cls, construct):
        """The names one word stands for. Raises on a word this does not know."""
        names = cls._GROUPS.get(construct, (construct,))
        for name in names:
            if name not in cls._CONSTRUCTS and name not in cls._STATEMENTS:
                known = sorted(cls._CONSTRUCTS) + list(cls._STATEMENTS) + sorted(cls._GROUPS)
                raise ValueError("No such construct %r. Known: %s"
                                 % (construct, ", ".join(known)))
        return names

    def _refuse(self, offenders, message):
        if not offenders:
            return
        # The earliest one, so a student who wrote two reads about the first.
        # `ast.walk` is breadth-first, so position has to be asked for.
        first = min(offenders, key=lambda n: (getattr(n, "lineno", 0),
                                              getattr(n, "col_offset", 0)))
        if message:
            raise Exception(message)
        raise NotAllowed(self._construct_of(first))

    def uses(self, construct):
        """Whether the source contains that construct, or any one of that group."""
        wanted = set(self._names_of(construct))
        return any(self._construct_of(n) in wanted for n in ast.walk(self.tree))

    def disallow(self, *constructs, message=None):
        """Raises when the source uses any of these. Falls through when it uses none.

            program.disallow("loops", "functions")

        See `allow_only` for the other direction, which is usually the one an
        early lesson wants: a ban has to name everything, and misses whatever
        Python grows next.
        """
        banned = set()
        for construct in constructs:
            banned.update(self._names_of(construct))
        self._refuse([n for n in ast.walk(self.tree)
                      if self._construct_of(n) in banned], message)

    def allow_only(self, *constructs, message=None):
        """Raises when the source uses anything **but** these.

        What an early step wants: after one page on `print`, the answer is calls
        and nothing else, and saying so is one line that stays right as the
        language grows.

            program.allow_only("call")
            program.allow_only("call", "assignment")

        A bare expression — a stray `42`, a docstring — is always allowed. It is
        not a construct a lesson teaches, and tripping over a docstring would
        read to a student as the checker being broken.
        """
        allowed = {"expression"}
        for construct in constructs:
            allowed.update(self._names_of(construct))
        offenders = []
        for node in ast.walk(self.tree):
            name = self._construct_of(node)
            if name is not None and name not in allowed:
                offenders.append(node)
        self._refuse(offenders, message)

    def _tests(self):
        """The functions pytest collects by default: `test*` at module level, and
        `test*` methods of a `Test*` class. In source order."""
        functions = _types("FunctionDef", "AsyncFunctionDef")
        found = [n for n in self.tree.body if isinstance(n, functions)]
        for node in self.tree.body:
            if isinstance(node, ast.ClassDef) and node.name.startswith("Test"):
                found += [n for n in node.body if isinstance(n, functions)]
        return sorted((n for n in found if n.name.startswith("test")), key=lambda n: n.lineno)

    def require_aaa(self, message=None):
        """Raises unless every test marks its three parts with a comment:

            def test_korting():
                # Arrange
                prijs = 100
                # Act
                nieuw = korting(prijs)
                # Assert
                assert nieuw == 90

        Each of `# Arrange`, `# Act` and `# Assert` MUST appear exactly once inside
        the test, in that order. Case does not matter, and text may follow the
        word. `# Act / Assert` (or `&`, `+`, `,`, `and`, `en`) marks two parts at
        once. Whether a part holds any code is not checked. A source without
        tests passes; the run itself fails when pytest collects none.
        """
        markers = []
        for token in tokenize.generate_tokens(io.StringIO(self.source).readline):
            found = _AAA_MARKER.match(token.string) if token.type == tokenize.COMMENT else None
            if found:
                for word in re.findall(_AAA_WORD, found.group(0), re.IGNORECASE):
                    markers.append((token.start[0], word.lower()))
        for test in self._tests():
            inside = [word for line, word in markers if test.lineno <= line <= test.end_lineno]
            if inside != ["arrange", "act", "assert"]:
                if message:
                    raise Exception(message)
                raise AaaMissing(test.name)


def analyze(source):
    """Reads a source string as a `Program`. The validator is handed one already."""
    return Program(source)
''';
