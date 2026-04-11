import 'package:appflowy_editor/appflowy_editor.dart';

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
  final lines = markdown.split('\n');
  final nodes = <Node>[];

  final dividerRegex = RegExp(r'^([-*_])\1{2,}$|^—-$|^——-$');

  for (var line in lines) {
    // Process Windows line endings if any
    line = line.replaceAll('\r', '');

    if (dividerRegex.hasMatch(line)) {
      nodes.add(dividerNode());
    } else {
      final delta = _parseLineToDelta(line, baseAttributes: baseAttributes);
      if (line.startsWith('> ')) {
        nodes.add(quoteNode(delta: delta));
      } else {
        nodes.add(paragraphNode(delta: delta));
      }
    }
  }

  // Ensure there's at least one node
  if (nodes.isEmpty) {
    nodes.add(paragraphNode());
  }

  return nodes;
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
