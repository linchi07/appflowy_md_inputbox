import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

final List<CommandShortcutEvent> pasteCommands = [
  pasteCommand,
  pasteTextWithoutFormattingCommand,
];

/// Paste.
///
/// - support
///   - desktop
///   - web
///
final CommandShortcutEvent pasteCommand = CommandShortcutEvent(
  key: 'paste the content',
  getDescription: () => AppFlowyEditorL10n.current.cmdPasteContent,
  command: 'ctrl+v',
  macOSCommand: 'cmd+v',
  handler: _pasteCommandHandler,
);

final CommandShortcutEvent pasteTextWithoutFormattingCommand =
    CommandShortcutEvent(
  key: 'paste the content as plain text',
  getDescription: () => AppFlowyEditorL10n.current.cmdPasteContentAsPlainText,
  command: 'ctrl+shift+v',
  macOSCommand: 'cmd+shift+v',
  handler: _pasteTextWithoutFormattingCommandHandler,
);

CommandShortcutEventHandler _pasteTextWithoutFormattingCommandHandler =
    (editorState) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }

  () async {
    final data = await AppFlowyClipboard.getData();
    final text = data.text;
    if (text != null && text.isNotEmpty) {
      await editorState.insertMarkdown(text);
    }
  }();

  return KeyEventResult.handled;
};

CommandShortcutEventHandler _pasteCommandHandler = (editorState) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }

  () async {
    // Trigger onPaste callback if available
    final onPaste = editorState.onPaste;
    if (onPaste != null) {
      final handled = await onPaste();
      if (handled) {
        return;
      }
    }
    final data = await AppFlowyClipboard.getData();
    final text = data.text;
    if (text != null && text.isNotEmpty) {
      await editorState.insertMarkdown(text);
    }
  }();

  return KeyEventResult.handled;
};
