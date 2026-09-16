import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/editor_component/service/ime/non_delta_input_service.dart';
import 'package:appflowy_editor/src/editor/editor_component/service/selection/mobile_magnifier.dart';
import 'package:appflowy_editor/src/render/selection/mobile_selection_handle.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void useAndroidTargetPlatform() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  }

  testWidgets('MDEditor restores mobile selection visuals', (tester) async {
    useAndroidTargetPlatform();
    final controller = MDEditorController(initialText: '中文输入测试');

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 200,
          child: MDEditor(controller: controller),
        ),
      ),
    );
    await tester.pump();

    final editor = tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor));
    expect(editor.showMagnifier, isTrue);
    expect(editor.editorStyle.magnifierSize, const Size(72, 48));
    expect(editor.editorStyle.mobileDragHandleBallSize, const Size(8, 8));
    expect(editor.editorStyle.dragHandleColor, isNot(Colors.transparent));

    final text = find.byType(AppFlowyRichText);
    final gesture = await tester.startGesture(tester.getCenter(text));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();

    expect(find.byType(MobileMagnifier), findsOneWidget);
    expect(find.byType(MobileSelectionHandle), findsNWidgets(2));

    await gesture.up();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a mobile selection change finishes active IME composition',
      (tester) async {
    useAndroidTargetPlatform();
    final controller = MDEditorController(initialText: 'ni中文');

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 200,
          child: MDEditor(controller: controller),
        ),
      ),
    );
    await tester.pump();

    final keyboardState = tester.state<KeyboardServiceWidgetState>(
      find.byType(KeyboardServiceWidget),
    );
    final textInputService =
        keyboardState.textInputService as NonDeltaTextInputService;
    textInputService.composingTextRange = const TextRange(start: 0, end: 2);

    controller.editorState.updateSelectionWithReason(
      Selection.single(path: [0], startOffset: 3),
      reason: SelectionUpdateReason.uiEvent,
      customSelectionType: SelectionType.inline,
    );

    expect(
      textInputService.composingTextRange,
      TextRange.empty,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('MDEditor can still explicitly disable the magnifier',
      (tester) async {
    useAndroidTargetPlatform();
    final controller = MDEditorController(initialText: 'text');

    await tester.pumpWidget(
      MaterialApp(
        home: MDEditor(
          controller: controller,
          showMagnifier: false,
        ),
      ),
    );

    final editor = tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor));
    expect(editor.showMagnifier, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
