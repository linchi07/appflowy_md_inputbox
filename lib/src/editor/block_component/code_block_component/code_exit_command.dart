import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

bool insertParagraphAfterCode(EditorState editorState, Node node) {
  if (!editorState.editable ||
      node.type != CodeBlockKeys.type ||
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

/// At the end of the final code node, Down creates a normal paragraph.
final codeArrowDownExitCommand = CommandShortcutEvent(
  key: 'leave final code block with arrow down',
  command: 'arrow down',
  getDescription: () => 'Continue writing after code',
  handler: (editorState) {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final node = editorState.getNodeAtPath(selection.start.path);
    if (node == null ||
        editorState.getNodeAtPath(node.path.next) != null ||
        selection.start.offset < (node.delta?.length ?? 0)) {
      return KeyEventResult.ignored;
    }
    return insertParagraphAfterCode(editorState, node)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  },
);
