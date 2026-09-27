import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:node_code_editor/node_code_editor.dart';

// Add your custom block keys if it supports auto complete
final autoCompletableBlockTypes = {
  ParagraphBlockKeys.type,
  QuoteBlockKeys.type,
  HeadingBlockKeys.type,
  CodeBlockKeys.type,
};

/// Auto complete the current block
///
/// - support
///   - desktop
///   - web
///
final CommandShortcutEvent tabToAutoCompleteCommand = CommandShortcutEvent(
  key: 'tab to auto complete',
  getDescription: () => 'Tab to auto complete',
  command: 'tab',
  handler: _tabToAutoCompleteCommandHandler,
);

CommandShortcutEventHandler _tabToAutoCompleteCommandHandler = (editorState) {
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) {
    return KeyEventResult.ignored;
  }

  final node = editorState.getNodeAtPath(selection.end.path);
  final context = node?.context ?? editorState.document.root.context;
  final delta = node?.delta;

  // Now, this command only support auto complete the text if the cursor is at the end of the block
  if (node == null ||
      (context == null && node.type != CodeBlockKeys.type) ||
      !autoCompletableBlockTypes.contains(node.type) ||
      delta == null ||
      selection.endIndex != delta.length) {
    return KeyEventResult.ignored;
  }

  // Support async auto complete text provider in the future
  final autoCompleteText = node.type == CodeBlockKeys.type
      ? codeCompletionSuffix(
          node.delta?.toPlainText() ?? '',
          node.attributes[CodeBlockKeys.language] as String? ?? '',
        )
      : editorState.autoCompleteTextProvider?.call(context!, node, null);
  if (autoCompleteText == null || autoCompleteText.isEmpty) {
    return KeyEventResult.ignored;
  }

  final transaction = editorState.transaction
    ..insertText(
      node,
      selection.endIndex,
      autoCompleteText,
    )
    ..afterSelection = Selection.collapsed(
      Position(
        path: node.path,
        offset: selection.endIndex + autoCompleteText.length,
      ),
    );
  editorState.apply(transaction);

  return KeyEventResult.handled;
};
