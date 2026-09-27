import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:node_code_editor/node_code_editor.dart';

/// Uses the editor's existing character shortcut path, so IME composition and
/// text input remain owned by AppFlowyRichText.
final codeCharacterShortcut = CharacterShortcutEvent(
  key: 'code bracket pairing',
  character: '',
  regExp: RegExp(r'[{}\[\]"\n]'),
  handler: (_) async => false,
  handlerWithCharacter: (editorState, character) async {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) return false;
    final node = editorState.getNodeAtPath(selection.start.path);
    if (node == null) return false;
    final edit = codeEditForInsertion(
      node.delta?.toPlainText() ?? '',
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
