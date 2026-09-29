import 'dart:ui';
import 'package:flutter/gestures.dart';
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
      final endOffset = tableTopLeft + const Offset(222, 70);

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
      final end = tableTopLeft + const Offset(222, 70);
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
        'clicking col x button deletes the entire column and can be undone',
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

      final colDeleteBtn = find.descendant(
        of: colHandle,
        matching: find.byIcon(Icons.close),
      );
      expect(colDeleteBtn, findsOneWidget);
      final colPaletteBtn = find.descendant(
        of: colHandle,
        matching: find.byIcon(Icons.palette_outlined),
      );
      expect(colPaletteBtn, findsOneWidget);

      await tester.tap(colDeleteBtn);
      await tester.pump();

      // 点击 x 按钮后，第 0 列已被完整删除，表格变为 1 列
      final table = TableNode(node: state.document.root.children.single);
      expect(table.colsLen, 1);
      // 原第 1 列（B, 2）成为当前第 0 列
      expect(table.getCell(0, 0).children.single.delta?.toPlainText(), 'B');
      expect(table.getCell(0, 1).children.single.delta?.toPlainText(), '2');

      // 撤销验证
      state.undoManager.undo();
      await tester.pump();
      final restoredTable =
          TableNode(node: state.document.root.children.single);
      expect(restoredTable.colsLen, 2);
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

    testWidgets(
        'clicking row x button deletes the entire row and can be undone',
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

      // 悬浮在第 0 行 handle 区域
      final row0Height =
          TableNode(node: state.document.root.children.single).getRowHeight(0);
      final row0CenterY = 26.0 + 1.0 + row0Height / 2;
      await mouse.moveTo(tableTopLeft + Offset(12, row0CenterY));
      await tester.pump();

      final rowHandle = find.byKey(const ValueKey('table-row-handle-0'));
      expect(rowHandle, findsOneWidget);

      final rowDeleteBtn = find.descendant(
        of: rowHandle,
        matching: find.byIcon(Icons.close),
      );
      expect(rowDeleteBtn, findsOneWidget);
      final rowPaletteBtn = find.descendant(
        of: rowHandle,
        matching: find.byIcon(Icons.palette_outlined),
      );
      expect(rowPaletteBtn, findsOneWidget);

      await tester.tap(rowDeleteBtn);
      await tester.pump();

      // 点击 x 按钮后，第 0 行已被完整删除，表格变为 1 行
      final table = TableNode(node: state.document.root.children.single);
      expect(table.rowsLen, 1);
      // 原第 1 行（1, 2）成为当前第 0 行
      expect(table.getCell(0, 0).children.single.delta?.toPlainText(), '1');
      expect(table.getCell(1, 0).children.single.delta?.toPlainText(), '2');

      // 撤销验证
      state.undoManager.undo();
      await tester.pump();
      final restoredTable =
          TableNode(node: state.document.root.children.single);
      expect(restoredTable.rowsLen, 2);
      expect(
        restoredTable.getCell(0, 0).children.single.delta?.toPlainText(),
        'A',
      );
      expect(
        restoredTable.getCell(1, 0).children.single.delta?.toPlainText(),
        'B',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });

    testWidgets(
        'clicking palette button opens color menu and sets column background color',
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

      // 悬浮在第 0 列 handle 区域
      await mouse.moveTo(tableTopLeft + const Offset(114, 12));
      await tester.pump();

      final colPaletteBtn = find.byKey(const ValueKey('table-col-color-0'));
      expect(colPaletteBtn, findsOneWidget);

      await tester.tap(colPaletteBtn);
      await tester.pumpAndSettle();

      // 调色板使用与表格其他操作相同的菜单界面。
      final firstColor = generateHighlightColorOptions().first;
      expect(find.text(firstColor.name), findsOneWidget);
      await tester.tap(find.text(firstColor.name));
      await tester.pumpAndSettle();

      // 验证第 0 列背景颜色已设置
      final table = TableNode(node: state.document.root.children.single);
      final cell0 = table.getCell(0, 0);
      expect(
        cell0.attributes[TableCellBlockKeys.colBackgroundColor],
        firstColor.colorHex,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });

    testWidgets('row palette stays visible while the mouse moves onto it',
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
      final rowHeight =
          TableNode(node: state.document.root.children.single).getRowHeight(0);
      final rowCenterY = 26.0 + 1.0 + rowHeight / 2;

      await mouse.moveTo(tableTopLeft + Offset(30, rowCenterY));
      await tester.pump();
      final palette = find.byKey(const ValueKey('table-row-color-0'));
      expect(palette, findsOneWidget);

      final paletteCenter = tester.getCenter(palette);
      await mouse.moveTo(paletteCenter);
      await tester.pump();
      expect(palette, findsOneWidget);

      await mouse.down(paletteCenter);
      await mouse.up();
      await tester.pumpAndSettle();
      expect(
        find.text(generateHighlightColorOptions().first.name),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });

    testWidgets('row action menu can open its color submenu', (tester) async {
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
      final rowHeight =
          TableNode(node: state.document.root.children.single).getRowHeight(0);
      await mouse.moveTo(tableTopLeft + Offset(30, 27 + rowHeight / 2));
      await tester.pump();
      final palette = find.byKey(const ValueKey('table-row-color-0'));
      expect(palette, findsOneWidget);
      await tester.tapAt(
        tester.getCenter(palette),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();

      await tester.tap(find.text(AppFlowyEditorL10n.current.backgroundColor));
      await tester.pump();
      expect(
        find.text(generateHighlightColorOptions().first.name),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });

    testWidgets('table menus accept entries from the shared menu interface',
        (tester) async {
      final state = createTableState();
      var selected = false;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 700,
            height: 400,
            child: AppFlowyEditor(
              editorState: state,
              editorStyle: EditorStyle.desktop(padding: EdgeInsets.zero),
              blockComponentBuilders: {
                ...standardBlockComponentBuilderMap,
                TableBlockKeys.type: TableBlockComponentBuilder(
                  menuEntriesBuilder:
                      (node, editorState, position, direction) => [
                    EditorMenuEntry(
                      label: 'Custom table action',
                      onSelected: () => selected = true,
                    ),
                  ],
                ),
              },
            ),
          ),
        ),
      );
      await tester.pump();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      final tableTopLeft = tester.getTopLeft(find.byType(TableView));
      final rowHeight =
          TableNode(node: state.document.root.children.single).getRowHeight(0);
      await mouse.moveTo(tableTopLeft + Offset(30, 27 + rowHeight / 2));
      await tester.pump();
      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('table-row-color-0'))),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      expect(find.text('Custom table action'), findsOneWidget);
      await tester.tap(find.text('Custom table action'));
      await tester.pump();
      expect(selected, isTrue);

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
      final endOffset = tableTopLeft + const Offset(222, 70);

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
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        copyCommand.updateCommand(command: 'ctrl+c', macOSCommand: 'cmd+c');
      });
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
      expect(
          clipboardText, 'ove paragraph\n| A | B |\n| --- | --- |\n| 1 | 2 |');

      final tableTopLeft = tester.getTopLeft(find.byType(TableView));
      final after = tester.getTopLeft(
            find.byKey(state.document.root.children.last.key),
          ) +
          const Offset(10, 12);
      final drag =
          await tester.startGesture(tableTopLeft + const Offset(50, 40));
      await tester.pump();
      await drag.moveTo(tableTopLeft + const Offset(222, 70));
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
      expect(
          clipboardText, startsWith('| A | B |\n| --- | --- |\n| 1 | 2 |\n'));

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
      debugDefaultTargetPlatformOverride = null;
      copyCommand.updateCommand(command: 'ctrl+c', macOSCommand: 'cmd+c');
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
      expect(
          clipboardText, 'ove paragraph\n| A | B |\n| --- | --- |\n| 1 | 2 |');
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

    testWidgets(
        'cmd+c copies active table selection and cmd+x cuts and clears cell contents',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        copyCommand.updateCommand(command: 'ctrl+c', macOSCommand: 'cmd+c');
        cutCommand.updateCommand(command: 'ctrl+x', macOSCommand: 'cmd+x');
      });
      copyCommand.updateCommand(command: 'ctrl+c', macOSCommand: 'cmd+c');
      cutCommand.updateCommand(command: 'ctrl+x', macOSCommand: 'cmd+x');

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

      final tableFinder = find.byType(TableView);
      final tableTopLeft = tester.getTopLeft(tableFinder);

      // 拖拽框选整表单元格
      final drag =
          await tester.startGesture(tableTopLeft + const Offset(50, 40));
      await tester.pump();
      await drag.moveTo(tableTopLeft + const Offset(222, 70));
      await tester.pump();
      await drag.up();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('table-selection-border')),
        findsOneWidget,
      );

      // 测试 Cmd + C
      clipboardText = null;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();

      expect(clipboardText, '| A | B |\n| --- | --- |\n| 1 | 2 |');

      // 测试 Cmd + X
      clipboardText = null;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();

      expect(clipboardText, '| A | B |\n| --- | --- |\n| 1 | 2 |');

      // 验证剪切后单元格内容已被清空
      final tableNode = TableNode(node: state.document.root.children[1]);
      for (var r = 0; r < tableNode.rowsLen; r++) {
        for (var c = 0; c < tableNode.colsLen; c++) {
          final text = tableNode
                  .getCell(c, r)
                  .children
                  .firstOrNull
                  ?.delta
                  ?.toPlainText() ??
              '';
          expect(text, '');
        }
      }

      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
      await tester.pump(const Duration(milliseconds: 600));
      debugDefaultTargetPlatformOverride = null;
      copyCommand.updateCommand(command: 'ctrl+c', macOSCommand: 'cmd+c');
      cutCommand.updateCommand(command: 'ctrl+x', macOSCommand: 'cmd+x');
    });
  });
}
