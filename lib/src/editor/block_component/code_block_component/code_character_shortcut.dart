import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:node_code_editor/node_code_editor.dart';

/// Uses the editor's existing character shortcut path, so IME composition and
/// text input remain owned by AppFlowyRichText.
final codeCharacterShortcut = CharacterShortcutEvent(
  key: 'code bracket pairing',
  character: '',
  regExp: RegExp(r'''[{}\[\]()"'`\n]'''),
  handler: (_) async => false,
  handlerWithCharacter: (editorState, character) async {
    final selection = editorState.selection;
    if (selection == null || !selection.isSingle) return false;
    final node = editorState.getNodeAtPath(selection.start.path);
    if (node == null) return false;
    final source = node.delta?.toPlainText() ?? '';
    if (!selection.isCollapsed) {
      final normalized = selection.normalized;
      final pair = codeEditForInsertion(
        '',
        0,
        character,
        node.attributes[CodeBlockKeys.language] as String? ?? '',
      );
      if (pair == null || pair.text.length != 2) return false;
      final selected =
          source.substring(normalized.startIndex, normalized.endIndex);
      await editorState.apply(
        editorState.transaction
          ..deleteText(node, normalized.startIndex, normalized.length)
          ..insertText(
            node,
            normalized.startIndex,
            pair.text[0] + selected + pair.text[1],
          )
          ..afterSelection = Selection(
            start: Position(
              path: node.path,
              offset: normalized.startIndex + 1,
            ),
            end: Position(
              path: node.path,
              offset: normalized.startIndex + 1 + selected.length,
            ),
          ),
      );
      return true;
    }
    final edit = codeEditForInsertion(
      source,
      selection.start.offset,
      character,
      node.attributes[CodeBlockKeys.language] as String? ?? '',
    );
    if (edit == null) return false;
    if (edit.text.isEmpty) {
      editorState.selection = Selection.collapsed(
        Position(
          path: node.path,
          offset: edit.caretOffset,
        ),
      );
    } else {
      await editorState.apply(
        editorState.transaction
          ..deleteText(node, edit.offset, edit.deleteLength)
          ..insertText(node, edit.offset, edit.text)
          ..afterSelection = Selection.collapsed(
            Position(
              path: node.path,
              offset: edit.caretOffset,
            ),
          ),
      );
    }
    return true;
  },
);
