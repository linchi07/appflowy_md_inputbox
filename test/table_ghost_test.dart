import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_ghost_cell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  EditorState tableState() {
    final table = TableNode.fromList([
      ['A', '1'],
      ['B', '2'],
    ]);
    return EditorState(
      document: Document(root: pageNode(children: [table.node])),
    );
  }

  test('ghost column is absent until text commits, then forms one undo step',
      () async {
    final state = tableState();
    final node = state.document.root.children.single;
    final before = node.toJson();

    await TableActions.materializeGhostCell(
      node,
      state,
      col: 2,
      row: 1,
      text: '',
    );
    expect(node.toJson(), before);

    await TableActions.materializeGhostCell(
      node,
      state,
      col: 2,
      row: 1,
      text: 'new',
    );
    var table = TableNode(node: node);
    expect(table.colsLen, 3);
    expect(table.rowsLen, 2);
    expect(table.getCell(2, 0).children.single.delta?.toPlainText(), '');
    expect(table.getCell(2, 1).children.single.delta?.toPlainText(), 'new');
    expect(state.selection?.end.path, [0, 5, 0]);
    expect(state.selection?.end.offset, 3);

    state.undoManager.undo();
    table = TableNode(node: state.document.root.children.single);
    expect(table.colsLen, 2);
    expect(table.rowsLen, 2);
    state.dispose();
  });

  test('ghost row commits into the selected column without shifting cells',
      () async {
    final state = tableState();
    final node = state.document.root.children.single;
    await TableActions.materializeGhostCell(
      node,
      state,
      col: 1,
      row: 2,
      text: 'bottom',
    );

    final table = TableNode(node: node);
    expect(table.colsLen, 2);
    expect(table.rowsLen, 3);
    expect(table.getCell(0, 0).children.single.delta?.toPlainText(), 'A');
    expect(table.getCell(0, 1).children.single.delta?.toPlainText(), '1');
    expect(table.getCell(0, 2).children.single.delta?.toPlainText(), '');
    expect(table.getCell(1, 0).children.single.delta?.toPlainText(), 'B');
    expect(table.getCell(1, 1).children.single.delta?.toPlainText(), '2');
    expect(table.getCell(1, 2).children.single.delta?.toPlainText(), 'bottom');
    expect(state.selection?.end.path, [0, 5, 0]);
    expect(state.selection?.end.offset, 6);
    state.undoManager.undo();
    final restored = TableNode(node: state.document.root.children.single);
    expect(restored.rowsLen, 2);
    expect(restored.getCell(1, 1).children.single.delta?.toPlainText(), '2');
    state.dispose();
  });

  test('table style flags are stored on the table node', () {
    final state = tableState();
    final node = state.document.root.children.single;
    TableActions.toggleStyle(node, state, TableBlockKeys.shadeFirstRow);
    expect(node.attributes[TableBlockKeys.shadeFirstRow], true);
    TableActions.toggleStyle(node, state, TableBlockKeys.shadeFirstColumn);
    TableActions.toggleStyle(node, state, TableBlockKeys.stripeRows);
    final colors = ColorScheme.fromSeed(seedColor: Colors.blue);
    final table = TableNode(node: node);
    expect(tableStyleCellColor(node, table.getCell(1, 0), colors), isNotNull);
    expect(tableStyleCellColor(node, table.getCell(0, 1), colors), isNotNull);
    expect(tableStyleCellColor(node, table.getCell(1, 1), colors), isNotNull);
    TableActions.toggleStyle(node, state, TableBlockKeys.shadeFirstRow);
    expect(node.attributes[TableBlockKeys.shadeFirstRow], false);
    state.dispose();
  });

  testWidgets(
      'ghost inputs materialize only after typing and style menu shades',
      (tester) async {
    final state = tableState();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 700,
          height: 320,
          child: AppFlowyEditor(
            editorState: state,
            editorStyle: EditorStyle.desktop(padding: EdgeInsets.zero),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('table-ghost-row-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('table-ghost-col-1')), findsOneWidget);
    expect(TableNode(node: state.document.root.children.single).colsLen, 2);

    final ghost = find.descendant(
      of: find.byKey(const ValueKey('table-ghost-col-1')),
      matching: find.byType(TextField),
    );
    await tester.tap(ghost);
    await tester.pump();
    expect(TableNode(node: state.document.root.children.single).colsLen, 2);
    await tester.enterText(ghost, 'new');
    await tester.pump();
    await tester.pump();

    final node = state.document.root.children.single;
    final table = TableNode(node: node);
    expect(table.colsLen, 3);
    expect(table.getCell(2, 1).children.single.delta?.toPlainText(), 'new');
    expect(state.selection?.end.path, table.getCell(2, 1).children.single.path);
    expect(state.focusNotifier.value, isTrue);

    final ghostRow = find.descendant(
      of: find.byKey(const ValueKey('table-ghost-row-1')),
      matching: find.byType(TextField),
    );
    await tester.tap(ghostRow);
    await tester.pump();
    expect(TableNode(node: node).rowsLen, 2);
    await tester.enterText(ghostRow, 'bottom');
    await tester.pump();
    await tester.pump();
    final expanded = TableNode(node: node);
    expect(expanded.rowsLen, 3);
    expect(
      expanded.getCell(1, 2).children.single.delta?.toPlainText(),
      'bottom',
    );

    await tester.tap(find.byKey(const ValueKey('table-style-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text('首行灰色'),
        matching: find.byType(CheckedPopupMenuItem<String>),
      ),
    );
    await tester.pump();
    expect(node.attributes[TableBlockKeys.shadeFirstRow], true);
    expect(
      tableStyleCellColor(
        node,
        expanded.getCell(0, 0),
        Theme.of(tester.element(find.byType(AppFlowyEditor))).colorScheme,
      ),
      isNotNull,
    );
    final shade = tableStyleCellColor(
      node,
      expanded.getCell(0, 0),
      Theme.of(tester.element(find.byType(AppFlowyEditor))).colorScheme,
    );
    expect(
      find.descendant(
        of: find.byKey(expanded.getCell(0, 0).key),
        matching: find.byWidgetPredicate(
          (widget) => widget is Container && widget.color == shade,
        ),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('read-only tables omit ghost inputs and editing controls',
      (tester) async {
    final state = tableState();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 700,
          height: 320,
          child: AppFlowyEditor(
            editorState: state,
            editable: false,
            disableKeyboardService: true,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(TableGhostCell), findsNothing);
    expect(find.byKey(const ValueKey('table-style-button')), findsNothing);
    expect(TableNode(node: state.document.root.children.single).colsLen, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('IME composition does not materialize a ghost cell early',
      (tester) async {
    final state = tableState();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 700,
          height: 320,
          child: AppFlowyEditor(editorState: state),
        ),
      ),
    );
    await tester.pump();
    final ghost = find.descendant(
      of: find.byKey(const ValueKey('table-ghost-row-0')),
      matching: find.byType(TextField),
    );
    await tester.showKeyboard(ghost);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '中',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1),
      ),
    );
    await tester.pump();
    expect(TableNode(node: state.document.root.children.single).rowsLen, 2);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '中',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    await tester.pump();
    final table = TableNode(node: state.document.root.children.single);
    expect(table.rowsLen, 3);
    expect(table.getCell(0, 2).children.single.delta?.toPlainText(), '中');
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
