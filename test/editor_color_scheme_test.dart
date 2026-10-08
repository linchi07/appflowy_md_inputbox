import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('changing primary recalculates dependent defaults', () {
    final colors = const EditorColorScheme.light().copyWith(
      primary: Colors.indigo,
    );
    expect(colors.selection, Colors.indigo.withValues(alpha: 0.14));
    expect(colors.tagBackground, Colors.indigo.withValues(alpha: 0.08));
    expect(colors.onPrimary, Colors.white);
    expect(const EditorColorScheme.dark().onPrimary, Colors.black);
    expect(
      const EditorColorScheme.light()
          .copyWith(brightness: Brightness.dark)
          .syntaxColors,
      const EditorSyntaxColors.dark(),
    );
  });

  testWidgets('editor defaults ignore the host Material palette',
      (tester) async {
    final controller = MDEditorController();
    addTearDown(controller.dispose);

    Future<void> pumpWithHostColor(Color color) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: color),
          ),
          home: MDEditor(controller: controller),
        ),
      );
    }

    await pumpWithHostColor(Colors.red);
    expect(
      controller.editorState.editorStyle.colorScheme,
      const EditorColorScheme.light(),
    );
    expect(
      tester.widget<EditorTheme>(find.byType(EditorTheme)).colors,
      const EditorColorScheme.light(),
    );

    await pumpWithHostColor(Colors.green);
    expect(
      controller.editorState.editorStyle.colorScheme,
      const EditorColorScheme.light(),
    );
  });

  testWidgets('two editors resolve their own explicit palettes',
      (tester) async {
    final first = EditorState.blank();
    final second = EditorState.blank();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    const firstColors = EditorColorScheme.dark(primary: Colors.orange);
    const secondColors = EditorColorScheme.light(primary: Colors.teal);

    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            Expanded(
              child: AppFlowyEditor(
                editorState: first,
                editorStyle: EditorStyle.desktop(colorScheme: firstColors),
                disableKeyboardService: true,
              ),
            ),
            Expanded(
              child: AppFlowyEditor(
                editorState: second,
                editorStyle: EditorStyle.desktop(colorScheme: secondColors),
                disableKeyboardService: true,
              ),
            ),
          ],
        ),
      ),
    );

    expect(first.editorStyle.colorScheme, firstColors);
    expect(first.editorStyle.cursorColor, firstColors.primary);
    expect(second.editorStyle.colorScheme, secondColors);
    expect(second.editorStyle.cursorColor, secondColors.primary);
    expect(
      tester
          .widgetList<EditorTheme>(find.byType(EditorTheme))
          .map((theme) => theme.colors),
      containsAll([firstColors, secondColors]),
    );
  });

  testWidgets('same-brightness palette changes update mounted nodes',
      (tester) async {
    final state = EditorState.blank();
    addTearDown(state.dispose);

    Future<void> pumpWithPrimary(Color primary) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppFlowyEditor(
            editorState: state,
            editorStyle: EditorStyle.desktop(
              colorScheme: EditorColorScheme.light(primary: primary),
            ),
            disableKeyboardService: true,
          ),
        ),
      );
    }

    await pumpWithPrimary(Colors.orange);
    expect(
      tester
          .widget<AppFlowyRichText>(find.byType(AppFlowyRichText))
          .cursorColor,
      Colors.orange,
    );

    await pumpWithPrimary(Colors.purple);
    expect(state.editorStyle.colorScheme.primary, Colors.purple);
    expect(
      tester
          .widget<AppFlowyRichText>(find.byType(AppFlowyRichText))
          .cursorColor,
      Colors.purple,
    );
  });
}
