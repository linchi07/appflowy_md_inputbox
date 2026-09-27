# node_code_editor

A small Flutter package with code highlighting, JSON bracket pairing, YAML
indentation and literal completion rules. It has no dependency on
`flutter_code_editor`, `highlight` or `flutter_highlight`.

The host editor owns the text model, IME, selection and undo. Call
`codeEditForInsertion` from the host's character and Enter shortcuts, use
`CodeHighlighter.spanForSegment` when rendering a node, and pass
`codeCompletionSuffix` to the host's ghost text and Tab completion hooks.

The AppFlowy integration is in
`lib/src/editor/block_component/code_block_component/`. Its `codeNodeBehavior`
registers node-local character and command shortcuts, completion, Markdown
serialization, and paste boundaries through the editor's `NodeBehavior`
contract. `codeFencePromotionRule` uses the generic `TextNodePromotionRule` to
turn a typed fenced paragraph into a code node after the text transaction.
`MDEditor` supplies the builder, behavior, and rule; other hosts can choose
their own integration while reusing this package's editing and highlighting
logic.
