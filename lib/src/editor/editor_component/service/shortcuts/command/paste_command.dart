import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../../service/markdown_parser.dart';

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
      await editorState.pastePlainText(text);
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
      editorState.pastePlainText(text);
    }
  }();

  return KeyEventResult.handled;
};

RegExp _hrefRegex = RegExp(
  r'https?://(?:www\.)?[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}(?:/[^\s]*)?',
);

RegExp _phoneRegex = RegExp(r'^\+?' // Optional '+' at start
    r'(?:[0-9][\s-.]?)+' // Sequence of digits with optional separators
    r'[0-9]$' // Ensure it ends with a digit
    );

extension on EditorState {
  Future<void> pastePlainText(String plainText) async {
    final selectionAttributes = getDeltaAttributesInSelectionStart();
    // TODO remove this deletion after refactoring pasteHtmlIfAvailable below
    final selection = await deleteSelectionIfNeeded();

    if (selection == null) {
      return;
    }

    if (await maybeConvertToUrlOrPhone(plainText)) {
      return;
    }

    final List<Node> nodes;
    if (plainText.length >= 1000) {
      nodes = await compute(
        parseMarkdownToNodesCompute,
        (plainText, selectionAttributes),
      );
    } else {
      nodes =
          parseMarkdownToNodes(plainText, baseAttributes: selectionAttributes);
    }

    if (nodes.isEmpty) {
      return;
    }
    if (nodes.length == 1) {
      await pasteSingleLineNode(nodes.first);
    } else {
      await pasteMultiLineNodes(nodes.toList());
    }
  }

  Future<bool> maybeConvertToUrlOrPhone(String plainText) async {
    final selection = this.selection;
    if (selection == null ||
        !selection.isSingle ||
        selection.isCollapsed ||
        (!_hrefRegex.hasMatch(plainText) && !_phoneRegex.hasMatch(plainText))) {
      return false;
    }

    final node = getNodeAtPath(selection.start.path);
    if (node == null) {
      return false;
    }

    final transaction = this.transaction;
    final isPhone = _phoneRegex.hasMatch(plainText);
    transaction.formatText(node, selection.startIndex, selection.length, {
      AppFlowyRichTextKeys.href: isPhone ? 'tel:$plainText' : plainText,
    });
    await apply(transaction);

    return true;
  }
}
