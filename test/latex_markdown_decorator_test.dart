import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/rich_text/markdown_decorator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  group('LaTeX Markdown decoration', () {
    testWidgets('renders closed inline math after the caret leaves',
        (tester) async {
      final result = await decorate(
        tester,
        r'Before $x^2$ after',
        caretOffset: 0,
      );

      expect(widgetSpans(result), hasLength(1));
      expect(result.toPlainText(), hasLength(r'Before $x^2$ after'.length));
    });

    testWidgets('keeps inline math source visible while the caret is inside',
        (tester) async {
      final result = await decorate(
        tester,
        r'Before $x^2$ after',
        caretOffset: 10,
      );

      expect(widgetSpans(result), isEmpty);
      expect(result.toPlainText(), r'Before $x^2$ after');
    });

    testWidgets('math takes precedence over Markdown markers', (tester) async {
      final result = await decorate(
        tester,
        r'ok $x*y$',
        caretOffset: 0,
      );

      expect(widgetSpans(result), hasLength(1));
    });

    testWidgets('does not render math inside inline code', (tester) async {
      final result = await decorate(
        tester,
        r'`$x$`',
        caretOffset: 6,
      );

      expect(widgetSpans(result), isEmpty);
    });

    testWidgets('does not render an escaped dollar delimiter', (tester) async {
      final result = await decorate(
        tester,
        r'\$x$',
        caretOffset: 5,
      );

      expect(widgetSpans(result), isEmpty);
    });

    testWidgets('renders a single-line display formula', (tester) async {
      final result = await decorate(
        tester,
        r'ok $$\frac{a}{b}$$',
        caretOffset: 0,
        selectionInOtherNode: true,
      );

      expect(widgetSpans(result), hasLength(1));
      expect(result.toPlainText(), hasLength(r'ok $$\frac{a}{b}$$'.length));
    });

    testWidgets('renders a multi-line display formula as one preview',
        (tester) async {
      const source = r'''$$
\begin{aligned}
a &= b + c \\
d &= e - f
\end{aligned}
$$''';
      final result = await decorate(
        tester,
        source,
        caretOffset: 0,
        selectionInOtherNode: true,
      );

      expect(widgetSpans(result), hasLength(1));
      expect(result.toPlainText(), hasLength(source.length));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('duplicate expressions use independent math trees',
        (tester) async {
      final result = await decorate(
        tester,
        r'$x^2$ then $x^2$',
        caretOffset: 0,
        selectionInOtherNode: true,
      );

      expect(widgetSpans(result), hasLength(2));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('Todo Markdown decoration', () {
    testWidgets('always renders a real checkbox while the caret is inside',
        (tester) async {
      final source = '- [ ] todo';
      final node = paragraphNode(delta: Delta()..insert(source));
      final editorState = EditorState(
        document: Document(root: pageNode(children: [node])),
      )..selection = Selection.collapsed(
          Position(path: node.path, offset: 3),
        );

      await tester.pumpWidget(
        Provider<EditorState>.value(
          value: editorState,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                const original = TextSpan(
                  text: '',
                  style: TextStyle(fontSize: 16),
                );
                final decorated = markdownTextSpanDecorator(
                  context,
                  node,
                  0,
                  TextInsert(source),
                  original,
                  original,
                );
                return Text.rich(decorated);
              },
            ),
          ),
        ),
      );

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isFalse);
      expect(checkbox.onChanged, isNotNull);
      expect(checkbox.splashRadius, 0);
      expect(
        checkbox.overlayColor?.resolve({WidgetState.pressed}),
        Colors.transparent,
      );

      checkbox.onChanged!(true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(editorState.text, '- [x] todo');
    });
  });

  group('Fenced code paragraph fallback', () {
    testWidgets('keeps source literal when no code node is registered',
        (tester) async {
      const source = '```dart\nfinal answer = 42;\n```';
      final result = await decorate(
        tester,
        source,
        caretOffset: 0,
        selectionInOtherNode: true,
      );

      expect(widgetSpans(result), isEmpty);
      expect(result.children, isNull);
      expect(result.toPlainText(), source);
    });
  });
}

Future<TextSpan> decorate(
  WidgetTester tester,
  String source, {
  required int caretOffset,
  bool selectionInOtherNode = false,
}) async {
  final node = paragraphNode(delta: Delta()..insert(source));
  final otherNode = paragraphNode();
  final editorState = EditorState(
    document: Document(root: pageNode(children: [node, otherNode])),
  )..selection = Selection.collapsed(
      Position(
        path: selectionInOtherNode ? otherNode.path : node.path,
        offset: caretOffset,
      ),
    );
  late TextSpan result;

  await tester.pumpWidget(
    Provider<EditorState>.value(
      value: editorState,
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            final text = TextInsert(source);
            const original = TextSpan(
              text: '',
              style: TextStyle(fontSize: 16),
            );
            result = markdownTextSpanDecorator(
              context,
              node,
              0,
              text,
              original,
              original,
            );
            return Text.rich(result);
          },
        ),
      ),
    ),
  );

  return result;
}

List<WidgetSpan> widgetSpans(TextSpan span) {
  final result = <WidgetSpan>[];
  bool collect(InlineSpan child) {
    if (child is WidgetSpan) result.add(child);
    return true;
  }

  span.visitChildren(collect);
  return result;
}
