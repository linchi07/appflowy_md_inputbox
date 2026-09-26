import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inserting many sibling nodes notifies the document root once', () {
    final document = Document.blank(withInitialText: true);
    var notifications = 0;
    document.root.addListener(() => notifications++);

    document.insert(
      const [1],
      List.generate(1000, (index) => paragraphNode(text: 'line $index')),
    );

    expect(document.root.children, hasLength(1001));
    expect(notifications, 1);
    document.dispose();
  });

  test('pending text deltas are isolated between transactions', () {
    final firstDocument = Document.blank(withInitialText: true);
    final secondDocument = Document.blank(withInitialText: true);
    final firstNode = firstDocument.root.children.single;
    final secondNode = secondDocument.root.children.single;
    final first = Transaction(document: firstDocument)
      ..insertText(firstNode, 0, 'first');
    final second = Transaction(document: secondDocument)
      ..insertText(secondNode, 0, 'second');

    final firstOperations = first.operations;
    final secondOperations = second.operations;

    expect(firstOperations, hasLength(1));
    expect(secondOperations, hasLength(1));
    expect(firstOperations.single.path, firstNode.path);
    expect(secondOperations.single.path, secondNode.path);

    firstDocument.dispose();
    secondDocument.dispose();
  });

  test('middle batch mutations keep sibling paths consistent', () {
    final document = Document.blank();
    document.insert(
      const [0],
      List.generate(2000, (index) => paragraphNode(text: 'old $index')),
    );
    document.insert(
      const [700],
      List.generate(500, (index) => paragraphNode(text: 'new $index')),
    );

    for (var index = 0; index < document.root.children.length; index++) {
      expect(document.root.children[index].path, [index]);
    }

    document.delete(const [650], 600);
    for (var index = 0; index < document.root.children.length; index++) {
      expect(document.root.children[index].path, [index]);
    }

    final first = document.root.children.first;
    final last = document.root.children.last;
    first.insertBefore(paragraphNode(text: 'before'));
    last.insertAfter(paragraphNode(text: 'after'));
    for (var index = 0; index < document.root.children.length; index++) {
      expect(document.root.children[index].path, [index]);
    }
    document.dispose();
  });

  test('deleting a large plain-text selection batches sibling removal',
      () async {
    final document = Document.blank();
    final lines = List.generate(2000, (index) => 'line $index');
    document.insert(
      const [0],
      lines.map((line) => paragraphNode(text: line)),
    );
    final state = EditorState(document: document);
    final selection = Selection(
      start: Position(path: [0], offset: 1),
      end: Position(path: [lines.length - 1], offset: 2),
    );

    expect(await state.deleteSelection(selection), isTrue);
    expect(state.document.root.children, hasLength(1));
    expect(state.text, 'lne 1999');
    expect(state.undoManager.undoStack.last.operations, hasLength(2));

    state.undoManager.undo();
    await Future<void>.delayed(Duration.zero);
    expect(state.document.root.children, hasLength(lines.length));
    expect(state.text, lines.join('\n'));

    state.undoManager.redo();
    await Future<void>.delayed(Duration.zero);
    expect(state.text, 'lne 1999');
    state.dispose();
  });
}
