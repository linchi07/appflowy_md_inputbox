import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// cut.
///
/// - support
///   - desktop
///   - web
///
final CommandShortcutEvent cutCommand = CommandShortcutEvent(
  key: 'cut the selected content',
  getDescription: () => AppFlowyEditorL10n.current.cmdCutSelection,
  command: 'ctrl+x',
  macOSCommand: 'cmd+x',
  handler: _cutCommandHandler,
);

CommandShortcutEventHandler _cutCommandHandler = (editorState) {
  final rangeHandler = editorState.activeRangeSelectionHandler;
  if (rangeHandler != null) {
    final text = rangeHandler.getSelectedText();
    if (text != null && text.isNotEmpty) {
      () async {
        await AppFlowyClipboard.setData(text: text);
        await rangeHandler.clearSelectedContent();
      }();

      return KeyEventResult.handled;
    }
  }

  final selection = editorState.selection?.normalized;
  if (selection == null || selection.isCollapsed) {
    return KeyEventResult.ignored;
  }

  // plain text.
  handleCut(editorState);

  return KeyEventResult.handled;
};
