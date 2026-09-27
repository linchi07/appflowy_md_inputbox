import 'dart:collection';

import 'package:flutter/foundation.dart';

enum MarkdownFencedBlockKind {
  code,
  displayMath,
}

/// The structural ranges of a fenced Markdown block stored in one text node.
class MarkdownFencedBlock {
  const MarkdownFencedBlock({
    required this.kind,
    required this.source,
    required this.openingEnd,
    required this.closingStart,
    this.language,
  });

  final MarkdownFencedBlockKind kind;
  final String source;

  /// The first source offset after the opening delimiter and its newline.
  final int openingEnd;

  /// The source offset of the closing delimiter, or null for an open block.
  final int? closingStart;

  final String? language;

  bool get isClosed => closingStart != null;

  /// The newline immediately before the closing delimiter is presentation
  /// syntax too, so hide it together with the delimiter in preview mode.
  int get contentEnd {
    final closing = closingStart;
    if (closing == null) return source.length;
    return closing > openingEnd && source.codeUnitAt(closing - 1) == 0x0A
        ? closing - 1
        : closing;
  }
}

bool isFencedCodeOpeningLine(String line) {
  final trimmed = line.trimLeft();
  return trimmed.startsWith('```');
}

bool isFencedCodeClosingLine(String line) =>
    RegExp(r'^```[ \t]*$').hasMatch(line.trimLeft());

bool isDisplayMathFenceLine(String line) => line.trim() == r'$$';

/// Returns block ranges only when [source] starts with a fenced block marker.
///
/// A closing marker must be on a later line. This intentionally leaves
/// single-line `$$...$$` formulas to the inline Markdown decorator.
MarkdownFencedBlock? parseMarkdownFencedBlock(String source) {
  if (source.isEmpty) return null;

  var firstNonWhitespace = 0;
  while (firstNonWhitespace < source.length) {
    final codeUnit = source.codeUnitAt(firstNonWhitespace);
    if (codeUnit != 0x20 && codeUnit != 0x09) break;
    firstNonWhitespace++;
  }
  if (firstNonWhitespace >= source.length) return null;
  final first = source.codeUnitAt(firstNonWhitespace);
  if (first != 0x60 && first != 0x24) return null;

  return _FencedBlockCache.parse(source);
}

class _FencedBlockCache {
  static const _capacity = 128;
  static const _sourceCharacterBudget = 1024 * 1024;
  static final LinkedHashMap<String, MarkdownFencedBlock?> _entries =
      LinkedHashMap();
  static int _sourceCharacters = 0;
  static int parseCount = 0;

  static MarkdownFencedBlock? parse(String source) {
    if (_entries.containsKey(source)) {
      final cached = _entries.remove(source);
      _entries[source] = cached;
      return cached;
    }

    parseCount++;
    final parsed = _parseMarkdownFencedBlock(source);
    _entries[source] = parsed;
    _sourceCharacters += source.length;
    while (_entries.length > _capacity ||
        _sourceCharacters > _sourceCharacterBudget) {
      final oldest = _entries.keys.first;
      _sourceCharacters -= oldest.length;
      _entries.remove(oldest);
    }
    return parsed;
  }

  static void clear() {
    _entries.clear();
    _sourceCharacters = 0;
    parseCount = 0;
  }
}

@visibleForTesting
int get markdownFencedBlockParseCount => _FencedBlockCache.parseCount;

@visibleForTesting
void clearMarkdownFencedBlockCache() => _FencedBlockCache.clear();

MarkdownFencedBlock? _parseMarkdownFencedBlock(String source) {
  final firstLineEnd = source.indexOf('\n');
  final firstLine =
      firstLineEnd == -1 ? source : source.substring(0, firstLineEnd);

  final MarkdownFencedBlockKind kind;
  String? language;
  if (isFencedCodeOpeningLine(firstLine)) {
    kind = MarkdownFencedBlockKind.code;
    language = firstLine.trimLeft().substring(3).trim();
    if (language.isEmpty) language = null;
  } else if (isDisplayMathFenceLine(firstLine)) {
    kind = MarkdownFencedBlockKind.displayMath;
  } else {
    return null;
  }

  final openingEnd = firstLineEnd == -1 ? source.length : firstLineEnd + 1;
  int? closingStart;
  var lineStart = openingEnd;
  while (lineStart < source.length) {
    final newline = source.indexOf('\n', lineStart);
    final lineEnd = newline == -1 ? source.length : newline;
    final line = source.substring(lineStart, lineEnd);
    final isClosing = kind == MarkdownFencedBlockKind.code
        ? isFencedCodeClosingLine(line)
        : isDisplayMathFenceLine(line);
    if (isClosing) {
      closingStart = lineStart;
      break;
    }
    if (newline == -1) break;
    lineStart = newline + 1;
  }

  return MarkdownFencedBlock(
    kind: kind,
    source: source,
    openingEnd: openingEnd,
    closingStart: closingStart,
    language: language,
  );
}

/// Whether Enter should insert a literal newline instead of splitting a node.
bool shouldInsertNewlineInFencedBlock(String source, int offset) {
  final block = parseMarkdownFencedBlock(source);
  if (block == null) return false;
  return !block.isClosed || offset < source.length;
}
