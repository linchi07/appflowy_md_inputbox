import 'package:appflowy_editor/appflowy_editor.dart';

/// Behavior supplied by an optional node implementation. The editor dispatches
/// these events only while the selection is inside a node of the matching type.
typedef NodeCompletionProvider = String? Function(EditorState state, Node node);
typedef NodeTextSerializer = String Function(Node node);

/// Return replacement text to paste literally, or null to use Markdown paste.
typedef NodeLiteralPaste = String? Function(
  EditorState state,
  Node node,
  Selection selection,
  String text,
);
typedef NodeExtentEstimator = double? Function(
  EditorState state,
  Node node,
  double availableWidth,
);

class NodeBehavior {
  const NodeBehavior({
    this.characterShortcuts = const [],
    this.commandShortcuts = const [],
    this.completion,
    this.serialize,
    this.pasteAsPlainText = false,
    this.literalPaste,
    this.isolateOnPaste = false,
    this.slashMenuEnabled = true,
    this.estimateExtent,
  });

  final List<CharacterShortcutEvent> characterShortcuts;
  final List<CommandShortcutEvent> commandShortcuts;
  final NodeCompletionProvider? completion;
  final NodeTextSerializer? serialize;

  /// Treat pasted text as literal content while editing this node.
  final bool pasteAsPlainText;

  /// Lets a node keep a paste in its current text transaction when its syntax
  /// is incomplete. The rule may also add delimiters needed by that syntax.
  final NodeLiteralPaste? literalPaste;

  /// Preserve this node as a separate block when Markdown is pasted into text.
  final bool isolateOnPaste;

  /// Whether slash shortcuts may open a block-command menu in this node.
  final bool slashMenuEnabled;

  /// Estimated full block height until its real layout is measured.
  final NodeExtentEstimator? estimateExtent;
}
