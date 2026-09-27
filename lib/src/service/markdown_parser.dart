import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/rich_text/markdown_block_syntax.dart';

final RegExp _hrefRegex = RegExp(
  r'https?://(?:www\.)?[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}(?:/[^\s]*)?',
);

final RegExp _phoneRegex = RegExp(r'^\+?' // Optional '+' at start
    r'(?:[0-9][\s-.]?)+' // Sequence of digits with optional separators
    r'[0-9]$' // Ensure it ends with a digit
    );

/// Parses a Markdown string into a list of [Node] objects.
///
/// This is a top-level function so it can be used with [compute].
/// The [baseAttributes] can be used to apply default styles (e.g., from the current selection).
List<Node> parseMarkdownToNodes(
  String markdown, {
  Attributes? baseAttributes,
}) {
  // Skip structural fence recognition once the Markdown decoration budget is
  // exceeded. Large input remains editable as ordinary text nodes.
  final parseCodeFences = markdown.length <= 64 * 1024;
  final lines = markdown.split('\n');
  final nodes = <Node>[];

  final dividerRegex = RegExp(r'^([-*_])\1{2,}$|^—-$|^——-$');
  final tableLines = <String>[];

  void flushTable() {
    if (tableLines.isNotEmpty) {
      final tableNode = _parseTableLinesToNode(tableLines);
      if (tableNode != null) {
        nodes.add(tableNode);
      } else {
        for (final tLine in tableLines) {
          final delta =
              _parseLineToDelta(tLine, baseAttributes: baseAttributes);
          if (tLine.trim().startsWith('> ')) {
            nodes.add(quoteNode(delta: delta));
          } else {
            nodes.add(paragraphNode(delta: delta));
          }
        }
      }
      tableLines.clear();
    }
  }

  void addTextNode(String text) {
    final delta = _parseLineToDelta(text, baseAttributes: baseAttributes);
    if (text.trim().startsWith('> ')) {
      nodes.add(quoteNode(delta: delta));
    } else {
      nodes.add(paragraphNode(delta: delta));
    }
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].replaceAll('\r', '');
    final trimmedLine = line.trim();

    final isCodeFence = parseCodeFences && isFencedCodeOpeningLine(line);
    final isMathFence = isDisplayMathFenceLine(line);
    if (isCodeFence || isMathFence) {
      flushTable();
      final blockLines = <String>[line];
      while (++i < lines.length) {
        final blockLine = lines[i].replaceAll('\r', '');
        blockLines.add(blockLine);
        final isClosing = isCodeFence
            ? isFencedCodeClosingLine(blockLine)
            : isDisplayMathFenceLine(blockLine);
        if (isClosing) break;
      }
      final blockSource = blockLines.join('\n');
      // Keep a lone opening fence as exact source while its language is typed.
      final codeBlock = isCodeFence && blockSource.contains('\n')
          ? parseMarkdownFencedBlock(blockSource)
          : null;
      if (codeBlock != null && codeBlock.hasMultipleCodeLines) {
        nodes.add(
          codeBlockNode(
            code: blockSource.substring(
              codeBlock.openingEnd,
              codeBlock.contentEnd,
            ),
            language: codeBlock.language ?? '',
            openingFence: line,
            closed: codeBlock.isClosed,
          ),
        );
      } else {
        nodes.add(
          paragraphNode(
            delta: Delta()..insert(blockSource, attributes: baseAttributes),
          ),
        );
      }
    } else if (trimmedLine.startsWith('|') && trimmedLine.endsWith('|')) {
      tableLines.add(line);
    } else {
      flushTable();

      if (dividerRegex.hasMatch(trimmedLine)) {
        nodes.add(dividerNode());
      } else {
        addTextNode(line);
      }
    }
  }

  flushTable();

  // Ensure there's at least one node
  if (nodes.isEmpty) {
    nodes.add(paragraphNode());
  }

  return nodes;
}

Node? _parseTableLinesToNode(List<String> tableLines) {
  if (tableLines.isEmpty) return null;

  final List<List<String>> rows = [];
  int maxCols = 0;
  int separatorIndex = -1;

  for (var i = 0; i < tableLines.length; i++) {
    final line = tableLines[i].trim();
    if (!line.startsWith('|') || !line.endsWith('|')) {
      continue;
    }

    final parts = line.split('|');
    if (parts.length < 2) continue;

    final cells =
        parts.sublist(1, parts.length - 1).map((e) => e.trim()).toList();

    final isSeparator = cells.isNotEmpty &&
        cells.every(
          (cell) =>
              cell.isNotEmpty && cell.replaceAll(RegExp('[:-]'), '').isEmpty,
        );

    if (isSeparator && separatorIndex == -1) {
      separatorIndex = i;
      continue;
    }

    rows.add(cells);
    if (cells.length > maxCols) {
      maxCols = cells.length;
    }
  }

  if (rows.isEmpty || maxCols == 0) return null;

  for (var i = 0; i < rows.length; i++) {
    while (rows[i].length < maxCols) {
      rows[i].add('');
    }
  }

  final List<List<String>> cols = List.generate(maxCols, (_) => []);
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < maxCols; c++) {
      cols[c].add(rows[r][c]);
    }
  }

  try {
    return TableNode.fromList(cols).node;
  } catch (e) {
    return null;
  }
}

Delta _parseLineToDelta(String text, {Attributes? baseAttributes}) {
  final delta = Delta();
  if (_hrefRegex.hasMatch(text) || _phoneRegex.hasMatch(text)) {
    final match = _hrefRegex.firstMatch(text) ?? _phoneRegex.firstMatch(text);
    if (match != null) {
      int startPos = match.start;
      int endPos = match.end;
      final String? entity = match.group(0);
      if (entity != null) {
        if (startPos > 0) {
          delta.insert(text.substring(0, startPos), attributes: baseAttributes);
        }

        delta.insert(
          text.substring(startPos, endPos),
          attributes: {
            if (baseAttributes != null) ...baseAttributes,
            AppFlowyRichTextKeys.href:
                _phoneRegex.hasMatch(entity) ? 'tel:$entity' : entity,
          },
        );

        if (endPos < text.length) {
          delta.insert(text.substring(endPos), attributes: baseAttributes);
        }
      }
    }
  } else {
    delta.insert(text, attributes: baseAttributes);
  }

  return delta;
}

typedef MarkdownParserData = (String, Attributes?);

/// Wrapper for [compute] compatibility.
List<Node> parseMarkdownToNodesCompute(MarkdownParserData data) {
  return parseMarkdownToNodes(data.$1, baseAttributes: data.$2);
}
