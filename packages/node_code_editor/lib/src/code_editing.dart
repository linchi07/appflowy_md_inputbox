import 'syntax_highlight/registry.dart' as syntax;
import 'syntax_highlight/src/mode.dart' show Mode;

/// One atomic edit in the host document. Offsets use UTF-16.
class CodeEdit {
  const CodeEdit(this.offset, this.deleteLength, this.text, this.caretOffset);
  final int offset;
  final int deleteLength;
  final String text;
  final int caretOffset;
}

final Map<String, Mode> _modes = {
  for (final entry in syntax.codeLanguageModes.entries) ...{
    entry.key: entry.value,
    for (final alias in entry.value.aliases ?? const <String>[])
      alias: entry.value,
  },
};
final Map<String, List<String>> _keywordCache = {};

/// A ghost suffix from language keywords, then recently used code identifiers.
/// The host renders it and accepts it on Tab.
String? codeCompletionSuffix(String source, String language) {
  if (source.length > 64 * 1024 ||
      _insideStringOrComment(source, source.length, language)) {
    return null;
  }
  final id = language.toLowerCase();
  if (id.isEmpty || id == 'plaintext') return null;
  final mode = _modes[id];
  final prefix = RegExp(r'[A-Za-z_][A-Za-z_0-9]*$').stringMatch(source);
  if (prefix == null || prefix.length < 2) return null;
  final keywords = (mode == null ? const <String>[] : _keywordsFor(id, mode))
      .where((word) => word.length > prefix.length && word.startsWith(prefix))
      .toList()
    ..sort((a, b) {
      final byLength = a.length.compareTo(b.length);
      return byLength == 0 ? a.compareTo(b) : byLength;
    });
  if (keywords.isNotEmpty) return keywords.first.substring(prefix.length);

  final identifiers = _recentIdentifiers(
    source,
    source.length - prefix.length,
    id,
  )
      .entries
      .where((entry) =>
          entry.key.length > prefix.length && entry.key.startsWith(prefix))
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return identifiers.isEmpty
      ? null
      : identifiers.first.key.substring(prefix.length);
}

Map<String, int> _recentIdentifiers(String source, int end, String language) {
  final found = <String, int>{};
  final hashComments = const {
    'python',
    'py',
    'yaml',
    'yml',
    'bash',
    'sh',
    'ruby',
    'rb',
  }.contains(language);
  String? quote;
  var escaped = false;
  var lineComment = false;
  var blockComment = false;
  for (var i = 0; i < end;) {
    final char = source[i];
    final next = i + 1 < end ? source[i + 1] : '';
    if (char == '\n') {
      lineComment = false;
      escaped = false;
      i++;
      continue;
    }
    if (lineComment) {
      i++;
      continue;
    }
    if (blockComment) {
      if (char == '*' && next == '/') {
        blockComment = false;
        i++;
      }
      i++;
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
      i++;
      continue;
    }
    if (char == '/' && next == '/') {
      lineComment = true;
      i += 2;
      continue;
    }
    if (char == '/' && next == '*') {
      blockComment = true;
      i += 2;
      continue;
    }
    if (hashComments && char == '#') {
      lineComment = true;
      i++;
      continue;
    }
    if (char == '"' || char == "'" || char == '`') {
      quote = char;
      i++;
      continue;
    }
    final unit = source.codeUnitAt(i);
    if (_identifierStart(unit)) {
      final start = i++;
      while (i < end && _identifierPart(source.codeUnitAt(i))) {
        i++;
      }
      found[source.substring(start, i)] = start;
      continue;
    }
    i++;
  }
  return found;
}

bool _identifierStart(int unit) =>
    unit == 0x5f ||
    (unit >= 0x41 && unit <= 0x5a) ||
    (unit >= 0x61 && unit <= 0x7a);

bool _identifierPart(int unit) =>
    _identifierStart(unit) || (unit >= 0x30 && unit <= 0x39);

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
