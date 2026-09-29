import 'package:flutter_test/flutter_test.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/service/markdown_parser.dart';

void main() {
  test('Test parseMarkdownToNodes for table', () {
    const markdown = '| A | B |\n|---|---|\n| 1 | 2 |';

    final nodes = parseMarkdownToNodes(markdown);
    expect(nodes.length, 1);
    expect(nodes.first.type, TableBlockKeys.type);

    final tableNode = TableNode(node: nodes.first);
    expect(tableNode.colsLen, 2);
    expect(tableNode.rowsLen, 2);

    expect(tableNode.getCell(0, 0).children.first.delta?.toPlainText(), 'A');
    expect(tableNode.getCell(1, 0).children.first.delta?.toPlainText(), 'B');
    expect(tableNode.getCell(0, 1).children.first.delta?.toPlainText(), '1');
    expect(tableNode.getCell(1, 1).children.first.delta?.toPlainText(), '2');
  });

  test('Test EditorState.text getter for table', () async {
    final tableNode = TableNode.fromList([
      ['A', '1'],
      ['B', '2'],
    ]);

    final editorState = EditorState(
      document: Document(
        root: pageNode(children: [tableNode.node]),
      ),
    );

    final text = editorState.text;
    expect(text.contains('| A | B |'), true);
    expect(text.contains('| --- | --- |'), true);
    expect(text.contains('| 1 | 2 |'), true);
    editorState.dispose();
  });

  test('EditorState uses the table serializer for special characters', () {
    final table = TableNode.fromList([
      ['A|B', 'line 1\nline 2'],
      ['C', 'D'],
    ]);
    final state = EditorState(
      document: Document(root: pageNode(children: [table.node])),
    );
    expect(state.text, table.toMarkdown());
    expect(state.text, contains(r'A\|B'));
    state.dispose();
  });
}
