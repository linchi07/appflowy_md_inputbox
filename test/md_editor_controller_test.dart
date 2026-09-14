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
}
