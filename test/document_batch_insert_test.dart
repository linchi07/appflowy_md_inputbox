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
}
