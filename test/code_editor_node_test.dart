import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/service/markdown_parser.dart';
import 'package:appflowy_editor/src/editor/editor_component/service/ime/character_shortcut_event_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:node_code_editor/node_code_editor.dart';

void main() {
  test('code editing rules pair JSON brackets and indent YAML', () {
    expect(codeEditForInsertion('{', 1, '\n', 'json')?.text, '\n  ');
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

  test('curated grammars remain available with stable offsets', () {
    expect(CodeHighlighter.supportedLanguages.length, 47);
    expect(CodeHighlighter.supportedLanguages,
        containsAll(['dart', 'python', 'json', 'yaml', 'cpp']));
    expect(CodeHighlighter.supportedLanguages, isNot(contains('solidity')));
    for (final (language, source) in [
      ('go', 'package main\nfunc main() {}'),
      ('rust', 'fn main() { let x = 1; }'),
      ('sql', 'SELECT name FROM users;'),
      ('swift', 'let answer = 42'),
    ]) {
      final tokens = CodeHighlighter().tokenize(source, language);
      expect(tokens, isNotEmpty, reason: language);
      expect(
        tokens.every(
          (token) => token.start >= 0 && token.end <= source.length,
        ),
        isTrue,
        reason: language,
      );
    }
  });

  test('unlisted languages use the generic lexer', () {
    const source = 'function greet() { return 42; }';
    final tokens = CodeHighlighter().tokenize(source, 'solidity');
    expect(tokens, isNotEmpty);
    expect(tokens.first.kind, CodeTokenKind.keyword);
    expect(source.substring(tokens.first.start, tokens.first.end), 'function');
  });

  test('grammar words and document identifiers produce Tab suggestions', () {
    expect(codeCompletionSuffix('cla', 'dart'), 'ss');
    expect(codeCompletionSuffix('{"a": key', 'json'), isNull);
    expect(codeCompletionSuffix('calculateTotal\ncal', 'dart'), 'culateTotal');
    expect(codeCompletionSuffix('"cal', 'dart'), isNull);
    expect(codeEditForTab('', 0, 'dart').text, '    ');
    expect(codeEditForTab('    x', 5, 'dart', outdent: true).deleteLength, 4);
  });

  test('common languages pair brackets and indent by language', () {
    expect(codeEditForInsertion('', 0, '(', 'rust')?.text, '()');
    expect(codeEditForInsertion('{}', 1, '\n', 'rust')?.text, '\n    \n');
    expect(
      codeEditForInsertion('if (x) {', 8, '\n', 'javascript')?.text,
      '\n  ',
    );
    expect(
      codeEditForInsertion('if ready:', 9, '\n', 'python')?.text,
      '\n    ',
    );
    final outdent = codeEditForInsertion('    ', 4, '}', 'dart');
    expect(outdent?.deleteLength, 4);
    expect(outdent?.text, '}');
    expect(codeEditForInsertion('"text', 5, '(', 'dart'), isNull);
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

    final end = node.delta!.length;
    state.selection = Selection.collapsed(Position(path: [0], offset: end));
    expect(
      await codeCharacterShortcut.executeWithCharacter(state, '{'),
      isTrue,
    );
    expect(node.delta?.toPlainText().endsWith('{}'), isTrue);
    expect(state.selection?.start.offset, end + 1);

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

  test('selected code is surrounded and empty pairs delete together', () async {
    final node = codeBlockNode(code: 'word', language: 'dart');
    final state = EditorState(
      document: Document(root: pageNode(children: [node])),
    )..selection = Selection(
        start: Position(path: [0], offset: 0),
        end: Position(path: [0], offset: 4),
      );
    expect(
      await codeCharacterShortcut.executeWithCharacter(state, '('),
      isTrue,
    );
    expect(node.delta?.toPlainText(), '(word)');
    expect(state.selection?.start.offset, 1);
    expect(state.selection?.end.offset, 5);

    await state.apply(
      state.transaction
        ..deleteText(node, 1, 4)
        ..afterSelection = Selection.collapsed(
          Position(path: [0], offset: 1),
        ),
    );
    expect(codePairBackspaceCommand.execute(state), KeyEventResult.handled);
    await Future<void>.delayed(Duration.zero);
    expect(node.delta?.toPlainText(), '');
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

  test('a fenced block with one content line stays Markdown', () async {
    const source = '```dart\nprint(1);\n```';
    final nodes = parseMarkdownToNodes(source);
    expect(nodes.single.type, ParagraphBlockKeys.type);
    expect(nodes.single.delta?.toPlainText(), source);
    final controller = MDEditorController();
    await controller.setText(source);
    expect(
      controller.editorState.document.root.children.single.type,
      ParagraphBlockKeys.type,
    );
    controller.dispose();
  });

  testWidgets('one-line fence keeps Markdown renderer and has no copy control',
      (tester) async {
    final controller = MDEditorController();
    await controller.setText('```dart\nprint(1);\n```');
    await tester
        .pumpWidget(MaterialApp(home: MDEditor(controller: controller)));
    await tester.pump();
    expect(find.byType(CodeBlockComponentWidget), findsNothing);
    expect(find.byKey(markdownCodeBlockKey), findsOneWidget);
    expect(find.byKey(const ValueKey('copy-code-block')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  test('adding a second fenced content line promotes the paragraph', () async {
    final controller = MDEditorController();
    await controller.setText('```dart\nprint(1);');
    final state = controller.editorState;
    final paragraph = state.document.root.children.single;
    expect(paragraph.type, ParagraphBlockKeys.type);
    final offset = paragraph.delta!.length;
    await state.apply(
      state.transaction
        ..insertText(paragraph, offset, '\nprint(2);')
        ..afterSelection = Selection.collapsed(
          Position(path: [0], offset: offset + 10),
        ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(state.document.root.children.single.type, CodeBlockKeys.type);
    controller.dispose();
  });

  test('code node language metadata round-trips through Markdown', () async {
    final state = EditorState.blank()
      ..nodeBehaviors = {CodeBlockKeys.type: codeNodeBehavior};
    await state.setText('```yaml\nkey: value\nnext: true\n```');
    final node = state.document.root.children.single;
    expect(node.type, CodeBlockKeys.type);
    expect(state.text, '```yaml\nkey: value\nnext: true\n```');
    await state.apply(
      state.transaction
        ..updateNode(node, {
          CodeBlockKeys.language: 'json',
          CodeBlockKeys.openingFence: '```json',
        }),
    );
    expect(state.text, '```json\nkey: value\nnext: true\n```');
    state.dispose();
  });

  test('pasting a code node into a paragraph keeps the boundaries', () async {
    final state = EditorState.blank()
      ..nodeBehaviors = {CodeBlockKeys.type: codeNodeBehavior};
    await state.setText('before after');
    state.selection = Selection.collapsed(Position(path: [0], offset: 7));
    await state.pastePlainText('```json\n{"ok": true}\n{"n": 2}\n```');
    final nodes = state.document.root.children;
    expect(nodes.map((node) => node.type), [
      ParagraphBlockKeys.type,
      CodeBlockKeys.type,
      ParagraphBlockKeys.type,
    ]);
    expect(nodes[1].delta?.toPlainText(), '{"ok": true}\n{"n": 2}');
    expect(state.text, 'before \n```json\n{"ok": true}\n{"n": 2}\n```\nafter');
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
    await controller.setText('```json\n{"ok": true}\n{"n": 2}\n```');
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
    expect(find.byKey(const ValueKey('copy-code-block')), findsOneWidget);
    final richText = tester
        .widgetList<RichText>(
          find.descendant(
            of: find.byType(AppFlowyRichText),
            matching: find.byType(RichText),
          ),
        )
        .firstWhere(
          (widget) => widget.text.toPlainText() == '{"ok": true}\n{"n": 2}',
        );
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

  testWidgets('copy icon copies code content without fences', (tester) async {
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
    final controller = MDEditorController();
    await controller.setText('```dart\nconst a = 1;\nconst b = 2;\n```');
    await tester.pumpWidget(
      MaterialApp(home: MDEditor(controller: controller, editable: false)),
    );
    await tester.tap(find.byKey(const ValueKey('copy-code-block')));
    await tester.pump();
    expect(copied, 'const a = 1;\nconst b = 2;');
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    controller.dispose();
  });

  testWidgets('language picker searches the full grammar list', (tester) async {
    final controller = MDEditorController();
    await controller.setText('```dart\nconst a = 1;\nconst b = 2;\n```');
    await tester
        .pumpWidget(MaterialApp(home: MDEditor(controller: controller)));
    await tester.tap(find.byKey(const ValueKey('code-language-picker')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'rust');
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsOneWidget);
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    expect(
      controller.editorState.document.root.children.single
          .attributes[CodeBlockKeys.language],
      'rust',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('code completion uses AppFlowy ghost text', (tester) async {
    final controller = MDEditorController();
    await controller.setText('```json\n{"ok": false}\ntr\n```');
    controller.editorState.selection =
        Selection.collapsed(Position(path: [0], offset: 16));
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
    expect(
      texts.any(
        (widget) => widget.text.toPlainText() == '{"ok": false}\ntrue',
      ),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('Tab accepts a keyword suggestion before the next code line',
      (tester) async {
    final controller = MDEditorController();
    await controller.setText('```dart\ncla\nfinal x = 1;\n```');
    controller.editorState.selection =
        Selection.collapsed(Position(path: [0], offset: 3));
    await tester.pumpWidget(
      MaterialApp(home: MDEditor(controller: controller, autoFocus: true)),
    );
    await tester.pumpAndSettle();
    final ghostText = tester.widgetList<RichText>(
      find.descendant(
        of: find.byType(AppFlowyRichText),
        matching: find.byType(RichText),
      ),
    );
    expect(
      ghostText
          .any((widget) => widget.text.toPlainText() == 'class\nfinal x = 1;'),
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      controller.editorState.document.root.children.single.delta?.toPlainText(),
      'class\nfinal x = 1;',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('command shortcuts dispatch to the selected code node',
      (tester) async {
    final controller = MDEditorController();
    await controller.setText('```yaml\nfirst: value\nkey:\n```');
    await tester.pumpWidget(
      MaterialApp(home: MDEditor(controller: controller, autoFocus: true)),
    );
    await tester.pumpAndSettle();
    controller.editorState.selection =
        Selection.collapsed(Position(path: [0], offset: 17));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.editorState.document.root.children, hasLength(1));
    expect(
      controller.editorState.document.root.children.single.delta?.toPlainText(),
      'first: value\nkey:\n  ',
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
    const source = '```json\n{"a": 1}\n{"b": 2}';
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
    expect(controller.text, source);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
