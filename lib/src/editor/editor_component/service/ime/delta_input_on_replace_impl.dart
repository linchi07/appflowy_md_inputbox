import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/editor_component/service/ime/character_shortcut_event_helper.dart';
import 'package:appflowy_editor/src/editor/editor_component/service/ime/delta_input_impl.dart';
import 'package:appflowy_editor/src/editor/util/platform_extension.dart';
import 'package:flutter/services.dart';

Future<void> onReplace(
  TextEditingDeltaReplacement replacement,
  EditorState editorState,
  List<CharacterShortcutEvent> characterShortcutEvents,
) async {
  AppFlowyEditorLog.input.debugLazy(() => 'onReplace: $replacement');

  final generation = editorState.imeCompositionGeneration;

  // delete the selection
  final selection = editorState.selection;
  if (selection == null) {
    return;
  }

  if (selection.isSingle) {
    if (!editorState.isImeComposing) {
      final execution = await executeCharacterShortcutEvent(
        editorState,
        replacement.replacementText,
        characterShortcutEvents,
      );
      if (execution) return;
    }

    if (PlatformExtension.isIOS) {
      // remove the trailing '\n' when pressing the return key
      if (replacement.replacementText.endsWith('\n')) {
        replacement = TextEditingDeltaReplacement(
          oldText: replacement.oldText,
          replacementText: replacement.replacementText
              .substring(0, replacement.replacementText.length - 1),
          replacedRange: replacement.replacedRange,
          selection: replacement.selection,
          composing: replacement.composing,
        );
      }
    }

    final node = editorState.getNodesInSelection(selection).first;
    final transaction = editorState.transaction;
    final start = replacement.replacedRange.start;
    final length = replacement.replacedRange.end - start;
    final afterSelection = Selection(
      start: Position(
        path: node.path,
        offset: replacement.selection.baseOffset,
      ),
      end: Position(
        path: node.path,
        offset: replacement.selection.extentOffset,
      ),
    );
    transaction
      ..replaceText(node, start, length, replacement.replacementText)
      ..afterSelection = afterSelection;
    await editorState.apply(transaction);
  } else {
    // Non-delta diffs may retain identical letters inside the selected range.
    // Recover the complete candidate from the native value before deleting the
    // editor's multi-node selection, rather than inserting only the trimmed diff.
    final normalized = selection.normalized;
    final first = editorState.document.nodeAtPath(normalized.start.path);
    final last = editorState.document.nodeAtPath(normalized.end.path);
    final value = replacement.oldText.replaceRange(
      replacement.replacedRange.start,
      replacement.replacedRange.end,
      replacement.replacementText,
    );
    final suffix = (last?.delta?.length ?? 0) - normalized.end.offset;
    final candidate = first?.delta != null &&
            last?.delta != null &&
            normalized.start.offset <= value.length - suffix
        ? value.substring(normalized.start.offset, value.length - suffix)
        : replacement.replacementText;
    await editorState.deleteSelection(selection);
    if (generation != editorState.imeCompositionGeneration) return;
    final insertion = TextEditingDeltaInsertion(
      oldText: value,
      textInserted: candidate,
      insertionOffset: normalized.start.offset,
      selection: replacement.selection,
      composing: replacement.composing,
    );
    await onInsert(
      insertion,
      editorState,
      characterShortcutEvents,
    );
  }
}
