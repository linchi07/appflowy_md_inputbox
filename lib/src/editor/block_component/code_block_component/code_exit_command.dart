import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

bool insertParagraphAfterCode(EditorState editorState, Node node) {
  if (!editorState.editable ||
      node.type != CodeBlockKeys.type ||
      (editorState.isNodeReference && editorState.referenceNodeId == node.id) ||
      editorState.getNodeAtPath(node.path) != node) {
    return false;
  }
  final nextPath = node.path.next;
  editorState.apply(
    editorState.transaction
      ..insertNode(nextPath, paragraphNode())
      ..afterSelection = Selection.collapsed(Position(path: nextPath)),
  );
  return true;
}

/// Ctrl/Cmd+Enter leaves the code editor and creates a normal paragraph.
final codeExitCommand = CommandShortcutEvent(
  key: 'exit code block',
  command: 'ctrl+enter',
  macOSCommand: 'ctrl+enter,cmd+enter',
  getDescription: () => 'Leave code block',
  handler: (editorState) {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final node = editorState.getNodeAtPath(selection.start.path);
    if (node == null) return KeyEventResult.ignored;
    return insertParagraphAfterCode(editorState, node)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  },
);
