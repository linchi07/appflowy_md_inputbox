import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('editor right click uses the shared menu and restores focus',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final controller = MDEditorController();
    final focus = FocusNode();
    await controller.setText('Editor context menu');
    await tester.pumpWidget(
      MaterialApp(home: MDEditor(controller: controller, focusNode: focus)),
    );
    focus.requestFocus();
    controller.editorState.updateSelectionWithReason(
      Selection.single(path: [0], startOffset: 0, endOffset: 6),
      reason: SelectionUpdateReason.uiEvent,
    );
    await tester.pump();
    await tester.pump();
    final rect = tester.getRect(find.byType(AppFlowyRichText));
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.down(rect.topLeft + const Offset(16, 10));
    await mouse.up();
    await tester.pumpAndSettle();

    expect(find.byType(ContextMenu), findsOneWidget);
    expect(find.byType(EditorMenuSurface), findsOneWidget);
    expect(find.byType(EditorMenuItem), findsNWidgets(3));
    expect(find.byType(InkWell), findsNothing);
    final surface = tester.element(find.byType(EditorMenuSurface));
    expect(
      EditorMenuSurface.decoration(surface).color,
      const EditorColorScheme.light().surface,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(ContextMenu), findsNothing);
    expect(
      controller.editorState.selection,
      Selection.single(path: [0], startOffset: 0, endOffset: 6),
    );
    expect(focus.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    focus.dispose();
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('input clipboard actions use the shared surface', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final controller = TextEditingController(text: 'Search text');
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    const colors = EditorColorScheme.dark();
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: EditorTheme(
            colors: colors,
            child: SizedBox(
              width: 240,
              child:
                  EditorMenuTextField(controller: controller, autofocus: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 6);
    await tester.pump();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    editable.showToolbar();
    await tester.pumpAndSettle();
    expect(find.byType(EditorMenuSurface), findsOneWidget);
    expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
    final surface = tester.element(find.byType(EditorMenuSurface));
    expect(EditorMenuSurface.decoration(surface).color, colors.surface);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(find.byType(EditorMenuSurface), findsNothing);
    expect(copied, 'Search');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
