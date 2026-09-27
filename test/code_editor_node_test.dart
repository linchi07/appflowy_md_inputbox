import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/service/markdown_parser.dart';
import 'package:appflowy_editor/src/editor/editor_component/service/ime/character_shortcut_event_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          ..selection = Selection.collapsed(Position(path: [0], offset: 9))
          ..nodeBehaviors = {CodeBlockKeys.type: codeNodeBehavior};
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

  test('character shortcuts dispatch by node type', () async {
    var invoked = 0;
    final widgetNode = Node(
      type: 'custom_widget',
      attributes: {blockComponentDelta: (Delta()..insert('value')).toJson()},
    );
    final state = EditorState(
      document: Document(root: pageNode(children: [widgetNode])),
    )
      ..selection = Selection.collapsed(Position(path: [0], offset: 5))
      ..nodeBehaviors = {
        'custom_widget': NodeBehavior(
          characterShortcuts: [
            CharacterShortcutEvent(
              key: 'custom exclamation',
              character: '!',
              handler: (_) async {
                invoked++;
                return true;
              },
            ),
          ],
        ),
      };
    expect(await executeCharacterShortcutEvent(state, '!', const []), isTrue);
    expect(invoked, 1);
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
    final state = EditorState.blank()
      ..nodeBehaviors = {CodeBlockKeys.type: codeNodeBehavior};
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
    final state = EditorState.blank()
      ..nodeBehaviors = {CodeBlockKeys.type: codeNodeBehavior};
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

  test('literal paste inside a registered node keeps its contents', () async {
    final node = codeBlockNode(code: 'before', language: 'yaml');
    final state = EditorState(
      document: Document(root: pageNode(children: [node])),
    )
      ..nodeBehaviors = {CodeBlockKeys.type: codeNodeBehavior}
      ..selection = Selection.collapsed(Position(path: [0], offset: 6));

    await state.pastePlainText('\n```json\n{"ok": true}\n```');
    expect(state.document.root.children, hasLength(1));
    expect(node.delta?.toPlainText(), 'before\n```json\n{"ok": true}\n```');
    state.dispose();
  });

  test('text promotion rule supports unrelated widget nodes', () async {
    final state = EditorState.blank()
      ..documentRules = [
        TextNodePromotionRule(
          sourceType: ParagraphBlockKeys.type,
          promote: (node) => node.delta?.toPlainText() == '::widget'
              ? TextNodePromotion(
                  nodes: [Node(type: 'custom_widget')],
                  caretNodeIndex: 0,
                  caretOffset: (_) => 0,
                )
              : null,
        ),
      ];
    final paragraph = state.document.root.children.single;
    await state.apply(
      state.transaction
        ..insertText(paragraph, 0, '::widget')
        ..afterSelection = Selection.collapsed(
          Position(path: [0], offset: 8),
        ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(state.document.root.children.single.type, 'custom_widget');
    state.dispose();
  });

  test('divider promotion runs without a renderer', () async {
    final controller = MDEditorController();
    final state = controller.editorState;
    final paragraph = state.document.root.children.single;
    await state.apply(
      state.transaction
        ..insertText(paragraph, 0, '---')
        ..afterSelection = Selection.collapsed(
          Position(path: [0], offset: 3),
        ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(state.document.root.children.map((node) => node.type), [
      DividerBlockKeys.type,
      ParagraphBlockKeys.type,
    ]);
    expect(state.selection?.start.path, [1]);
    controller.dispose();
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

  testWidgets('code completion uses AppFlowy ghost text', (tester) async {
    final controller = MDEditorController();
    await controller.setText('```json\ntr\n```');
    controller.editorState.selection =
        Selection.collapsed(Position(path: [0], offset: 2));
    await tester.pumpWidget(
      MaterialApp(
        home: MDEditor(controller: controller),
      ),
    );
    await tester.pump();
    final texts = tester.widgetList<RichText>(
      find.descendant(
        of: find.byType(AppFlowyRichText),
        matching: find.byType(RichText),
      ),
    );
    expect(texts.any((widget) => widget.text.toPlainText() == 'true'), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('command shortcuts dispatch to the selected code node',
      (tester) async {
    final controller = MDEditorController();
    await controller.setText('```yaml\nkey:\n```');
    await tester.pumpWidget(
      MaterialApp(home: MDEditor(controller: controller, autoFocus: true)),
    );
    await tester.pumpAndSettle();
    controller.editorState.selection =
        Selection.collapsed(Position(path: [0], offset: 4));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.editorState.document.root.children, hasLength(1));
    expect(
      controller.editorState.document.root.children.single.delta?.toPlainText(),
      'key:\n  ',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('typing a fence converts a paragraph into a code node',
      (tester) async {
    final controller = MDEditorController();
    await tester.pumpWidget(
      MaterialApp(
        home: MDEditor(
          controller: controller,
        ),
      ),
    );
    final paragraph = controller.editorState.document.root.children.first;
    const source = '```json\n{"a": 1}';
    await controller.editorState.apply(
      controller.editorState.transaction
        ..insertText(paragraph, 0, source)
        ..afterSelection = Selection.collapsed(
          Position(
            path: [0],
            offset: source.length,
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
