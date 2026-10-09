import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'public Markdown import creates a structured baseline with valid paths',
    () {
      final document = Document.fromMarkdown(
        '# title\n\n| a | b |\n| --- | --- |\n| c | d |',
      );
      final table = document.root.children.firstWhere(
        (node) => node.type == TableBlockKeys.type,
      );
      expect(table.parent, same(document.root));
      final text = TableNode(node: table).getCell(1, 1).children.single;
      expect(document.nodeAtPath(text.path), same(text));
      final loaded = Document.fromJson(document.toJson());
      expect(loaded.nodeAtPath(text.path)!.id, text.id);
      document.dispose();
      loaded.dispose();
    },
  );

  test(
    'UUIDv7 identity survives JSON and view cloning but duplication is new',
    () {
      final node = paragraphNode(text: 'hello');
      final table = Node(type: 'group', children: [node]);
      expect(
        node.id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      final restored = Node.fromJson(table.toJson());
      expect(restored.id, table.id);
      expect(restored.children.single.id, node.id);
      final view = table.cloneForView();
      expect(view.id, table.id);
      expect(view.children.single.id, node.id);
      expect(view.children.single.key, isNot(same(node.key)));
      final duplicate = table.deepCopy();
      expect(duplicate.id, isNot(table.id));
      expect(duplicate.children.single.id, isNot(node.id));
      final legacy = Node.fromJson({'type': 'paragraph'});
      expect(legacy.id, isNotEmpty);
    },
  );
}
