# Performance profiles

`MDEditor` is a convenience layer over AppFlowy Editor. Its document model,
selection, keyboard input, scrolling, undo history, and rendering services are
owned per controller/editor pair; package code and a bounded LaTeX render cache
are shared by the process. Formula cache entries are isolated by editor, node,
and source offset because `flutter_math_fork` syntax trees contain mutable
layout state and cannot safely be shared by duplicate expressions.

## Several compact inputs on mobile

Use the default controller and do not autofocus every field:

```dart
final controller = MDEditorController(); // 30 undo groups

MDEditor(
  controller: controller,
  autoFocus: false,
  maxHeight: 160,
);

@override
void dispose() {
  controller.dispose();
  super.dispose();
}
```

A handful of simultaneously mounted editors is a reasonable use case. In a
long `ListView`, create editors only for visible/active rows and dispose or pool
their controllers. Keeping hundreds of controllers alive also keeps hundreds
of documents, undo stacks, notifiers, focus/selection services, and overlays
alive; use plain preview widgets for inactive rows instead.

Avoid `autoFocus: true` on more than one editor. Avoid `multiLine: true` with
`shrinkWrap: true` in dense lists because intrinsic sizing adds an extra layout
pass.

Use one color scheme for the editor and all Markdown preview widgets:

```dart
const colors = MDEditorColorScheme.light(
  primary: Color(0xFF6750A4),
  selection: Color(0x286750A4),
);

MDEditor(controller: controller, colorScheme: colors);
```

## Large document editing

Use the large-document controller, a bounded viewport, and lazy block layout:

```dart
final controller = MDEditorController.largeDocument(
  onInput: saveMarkdown,
);

Expanded(
  child: MDEditor(
    controller: controller,
    shrinkWrap: false,
    useIndexedScrollbar: true,
    minCacheExtent: 800,
    multiLine: true,
  ),
);
```

The large-document profile keeps 200 undo groups and debounces full Markdown
serialization by 150 ms. `shrinkWrap: false` uses block virtualization, so only
visible and cached blocks are mounted. Tune `minCacheExtent` between roughly
one and two viewport heights: a larger value makes scrolling smoother at the
cost of more live widgets.

`useIndexedScrollbar` is enabled by default on `MDEditor`. Its thumb maps the
document percentage to a block index and calls `ItemScrollController.jumpTo`,
instead of assigning a distant raw pixel offset to a variable-height sliver.
Heights of visited blocks are keyed by stable block IDs in a prefix-sum index,
so inserting or deleting earlier blocks does not attach a measurement to the
wrong block. The virtual list keeps the first surviving visible block at its
screen position after structural edits. Thumb updates are coalesced to at most
one jump per frame. Set `useIndexedScrollbar` to `false` to compare against the
platform scrollbar when profiling.

When replacing a large document after construction, await parsing explicitly:

```dart
await controller.setText(markdown);
```

Large clipboard payloads are parsed in an isolate. Before applying the result,
the editor checks that the document revision and selection still match the
paste request; a stale result is discarded. Sibling insertion is batched so a
paste containing thousands of lines emits one document notification rather
than one notification per line. The selected text is kept in place while
parsing runs. Replacing a non-collapsed selection still uses a separate delete
transaction before the insertion transaction.

Parsing clipboard input in fixed pages is not currently the default. It would
make the first page appear earlier, but it also breaks Markdown constructs at
page boundaries, produces multiple document transactions, complicates one-step
undo, and repeatedly changes paths while the user is editing. The safer next
step for extremely large files is an incremental block parser with stable block
IDs and file-backed unloaded blocks, rather than splitting raw Markdown every N
characters.

The editor can support normal note-sized documents, but it is not yet a full
Obsidian replacement. Important remaining limits are:

- multi-line `$$ ... $$` does not span document nodes;
- Markdown decoration is regex-based rather than an incremental syntax tree;
- the complete document tree remains resident in memory;
- exporting Markdown is linear in total document size (callbacks are debounced,
  but not incremental);
- no file-backed paging or unloaded block representation exists;
- very long individual paragraphs are not virtualized internally.

Live Markdown decoration is bounded independently of document block
virtualization. By default a paragraph longer than 64 KiB, one containing
more than 512 recognized Markdown constructs, or one requiring over 2,048
decorated spans remains editable as exact plain source. This prevents dense
generated text from creating thousands of inline widgets in one frame.
Override the character limit when constructing `MDEditor`; passing `null`
disables these safeguards and should only be done after profiling the target
devices.

The decorator checks the paragraph limit before parsing display math. Code
fences with at least two content lines at or below 64 KiB become independent
code nodes; one-line fenced blocks remain Markdown paragraphs. Larger input
skips code fence recognition and remains ordinary editable text. The code
highlighter stops parsing a node beyond 64 KiB. Its rules use the Dart
`highlight` package's language grammars without `flutter_highlight` widgets.

Selection-only rebuilds reuse a 256-entry lexical cache capped at 1 MiB of
source. The cache is safe to share across editors because entries contain only
immutable regexp match results. IME timers, transaction composition, selection
handles, floating cursors, toolbars, delayed scrolling, and overlay-focus state
are editor/widget scoped, so simultaneously mounted editors no longer cancel
or redirect one another's pending work.

For book-sized or generated documents, profile live parsing and paragraph
layout, then add the required incremental rendering/parser and persistence
layers before treating this component as the sole document engine.

See [Large-paragraph parsing and document model evaluation](parser_and_node_evaluation.md)
for the recommended dependency-free path and the `Node` removal assessment.

### Fenced code and display math

Fenced code with at least two content lines at or below 64 KiB becomes an
independent editable node. Display math remains in a text node. Fence detection
is linear, uses an LRU capped at
128 entries and 1 MiB of source, and ordinary paragraphs take a constant-time
prefix fast path. Code nodes bypass the general Markdown regexp scanner.

One very large code node still has a single `RenderParagraph`, so it cannot
benefit from document-level block virtualization. The synthetic debug widget
benchmark on the development host measured about 23 ms for a 64 KiB code block
and 3.6 ms to parse a 256 KiB fenced block. A 20-line display formula took
about 109 ms on its first debug render; TeX parsing/layout, rather than fence
detection, dominates that case. Treat these numbers as directional and profile
in release/profile mode on target devices. Code input over 64 KiB skips fence
promotion and syntax highlighting; avoid continuously rewriting large formulas
on low-end devices.
