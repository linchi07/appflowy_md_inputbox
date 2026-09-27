import 'package:appflowy_editor/appflowy_editor.dart';

Future<bool> executeCharacterShortcutEvent(
  EditorState editorState,
  String? character,
  List<CharacterShortcutEvent> characterShortcutEvents,
) async {
  // if the character is a space + enter, we should execute the enter event
  if (character == ' \n') {
    character = '\n';
  }

  if (character?.length != 1) {
    return false;
  }

  final selection = editorState.selection;
  final node = selection == null || !selection.isSingle
      ? null
      : editorState.getNodeAtPath(selection.start.path);
  final nodeEvents = editorState.behaviorFor(node)?.characterShortcuts ??
      const <CharacterShortcutEvent>[];
  for (final shortcutEvent in [...nodeEvents, ...characterShortcutEvents]) {
    bool hasMatchRegExp = false;
    final regExp = shortcutEvent.regExp;
    if (regExp != null && character != null) {
      hasMatchRegExp = regExp.hasMatch(character);
      if (hasMatchRegExp &&
          shortcutEvent.handlerWithCharacter != null &&
          await shortcutEvent.executeWithCharacter(
            editorState,
            character,
          )) {
        AppFlowyEditorLog.input.debug(
          'keyboard service - handled by character shortcut event: $shortcutEvent',
        );

        return true;
      }
    }
    if ((shortcutEvent.character == character || hasMatchRegExp) &&
        await shortcutEvent.handler(editorState)) {
      AppFlowyEditorLog.input.debug(
        'keyboard service - handled by character shortcut event: $shortcutEvent',
      );

      return true;
    }
  }

  return false;
}
