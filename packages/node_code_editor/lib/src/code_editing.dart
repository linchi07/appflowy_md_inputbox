import 'package:highlight/languages/all.dart' as languages;
import 'package:highlight/highlight_core.dart' show Mode;

/// One atomic edit in the host document. Offsets use UTF-16.
class CodeEdit {
  const CodeEdit(this.offset, this.deleteLength, this.text, this.caretOffset);
  final int offset;
  final int deleteLength;
  final String text;
  final int caretOffset;
}

final Map<String, Mode> _modes = {
  for (final entry in languages.allLanguages.entries) ...{
    entry.key: entry.value,
    for (final alias in entry.value.aliases ?? const <String>[])
      alias: entry.value,
  },
};
final Map<String, List<String>> _keywordCache = {};

/// A ghost suffix from the current language's keywords or existing document
/// words. The host renders it and accepts it on Tab.
String? codeCompletionSuffix(String source, String language) {
  if (source.length > 64 * 1024 ||
      _insideStringOrComment(source, source.length, language)) {
    return null;
  }
  final id = language.toLowerCase();
  final mode = _modes[id];
  if (mode == null) return null;
  final prefix = RegExp(r'[A-Za-z_][A-Za-z_0-9]*$').stringMatch(source);
  if (prefix == null || prefix.length < 2) return null;
  final candidates = <String>{..._keywordsFor(id, mode)};
  for (final match in RegExp('[A-Za-z_][A-Za-z_0-9]*').allMatches(source)) {
    if (match.end < source.length && match.group(0)!.length > prefix.length) {
      candidates.add(match.group(0)!);
    }
  }
  final matching = candidates
      .where((word) => word.length > prefix.length && word.startsWith(prefix))
      .toList()
    ..sort((a, b) {
      final byLength = a.length.compareTo(b.length);
      return byLength == 0 ? a.compareTo(b) : byLength;
    });
  return matching.isEmpty ? null : matching.first.substring(prefix.length);
}

List<String> _keywordsFor(String id, Mode mode) =>
    _keywordCache.putIfAbsent(id, () {
      final definitions = mode.keywords;
      const groups = {
        'keyword',
        'built_in',
        'literal',
        'type',
        'meta',
        'function',
        'params',
        'symbol',
        'attribute',
        'title',
        'name',
        'operator',
        'variable',
        'section',
      };
      final values = <String>[
        if (definitions is String) definitions,
        if (definitions is Map &&
            definitions.keys.whereType<String>().every(groups.contains))
          ...definitions.values.whereType<String>(),
        if (definitions is Map &&
            !definitions.keys.whereType<String>().every(groups.contains))
          ...definitions.keys.whereType<String>(),
      ];
      return values
          .expand((text) => text.split(RegExp(r'\s+')))
          .map((word) => word.split('|').first)
          .where((word) => RegExp(r'^[A-Za-z_][A-Za-z_0-9]*$').hasMatch(word))
          .toList(growable: false);
    });

/// Detect a document's indentation where possible, then use a language
/// default. Most languages use four spaces; web formats use two.
int codeIndentWidth(String source, String language) {
  for (final line in source.split('\n')) {
    if (line.trim().isEmpty) continue;
    final spaces = RegExp('^ +').stringMatch(line)?.length ?? 0;
    if (spaces > 0) return spaces.clamp(1, 8);
  }
  const twoSpaces = {
    'json',
    'jsonc',
    'yaml',
    'yml',
    'javascript',
    'js',
    'typescript',
    'ts',
    'jsx',
    'tsx',
    'css',
    'scss',
    'html',
    'xml',
    'vue',
    'svelte',
  };
  return twoSpaces.contains(language.toLowerCase()) ? 2 : 4;
}

CodeEdit codeEditForTab(
  String source,
  int offset,
  String language, {
  bool outdent = false,
}) {
  final lineStart = offset == 0 ? 0 : source.lastIndexOf('\n', offset - 1) + 1;
  final before = source.substring(lineStart, offset);
  final indent = RegExp(r'^[ \t]*').stringMatch(before) ?? '';
  final width = codeIndentWidth(source, language);
  if (outdent) {
    final remove = indent.endsWith('\t')
        ? 1
        : indent.length < width
            ? indent.length
            : width;
    return CodeEdit(
      lineStart + indent.length - remove,
      remove,
      '',
      offset - remove,
    );
  }
  final spaces = width - (before.length % width);
  return CodeEdit(offset, 0, ' ' * spaces, offset + spaces);
}

/// Language-neutral editing rules inspired by VS Code's language
/// configuration: indentation, pairs, skip-over and closing-bracket outdent.
CodeEdit? codeEditForInsertion(
  String source,
  int offset,
  String inserted,
  String language,
) {
  if (offset < 0 || offset > source.length) return null;
  final id = language.toLowerCase();
  final codeLike = id.isNotEmpty &&
      !const {'plaintext', 'text', 'markdown', 'md', 'diff', 'csv'}
          .contains(id);
  if (inserted == '\n') {
    final lineStart =
        offset == 0 ? 0 : source.lastIndexOf('\n', offset - 1) + 1;
    final before = source.substring(lineStart, offset);
    final after = source.substring(offset).split('\n').first.trimLeft();
    final indent = RegExp(r'^[ \t]*').stringMatch(before) ?? '';
    final trimmed = before.trimRight();
    final opening = trimmed.isEmpty ? '' : trimmed[trimmed.length - 1];
    final closing = after.isEmpty ? '' : after[0];
    final width = codeIndentWidth(source, id);
    final increase = codeLike &&
        (const {'{', '[', '('}.contains(opening) ||
            (const {'python', 'py', 'yaml', 'yml'}.contains(id) &&
                opening == ':'));
    final paired = const {'{': '}', '[': ']', '(': ')'}[opening] == closing;
    if (paired && increase) {
      final inner = indent + ' ' * width;
      return CodeEdit(
        offset,
        0,
        '\n$inner\n$indent',
        offset + 1 + inner.length,
      );
    }
    final nextIndent = indent + (increase ? ' ' * width : '');
    return CodeEdit(offset, 0, '\n$nextIndent', offset + 1 + nextIndent.length);
  }
  if (!codeLike || inserted.length != 1) return null;
  final next = offset < source.length ? source[offset] : '';
  if (const {'}', ']', ')', '"', "'", '`'}.contains(inserted) &&
      next == inserted) {
    return CodeEdit(offset, 0, '', offset + 1);
  }
  final context = _insideStringOrComment(source, offset, id);
  const pairs = {'{': '}', '[': ']', '(': ')', '"': '"', "'": "'", '`': '`'};
  final closing = pairs[inserted];
  if (closing != null &&
      !context &&
      (inserted != '`' ||
          const {'javascript', 'js', 'typescript', 'ts'}.contains(id)) &&
      (inserted != "'" || id != 'json') &&
      (next.isEmpty || RegExp(r'^[\s;:.,=}\])>]$').hasMatch(next))) {
    return CodeEdit(offset, 0, '$inserted$closing', offset + 1);
  }
  if (const {'}', ']', ')'}.contains(inserted)) {
    final lineStart =
        offset == 0 ? 0 : source.lastIndexOf('\n', offset - 1) + 1;
    final before = source.substring(lineStart, offset);
    if (before.trim().isEmpty && before.isNotEmpty) {
      final width = codeIndentWidth(source, id);
      final remove = before.endsWith('\t') ? 1 : before.length.clamp(0, width);
      return CodeEdit(offset - remove, remove, inserted, offset - remove + 1);
    }
  }
  return null;
}

bool _insideStringOrComment(String source, int offset, String language) {
  String? quote;
  var escaped = false;
  var blockComment = false;
  var lineComment = false;
  final hashComments = const {
    'python',
    'py',
    'yaml',
    'yml',
    'bash',
    'sh',
    'ruby',
    'rb',
  }.contains(language.toLowerCase());
  for (var i = 0; i < offset; i++) {
    final char = source[i];
    final next = i + 1 < offset ? source[i + 1] : '';
    if (char == '\n') {
      lineComment = false;
      escaped = false;
      continue;
    }
    if (lineComment) continue;
    if (blockComment) {
      if (char == '*' && next == '/') {
        blockComment = false;
        i++;
      }
      continue;
    }
    if (quote != null) {
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }
    if (char == '/' && next == '/') {
      lineComment = true;
      i++;
    } else if (char == '/' && next == '*') {
      blockComment = true;
      i++;
    } else if (hashComments && char == '#') {
      lineComment = true;
    } else if (char == '"' || char == "'" || char == '`') {
      quote = char;
    }
  }
  return quote != null || lineComment || blockComment;
}
