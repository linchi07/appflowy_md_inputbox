import 'package:appflowy_editor/appflowy_editor.dart';

/// Behavior supplied by an optional node implementation. The editor dispatches
/// these events only while the selection is inside a node of the matching type.
typedef NodeCompletionProvider = String? Function(EditorState state, Node node);
typedef NodeTextSerializer = String Function(Node node);

class NodeBehavior {
  const NodeBehavior({
    this.characterShortcuts = const [],
    this.commandShortcuts = const [],
    this.completion,
    this.serialize,
    this.pasteAsPlainText = false,
    this.isolateOnPaste = false,
  });

  final List<CharacterShortcutEvent> characterShortcuts;
  final List<CommandShortcutEvent> commandShortcuts;
  final NodeCompletionProvider? completion;
  final NodeTextSerializer? serialize;

  /// Treat pasted text as literal content while editing this node.
  final bool pasteAsPlainText;

  /// Preserve this node as a separate block when Markdown is pasted into text.
  final bool isolateOnPaste;
}
