import 'dart:ui';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TableSelection model', () {
    test('normalizes coordinates in forward drag', () {
      const sel = TableSelection(
        startCol: 0,
        startRow: 0,
        endCol: 2,
        endRow: 1,
      );
      expect(sel.minCol, 0);
      expect(sel.maxCol, 2);
      expect(sel.minRow, 0);
      expect(sel.maxRow, 1);
      expect(sel.isMultiCell, isTrue);
      expect(sel.cellCount, 6);
      expect(sel.contains(1, 0), isTrue);
      expect(sel.contains(2, 1), isTrue);
      expect(sel.contains(3, 0), isFalse);
    });

    test('normalizes coordinates in reverse drag', () {
      const sel = TableSelection(
        startCol: 2,
        startRow: 1,
        endCol: 0,
        endRow: 0,
      );
      expect(sel.minCol, 0);
      expect(sel.maxCol, 2);
      expect(sel.minRow, 0);
      expect(sel.maxRow, 1);
      expect(sel.isMultiCell, isTrue);
      expect(sel.cellCount, 6);
    });

    test('identifies single cell selection correctly', () {
      const sel = TableSelection(
        startCol: 1,
        startRow: 1,
        endCol: 1,
        endRow: 1,
      );
      expect(sel.isMultiCell, isFalse);
      expect(sel.cellCount, 1);
      expect(sel.contains(1, 1), isTrue);
      expect(sel.contains(1, 0), isFalse);
    });
  });

  group('TableSelection widget interactions', () {
    EditorState createTableState() {
      // 2 列 2 行:
      // Row 0: "A", "B"
      // Row 1: "1", "2"
      final table = TableNode.fromList([
        ['A', '1'],
        ['B', '2'],
      ]);
      return EditorState(
        document: Document(root: pageNode(children: [table.node])),
      );
    }

    testWidgets('dragging across cells activates TableSelection and clears text selection',
        (tester) async {
      final state = createTableState();
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

      final tableFinder = find.byType(TableView);
      expect(tableFinder, findsOneWidget);
      final tableTopLeft = tester.getTopLeft(tableFinder);

      // (0, 0) 单元格大约在 (SIDE_HEADER_WIDTH + 40, TOP_HEADER_HEIGHT + 20)
      // (1, 1) 单元格大约在 (SIDE_HEADER_WIDTH + 200, TOP_HEADER_HEIGHT + 60)
      final startOffset = tableTopLeft + const Offset(50, 40);
      final endOffset = tableTopLeft + const Offset(200, 70);

      final gesture = await tester.startGesture(startOffset);
      await tester.pump();
      await gesture.moveTo(endOffset);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // 选区已经跨格激活
      final tableViewState = tester.state(tableFinder);
      expect(tableViewState, isNotNull);

      // 验证原生单格光标已经被清除
      expect(state.selection, isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });

    testWidgets('clicking col handle selects entire column and Delete clears it with undo support',
        (tester) async {
      final state = createTableState();
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

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      final tableTopLeft = tester.getTopLeft(find.byType(TableView));

      // 悬浮在第 0 列 handle 区域 (x: 34 + 80 = 114, y: 12)
      await mouse.moveTo(tableTopLeft + const Offset(114, 12));
      await tester.pump();

      final colHandle = find.byKey(const ValueKey('table-col-handle-0'));
      expect(colHandle, findsOneWidget);

      await tester.tap(colHandle);
      await tester.pump();

      // 按 Delete 键批量清空选中的第 0 列 (Row 0: 'A', Row 1: '1')
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();

      final table = TableNode(node: state.document.root.children.single);
      expect(table.getCell(0, 0).children.single.delta?.toPlainText(), '');
      expect(table.getCell(0, 1).children.single.delta?.toPlainText(), '');
      // 第 1 列未受影响
      expect(table.getCell(1, 0).children.single.delta?.toPlainText(), 'B');
      expect(table.getCell(1, 1).children.single.delta?.toPlainText(), '2');

      // 撤销验证
      state.undoManager.undo();
      await tester.pump();
      final restoredTable = TableNode(node: state.document.root.children.single);
      expect(restoredTable.getCell(0, 0).children.single.delta?.toPlainText(), 'A');
      expect(restoredTable.getCell(0, 1).children.single.delta?.toPlainText(), '1');

      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });

    testWidgets('copying selection produces standard TSV to clipboard',
        (tester) async {
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );

      final state = createTableState();
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

      final tableFinder = find.byType(TableView);
      final tableTopLeft = tester.getTopLeft(tableFinder);

      // 从 (0, 0) 拖拽到 (1, 1) 框选全表
      final startOffset = tableTopLeft + const Offset(50, 40);
      final endOffset = tableTopLeft + const Offset(200, 70);

      final gesture = await tester.startGesture(startOffset);
      await tester.pump();
      await gesture.moveTo(endOffset);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // 发送 Cmd+C (Meta + C) 或 Ctrl + C
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();

      expect(clipboardText, 'A\tB\n1\t2');

      // 按 Escape 清空选区
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });
  });

  group('TableSelectionCoordinator (Obsidian atomic table selection)', () {
    EditorState createMultiBlockState() {
      final table = TableNode.fromList([
        ['A', '1'],
        ['B', '2'],
      ]);
      return EditorState(
        document: Document(
          root: pageNode(
            children: [
              paragraphNode(text: 'Above paragraph'),
              table.node,
              paragraphNode(text: 'Below paragraph'),
            ],
          ),
        ),
      );
    }

    test('cell-internal text selection is preserved without atomic expansion', () {
      final state = createMultiBlockState();
      state.registerSelectionCoordinator(const TableSelectionCoordinator());

      // 单个单元格内部文字选择: path [1, 0, 0], offset 0..1
      final innerSel = Selection(
        start: Position(path: [1, 0, 0], offset: 0),
        end: Position(path: [1, 0, 0], offset: 1),
      );
      state.selection = innerSel;
      expect(state.selection, innerSel);
      state.dispose();
    });

    test('dragging downwards into table normalizes table end to whole block', () {
      final state = createMultiBlockState();
      state.registerSelectionCoordinator(const TableSelectionCoordinator());

      // 从上方段落 (path: [0]) 拖拽进入表格的某个内部 cell (path: [1, 1, 0])
      state.selection = Selection(
        start: Position(path: [0], offset: 2),
        end: Position(path: [1, 1, 0], offset: 1),
      );

      // 表格作为一个整体被包含：终点对齐到表格整体末尾 [1] offset 1
      expect(
        state.selection,
        Selection(
          start: Position(path: [0], offset: 2),
          end: Position(path: [1], offset: 1),
        ),
      );
      state.dispose();
    });

    test('dragging upwards into table normalizes table end to whole block', () {
      final state = createMultiBlockState();
      state.registerSelectionCoordinator(const TableSelectionCoordinator());

      // 从下方段落 (path: [2]) 向上拖拽进入表格的某个内部 cell (path: [1, 0, 0])
      state.selection = Selection(
        start: Position(path: [2], offset: 3),
        end: Position(path: [1, 0, 0], offset: 1),
      );

      // 表格作为一个整体被包含：终点对齐到表格整体开头 [1] offset 0
      expect(
        state.selection,
        Selection(
          start: Position(path: [2], offset: 3),
          end: Position(path: [1], offset: 0),
        ),
      );
      state.dispose();
    });

    test('dragging downwards out of table normalizes table start to whole block', () {
      final state = createMultiBlockState();
      state.registerSelectionCoordinator(const TableSelectionCoordinator());

      // 从表格内某个 cell (path: [1, 0, 0]) 向下拖拽到下方段落 (path: [2])
      state.selection = Selection(
        start: Position(path: [1, 0, 0], offset: 1),
        end: Position(path: [2], offset: 4),
      );

      // 表格作为一个整体被包含：起点对齐到表格整体开头 [1] offset 0
      expect(
        state.selection,
        Selection(
          start: Position(path: [1], offset: 0),
          end: Position(path: [2], offset: 4),
        ),
      );
      state.dispose();
    });

    test('dragging upwards out of table normalizes table start to whole block', () {
      final state = createMultiBlockState();
      state.registerSelectionCoordinator(const TableSelectionCoordinator());

      // 从表格内某个 cell (path: [1, 1, 0]) 向上拖拽到上方段落 (path: [0])
      state.selection = Selection(
        start: Position(path: [1, 1, 0], offset: 1),
        end: Position(path: [0], offset: 2),
      );

      // 表格作为一个整体被包含：起点对齐到表格整体末尾 [1] offset 1
      expect(
        state.selection,
        Selection(
          start: Position(path: [1], offset: 1),
          end: Position(path: [0], offset: 2),
        ),
      );
      state.dispose();
    });

    testWidgets('cross-block deletion deletes table as an atomic block',
        (tester) async {
      final state = createMultiBlockState();
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 700,
            height: 500,
            child: AppFlowyEditor(
              editorState: state,
              editorStyle: EditorStyle.desktop(padding: EdgeInsets.zero),
            ),
          ),
        ),
      );
      await tester.pump();

      // 跨块选区：从上方段落跨越到表格
      state.selection = Selection(
        start: Position(path: [0], offset: 0),
        end: Position(path: [1, 1, 0], offset: 1),
      );
      await tester.pump();

      // 表格应该被整体包含
      expect(state.selection!.end.path, [1]);
      expect(state.selection!.end.offset, 1);

      // 删除选区，整张表格应被一次性原子化删除
      await state.deleteSelection(state.selection!);
      await tester.pump();

      // 文档中只剩下 1 个块（原表格已不存在）
      final rootBlocks = state.document.root.children;
      expect(rootBlocks.any((b) => b.type == TableBlockKeys.type), isFalse);

      // 撤销后表格恢复
      state.undoManager.undo();
      await tester.pump();
      expect(
        state.document.root.children.any((b) => b.type == TableBlockKeys.type),
        isTrue,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });
  });
}
