import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// Copy.
///
/// - support
///   - desktop
///   - web
///
final CommandShortcutEvent copyCommand = CommandShortcutEvent(
  key: 'copy the selected content',
  getDescription: () => AppFlowyEditorL10n.current.cmdCopySelection,
  command: 'ctrl+c',
  macOSCommand: 'cmd+c',
  handler: _copyCommandHandler,
);

CommandShortcutEventHandler _copyCommandHandler = (editorState) {
  final rangeHandler = editorState.activeRangeSelectionHandler;
  if (rangeHandler != null) {
    final text = rangeHandler.getSelectedText();
    if (text != null && text.isNotEmpty) {
      () async {
        await AppFlowyClipboard.setData(
          text: text,
        );
      }();

      return KeyEventResult.handled;
    }
  }

  final selection = editorState.selection?.normalized;
  if (selection == null || selection.isCollapsed) {
    return KeyEventResult.ignored;
  }

  final text = editorState.getTextForCopy(selection);

  () async {
    await AppFlowyClipboard.setData(
      text: text,
    );
  }();

  return KeyEventResult.handled;
};
