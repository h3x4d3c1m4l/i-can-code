# Sample: a reading step

One `info` section, and what it may carry.

```metadata
id: sample-info
emoji: "📖"
```

## Reading a step

```metadata
type: info
id: reading
emoji: "👋"
```

An `info` step is prose and nothing else. There is no editor, nothing to run and
nothing to check — leaving it is what completes it.

A fenced block with no role suffix is a **worked example**: it stays in the prose
and is drawn on the editor's own dark card, but the student cannot type in it.

```python
print("Hello, world")
```

### A foldable subheading

Every `###` inside a section's prose becomes a block the student can fold away by
pressing its heading. The prose before the first `###` stays put.

### One that arrives folded {collapsed}

End a heading with `{collapsed}` and its group opens folded — reference material
rather than something to read straight through. The marker is stripped from the
title, and folding is never remembered between visits.
