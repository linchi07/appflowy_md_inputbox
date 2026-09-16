import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/rich_text/markdown_decorator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selection-only rebuilds reuse Markdown lexical matches',
      (tester) async {
    clearMarkdownLexicalCache();
    final controller = MDEditorController();
    await controller.setText('**cache me** and #tag');

    await tester.pumpWidget(
      MaterialApp(home: MDEditor(controller: controller)),
    );
    await tester.pump();
    final scansAfterFirstBuild = markdownLexicalScanCount;
    expect(scansAfterFirstBuild, greaterThan(0));

    controller.editorState.updateSelectionWithReason(
      Selection.single(path: [0], startOffset: 3),
      reason: SelectionUpdateReason.uiEvent,
    );
    await tester.pump();
    controller.editorState.updateSelectionWithReason(
      Selection.single(path: [0], startOffset: 8),
      reason: SelectionUpdateReason.uiEvent,
    );
    await tester.pump();

    expect(markdownLexicalScanCount, scansAfterFirstBuild);

    final node = controller.editorState.document.root.children.single;
    await controller.editorState.apply(
      controller.editorState.transaction..insertText(node, 5, '!'),
    );
    await tester.pump();
    expect(markdownLexicalScanCount, scansAfterFirstBuild + 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    controller.dispose();
  });

  testWidgets('oversized paragraphs bypass rich Markdown decoration',
      (tester) async {
    clearMarkdownLexicalCache();
    final source = '**${List.filled(512, '中').join()}**';
    final controller = MDEditorController();
    await controller.setText(source);

    await tester.pumpWidget(
      MaterialApp(
        home: MDEditor(
          controller: controller,
          maxMarkdownDecorationCharacters: 128,
        ),
      ),
    );
    await tester.pump();

    expect(markdownLexicalScanCount, 0);
    expect(controller.text, source);
    final editor = tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor));
    expect(editor.editorStyle.maxMarkdownDecorationCharacters, 128);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    controller.dispose();
  });

  testWidgets('markup-dense paragraphs use the plain-text safety path',
      (tester) async {
    clearMarkdownLexicalCache();
    final source = List.filled(600, '[ ]').join(' ');
    final controller = MDEditorController();
    final node = controller.editorState.document.root.children.single;
    node.updateAttributes({
      'delta': (Delta()..insert(source)).toJson(),
    });

    await tester.pumpWidget(
      MaterialApp(home: MDEditor(controller: controller)),
    );
    await tester.pump();

    expect(markdownLexicalScanCount, 1);
    expect(controller.text, source);
    expect(find.byType(Checkbox), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    controller.dispose();
  });
}
