import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/rich_text/markdown_decorator.dart';
import 'package:appflowy_editor/src/service/markdown_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('long paragraph first-frame benchmark', (tester) async {
    await _pumpCase(tester, 'warm-up', _source(1024));

    await _pumpCase(tester, '10 KiB density-guarded', _source(10 * 1024));
    await _pumpCase(tester, '64 KiB density-guarded', _source(64 * 1024));
    await _pumpCase(tester, '100 KiB guarded', _source(100 * 1024));
    await _pumpCase(tester, '64 KiB fenced code', _codeSource(64 * 1024));
    await _pumpCase(tester, '20-line display math', _displayMathSource(20));

    final parserSource = _codeSource(256 * 1024);
    final parserStopwatch = Stopwatch()..start();
    final parsed = parseMarkdownToNodes(parserSource);
    parserStopwatch.stop();
    _report('256 KiB fenced parser', parserStopwatch.elapsed, 0);
    expect(parsed, hasLength(1));

    final first = MDEditorController();
    final second = MDEditorController();
    final firstSource = _source(64 * 1024);
    final secondSource = '${_source(64 * 1024 - 1)}二';
    _replaceSingleParagraph(first, firstSource);
    _replaceSingleParagraph(second, secondSource);
    // ignore: invalid_use_of_visible_for_testing_member
    clearMarkdownLexicalCache();
    final stopwatch = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            Expanded(child: MDEditor(controller: first)),
            Expanded(child: MDEditor(controller: second)),
          ],
        ),
      ),
    );
    await tester.pump();
    stopwatch.stop();
    // ignore: invalid_use_of_visible_for_testing_member
    final scans = markdownLexicalScanCount;
    _report('two 64 KiB editors', stopwatch.elapsed, scans);
    expect(first.text, firstSource);
    expect(second.text, secondSource);
    await _dispose(tester, [first, second]);
  });
}

Future<void> _pumpCase(
  WidgetTester tester,
  String name,
  String source, {
  int? decorationLimit = 64 * 1024,
}) async {
  final controller = MDEditorController();
  // Avoid including the asynchronous import parser in this live-rendering
  // benchmark. The benchmark deliberately creates one pathological paragraph.
  _replaceSingleParagraph(controller, source);
  // ignore: invalid_use_of_visible_for_testing_member
  clearMarkdownLexicalCache();
  final stopwatch = Stopwatch()..start();
  await tester.pumpWidget(
    MaterialApp(
      home: MDEditor(
        controller: controller,
        maxMarkdownDecorationCharacters: decorationLimit,
      ),
    ),
  );
  await tester.pump();
  stopwatch.stop();
  // ignore: invalid_use_of_visible_for_testing_member
  final scans = markdownLexicalScanCount;
  _report(name, stopwatch.elapsed, scans);
  expect(controller.text, source);
  await _dispose(tester, [controller]);
}

void _replaceSingleParagraph(MDEditorController controller, String source) {
  final node = controller.editorState.document.root.children.single;
  node.updateAttributes({
    'delta': (Delta()..insert(source)).toJson(),
  });
}

String _source(int length) {
  const chunk = '中文输入 **粗体** *斜体* `code` #标签 与普通文本。';
  final buffer = StringBuffer();
  while (buffer.length < length) {
    buffer.write(chunk);
  }
  return buffer.toString().substring(0, length);
}

String _codeSource(int minimumLength) {
  const line = 'final value = source.map(transform).toList();\n';
  final buffer = StringBuffer('```dart\n');
  while (buffer.length < minimumLength - 4) {
    buffer.write(line);
  }
  buffer.write('```');
  return buffer.toString();
}

String _displayMathSource(int lines) {
  final rows = List.generate(lines, (index) => 'x_{$index} &= y_{$index} + 1');
  return '\$\$\n\\begin{aligned}\n${rows.join(' \\\\\n')}\n\\end{aligned}\n\$\$';
}

Future<void> _dispose(
  WidgetTester tester,
  List<MDEditorController> controllers,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 300));
  for (final controller in controllers) {
    controller.dispose();
  }
}

void _report(String name, Duration elapsed, int scans) {
  // This benchmark is intentionally directional. Run it in profile mode on a
  // physical target before changing production thresholds.
  // ignore: avoid_print
  print('$name: ${elapsed.inMicroseconds / 1000} ms, regex scans: $scans');
}
