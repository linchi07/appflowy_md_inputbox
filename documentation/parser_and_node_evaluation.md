# Large-paragraph parsing and document model evaluation

## Decision

- Do not port CodeMirror 6 or Lezer into this Flutter editor.
- Do not remove `Node` from the current engine.
- Optimize the existing paragraph path in small, measurable steps: cache
  unchanged lexical results, add a guarded plain-text fallback for pathological
  paragraphs, and only then consider a tiny incremental tokenizer.

This keeps the editor dependency-free and avoids building a second document
model beside the one already used by selection, transactions, undo, rendering,
tables, and scrolling.

This path is now implemented: lexical results use a bounded LRU cache,
paragraphs above 64 KiB render as exact plain source, and paragraphs with more
than 512 Markdown matches take the same fallback. Passing `null` as
`maxMarkdownDecorationCharacters` disables both safeguards for diagnostics or
specialized clients.

## What is slow today

There are three separate paths that should not be conflated:

1. Import and paste parsing in `markdown_parser.dart` splits source by newline.
   Inputs of at least 1,000 characters already run in an isolate.
2. Live Markdown decoration in `markdown_decorator.dart` is regexp-based.
   Unchanged text now reuses bounded lexical results, so caret and handle
   movement do not scan the same source again.
3. `AppFlowyRichText` lays out one complete `RenderParagraph`. Even a free
   incremental parser cannot make Flutter lay out only part of one enormous
   wrapped paragraph.

The third item is important: CodeMirror's large-document behavior combines
incremental parsing with viewport rendering. This project already virtualizes
document blocks when `shrinkWrap` is false, but one huge paragraph is still one
huge render object.

## What is worth borrowing from CodeMirror 6

Borrow the principles, not the implementation:

- preserve parse results and pass exact edit ranges forward;
- reuse unaffected ranges;
- allow parsing to stop after a small frame budget;
- decorate visible content first;
- accept that an opener edit can invalidate the remaining suffix.

Lezer realizes these principles with generated LR parse tables, compact syntax
trees, reusable tree fragments, and a background parse scheduler. Recreating
that machinery for the current small Markdown preview grammar would add more
complexity than it removes.

## Minimal implementation path

1. **Implemented:** cache lexical matches for unchanged paragraph text with a
   256-entry/1-MiB LRU budget.
2. **Implemented:** disable rich preview above 64 KiB or 512 matches while
   editing, while preserving exact source text and offsets.
3. **Implemented:** add the repeatable
   `benchmark/markdown_long_paragraph_benchmark.dart` harness. A debug host run
   reduced the representative cases from 10.7 s for one rich 64-KiB paragraph
   and 22.7 s for two, to about 105 ms and 127 ms after the density guard. A
   100-KiB character-guarded paragraph took about 109 ms, versus 28.0 s when
   rich preview was forcibly enabled. These are directional debug timings;
   release p50/p95 still belongs on a mid-range Android device.
4. If later profiling attributes meaningful frame time to scanning, replace the
   combined regexp with a single-pass tokenizer. Store checkpoints every
   256-512 UTF-16 code units and restart at the checkpoint preceding the
   `UpdateTextOperation` edit range. Stop when tokenizer state and unchanged
   tokens converge with the old result.
5. Current evidence says span/widget construction and paragraph layout
   dominate. Supporting a multi-megabyte paragraph with rich preview therefore
   requires internal visual chunking or line virtualization, which is a
   separate rendering project.

The checkpoint tokenizer is intentionally not being added now: with cached
scans and bounded rich decoration, it would add state invalidation machinery
without addressing the measured dominant cost.

## Multiple editors

Several process-global mutable values also made simultaneous editors interfere
with one another. Transactions, IME debounce timers, floating-cursor state,
mobile handle keys, toolbar debounce keys, pending scroll timers, and overlay
focus tracking are now owned by the relevant transaction/editor/widget
instance. The remaining shared Markdown cache is pure, read-only after entry
creation, and bounded by source size and entry count.

## Why `Node` should stay

`Node` is not currently a passive AppFlowy compatibility wrapper. It is the
identity and hierarchy used by:

- `Path`-based selections and hit testing;
- text and structural transaction operations;
- undo/redo inversion;
- lazy block rendering and height/index tracking;
- nested lists, quotes, dividers, and tables;
- per-block render anchors (`GlobalKey` and `LayerLink`).

The current source has `Node` references across roughly 70 files, with about
350 occurrences. Removing it while retaining behavior would be an input-engine
rewrite, not cleanup, and would temporarily require a replacement model with
the same responsibilities.

There is still safe cleanup available around it:

- remove the deprecated `TextNode` subtype after confirming external API
  compatibility;
- replace untyped `extraInfos` and unused external values with explicit,
  narrowly scoped state;
- eventually move render-only anchors out of the document object if profiling
  shows that doing so matters.

If the product is deliberately reduced to a flat Markdown textbox with no
tables, nesting, block transforms, or structural clipboard behavior, a new flat
engine may be smaller. That should be designed as a clean replacement and
benchmarked side by side, rather than produced by deleting `Node` piecemeal.

## References

- [Lezer system guide](https://lezer.codemirror.net/docs/guide/)
- [CodeMirror system guide](https://codemirror.net/docs/guide/)
- [CodeMirror reference manual](https://codemirror.net/docs/ref/)
