import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/render/selection/cursor.dart'
    as editor_cursor;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desktop collapsed selection renders a visible cursor',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final controller = MDEditorController();
    final focusNode = FocusNode();
    await controller.setText('desktop cursor');

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 600,
          height: 200,
          child: MDEditor(
            controller: controller,
            focusNode: focusNode,
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    controller.editorState.updateSelectionWithReason(
      Selection.single(path: [0], startOffset: 7),
      reason: SelectionUpdateReason.uiEvent,
    );
    await tester.pump();
    await tester.pump();

    final cursorFinder = find.byType(editor_cursor.Cursor);
    expect(cursorFinder, findsOneWidget);
    final cursor = tester.widget<editor_cursor.Cursor>(cursorFinder);
    expect(cursor.rect, isNot(Rect.zero));
    expect(cursor.color.a, greaterThan(0));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    focusNode.dispose();
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop focus switch leaves one cursor in the active editor',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final first = MDEditorController();
    final second = MDEditorController();
    final firstFocus = FocusNode();
    final secondFocus = FocusNode();
    await first.setText('first editor');
    await second.setText('second editor');

    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            Expanded(
              child: MDEditor(
                controller: first,
                focusNode: firstFocus,
                frontGroundColor: Colors.red,
              ),
            ),
            Expanded(
              child: MDEditor(
                controller: second,
                focusNode: secondFocus,
                frontGroundColor: Colors.blue,
              ),
            ),
          ],
        ),
      ),
    );

    expect(find.byType(editor_cursor.Cursor), findsNothing);

    firstFocus.requestFocus();
    first.editorState.updateSelectionWithReason(
      Selection.single(path: [0], startOffset: 2),
      reason: SelectionUpdateReason.uiEvent,
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(editor_cursor.Cursor), findsOneWidget);

    secondFocus.requestFocus();
    await tester.pump();
    second.editorState.updateSelectionWithReason(
      Selection.single(path: [0], startOffset: 3),
      reason: SelectionUpdateReason.uiEvent,
    );
    await tester.pump();
    await tester.pump();

    expect(first.editorState.selection, isNull);
    final cursorFinder = find.byType(editor_cursor.Cursor);
    expect(cursorFinder, findsOneWidget);
    expect(
      tester.widget<editor_cursor.Cursor>(cursorFinder).color,
      Colors.blue,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    firstFocus.dispose();
    secondFocus.dispose();
    first.dispose();
    second.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
