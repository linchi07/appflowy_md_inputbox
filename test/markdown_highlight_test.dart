import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/rich_text/markdown_block_syntax.dart';
import 'package:appflowy_editor/src/editor/block_component/rich_text/markdown_decorator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  final highlightColor = const MDEditorColorScheme.light().highlightBackground;

  testWidgets('highlights triple-equals text without changing source offsets',
      (tester) async {
    const source = 'before ===bright=== after';
    final result = await _decorate(tester, source);

    expect(result.toPlainText(), source);
    expect(
      _textSpans(result).any(
        (span) =>
            span.text == 'bright' &&
            span.style?.backgroundColor == highlightColor,
      ),
      isTrue,
    );
    expect(
      _textSpans(result).where((span) => span.text == '==='),
      hasLength(2),
    );
  });

  testWidgets('shows highlight source while editing the marked range',
      (tester) async {
    const source = '===bright===';
    final result = await _decorate(tester, source, caretOffset: 5);

    expect(result.toPlainText(), source);
    expect(_textSpans(result).single.text, source);
  });

  testWidgets('supports bold within highlight', (tester) async {
    const source = '===plain **bold** plain===';
    final result = await _decorate(tester, source);

    expect(result.toPlainText(), source);
    expect(
      _textSpans(result).any(
        (span) =>
            span.text == 'bold' &&
            span.style?.fontWeight == FontWeight.bold &&
            span.style?.backgroundColor == highlightColor,
      ),
      isTrue,
    );
  });

  testWidgets('supports highlight within bold', (tester) async {
    const source = '**plain ===bright=== plain**';
    final result = await _decorate(tester, source);

    expect(result.toPlainText(), source);
    expect(
      _textSpans(result).any(
        (span) =>
            span.text == 'bright' &&
            span.style?.fontWeight == FontWeight.bold &&
            span.style?.backgroundColor == highlightColor,
      ),
      isTrue,
    );
  });

  testWidgets('does not highlight markers inside inline code', (tester) async {
    final result = await _decorate(tester, '`===literal===`');

    expect(
      _textSpans(result).any(
        (span) => span.style?.backgroundColor == highlightColor,
      ),
      isFalse,
    );
  });

  testWidgets('dense nested markup takes the plain-text safety path',
      (tester) async {
    final source = '===${List.filled(800, '**x**').join()}===';
    final result = await _decorate(tester, source);

    expect(result.children, isNull);
    expect(result.toPlainText(), source);
  });

  testWidgets('oversized paragraphs skip fenced parsing before decoration',
      (tester) async {
    clearMarkdownFencedBlockCache();
    final source = '```\n${List.filled(256, 'x').join()}\n```';
    final result = await _decorate(tester, source, decorationLimit: 128);

    expect(markdownFencedBlockParseCount, 0);
    expect(result.children, isNull);
    expect(result.toPlainText(), source);
  });

  testWidgets('the size guard uses the whole node, not one text operation',
      (tester) async {
    clearMarkdownFencedBlockCache();
    final delta = Delta()
      ..insert('```\n')
      ..insert(List.filled(256, 'x').join(), attributes: {'bold': true});
    final result = await _decorate(
      tester,
      delta.toPlainText(),
      delta: delta,
      segment: '```\n',
      decorationLimit: 128,
    );

    expect(markdownFencedBlockParseCount, 0);
    expect(result.children, isNull);
    expect(result.toPlainText(), '```\n');
  });

  testWidgets('fenced source is not treated as inline code', (tester) async {
    clearMarkdownFencedBlockCache();
    const source = '```\ncode\n```';
    final result = await _decorate(
      tester,
      source,
      decorationLimit: source.length,
    );

    expect(markdownFencedBlockParseCount, 0);
    expect(result.children, isNull);
    expect(result.toPlainText(), source);
  });

  testWidgets('single-backtick inline code remains decorated', (tester) async {
    final result = await _decorate(tester, 'before `code` after');
    expect(result.children, isNotNull);
    expect(result.toPlainText(), 'before `code` after');
  });
}

Future<TextSpan> _decorate(
  WidgetTester tester,
  String source, {
  Delta? delta,
  String? segment,
  int? caretOffset,
  int decorationLimit = 64 * 1024,
}) async {
  final node = paragraphNode(delta: delta ?? (Delta()..insert(source)));
  final otherNode = paragraphNode();
  final editorState = EditorState(
    document: Document(root: pageNode(children: [node, otherNode])),
  )
    ..editorStyle = EditorStyle.desktop(
      maxMarkdownDecorationCharacters: decorationLimit,
    )
    ..selection = Selection.collapsed(
      Position(
        path: caretOffset == null ? otherNode.path : node.path,
        offset: caretOffset ?? 0,
      ),
    );
  late TextSpan result;

  await tester.pumpWidget(
    Provider<EditorState>.value(
      value: editorState,
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            const original = TextSpan(style: TextStyle(fontSize: 16));
            result = markdownTextSpanDecorator(
              context,
              node,
              0,
              TextInsert(segment ?? source),
              original,
              original,
            );
            return Text.rich(result);
          },
        ),
      ),
    ),
  );
  await tester.pumpWidget(const SizedBox.shrink());
  editorState.dispose();
  return result;
}

List<TextSpan> _textSpans(TextSpan span) =>
    span.children?.whereType<TextSpan>().toList() ?? [span];
