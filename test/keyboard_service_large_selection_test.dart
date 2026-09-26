import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/editor_component/service/ime/non_delta_input_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('select all attaches complete multi-block text to the IME',
      (tester) async {
    final controller = MDEditorController.largeDocument();
    final lines = List.generate(
      5000,
      (index) => 'paragraph $index'.padRight(199, 'x'),
    );
    await tester.runAsync(() => controller.setText(lines.join('\n')));

    await tester.pumpWidget(
      MaterialApp(
        home: MDEditor(
          controller: controller,
          shrinkWrap: false,
          maxHeight: 300,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = controller.editorState;
    state.selection = Selection.single(path: [0], startOffset: 0);
    selectAllCommand.handler(state);

    final keyboard = tester.state<KeyboardServiceWidgetState>(
      find.byType(KeyboardServiceWidget),
    );
    final input = keyboard.textInputService as NonDeltaTextInputService;
    expect(input.currentTextEditingValue?.text, ' ${lines.join('\n')}');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
