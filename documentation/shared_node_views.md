# Shared documents and live node views

`SharedEditorDocument` is the local content authority. Each view has its own
`EditorState`, node objects, render keys, selection, focus, scroll and input
services. Applications do not implement or register a binding themselves.

```dart
final shared = SharedEditorDocument(document: existingDocument);
final main = shared.createEditorState();
final nodeId = main.document.root.children.first.id;
final enlarged = main.createNodeView(nodeId);

final mainController = MDEditorController.fromEditorState(main);
final enlargedController = MDEditorController.fromEditorState(enlarged);
```

Use a separate `MDEditor` or `AppFlowyEditor` for each state. For large documents,
give the editor a bounded viewport and use `shrinkWrap: false`.

A reference displays one node and its descendants. A table therefore includes
its cells. Editing a referenced paragraph changes the paragraph in every view.
Enter, multiline paste, append and `setText` keep that reference inside the same
text node; the reference cannot insert hidden sibling blocks. A transformation
to one widget node preserves the identity; a transformation requiring multiple
sibling blocks stays as source text inside a reference. Such transformations
can still be performed in the full-document view.

Moving a node preserves references. Deleting it empties its reference views;
check `isReferenceMissing` to show a deleted-content UI. Undo can restore the
same identity. Closing a view detaches it without deleting content or closing
other views. Controllers created with `fromEditorState` own and dispose that
one state. Dispose the shared document when the document session closes; that
disposes any remaining views too.

## Persistent identity

Node IDs are UUIDv7 values, stored in node JSON and restored on load. Legacy
JSON without IDs receives IDs on import; save that resulting structured state
once. Each view preserves content IDs while creating new runtime/render objects.
`cloneForView` preserves IDs. `copyWith` and `deepCopy` duplicate content with
new IDs, recursively. IDs do not determine document order.

Markdown alone does not preserve these identities. Use `shared.toJson()` and
`SharedEditorDocument.fromJson()` for the structured baseline; Markdown remains
an import/export format. Build imported content once, then create its views.
Do not independently parse the same Markdown for every window.

## Transactions and local synchronization

Use the existing `state.transaction` and `state.apply()` APIs. The internal host
resolves paths against that view, validates an atomic commit, and emits immutable
operations addressed by node ID. Ordinary text transactions now retain their
incremental Delta instead of converting every edit into a full text replacement.
Typing updates only views containing the affected node; structural commits
reconcile the subtree while retaining unchanged live node/render instances.

`shared.changes` emits `SharedDocumentChange` with document ID, origin, base
revision and operations. It contains no selection or focus state. Its JSON is
transport-neutral, but **it is not a CRDT encoding**. `applyChange` accepts only
an exactly matching document and base revision. An out-of-order, duplicate or
concurrent update is rejected rather than applied to the wrong content. Remote
devices and offline edits require a later CRDT/transport implementation.

Transactions made through `state.transaction` capture their shared revision.
Rebuild a transaction if another commit happens before submission. Mutating a
node or document directly bypasses the host and is unsupported for shared views.

Undo is view-local and exposed through `state.undoManager`, including `canUndo`
and `canRedo`. Text history follows later edits from other views. Structural
history is conservatively discarded when its target disappears, its insertion
anchor disappears, or undo would delete a subtree another view has edited.
This is local ordered history, not CRDT selective undo. Histories are not saved
in the structured baseline. `setText` clears the originating view's history.

## Later Yrs integration

The commit boundary is inside Flamingo, behind `EditorTransactionHost`. A Yrs
backend can consume ID-addressed edits and publish the resulting projections
without changing the application's view-creation API. UUIDv7 provides entity
identity; Yrs must additionally provide text merging, structural conflict
policy, relative positions, selective undo and replica update encoding. Binary
transport, peer identity and persistence recovery belong to that later phase.

There is no Yrs, Rust build hook or native CRDT dependency in this stage.
