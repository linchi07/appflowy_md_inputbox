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

When replacing a large document after construction, await parsing explicitly:

```dart
await controller.setText(markdown);
```

Large clipboard payloads are parsed in an isolate and then inserted atomically.
Sibling insertion is batched so a paste containing thousands of lines emits one
document notification rather than one notification per line. The selected text
is kept in place until parsing succeeds.

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

For book-sized or generated documents, add an incremental parser and persistence
layer before treating this component as the sole document engine.
