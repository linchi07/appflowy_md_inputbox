import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/service/markdown_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:node_code_editor/node_code_editor.dart';

void main() {
  test('code editing rules pair JSON brackets and indent YAML', () {
    expect(codeEditForInsertion('{', 1, '\n', 'json')?.text, '\n');
    expect(codeEditForInsertion('{}', 1, '\n', 'json')?.text, '\n  \n');
    expect(codeEditForInsertion('', 0, '{', 'json')?.text, '{}');
    expect(codeEditForInsertion('}', 0, '}', 'json')?.caretOffset, 1);
    expect(codeEditForInsertion('key:', 4, '\n', 'yaml')?.text, '\n  ');
    expect(codeCompletionSuffix('{"ok": tr', 'json'), 'ue');
  });

  test('highlighter preserves offsets and recognizes JSON keys', () {
    const source = '{"name": true, "count": 2}';
    final tokens = CodeHighlighter().tokenize(source, 'json');
    expect(tokens.first.kind, CodeTokenKind.key);
    expect(source.substring(tokens.first.start, tokens.first.end), '"name"');
    expect(tokens.any((token) => token.kind == CodeTokenKind.keyword), isTrue);
    expect(tokens.any((token) => token.kind == CodeTokenKind.number), isTrue);
  });

  test('AppFlowy shortcuts edit code and accept ghost completion', () async {
    final node = codeBlockNode(code: '{"ok": tr', language: 'json');
    final state =
        EditorState(document: Document(root: pageNode(children: [node])))
          ..selection = Selection.collapsed(Position(path: [0], offset: 9));
    expect(tabToAutoCompleteCommand.execute(state), KeyEventResult.handled);
    await Future<void>.delayed(Duration.zero);
    expect(node.delta?.toPlainText(), '{"ok": true');

    state.selection = Selection.collapsed(Position(path: [0], offset: 0));
    expect(
      await codeCharacterShortcut.executeWithCharacter(state, '{'),
      isTrue,
    );
    expect(node.delta?.toPlainText().startsWith('{}'), isTrue);
    expect(state.selection?.start.offset, 1);

    expect(codeExitCommand.execute(state), KeyEventResult.handled);
    await Future<void>.delayed(Duration.zero);
    expect(state.document.root.children.last.type, ParagraphBlockKeys.type);
    state.dispose();
  });

  test('AppFlowy newline shortcut indents YAML in one transaction', () async {
    final node = codeBlockNode(code: 'key:', language: 'yaml');
    final state =
        EditorState(document: Document(root: pageNode(children: [node])))
          ..selection = Selection.collapsed(Position(path: [0], offset: 4));
    expect(
      await codeCharacterShortcut.executeWithCharacter(state, '\n'),
      isTrue,
    );
    expect(node.delta?.toPlainText(), 'key:\n  ');
    expect(state.selection?.start.offset, 7);
    state.dispose();
  });

  test('a 64 KiB paste skips code fence parsing', () {
    final source = '```json\n${'x' * (64 * 1024)}\n```';
    final nodes = parseMarkdownToNodes(source);
    expect(nodes.where((node) => node.type == CodeBlockKeys.type), isEmpty);
  });

  test('a lone opening fence remains an exact paragraph', () {
    final nodes = parseMarkdownToNodes('```json');
    expect(nodes.single.type, ParagraphBlockKeys.type);
    expect(nodes.single.delta?.toPlainText(), '```json');
  });

  test('code node language metadata round-trips through Markdown', () async {
    final state = EditorState.blank();
    await state.setText('```yaml\nkey: value\n```');
    final node = state.document.root.children.single;
    expect(node.type, CodeBlockKeys.type);
    expect(state.text, '```yaml\nkey: value\n```');
    await state.apply(
      state.transaction
        ..updateNode(node, {
          CodeBlockKeys.language: 'json',
          CodeBlockKeys.openingFence: '```json',
        }),
    );
    expect(state.text, '```json\nkey: value\n```');
    state.dispose();
  });

  test('pasting a code node into a paragraph keeps the boundaries', () async {
    final state = EditorState.blank();
    await state.setText('before after');
    state.selection = Selection.collapsed(Position(path: [0], offset: 7));
    await state.pastePlainText('```json\n{"ok": true}\n```');
    final nodes = state.document.root.children;
    expect(nodes.map((node) => node.type), [
      ParagraphBlockKeys.type,
      CodeBlockKeys.type,
      ParagraphBlockKeys.type,
    ]);
    expect(nodes[1].delta?.toPlainText(), '{"ok": true}');
    expect(state.text, 'before \n```json\n{"ok": true}\n```\nafter');
    state.dispose();
  });

  testWidgets('code block uses native rich text and syntax colors',
      (tester) async {
    final controller = MDEditorController();
    await controller.setText('```json\n{"ok": true}\n```');
    await tester.pumpWidget(
      MaterialApp(
        home: MDEditor(
          controller: controller,
          editable: false,
        ),
      ),
    );
    await tester.pump();
    expect(
      controller.editorState.document.root.children.single.type,
      CodeBlockKeys.type,
    );
    expect(find.byType(AppFlowyRichText), findsOneWidget);
    expect(find.byKey(markdownCodeBlockKey), findsOneWidget);
    final richText = tester
        .widgetList<RichText>(
          find.descendant(
            of: find.byType(AppFlowyRichText),
            matching: find.byType(RichText),
          ),
        )
        .firstWhere((widget) => widget.text.toPlainText() == '{"ok": true}');
    final spans = <TextSpan>[];
    void collect(InlineSpan span) {
      if (span is TextSpan) {
        spans.add(span);
        for (final child in span.children ?? const <InlineSpan>[]) {
          collect(child);
        }
      }
    }

    collect(richText.text);
    expect(
      spans.any(
        (span) =>
            span.text == '"ok"' && span.style?.color == const Color(0xFF006D77),
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('typing a fence converts a paragraph into a code node',
      (tester) async {
    final controller = MDEditorController();
    final paragraph = controller.editorState.document.root.children.first;
    paragraph.updateAttributes({
      blockComponentDelta: (Delta()..insert('```json\n{"a": 1}')).toJson(),
    });
    await tester.pumpWidget(
      MaterialApp(
        home: MDEditor(
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      controller.editorState.document.root.children.single.type,
      CodeBlockKeys.type,
    );
    expect(controller.text, '```json\n{"a": 1}');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
