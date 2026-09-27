# node_code_editor

A Flutter package with 47 curated language grammars, bracket pairing,
indentation and keyword completion. The syntax parser and grammars are vendored
from `highlight` 0.7.0 with the upstream license notices; see
[`lib/src/syntax_highlight/`](lib/src/syntax_highlight/README.md). The package
does not depend on `highlight`, `flutter_code_editor` or `flutter_highlight`.

The host editor owns the text model, IME, selection and undo. Call
`codeEditForInsertion` from the host's character and Enter shortcuts, use
`CodeHighlighter.spanForSegment` when rendering a node, and pass
`codeCompletionSuffix` to the host's ghost text and Tab completion hooks.
Completion prefers grammar keywords, then recently used identifiers before the
caret in the same code block. Identifiers inside comments and strings are
ignored. Suggestions appear at the end of a code line; Tab accepts the visible
suffix. When no suggestion is visible, Tab indents and Shift+Tab outdents.
Common brackets and quotes pair automatically, selected text can be
surrounded, and Backspace removes an empty pair together. Newlines inherit
indentation and indent after opening brackets; Python and YAML also indent
after a colon.

The AppFlowy integration is in
`lib/src/editor/block_component/code_block_component/`. Its `codeNodeBehavior`
registers node-local character and command shortcuts, completion, Markdown
serialization, and paste boundaries through the editor's `NodeBehavior`
contract. `codeFencePromotionRule` uses the generic `TextNodePromotionRule` to
turn a typed fenced paragraph into a code node after the text transaction.
`MDEditor` supplies the builder, behavior, and rule; other hosts can choose
their own integration while reusing this package's editing and highlighting
logic. A fenced block with only one content line remains a Markdown paragraph;
two or more content lines become a code node. The code header has a searchable
language picker and a small icon for copying the code without its fences. The
host disables block slash commands inside code. At the end of the last code
node, Down or Ctrl/Cmd+Enter creates a normal paragraph; a visible button does
the same. The code node provides an offscreen height estimate to the host's
scrollbar, which is replaced by the measured height when the node is visible.
