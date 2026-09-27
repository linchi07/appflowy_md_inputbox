/// One atomic edit in the host document. Offsets are UTF-16, like Flutter's
/// TextSelection and the AppFlowy delta.
class CodeEdit {
  const CodeEdit(this.offset, this.deleteLength, this.text, this.caretOffset);

  final int offset;
  final int deleteLength;
  final String text;
  final int caretOffset;
}

/// A short ghost suffix for an unfinished JSON/YAML literal at the end of a
/// node. Rendering and acceptance are handled by the host editor.
String? codeCompletionSuffix(String source, String language) {
  final id = language.toLowerCase();
  if (id != 'json' && id != 'jsonc' && id != 'yaml' && id != 'yml') {
    return null;
  }
  if ((id == 'json' || id == 'jsonc') &&
      _insideJsonString(source, source.length)) {
    return null;
  }
  final line = source.substring(source.lastIndexOf('\n') + 1);
  if ((id == 'yaml' || id == 'yml') && line.trimLeft().startsWith('#')) {
    return null;
  }
  final prefix = RegExp(r'[A-Za-z]+$').stringMatch(source);
  if (prefix == null || prefix.length < 2) return null;
  final words = id == 'json' || id == 'jsonc'
      ? const ['true', 'false', 'null']
      : const ['true', 'false', 'null', 'yes', 'no'];
  for (final word in words) {
    if (word.startsWith(prefix) && word != prefix) {
      return word.substring(prefix.length);
    }
  }
  return null;
}

/// Small, deterministic editing conveniences. The host owns selection, undo,
/// IME composition and persistence; this package only proposes an edit.
CodeEdit? codeEditForInsertion(
  String source,
  int offset,
  String inserted,
  String language,
) {
  if (offset < 0 || offset > source.length) return null;
  final id = language.toLowerCase();
  final isJson = id == 'json' || id == 'jsonc';
  final isYaml = id == 'yaml' || id == 'yml';
  if (inserted == '\n') {
    final lineStart = source.lastIndexOf('\n', offset - 1) + 1;
    final before = source.substring(lineStart, offset);
    final indent = RegExp(r'^[ \t]*').stringMatch(before) ?? '';
    final extra = isYaml && before.trimRight().endsWith(':') ? '  ' : '';
    final next = offset < source.length ? source[offset] : '';
    final previous = offset > 0 ? source[offset - 1] : '';
    if (isJson &&
        ((previous == '{' && next == '}') ||
            (previous == '[' && next == ']'))) {
      final inner = '$indent  ';
      return CodeEdit(
        offset,
        0,
        '\n$inner\n$indent',
        offset + 1 + inner.length,
      );
    }
    return CodeEdit(
      offset,
      0,
      '\n$indent$extra',
      offset + 1 + indent.length + extra.length,
    );
  }
  if (isJson && inserted.length == 1) {
    const pairs = {'{': '}', '[': ']', '"': '"'};
    final closing = pairs[inserted];
    if (closing != null && !_insideJsonString(source, offset)) {
      return CodeEdit(offset, 0, '$inserted$closing', offset + 1);
    }
    if ((inserted == '}' || inserted == ']' || inserted == '"') &&
        offset < source.length &&
        source[offset] == inserted) {
      return CodeEdit(offset, 0, '', offset + 1);
    }
  }
  return null;
}

bool _insideJsonString(String source, int offset) {
  var quoted = false;
  var escaped = false;
  for (var i = 0; i < offset; i++) {
    final char = source[i];
    if (char == '\n') {
      quoted = false;
      escaped = false;
    } else if (escaped) {
      escaped = false;
    } else if (char == '\\' && quoted) {
      escaped = true;
    } else if (char == '"') {
      quoted = !quoted;
    }
  }
  return quoted;
}
