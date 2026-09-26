import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compact and large-document controllers use bounded history profiles',
      () {
    final compact = MDEditorController();
    final document = MDEditorController.largeDocument();

    expect(compact.editorState.undoManager.undoStack.maxSize, 30);
    expect(document.editorState.undoManager.undoStack.maxSize, 200);

    compact.dispose();
    document.dispose();
    expect(compact.editorState.isDisposed, isTrue);
    expect(document.editorState.isDisposed, isTrue);

    // Disposal is intentionally idempotent for list/grid ownership patterns.
    compact.dispose();
    document.dispose();
  });

  testWidgets('large-document controller debounces full-text callbacks',
      (tester) async {
    var callbacks = 0;
    final controller = MDEditorController.largeDocument(
      onInput: (_) => callbacks++,
      inputDebounce: const Duration(milliseconds: 100),
    );
    final node = controller.editorState.document.root.children.first;

    await controller.editorState.apply(
      controller.editorState.transaction..insertText(node, 0, 'a'),
    );
    await controller.editorState.apply(
      controller.editorState.transaction..insertText(node, 1, 'b'),
    );

    await tester.pump(const Duration(milliseconds: 99));
    expect(callbacks, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(callbacks, 1);

    controller.dispose();
  });

  testWidgets('disposing cancels an in-flight large document replacement',
      (tester) async {
    final controller = MDEditorController(
      initialText: List.filled(2000, 'x').join(),
    );
    controller.dispose();

    await tester.pumpAndSettle();
    expect(controller.editorState.isDisposed, isTrue);
  });

  test('an edit cancels an in-flight large document replacement', () async {
    final state = EditorState.blank();
    final replacement = state.setText(List.filled(2000, 'x').join());
    await state.apply(
      state.transaction
        ..insertText(state.document.root.children.first, 0, 'local'),
    );

    await replacement;
    expect(state.text, 'local');
    state.dispose();
  });

  test('moving the caret cancels an in-flight large paste', () async {
    final state = EditorState.blank();
    await state.setText('base');
    state.selection = Selection.single(path: [0], startOffset: 4);
    final paste = state.pastePlainText(List.filled(2000, 'x').join());
    state.selection = Selection.single(path: [0], startOffset: 1);

    await paste;
    expect(state.text, 'base');
    expect(state.selection, Selection.single(path: [0], startOffset: 1));
    state.dispose();
  });

  test('append adds markdown text to the end of the document', () async {
    final controller = MDEditorController();
    await controller.setText('line 1');
    await controller.append('\nline 2');
    expect(controller.text, contains('line 1'));
    expect(controller.text, contains('line 2'));
    controller.dispose();
  });

  test('document insert clamps index out of range and appends nodes', () {
    final document = Document.blank(withInitialText: true);
    final initialCount = document.root.children.length;

    final result = document.insert(
      const [999],
      [paragraphNode(text: 'appended')],
    );

    expect(result, isTrue);
    expect(document.root.children.length, initialCount + 1);
    expect(document.root.children.last.delta?.toPlainText(), 'appended');
    document.dispose();
  });
}
