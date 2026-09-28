import 'dart:ui';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_ghost_cell.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_view.dart';
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
      'add column and row buttons expand table and style menu works',
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

    // 验证初始列数与行数
    expect(TableNode(node: state.document.root.children.single).colsLen, 2);
    expect(TableNode(node: state.document.root.children.single).rowsLen, 2);

    // 验证加列横框存在，点击增加一列
    final addColButton = find.byKey(const ValueKey('table-add-col-button'));
    expect(addColButton, findsOneWidget);
    await tester.tap(addColButton);
    await tester.pump();
    await tester.pump();
    expect(TableNode(node: state.document.root.children.single).colsLen, 3);

    // 验证加行横框存在，点击增加一行
    final addRowButton = find.byKey(const ValueKey('table-add-row-button'));
    expect(addRowButton, findsOneWidget);
    await tester.tap(addRowButton);
    await tester.pump();
    await tester.pump();
    expect(TableNode(node: state.document.root.children.single).rowsLen, 3);

    // 验证左上角样式切换按钮
    final styleButton = find.byKey(const ValueKey('table-style-button'));
    expect(styleButton, findsOneWidget);
    await tester.tap(styleButton);
    await tester.pumpAndSettle();

    await tester.tap(
      find.ancestor(
        of: find.text('首行灰色'),
        matching: find.byType(CheckedPopupMenuItem<String>),
      ),
    );
    await tester.pump();

    final node = state.document.root.children.single;
    expect(node.attributes[TableBlockKeys.shadeFirstRow], true);
    final expanded = TableNode(node: node);
    final shade = tableStyleCellColor(
      node,
      expanded.getCell(0, 0),
      Theme.of(tester.element(find.byType(AppFlowyEditor))).colorScheme,
    );
    expect(shade, isNotNull);
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

  testWidgets('read-only tables omit controls and buttons',
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
    expect(find.byKey(const ValueKey('table-add-col-button')), findsNothing);
    expect(find.byKey(const ValueKey('table-add-row-button')), findsNothing);
    expect(find.byKey(const ValueKey('table-style-button')), findsNothing);
    expect(TableNode(node: state.document.root.children.single).colsLen, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('hovering dividers reveals insertion triangles to add row/col',
      (tester) async {
    final state = tableState();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 700,
          height: 400,
          child: AppFlowyEditor(
            editorState: state,
            editorStyle: EditorStyle.desktop(padding: EdgeInsets.zero),
          ),
        ),
      ),
    );
    await tester.pump();

    // 移动鼠标到两列之间
    // 表格起始在 x=34 (8+26)，第一列宽160，边框1，分割线约在 34 + 1 + 160 = 195
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    final tableTopLeft = tester.getTopLeft(find.byType(TableView));

    // 悬浮在列分割线 (SIDE_HEADER_WIDTH + 1 + 160 + 0.5 = 187.5, y: 12)
    await gesture.moveTo(tableTopLeft + const Offset(187.5, 12));
    await tester.pump();

    final colTriangle = find.byKey(const ValueKey('table-insert-col-divider-1'));
    expect(colTriangle, findsOneWidget);
    await tester.tap(colTriangle);
    await tester.pump();
    expect(TableNode(node: state.document.root.children.single).colsLen, 3);

    final table = TableNode(node: state.document.root.children.single);
    final row0Height = table.getRowHeight(0);
    final divider1Y = 26.0 + 1.0 + row0Height + 0.5;

    // 悬浮在两行之间
    await gesture.moveTo(tableTopLeft + Offset(12, divider1Y));
    await tester.pump();

    final rowTriangle = find.byKey(const ValueKey('table-insert-row-divider-1'));
    expect(rowTriangle, findsOneWidget);
    await tester.tap(rowTriangle);
    await tester.pump();
    expect(TableNode(node: state.document.root.children.single).rowsLen, 3);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('column and row drag handles appear on hover outside table without fill or shape',
      (tester) async {
    final state = tableState();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 700,
          height: 400,
          child: AppFlowyEditor(
            editorState: state,
            editorStyle: EditorStyle.desktop(padding: EdgeInsets.zero),
          ),
        ),
      ),
    );
    await tester.pump();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    final tableTopLeft = tester.getTopLeft(find.byType(TableView));

    // 悬浮在第一列顶部外侧 (x: SIDE_HEADER_WIDTH + 50, y: TOP_HEADER_HEIGHT / 2)
    await gesture.moveTo(tableTopLeft + const Offset(70, 12));
    await tester.pump();

    final colHandle = find.byKey(const ValueKey('table-col-handle-0'));
    expect(colHandle, findsOneWidget);
    // 确保没有 Card
    expect(find.descendant(of: colHandle, matching: find.byType(Card)), findsNothing);
    // 确保包含 drag_indicator 图标
    expect(
      find.descendant(
        of: colHandle,
        matching: find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.drag_indicator,
        ),
      ),
      findsOneWidget,
    );

    // 悬浮在第一行左侧外侧
    final row0Height = TableNode(node: state.document.root.children.single).getRowHeight(0);
    final row0CenterY = 26.0 + 1.0 + row0Height / 2;
    await gesture.moveTo(tableTopLeft + Offset(12, row0CenterY));
    await tester.pump();

    final rowHandle = find.byKey(const ValueKey('table-row-handle-0'));
    expect(rowHandle, findsOneWidget);
    // 确保没有 Card
    expect(find.descendant(of: rowHandle, matching: find.byType(Card)), findsNothing);
    expect(
      find.descendant(
        of: rowHandle,
        matching: find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.drag_indicator,
        ),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
