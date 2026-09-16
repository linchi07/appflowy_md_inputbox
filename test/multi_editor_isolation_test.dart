import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/editor_component/service/ime/non_delta_input_service.dart';
import 'package:appflowy_editor/src/render/selection/mobile_collapsed_handle.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mobile IME debounce is isolated per editor', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final firstInsertions = <String>[];
    final secondInsertions = <String>[];
    final first = _textInputService(firstInsertions);
    final second = _textInputService(secondInsertions);
    first.currentTextEditingValue = const TextEditingValue(
      text: ' a',
      selection: TextSelection.collapsed(offset: 2),
    );
    second.currentTextEditingValue = const TextEditingValue(
      text: ' b',
      selection: TextSelection.collapsed(offset: 2),
    );

    first.updateEditingValue(
      const TextEditingValue(
        text: ' ax',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    second.updateEditingValue(
      const TextEditingValue(
        text: ' by',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );

    await tester.pump(const Duration(milliseconds: 11));

    expect(firstInsertions, ['x']);
    expect(secondInsertions, ['y']);

    first.close();
    second.close();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('two mobile editors own independent collapsed handle keys',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final first = EditorState.blank();
    final second = EditorState.blank();

    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            SizedBox(
              height: 100,
              child: AppFlowyEditor(
                editorState: first,
                editorStyle: EditorStyle.mobile(padding: EdgeInsets.zero),
                disableKeyboardService: true,
                shrinkWrap: true,
              ),
            ),
            SizedBox(
              height: 100,
              child: AppFlowyEditor(
                editorState: second,
                editorStyle: EditorStyle.mobile(padding: EdgeInsets.zero),
                disableKeyboardService: true,
                shrinkWrap: true,
              ),
            ),
          ],
        ),
      ),
    );

    first.updateSelectionWithReason(
      Selection.single(path: [0], startOffset: 0),
      reason: SelectionUpdateReason.uiEvent,
    );
    second.updateSelectionWithReason(
      Selection.single(path: [0], startOffset: 0),
      reason: SelectionUpdateReason.uiEvent,
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(MobileCollapsedHandle), findsNWidgets(2));
    final firstSelectionService =
        first.service.selectionService as MobileSelectionServiceControl;
    final secondSelectionService =
        second.service.selectionService as MobileSelectionServiceControl;
    expect(
      firstSelectionService.collapsedHandleKey,
      isNot(same(secondSelectionService.collapsedHandleKey)),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    first.dispose();
    second.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('closing an overlay restores only its owning editor focus',
      (tester) async {
    final first = EditorState.blank();
    final second = EditorState.blank();
    final firstFocus = FocusNode();
    final secondFocus = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            Expanded(
              child: AppFlowyEditor(
                editorState: first,
                focusNode: firstFocus,
              ),
            ),
            Expanded(
              child: AppFlowyEditor(
                editorState: second,
                focusNode: secondFocus,
              ),
            ),
          ],
        ),
      ),
    );

    secondFocus.requestFocus();
    await tester.pump();
    expect(secondFocus.hasFocus, isTrue);

    first.keepEditorFocusNotifier
      ..increase()
      ..decrease();
    await tester.pump();

    expect(firstFocus.hasFocus, isTrue);
    expect(secondFocus.hasFocus, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    firstFocus.dispose();
    secondFocus.dispose();
    first.dispose();
    second.dispose();
  });
}

NonDeltaTextInputService _textInputService(List<String> insertions) =>
    NonDeltaTextInputService(
      onInsert: (delta) async {
        insertions.add(delta.textInserted);
        return true;
      },
      onDelete: (_) async => true,
      onReplace: (_) async => true,
      onNonTextUpdate: (_) async => true,
      onPerformAction: (_) async {},
    );
