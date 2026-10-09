import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/editor_component/service/ime/delta_input_impl.dart'
    as ime;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('standalone editor keeps slow IME replacement in one undo step',
      () async {
    final state = EditorState(
      document: Document(
        root: pageNode(
          children: [paragraphNode(text: 'old ')],
        ),
      ),
    )..selection = Selection.collapsed(Position(path: [0], offset: 4));
    addTearDown(state.dispose);
    final input = ime.NonDeltaTextInputService(
      onCompositionStart: state.beginImeUndoGroup,
      onCompositionEnd: state.endImeUndoGroup,
      onInsert: (delta) async {
        await ime.onInsert(delta, state, []);
        return true;
      },
      onReplace: (delta) async {
        await ime.onReplace(delta, state, []);
        return true;
      },
      onDelete: (delta) async {
        await ime.onDelete(delta, state);
        return true;
      },
      onNonTextUpdate: (_) async => true,
      onPerformAction: (_) async {},
    );
    addTearDown(input.close);
    await input.apply(
      [
        const TextEditingDeltaInsertion(
          oldText: ' old ',
          textInserted: 'ni',
          insertionOffset: 5,
          selection: TextSelection.collapsed(offset: 7),
          composing: TextRange(start: 5, end: 7),
        ),
      ],
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await input.apply(
      [
        const TextEditingDeltaReplacement(
          oldText: ' old ni',
          replacementText: '你',
          replacedRange: TextRange(start: 5, end: 7),
          selection: TextSelection.collapsed(offset: 6),
          composing: TextRange.empty,
        ),
      ],
    );
    expect(state.undoManager.undoStack.length, 1);
    state.undoManager.undo();
    expect(state.document.root.children.single.delta!.toPlainText(), 'old ');
    state.undoManager.redo();
    expect(state.document.root.children.single.delta!.toPlainText(), 'old 你');
  });
}
