import 'package:flutter/material.dart';
import 'syntax_highlight/registry.dart' as syntax;
import 'syntax_highlight/src/node.dart' as hl;

enum CodeTokenKind { keyword, string, number, comment, key }

class CodeToken {
  const CodeToken(this.start, this.end, this.kind);
  final int start;
  final int end;
  final CodeTokenKind kind;
}

/// The curated, vendored syntax grammars, without a full highlight dependency.
/// Unknown language IDs fall back to a small, language-neutral lexer.
class CodeHighlighter {
  static final List<String> supportedLanguages =
      syntax.codeLanguageModes.keys.toList()..sort();

  static final RegExp _lexicalPattern = RegExp(
    r'"(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27|//[^\n]*|#[^\n]*|\b(?:[0-9]+(?:\.[0-9]+)?)\b|\b[A-Za-z_][A-Za-z_0-9]*\b',
  );
  String? _source;
  String? _language;
  List<CodeToken> _tokens = const [];

  List<CodeToken> tokenize(String source, String language) {
    if (_source == source && _language == language) return _tokens;
    _source = source;
    _language = language;
    // Keep the same per-node budget as Markdown decoration.
    if (source.length > 64 * 1024) return _tokens = const [];
    final id = language.toLowerCase();
    if (id.isEmpty || id == 'plaintext') return _tokens = const [];
    if (syntax.codeLanguageIds.contains(id)) {
      try {
        final nodes = syntax.codeHighlight.parse(source, language: id).nodes;
        if (nodes != null) {
          final tokens = <CodeToken>[];
          final reconstructed = StringBuffer();
          var offset = 0;

          void visit(hl.Node node, String? inheritedClass) {
            final className = node.className ?? inheritedClass;
            final value = node.value;
            if (value != null) {
              final start = offset;
              reconstructed.write(value);
              offset += value.length;
              final kind = _kindForClass(className);
              if (kind != null && value.isNotEmpty) {
                tokens.add(CodeToken(start, offset, kind));
              }
            } else {
              for (final child in node.children ?? const <hl.Node>[]) {
                visit(child, className);
              }
            }
          }

          for (final node in nodes) {
            visit(node, null);
          }
          // Some grammars can stop at illegal input. Never return offsets
          // that do not reconstruct the original editable source exactly.
          if (reconstructed.toString() == source) {
            return _tokens = tokens;
          }
        }
      } catch (_) {
        // Malformed language definitions or incomplete code stay editable.
      }
    }
    return _tokens = _tokenizeFallback(source, id);
  }

  List<CodeToken> _tokenizeFallback(String source, String id) {
    final json = id == 'json' || id == 'jsonc';
    final yaml = id == 'yaml' || id == 'yml';
    final hashComments =
        yaml || id == 'python' || id == 'py' || id == 'sh' || id == 'bash';
    final keywords = json
        ? _jsonKeywords
        : yaml
            ? _yamlKeywords
            : _genericKeywords;
    final tokens = <CodeToken>[];
    for (final match in _lexicalPattern.allMatches(source)) {
      final value = match.group(0)!;
      CodeTokenKind? kind;
      if (value.startsWith('"') || value.startsWith("'")) {
        kind = (json &&
                value.startsWith('"') &&
                _followedByColon(source, match.end))
            ? CodeTokenKind.key
            : CodeTokenKind.string;
      } else if (value.startsWith('//') ||
          (hashComments && value.startsWith('#'))) {
        kind = CodeTokenKind.comment;
      } else if (value.codeUnitAt(0) >= 0x30 && value.codeUnitAt(0) <= 0x39) {
        kind = CodeTokenKind.number;
      } else if (yaml && _followedByColon(source, match.end)) {
        kind = CodeTokenKind.key;
      } else if (keywords.contains(value)) {
        kind = CodeTokenKind.keyword;
      }
      if (kind != null) tokens.add(CodeToken(match.start, match.end, kind));
    }
    return tokens;
  }

  TextSpan spanForSegment({
    required String source,
    required String language,
    required int start,
    required String segment,
    required TextStyle style,
    required bool dark,
  }) {
    final end = start + segment.length;
    final children = <InlineSpan>[];
    var position = start;
    for (final token in tokenize(source, language)) {
      if (token.end <= start) continue;
      if (token.start >= end) break;
      final tokenStart = token.start < start ? start : token.start;
      final tokenEnd = token.end > end ? end : token.end;
      if (tokenStart > position) {
        children.add(TextSpan(text: source.substring(position, tokenStart)));
      }
      children.add(
        TextSpan(
          text: source.substring(tokenStart, tokenEnd),
          style: TextStyle(color: _color(token.kind, dark)),
        ),
      );
      position = tokenEnd;
    }
    if (position < end) {
      children.add(TextSpan(text: source.substring(position, end)));
    }
    return TextSpan(style: style, children: children);
  }
}

CodeTokenKind? _kindForClass(String? name) {
  if (name == null) return null;
  final kind = name.split(' ').first;
  if (kind.contains('comment') || kind == 'doctag') {
    return CodeTokenKind.comment;
  }
  if (kind.contains('string') || kind == 'regexp') {
    return CodeTokenKind.string;
  }
  if (kind == 'number') return CodeTokenKind.number;
  if (kind == 'attr' || kind == 'attribute') return CodeTokenKind.key;
  if (kind == 'keyword' ||
      kind == 'literal' ||
      kind == 'built_in' ||
      kind == 'type' ||
      kind == 'meta') {
    return CodeTokenKind.keyword;
  }
  return null;
}

bool _followedByColon(String source, int offset) {
  while (offset < source.length) {
    final unit = source.codeUnitAt(offset);
    if (unit != 0x20 && unit != 0x09) return unit == 0x3A;
    offset++;
  }
  return false;
}

const _jsonKeywords = {'true', 'false', 'null'};
const _yamlKeywords = {'true', 'false', 'null', 'yes', 'no', 'on', 'off'};
const _genericKeywords = {
  'abstract',
  'async',
  'await',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'def',
  'else',
  'enum',
  'export',
  'extends',
  'false',
  'final',
  'for',
  'from',
  'fun',
  'function',
  'if',
  'import',
  'in',
  'interface',
  'let',
  'new',
  'null',
  'return',
  'static',
  'switch',
  'this',
  'throw',
  'true',
  'try',
  'var',
  'void',
  'while',
  'yield',
};

Color _color(CodeTokenKind kind, bool dark) => switch (kind) {
      CodeTokenKind.keyword =>
        dark ? const Color(0xFFBFA7FF) : const Color(0xFF6F42C1),
      CodeTokenKind.string =>
        dark ? const Color(0xFFA5D6A7) : const Color(0xFF22863A),
      CodeTokenKind.number =>
        dark ? const Color(0xFFFFC078) : const Color(0xFFB05A00),
      CodeTokenKind.comment =>
        dark ? const Color(0xFF9199A4) : const Color(0xFF6A737D),
      CodeTokenKind.key =>
        dark ? const Color(0xFF80CBC4) : const Color(0xFF006D77),
    };
