# Introduction

What Python is, and why you would want to learn it.

```metadata
id: introduction
```

## What coding is

```metadata
type: info
id: coding
```

Coding is writing a computer program. You write sequences of instructions that a computer can carry out. The programs for early computers were mostly written in machine language. Machine language is the language a computer 'understands' directly, without any translation step.

These days machine language is hardly used any more. Programming languages have made coding far more accessible. Languages such as C and Python make coding easier, and make the process easier to follow.

## Choosing between programming languages

```metadata
type: info
id: different-languages
```

By now there are a great many programming languages. That raises the question of which one you should start with. You would want one of them to be the _holy grail_: the language that is easy to learn, that lets you build almost anything, and that produces a fast program. Sadly it is not that simple. Languages come with wildly different combinations of traits, some of them handy and others less so.

The next page goes deeper and sorts them in a few different ways. For each way, and for each type within it, you will find a list of popular languages. At the end it explains where Python sits. You may skip that page if you like.

## Sorting programming languages

```metadata
type: info
id: sorting-languages
optional: true
```

We tell programming languages apart on 3 fronts:

- **Paradigm**: which set of familiar patterns the language (mostly) uses.
- **How the code is run**: whether the code is translated into machine language before it runs, and at what moment that happens.
- **How values are treated**: when the language checks values (text, numbers, dates, ...) and how strict it is about them.

For each way of sorting you will find a list of a few popular languages.

You can fold the sections below open and shut yourself.

### Sorted by paradigm {collapsed}

- **Imperative**: The focus is on how a task should be carried out.
  - **Procedural**: Code is broken up into functions and procedures (Basic, C, Go, Pascal, Rust).
  - **Object-oriented (OOP)**: Behaviour and data are combined into objects (C++, C#, Dart, Java, JavaScript, PHP, **Python**, Ruby, Visual Basic).
- **Declarative**: The focus is on what the result of a task should be.
  - **Functional**: Based on mathematical functions, without changeable data (Elixir, F#, Haskell).
  - **Logic**: Based on facts and rules (Prolog).

### Sorted by how the code is run {collapsed}

- **Compiled**: Before it runs, the code is translated in full into machine language. That translating is called _compiling_. The result is a program the computer can run directly: fast, but it has to be compiled separately for each kind of computer (C, C++, Go, Haskell, Pascal, Rust).
- **Interpreted**: The code is translated line by line while it runs, by another program called the _interpreter_. That is slower, but the same code runs anywhere that interpreter is available (Bash, Basic).
- **Hybrid**: The code is first compiled into an intermediate language (_bytecode_), which is then run by a virtual machine. That combines part of the speed of compiling with the flexibility of interpreting (C#, Elixir, F#, Java, PHP, **Python**, Ruby).

### Sorted by how they treat values {collapsed}

A program works with _values_: a piece of text, a number, a date. Languages differ in how much they want to know about a given value. They also differ in how strict they are when something does not add up. Those are **two separate questions** — a language answers each of them on its own.

- **When is a value checked?**
  - **Static**: Up front, while compiling. You have to write more down, but mistakes come to light before the program ever runs (C, C++, Go, Java, Rust).
  - **Dynamic**: Only while running. You write code faster, but you only notice a mistake once that line actually comes up (**Python**, JavaScript, PHP, Ruby).
- **How strictly is a value checked?**
  - **Strong**: the language refuses to guess. Combine values that do not belong together and you get an error (**Python**, Haskell, Java, Ruby).
  - **Weak**: the language quietly adjusts your values so that an answer comes out anyway (C, JavaScript, PHP).

That these really are separate questions shows in C and Python: C wants to know everything up front but is relaxed about what it accepts, while Python wants to know nothing up front and is strict afterwards.

### Where Python sits

Python, then, is an object-oriented language, run in a hybrid way, that treats values dynamically but strictly. In practice that means three things:

- Everything you work with in Python is an object: data with behaviour attached to it. A piece of text knows how to write itself in capitals, and you ask for that with a dot: `name.upper()`. Designing objects of your own comes later in the course; using them starts with your very first line of code.
- Compiling to bytecode happens automatically and you barely notice it: you write your code, you run your program. In theory it makes Python a little slower than languages whose code is compiled all the way to machine language first.
- You never have to state anywhere what kind of value goes where. That saves typing and makes Python easier to start with. It can also be a trap, because a mistake in it may only show up much later.
