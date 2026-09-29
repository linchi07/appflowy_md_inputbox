import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

EditorState _editorWithText(String source, {int? offset}) {
  final node = paragraphNode(text: source);
  return EditorState(document: Document(root: pageNode(children: [node])))
    ..selection = Selection.collapsed(
      Position(path: node.path, offset: offset ?? source.length),
    );
}

void main() {
  test('table shortcuts are dispatched from the table behavior', () {
    expect(standardCommandShortcutEvents, contains(enterMarkdownShortcutEvent));
    final table = TableNode.fromList([
      [''],
    ]);
    final state =
        EditorState(document: Document(root: pageNode(children: [table.node])));
    final cellText = table.getCell(0, 0).children.first;
    expect(
      state.commandShortcutsFor(cellText),
      contains(enterInTableCell),
    );
    state.dispose();
  });

  test('Markdown Enter leaves native table-cell navigation to its handler', () {
    final table = TableNode.fromList([
      ['- item'],
    ]);
    final state = EditorState(
      document: Document(root: pageNode(children: [table.node])),
    );
    final cellText = table.getCell(0, 0).children.first;
    state.selection = Selection.collapsed(
      Position(path: cellText.path, offset: 6),
    );

    expect(enterMarkdownShortcutEvent.execute(state), KeyEventResult.ignored);
    expect(cellText.delta?.toPlainText(), '- item');
    state.dispose();
  });

  test('Enter continues a bullet and places the caret after the prefix', () {
    final state = _editorWithText('- first');

    expect(
      enterMarkdownShortcutEvent.execute(state),
      KeyEventResult.handled,
    );
    expect(
      state.document.root.children.map((node) => node.delta?.toPlainText()),
      ['- first', '- '],
    );
    expect(state.selection?.start, Position(path: [1], offset: 2));
    state.dispose();
  });

  test('Enter increments an ordered item and preserves text after the caret',
      () {
    final state = _editorWithText('9. first second', offset: 9);

    expect(
      enterMarkdownShortcutEvent.execute(state),
      KeyEventResult.handled,
    );
    expect(
      state.document.root.children.map((node) => node.delta?.toPlainText()),
      ['9. first ', '10. second'],
    );
    expect(state.selection?.start, Position(path: [1], offset: 4));
    state.dispose();
  });

  test('Enter on an empty list item exits the list', () {
    final state = _editorWithText('- ');

    expect(
      enterMarkdownShortcutEvent.execute(state),
      KeyEventResult.handled,
    );
    expect(state.document.root.children, hasLength(1));
    expect(state.document.root.children.single.delta?.toPlainText(), '');
    expect(state.selection?.start, Position(path: [0], offset: 0));
    state.dispose();
  });

  test('IME newline uses the same ordered-list continuation', () async {
    final state = _editorWithText('2. item');

    expect(await insertNewLine.execute(state), isTrue);
    expect(
      state.document.root.children.map((node) => node.delta?.toPlainText()),
      ['2. item', '3. '],
    );
    expect(state.selection?.start, Position(path: [1], offset: 3));
    state.dispose();
  });
}
