import 'package:appflowy_editor/appflowy_editor.dart';

/// A structural replacement proposed after a text transaction. Renderers only
/// display nodes and never write the document.
class TextNodePromotion {
  const TextNodePromotion({
    required this.nodes,
    required this.caretNodeIndex,
    required this.caretOffset,
    this.caretNodeIndexForOffset,
  });

  final List<Node> nodes;
  final int caretNodeIndex;
  final int Function(int oldOffset) caretOffset;

  /// Use when one source paragraph promotes into multiple output nodes.
  final int Function(int oldOffset)? caretNodeIndexForOffset;
}

typedef TextNodePromoter = TextNodePromotion? Function(Node node);

/// Reusable transaction rule for paragraph -> widget-node transformations.
/// It only examines the node touched by the transaction, so a long document
/// does not get rescanned on each keystroke.
class TextNodePromotionRule extends DocumentRule {
  const TextNodePromotionRule({
    required this.sourceType,
    required this.promote,
  });

  final String sourceType;
  final TextNodePromoter promote;

  (Node, TextNodePromotion, Selection)? _match(
    EditorState state,
    EditorTransactionValue value,
  ) {
    if (value.$1 != TransactionTime.after) return null;
    final selection = value.$2.afterSelection ?? state.selection;
    if (selection == null || !selection.isCollapsed || !selection.isSingle) {
      return null;
    }
    final path = selection.start.path;
    final touched = value.$2.operations.any((operation) {
      if (operation is! UpdateTextOperation &&
          operation is! UpdateOperation &&
          operation is! InsertOperation) {
        return false;
      }
      return operation.path.equals(path);
    });
    if (!touched) return null;
    final node = state.getNodeAtPath(path);
    if (node?.type != sourceType) return null;
    final result = promote(node!);
    if (result == null ||
        result.nodes.isEmpty ||
        result.caretNodeIndex < 0 ||
        result.caretNodeIndex >= result.nodes.length) {
      return null;
    }
    return (node, result, selection);
  }

  @override
  bool shouldApply({
    required EditorState editorState,
    required EditorTransactionValue value,
  }) =>
      _match(editorState, value) != null;

  @override
  Future<void> apply({
    required EditorState editorState,
    required EditorTransactionValue value,
  }) async {
    final match = _match(editorState, value);
    if (match == null) return;
    final (node, promotion, selection) = match;
    final path = node.path;
    final caretNodeIndex =
        promotion.caretNodeIndexForOffset?.call(selection.start.offset) ??
            promotion.caretNodeIndex;
    if (caretNodeIndex < 0 || caretNodeIndex >= promotion.nodes.length) return;
    await editorState.apply(
      editorState.transaction
        ..insertNodes(path, promotion.nodes)
        ..deleteNode(node)
        ..afterSelection = Selection.collapsed(
          Position(
            path: [
              ...path.take(path.length - 1),
              path.last + caretNodeIndex,
            ],
            offset: promotion.caretOffset(selection.start.offset),
          ),
        ),
    );
  }
}
