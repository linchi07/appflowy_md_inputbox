import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

// Built-in text blocks; optional nodes supply a NodeBehavior.completion.
final autoCompletableBlockTypes = {
  ParagraphBlockKeys.type,
  QuoteBlockKeys.type,
  HeadingBlockKeys.type,
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
  final completion = editorState.behaviorFor(node)?.completion;

  // Now, this command only support auto complete the text if the cursor is at the end of the block
  if (node == null ||
      (context == null && completion == null) ||
      (!autoCompletableBlockTypes.contains(node.type) && completion == null) ||
      delta == null ||
      (completion == null && selection.endIndex != delta.length)) {
    return KeyEventResult.ignored;
  }

  // Support async auto complete text provider in the future
  final autoCompleteText = completion != null
      ? completion(editorState, node)
      : context == null
          ? null
          : editorState.autoCompleteTextProvider?.call(context, node, null);
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
