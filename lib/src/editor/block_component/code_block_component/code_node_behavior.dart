import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:node_code_editor/node_code_editor.dart';

KeyEventResult _insertCodeNewline(EditorState state) {
  final selection = state.selection;
  if (selection == null || !selection.isCollapsed) {
    return KeyEventResult.ignored;
  }
  final node = state.getNodeAtPath(selection.start.path);
  if (node == null) return KeyEventResult.ignored;
  final edit = codeEditForInsertion(
    node.delta?.toPlainText() ?? '',
    selection.start.offset,
    '\n',
    node.attributes[CodeBlockKeys.language] as String? ?? '',
  );
  if (edit == null) return KeyEventResult.ignored;
  state.apply(
    state.transaction
      ..insertText(node, edit.offset, edit.text)
      ..afterSelection = Selection.collapsed(
        Position(
          path: node.path,
          offset: edit.caretOffset,
        ),
      ),
  );
  return KeyEventResult.handled;
}

final codeEnterCommand = CommandShortcutEvent(
  key: 'code newline',
  command: 'Enter',
  getDescription: () => 'Insert code newline',
  handler: _insertCodeNewline,
);

final codeShiftEnterCommand = CommandShortcutEvent(
  key: 'code shift newline',
  command: 'shift+enter',
  getDescription: () => 'Insert code newline',
  handler: _insertCodeNewline,
);

final codeIndentCommand = CommandShortcutEvent(
  key: 'code indent',
  command: 'tab',
  getDescription: () => 'Indent code',
  handler: (state) {
    final selection = state.selection;
    if (selection == null || !selection.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final node = state.getNodeAtPath(selection.start.path);
    if (node == null) return KeyEventResult.ignored;
    state.apply(
      state.transaction
        ..insertText(node, selection.start.offset, '  ')
        ..afterSelection = Selection.collapsed(
          Position(
            path: node.path,
            offset: selection.start.offset + 2,
          ),
        ),
    );
    return KeyEventResult.handled;
  },
);

final codeNodeBehavior = NodeBehavior(
  serialize: codeBlockToMarkdown,
  pasteAsPlainText: true,
  isolateOnPaste: true,
  characterShortcuts: [codeCharacterShortcut],
  commandShortcuts: [
    codeExitCommand,
    tabToAutoCompleteCommand,
    codeIndentCommand,
    codeEnterCommand,
    codeShiftEnterCommand,
  ],
  completion: (state, node) => codeCompletionSuffix(
    node.delta?.toPlainText() ?? '',
    node.attributes[CodeBlockKeys.language] as String? ?? '',
  ),
);
