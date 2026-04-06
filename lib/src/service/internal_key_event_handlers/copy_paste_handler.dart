import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/widgets.dart';

int _textLengthOfNode(Node node) => node.delta?.length ?? 0;


void handlePastePlainText(EditorState editorState, String plainText) {
  final selection = editorState.selection?.normalized;
  if (selection == null) {
    return;
  }

  // Simplified: treat entire text as lines and insert them.
  final lines = plainText.split('\n');
  final nodes = lines.map((line) => paragraphNode(text: line)).toList();
  if (nodes.isEmpty) {
    return;
  }

  if (nodes.length == 1) {
    _pasteSingleLineInText(
      editorState,
      selection.startIndex,
      nodes.first,
    );
  } else {
    _pasteMultipleLinesInText(
      editorState,
      selection.start.offset,
      nodes,
    );
  }
}


Selection _computeSelectionAfterPasteMultipleNodes(
  EditorState editorState,
  List<Node> nodes,
) {
  final currentSelection = editorState.selection!;
  final currentCursor = currentSelection.start;
  final currentPath = [...currentCursor.path];
  currentPath[currentPath.length - 1] += nodes.length;
  final int lenOfLastNode = _textLengthOfNode(nodes.last);

  return Selection.collapsed(
    Position(path: currentPath, offset: lenOfLastNode),
  );
}

void handleCopy(EditorState editorState) async {
  final selection = editorState.selection?.normalized;
  if (selection == null) {
    return;
  }
  String text;

  if (selection.isCollapsed) {
    final node = editorState.getNodeAtPath(selection.end.path);
    if (node == null) {
      return;
    }
    text = node.delta?.toPlainText() ?? '';
  } else {
    text = editorState.getTextInSelection(selection).join('\n');
  }

  return AppFlowyClipboard.setData(
    text: text,
    html: null,
  );
}

void _pasteSingleLineInText(
  EditorState editorState,
  int offset,
  Node insertedNode,
) {
  final transaction = editorState.transaction;
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) {
    return;
  }
  final node = editorState.getNodeAtPath(selection.end.path);
  final delta = node?.delta;
  if (node == null || delta == null) {
    return;
  }
  final insertedDelta = insertedNode.delta;
  if (delta.isEmpty || insertedDelta == null) {
    transaction.insertNode(selection.end.path.next, insertedNode);
    transaction.deleteNode(node);
    final length = insertedNode.delta?.length ?? 0;
    transaction.afterSelection =
        Selection.collapsed(Position(path: selection.end.path, offset: length));
    editorState.apply(transaction);
  } else {
    transaction.insertTextDelta(
      node,
      offset,
      insertedDelta,
    );
    editorState.apply(transaction);
  }
}

void _pasteMultipleLinesInText(
  EditorState editorState,
  int offset,
  List<Node> nodes,
) {
  final transaction = editorState.transaction;
  final selection = editorState.selection;
  final afterSelection =
      _computeSelectionAfterPasteMultipleNodes(editorState, nodes);

  final selectionNode = editorState.getNodesInSelection(selection!);
  if (selectionNode.length == 1) {
    final node = selectionNode.first;
    if (node.delta == null) {
      transaction.afterSelection = afterSelection;
      transaction.insertNodes(afterSelection.end.path, nodes);
      editorState.apply(transaction);
    }

    final (firstNode, afterNode) = sliceNode(node, offset);
    if (nodes.length == 1 && nodes.first.type == node.type) {
      transaction.deleteNode(node);
      final List<dynamic> newDelta = firstNode.delta != null
          ? firstNode.delta!.toJson()
          : Delta().toJson();
      final List<Node> children = [];
      children.addAll(firstNode.children);

      if (nodes.first.delta != null &&
          nodes.first.delta != null &&
          nodes.first.delta!.isNotEmpty) {
        newDelta.addAll(nodes.first.delta!.toJson());
        children.addAll(nodes.first.children);
      }
      if (afterNode != null &&
          afterNode.delta != null &&
          afterNode.delta!.isNotEmpty) {
        newDelta.addAll(afterNode.delta!.toJson());
        children.addAll(afterNode.children);
      }

      transaction.insertNodes(afterSelection.end.path, [
        Node(
          type: firstNode.type,
          children: children,
          attributes: firstNode.attributes
            ..remove(ParagraphBlockKeys.delta)
            ..addAll(
              {ParagraphBlockKeys.delta: Delta.fromJson(newDelta).toJson()},
            ),
        ),
      ]);
      transaction.afterSelection = afterSelection;
      editorState.apply(transaction);

      return;
    }
    final path = node.path;
    transaction.deleteNode(node);
    transaction.insertNodes([
      path.first + 1,
    ], [
      firstNode,
      ...nodes,
      if (afterNode != null &&
          afterNode.delta != null &&
          afterNode.delta!.isNotEmpty)
        afterNode,
    ]);
    transaction.afterSelection = afterSelection;
    editorState.apply(transaction);

    return;
  }

  transaction.afterSelection = afterSelection;
  transaction.insertNodes(afterSelection.end.path, nodes);
  editorState.apply(transaction);
}

void handlePaste(EditorState editorState) async {
  final data = await AppFlowyClipboard.getData();

  if (editorState.selection?.isCollapsed ?? false) {
    return _pasteRichClipboard(editorState, data);
  }

  deleteSelectedContent(editorState);

  WidgetsBinding.instance.addPostFrameCallback((_) {
    _pasteRichClipboard(editorState, data);
  });
}

(Node previousDelta, Node? nextDelta) sliceNode(
  Node node,
  int selectionIndex,
) {
  final delta = node.delta;
  if (delta == null) {
    return (node, null); // // Node doesn't have a delta
  }

  final previousDelta = delta.slice(0, selectionIndex);

  final nextDelta = delta.slice(selectionIndex, delta.length);

  return (
    Node(
      id: node.id,
      parent: node.parent,
      children: node.children,
      type: node.type,
      attributes: node.attributes
        ..remove(ParagraphBlockKeys.delta)
        ..addAll({ParagraphBlockKeys.delta: previousDelta.toJson()}),
    ),
    Node(
      type: node.type,
      attributes: node.attributes
        ..remove(ParagraphBlockKeys.delta)
        ..addAll({ParagraphBlockKeys.delta: nextDelta.toJson()}),
    )
  );
}

void _pasteRichClipboard(EditorState editorState, AppFlowyClipboardData data) {
  if (data.text != null) {
    handlePastePlainText(editorState, data.text!);

    return;
  }
}

bool _isNodeInsideTable(Node node) {
  Node? current = node;
  while (current != null) {
    if (current.type == 'table') {
      return true;
    }
    current = current.parent;
  }

  return false;
}

/// 2. delete selected content
void handleCut(EditorState editorState) {
  handleCopy(editorState);
  deleteSelectedContent(editorState);
}

Future<void> deleteSelectedContent(EditorState editorState) async {
  final selection = editorState.selection?.normalized;
  if (selection == null) {
    return;
  }
  final transaction = editorState.transaction;
  if (selection.isCollapsed) {
    // if the selection is collapsed, delete the current node
    final node = editorState.getNodeAtPath(selection.end.path);
    if (node == null || _isNodeInsideTable(node)) {
      return;
    }
    transaction.deleteNode(node);
    final nextNode = node.next;
    if (nextNode != null && nextNode.delta != null) {
      transaction.afterSelection = Selection.collapsed(
        Position(path: node.path, offset: nextNode.delta?.length ?? 0),
      );
    }
  } else {
    // if the selection is not collapsed, delete the selection
    await editorState.deleteSelection(selection);
    transaction.afterSelection = Selection.collapsed(selection.start);
  }

  await editorState.apply(transaction);
}
