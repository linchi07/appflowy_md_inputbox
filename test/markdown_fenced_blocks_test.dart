import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/service/markdown_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fenced Markdown parsing', () {
    test('groups a multi-line display formula into one node', () {
      const source = 'before\n\$\$\na + b\n= c\n\$\$\nafter';

      final nodes = parseMarkdownToNodes(source);

      expect(nodes, hasLength(3));
      expect(nodes[1].delta?.toPlainText(), '\$\$\na + b\n= c\n\$\$');
      expect(_serialize(nodes), source);
    });

    test('groups fenced code without parsing tables or links inside it', () {
      const source =
          '```dart\n| not | a table |\nfinal url = "https://example.com";\n```';

      final nodes = parseMarkdownToNodes(source);

      expect(nodes, hasLength(1));
      expect(nodes.single.type, ParagraphBlockKeys.type);
      expect(nodes.single.delta?.toList(), hasLength(1));
      expect(nodes.single.delta?.toPlainText(), source);
    });

    test('keeps an unfinished fence together through the end of input', () {
      const source = '```\nfirst\nsecond';

      final nodes = parseMarkdownToNodes(source);

      expect(nodes, hasLength(1));
      expect(nodes.single.delta?.toPlainText(), source);
    });
  });

  group('fenced Markdown editing', () {
    test('Enter stays inside an unfinished code block', () async {
      final node = paragraphNode(text: '```');
      final editorState = EditorState(
        document: Document(root: pageNode(children: [node])),
      )..selection = Selection.collapsed(
          Position(path: node.path, offset: 3),
        );

      expect(await insertNewLine.execute(editorState), isTrue);

      expect(editorState.document.root.children, hasLength(1));
      expect(node.delta?.toPlainText(), '```\n');
      expect(editorState.selection?.start.offset, 4);
      editorState.dispose();
    });

    test('Enter after a closing fence exits into a new paragraph', () async {
      const source = '```\ncode\n```';
      final node = paragraphNode(text: source);
      final editorState = EditorState(
        document: Document(root: pageNode(children: [node])),
      )..selection = Selection.collapsed(
          Position(path: node.path, offset: source.length),
        );

      expect(await insertNewLine.execute(editorState), isTrue);

      expect(editorState.document.root.children, hasLength(2));
      expect(
        editorState.document.root.children.first.delta?.toPlainText(),
        source,
      );
      expect(editorState.document.root.children.last.delta?.toPlainText(), '');
      editorState.dispose();
    });
  });

  testWidgets('renders code and display math with block-level containers',
      (tester) async {
    const source =
        '```dart\nfinal answer = 42;\n```\n\$\$\nx^2 + y^2\n\$\$\nafter';
    final controller = MDEditorController();
    await controller.setText(source);

    await tester.pumpWidget(
      MaterialApp(
        home: MDEditor(
          controller: controller,
          editable: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(markdownCodeBlockKey), findsOneWidget);
    expect(find.byKey(markdownDisplayMathBlockKey), findsOneWidget);
    final codeContainer = tester.widget<Container>(
      find.byKey(markdownCodeBlockKey),
    );
    final decoration = codeContainer.decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(8));
    expect(decoration.border, isNotNull);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    controller.dispose();
  });
}

String _serialize(List<Node> nodes) =>
    nodes.map((node) => node.delta?.toPlainText() ?? '').join('\n');
