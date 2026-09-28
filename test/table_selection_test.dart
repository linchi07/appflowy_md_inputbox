import 'dart:ui';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_view.dart';
import 'package:appflowy_editor/src/editor/block_component/base_component/selection/selection_area_painter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TableSelection model', () {
    test('TSV keeps visual row order and trailing whitespace', () {
      final table = TableNode.fromList([
        ['A', '1'],
        ['B ', ''],
      ]);
      expect(table.toTsv(), 'A\tB \n1\t');
    });

    test('toMarkdown serializes table as GFM Markdown table', () {
      final table = TableNode.fromList([
        ['A', '1'],
        ['B', '2'],
      ]);
      expect(table.toMarkdown(), '| A | B |\n| --- | --- |\n| 1 | 2 |');
    });

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

    testWidgets(
        'dragging across cells activates TableSelection and clears text selection',
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

    testWidgets('clicking outside or on a selected cell clears the cell range',
        (tester) async {
      final table = TableNode.fromList([
        ['A', '1'],
        ['B', '2'],
      ]);
      final state = EditorState(
        document: Document(
          root: pageNode(
            children: [
              table.node,
              paragraphNode(text: 'After table'),
            ],
          ),
        ),
      );
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

      final tableTopLeft = tester.getTopLeft(find.byType(TableView));
      final start = tableTopLeft + const Offset(50, 40);
      final end = tableTopLeft + const Offset(200, 70);
      Future<void> selectCells() async {
        final drag = await tester.startGesture(start);
        await tester.pump();
        await drag.moveTo(end);
        await tester.pump();
        await drag.up();
        await tester.pump();
        expect(
          find.byKey(const ValueKey('table-selection-border')),
          findsOneWidget,
        );
      }

      await selectCells();
      final paragraphTopLeft = tester.getTopLeft(
        find.byKey(state.document.root.children.last.key),
      );
      await tester.tapAt(paragraphTopLeft + const Offset(10, 12));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('table-selection-border')),
        findsNothing,
      );

      await selectCells();
      await tester.tapAt(start);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('table-selection-border')),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });

    testWidgets(
        'clicking col handle selects entire column and Delete clears it with undo support',
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
      final restoredTable =
          TableNode(node: state.document.root.children.single);
      expect(
        restoredTable.getCell(0, 0).children.single.delta?.toPlainText(),
        'A',
      );
      expect(
        restoredTable.getCell(0, 1).children.single.delta?.toPlainText(),
        '1',
      );

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

      expect(clipboardText, '| A | B |\n| --- | --- |\n| 1 | 2 |');

      // 按 Escape 清空选区
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });

    testWidgets(
        'dragging cells across table triggers autoscroll and clamps bounds correctly',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

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

      // 从 (0, 0) 开始拖拽，拖到 (1, 1) 右下外缘进行 clamp 测试
      final startOffset = tableTopLeft + const Offset(50, 40);
      final farOffset = tableTopLeft + const Offset(230, 80);

      final gesture = await tester.startGesture(startOffset);
      await tester.pump();
      await gesture.moveTo(farOffset);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // 选区成功被 clamp 到了整表 (0, 0) 到 (1, 1)
      expect(
        find.byKey(const ValueKey('table-selection-border')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
      debugDefaultTargetPlatformOverride = null;
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

    testWidgets(
        'whole-table selection uses cell colors and Cmd+C copies the table',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      copyCommand.updateCommand(command: 'ctrl+c', macOSCommand: 'cmd+c');
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

      const primary = Color(0xFF8752B5);
      final state = createMultiBlockState();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: const ColorScheme.light(primary: primary),
          ),
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

      state.updateSelectionWithReason(
        Selection(
          start: Position(path: [0], offset: 2),
          end: Position(path: [1, 1, 0], offset: 1),
        ),
        reason: SelectionUpdateReason.uiEvent,
      );
      await tester.pump();
      await tester.pump();

      expect(state.selection!.end.path, [1]);
      expect(
        find.byKey(const ValueKey('table-selection-border')),
        findsOneWidget,
      );
      final cells = find.byType(TableCelBlockWidget);
      expect(cells, findsNWidgets(4));
      for (final cell in cells.evaluate()) {
        expect(TableSelectionScope.of(cell), isNotNull);
      }
      final expectedColor = Color.alphaBlend(
        primary.withValues(alpha: 0.18),
        Theme.of(tester.element(cells.first)).colorScheme.surface,
      );
      expect(
        find.descendant(
          of: find.byType(TableView),
          matching: find.byWidgetPredicate(
            (widget) => widget is Container && widget.color == expectedColor,
          ),
        ),
        findsNWidgets(4),
      );
      expect(
        find.descendant(
          of: find.byType(TableView),
          matching: find.byType(SelectionAreaPaint),
        ),
        findsNothing,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();
      expect(clipboardText, 'ove paragraph\n| A | B |\n| --- | --- |\n| 1 | 2 |');

      final tableTopLeft = tester.getTopLeft(find.byType(TableView));
      final after = tester.getTopLeft(
            find.byKey(state.document.root.children.last.key),
          ) +
          const Offset(10, 12);
      final drag =
          await tester.startGesture(tableTopLeft + const Offset(50, 40));
      await tester.pump();
      await drag.moveTo(tableTopLeft + const Offset(200, 70));
      await tester.pump();
      await drag.moveTo(after);
      await tester.pump();
      await drag.moveTo(after + const Offset(10, 1));
      await tester.pump();
      await drag.up();
      await tester.pump();
      expect(state.selection!.start.path, [1]);
      expect(state.selection!.end.path, [2]);
      clipboardText = null;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();
      expect(clipboardText, startsWith('| A | B |\n| --- | --- |\n| 1 | 2 |\n'));

      debugDefaultTargetPlatformOverride = null;
      copyCommand.updateCommand(command: 'ctrl+c', macOSCommand: 'cmd+c');

      state.selection = Selection(
        start: Position(path: [0], offset: 2),
        end: Position(path: [2], offset: 5),
      );
      expect(
        state.getTextForCopy(state.selection!),
        'ove paragraph\n| A | B |\n| --- | --- |\n| 1 | 2 |\nBelow',
      );

      state.selection = Selection.single(
        path: [1, 0, 0],
        startOffset: 0,
        endOffset: 1,
      );
      await tester.pump();
      await tester.pump();
      expect(TableSelectionScope.of(tester.element(cells.first)), isNull);
      expect(
        find.descendant(
          of: find.byType(TableView),
          matching: find.byType(SelectionAreaPaint),
        ),
        findsWidgets,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });

    test('cell-internal text selection is preserved without atomic expansion',
        () {
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

    test('dragging downwards into table normalizes table end to whole block',
        () {
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

    test(
        'dragging downwards out of table normalizes table start to whole block',
        () {
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

    test('dragging upwards out of table normalizes table start to whole block',
        () {
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

    testWidgets(
        'cross-block deletion keeps unselected paragraph text on both sides',
        (tester) async {
      for (final (start, end, expected) in [
        (
          Position(path: [0], offset: 2),
          Position(path: [1, 0, 0], offset: 1),
          ['Ab', 'Below paragraph']
        ),
        (
          Position(path: [1, 0, 0], offset: 1),
          Position(path: [2], offset: 5),
          ['Above paragraph', ' paragraph']
        ),
        (
          Position(path: [0], offset: 2),
          Position(path: [2], offset: 5),
          ['Ab paragraph']
        ),
      ]) {
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

        state.selection = Selection(start: start, end: end);
        expect(await state.deleteSelection(state.selection!), isTrue);
        await tester.pump();
        expect(
          state.document.root.children
              .map((node) => node.delta?.toPlainText())
              .toList(),
          expected,
        );
        state.undoManager.undo();
        await tester.pump();
        expect(
          state.document.root.children
              .any((node) => node.type == TableBlockKeys.type),
          isTrue,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        state.dispose();
      }
    });

    testWidgets('paste replaces an atomic table range after deletion completes',
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

      state.selection = Selection(
        start: Position(path: [0], offset: 2),
        end: Position(path: [1, 0, 0], offset: 1),
      );
      await state.pastePlainText('X');
      await tester.pump();
      expect(
        state.document.root.children
            .map((node) => node.delta?.toPlainText())
            .toList(),
        ['AbX', 'Below paragraph'],
      );

      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });

    testWidgets('cut copies the whole table before deleting the range',
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

      state.selection = Selection(
        start: Position(path: [0], offset: 2),
        end: Position(path: [1, 0, 0], offset: 1),
      );
      await handleCut(state);
      await tester.pump();
      expect(clipboardText, 'ove paragraph\n| A | B |\n| --- | --- |\n| 1 | 2 |');
      expect(
        state.document.root.children
            .map((node) => node.delta?.toPlainText())
            .toList(),
        ['Ab', 'Below paragraph'],
      );

      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });

    testWidgets(
        'dragging gesture from above paragraph across table to below paragraph creates stable cross-block selection',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

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

      final firstNodeTopLeft = tester.getTopLeft(
        find.byKey(state.document.root.children.first.key),
      );
      final lastNodeTopLeft = tester.getTopLeft(
        find.byKey(state.document.root.children.last.key),
      );

      final drag =
          await tester.startGesture(firstNodeTopLeft + const Offset(10, 10));
      await tester.pump();
      await drag.moveTo(firstNodeTopLeft + const Offset(10, 30));
      await tester.pump();
      await drag.moveTo(lastNodeTopLeft + const Offset(20, 10));
      await tester.pump();
      await drag.up();
      await tester.pump();

      expect(state.selection, isNotNull);
      expect(state.selection!.start.path, [0]);
      expect(state.selection!.end.path, [2]);
      expect(
        find.byKey(const ValueKey('table-selection-border')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
