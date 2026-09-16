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
}
