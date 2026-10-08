import 'dart:ui';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_config.dart';
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

  test('TableActions.add expands columns and rows directly', () async {
    final state = tableState();
    final node = state.document.root.children.single;

    await TableActions.add(node, 2, state, TableDirection.col);
    var table = TableNode(node: node);
    expect(table.colsLen, 3);
    expect(table.rowsLen, 2);

    await TableActions.add(node, 2, state, TableDirection.row);
    table = TableNode(node: node);
    expect(table.colsLen, 3);
    expect(table.rowsLen, 3);

    state.undoManager.undo();
    table = TableNode(node: state.document.root.children.single);
    expect(table.rowsLen, 2);
    state.dispose();
  });

  test('table style flags are stored on the table node', () {
    final state = tableState();
    final node = state.document.root.children.single;
    TableActions.toggleStyle(node, state, TableBlockKeys.shadeFirstRow);
    expect(node.attributes[TableBlockKeys.shadeFirstRow], true);
    TableActions.toggleStyle(node, state, TableBlockKeys.shadeFirstColumn);
    TableActions.toggleStyle(node, state, TableBlockKeys.stripeRows);
    const colors = EditorColorScheme.light();
    final table = TableNode(node: node);
    expect(tableStyleCellColor(node, table.getCell(1, 0), colors), isNotNull);
    expect(tableStyleCellColor(node, table.getCell(0, 1), colors), isNotNull);
    expect(tableStyleCellColor(node, table.getCell(1, 1), colors), isNotNull);
    TableActions.toggleStyle(node, state, TableBlockKeys.shadeFirstRow);
    expect(node.attributes[TableBlockKeys.shadeFirstRow], false);
    state.dispose();
  });

  testWidgets('new table uses the current editor table style', (tester) async {
    final state = EditorState(
      document: Document(
        root: pageNode(children: [paragraphNode(delta: Delta()..insert('/'))]),
      ),
    )..selection = Selection.collapsed(Position(path: [0], offset: 1));
    const style = TableStyle(
      colWidth: 215,
      rowHeight: 44,
      colMinimumWidth: 55,
      borderWidth: 2,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AppFlowyEditor(
          editorState: state,
          blockComponentBuilders: {
            ...standardBlockComponentBuilderMap,
            TableBlockKeys.type: TableBlockComponentBuilder(tableStyle: style),
          },
        ),
      ),
    );
    await tester.pump();

    final context = tester.element(find.byType(AppFlowyEditor));
    tableMenuItem.handler(
      state,
      SelectionMenu(
        context: context,
        editorState: state,
        selectionMenuItems: [],
      ),
      context,
    );
    await tester.pump();

    final table = state.document.root.children.single;
    expect(table.type, TableBlockKeys.type);
    expect(TableConfig.fromJson(table.attributes).toJson(), {
      TableBlockKeys.colDefaultWidth: style.colWidth,
      TableBlockKeys.rowDefaultHeight: style.rowHeight,
      TableBlockKeys.colMinimumWidth: style.colMinimumWidth,
      TableBlockKeys.borderWidth: style.borderWidth,
    });
    expect(TableDefaults.colWidth, 160);
    expect(TableDefaults.borderWidth, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('add column and row buttons expand table and style menu works',
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

    // 验证左上角样式按钮存在
    final styleButton = find.byKey(const ValueKey('table-style-button'));
    expect(styleButton, findsOneWidget);

    await tester.tap(styleButton);
    await tester.pumpAndSettle();

    expect(find.text('首行灰色'), findsOneWidget);
    expect(find.text('首列灰色'), findsOneWidget);
    expect(find.text('交替行底色'), findsOneWidget);

    await tester.tap(find.text('首行灰色'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      state.document.root.children.single
          .attributes[TableBlockKeys.shadeFirstRow],
      true,
    );

    // 幽灵列应彻底不存在
    expect(
      find.byKey(const ValueKey('table-ghost-col-card')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('table-ghost-row-card')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('read-only tables omit controls and buttons', (tester) async {
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
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    final tableTopLeft = tester.getTopLeft(find.byType(TableView));

    // 悬浮在列分割线
    await gesture.moveTo(tableTopLeft + const Offset(209.5, 12));
    await tester.pump();

    final colTriangle =
        find.byKey(const ValueKey('table-insert-col-divider-1'));
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

    final rowTriangle =
        find.byKey(const ValueKey('table-insert-row-divider-1'));
    expect(rowTriangle, findsOneWidget);
    await tester.tap(rowTriangle);
    await tester.pump();
    expect(TableNode(node: state.document.root.children.single).rowsLen, 3);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets(
      'column and row drag handles appear on hover outside table without fill or shape',
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

    // 悬浮在第一列顶部外侧
    await gesture.moveTo(tableTopLeft + const Offset(70, 12));
    await tester.pump();

    final colHandle = find.byKey(const ValueKey('table-col-handle-0'));
    expect(colHandle, findsOneWidget);
    // 确保没有 Card
    expect(find.descendant(of: colHandle, matching: find.byType(Card)),
        findsNothing);
    // 确保包含 palette_outlined 图标 (调色板) 和 close 图标 (X删除按钮)
    expect(
      find.descendant(
        of: colHandle,
        matching: find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.palette_outlined,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: colHandle,
        matching: find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.close,
        ),
      ),
      findsOneWidget,
    );

    // 悬浮在第一行左侧外侧
    final row0Height =
        TableNode(node: state.document.root.children.single).getRowHeight(0);
    final row0CenterY = 26.0 + 1.0 + row0Height / 2;
    await gesture.moveTo(tableTopLeft + Offset(12, row0CenterY));
    await tester.pump();

    final rowHandle = find.byKey(const ValueKey('table-row-handle-0'));
    expect(rowHandle, findsOneWidget);
    expect(find.descendant(of: rowHandle, matching: find.byType(Card)),
        findsNothing);
    expect(
      find.descendant(
        of: rowHandle,
        matching: find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.palette_outlined,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: rowHandle,
        matching: find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.close,
        ),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets(
      'table row heights are aligned across all columns and borders match',
      (tester) async {
    // 构造一个多行文本表格：第 0 列包含多行长文本，第 1 列为单行短文本
    final tableNode = TableNode.fromList([
      [
        'This is a very long text that will wrap into multiple lines inside cell 0,0',
        'Short row 1 text',
      ],
      [
        'Col 1 Row 0',
        'Col 1 Row 1',
      ],
    ]);
    final state = EditorState(
      document: Document(root: pageNode(children: [tableNode.node])),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 700,
          height: 600,
          child: AppFlowyEditor(
            editorState: state,
            editorStyle: EditorStyle.desktop(padding: EdgeInsets.zero),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final table = TableNode(node: state.document.root.children.single);
    final rowsLen = table.rowsLen;
    final colsLen = table.colsLen;

    // 遍历每一行，验证该行下所有列的单元格高度完全一致，且顶部 Y 轴完全平齐
    for (var r = 0; r < rowsLen; r++) {
      double? expectedTop;
      double? expectedHeight;

      for (var c = 0; c < colsLen; c++) {
        final cellNode = table.getCell(c, r);
        final cellFinder = find.byKey(cellNode.key);
        expect(cellFinder, findsOneWidget);

        final cellRect = tester.getRect(cellFinder);
        expectedTop ??= cellRect.top;
        expectedHeight ??= cellRect.height;

        // 同一行的单元格顶部 Y 坐标必须绝对对齐
        expect(
          cellRect.top,
          closeTo(expectedTop, 0.01),
          reason: 'Cell ($c, $r) top is not aligned with other cells in row $r',
        );
        // 同一行的单元格高度必须严格一致
        expect(
          cellRect.height,
          closeTo(expectedHeight, 0.01),
          reason: 'Cell ($c, $r) height is not equal to other cells in row $r',
        );
      }
    }

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
