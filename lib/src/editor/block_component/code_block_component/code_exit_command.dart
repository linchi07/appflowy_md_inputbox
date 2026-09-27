import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// Ctrl/Cmd+Enter leaves the code editor and creates a normal paragraph.
final codeExitCommand = CommandShortcutEvent(
  key: 'exit code block',
  command: 'ctrl+enter',
  getDescription: () => 'Leave code block',
  handler: (editorState) {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final node = editorState.getNodeAtPath(selection.start.path);
    if (node?.type != CodeBlockKeys.type) return KeyEventResult.ignored;
    final nextPath = node!.path.next;
    editorState.apply(
      editorState.transaction
        ..insertNode(nextPath, paragraphNode())
        ..afterSelection = Selection.collapsed(Position(path: nextPath)),
    );
    return KeyEventResult.handled;
  },
);
