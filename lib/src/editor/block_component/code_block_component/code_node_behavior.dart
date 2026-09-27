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
      ..deleteText(node, edit.offset, edit.deleteLength)
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
    final edit = codeEditForTab(
      node.delta?.toPlainText() ?? '',
      selection.start.offset,
      node.attributes[CodeBlockKeys.language] as String? ?? '',
    );
    state.apply(
      state.transaction
        ..insertText(node, edit.offset, edit.text)
        ..afterSelection = Selection.collapsed(
          Position(path: node.path, offset: edit.caretOffset),
        ),
    );
    return KeyEventResult.handled;
  },
);

final codeOutdentCommand = CommandShortcutEvent(
  key: 'code outdent',
  command: 'shift+tab',
  getDescription: () => 'Outdent code',
  handler: (state) {
    final selection = state.selection;
    if (selection == null || !selection.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final node = state.getNodeAtPath(selection.start.path);
    if (node == null) return KeyEventResult.ignored;
    final edit = codeEditForTab(
      node.delta?.toPlainText() ?? '',
      selection.start.offset,
      node.attributes[CodeBlockKeys.language] as String? ?? '',
      outdent: true,
    );
    state.apply(
      state.transaction
        ..deleteText(node, edit.offset, edit.deleteLength)
        ..afterSelection = Selection.collapsed(
          Position(path: node.path, offset: edit.caretOffset),
        ),
    );
    return KeyEventResult.handled;
  },
);

final codePairBackspaceCommand = CommandShortcutEvent(
  key: 'code pair backspace',
  command: 'backspace',
  getDescription: () => 'Delete empty code pair',
  handler: (state) {
    final selection = state.selection;
    if (selection == null || !selection.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final node = state.getNodeAtPath(selection.start.path);
    final source = node?.delta?.toPlainText();
    final offset = selection.start.offset;
    if (node == null ||
        source == null ||
        offset <= 0 ||
        offset >= source.length) {
      return KeyEventResult.ignored;
    }
    if (const {
          '{': '}',
          '[': ']',
          '(': ')',
          '"': '"',
          "'": "'",
          '`': '`',
        }[source[offset - 1]] !=
        source[offset]) {
      return KeyEventResult.ignored;
    }
    state.apply(
      state.transaction
        ..deleteText(node, offset - 1, 2)
        ..afterSelection = Selection.collapsed(
          Position(path: node.path, offset: offset - 1),
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
    codeOutdentCommand,
    codePairBackspaceCommand,
    codeEnterCommand,
    codeShiftEnterCommand,
  ],
  completion: (state, node) {
    final selection = state.selection;
    final source = node.delta?.toPlainText() ?? '';
    if (selection == null ||
        !selection.isCollapsed ||
        !selection.start.path.equals(node.path)) {
      return null;
    }
    final offset = selection.start.offset;
    if (offset < 0 ||
        offset > source.length ||
        (offset < source.length && source[offset] != '\n')) {
      return null;
    }
    return codeCompletionSuffix(
      source.substring(0, offset),
      node.attributes[CodeBlockKeys.language] as String? ?? '',
    );
  },
);
