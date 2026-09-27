import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:provider/provider.dart';

import '../../../../appflowy_editor.dart';

final RegExp _markdownPattern = RegExp(
  r'(\*\*.*?(?:\*\*|$))|(\*.*?(?:\*|$))|(~~.*?(?:~~|$))|((?<![\\`])`(?!`)[^`\n]+`(?!`))|^(#{1,6}\s+.*)$|((?:^[-*]\s+)?\[[ x]])|(#[\w\u4e00-\u9fa5]+)|^([-*]\s+)|^(\d+\.\s+)|^([-*_]{3,})$|((?<![\\$])\$\$[\s\S]*?(?:(?<!\\)\$\$|(?![\s\S])))|((?<![\\$])\$(?!\$)(?!\s).*?(?:(?<![\\\s])\$(?!\$)|$))|(===[^\n]+?===)',
  multiLine: true,
);
final RegExp _headingPrefixPattern = RegExp(r'^#+\s+');
final RegExp _headingHashesPattern = RegExp('^#+');
final RegExp _checkboxPattern = RegExp(r'\[[ x]]');

// A paragraph can be shorter than the character limit yet contain thousands
// of inline decorations. Building and laying out that many InlineSpan and
// WidgetSpan objects is substantially more expensive than lexical scanning.
const int _maxDecoratedMatchesPerParagraph = 512;
const int _maxDecoratedSpansPerParagraph = 2048;

class _MarkdownMatchCache {
  static const _capacity = 256;
  static const _sourceCharacterBudget = 1024 * 1024;
  static final LinkedHashMap<String, List<RegExpMatch>> _entries =
      LinkedHashMap();
  static int _sourceCharacters = 0;
  static int scanCount = 0;

  static List<RegExpMatch> matches(String source) {
    final cached = _entries.remove(source);
    if (cached != null) {
      _entries[source] = cached;
      return cached;
    }

    scanCount++;
    final matches = _markdownPattern.allMatches(source).toList(growable: false);
    _entries[source] = matches;
    _sourceCharacters += source.length;
    while (_entries.length > _capacity ||
        _sourceCharacters > _sourceCharacterBudget) {
      final oldest = _entries.keys.first;
      _sourceCharacters -= oldest.length;
      _entries.remove(oldest);
    }

    return matches;
  }

  static void clear() {
    _entries.clear();
    _sourceCharacters = 0;
    scanCount = 0;
  }
}

@visibleForTesting
int get markdownLexicalScanCount => _MarkdownMatchCache.scanCount;

@visibleForTesting
void clearMarkdownLexicalCache() => _MarkdownMatchCache.clear();

class _MathPreviewCacheKey {
  const _MathPreviewCacheKey({
    required this.editorId,
    required this.nodeId,
    required this.offset,
    required this.expression,
    required this.display,
    required this.textStyle,
  });

  final int editorId;
  final String nodeId;
  final int offset;
  final String expression;
  final bool display;
  final TextStyle? textStyle;

  @override
  bool operator ==(Object other) =>
      other is _MathPreviewCacheKey &&
      other.editorId == editorId &&
      other.nodeId == nodeId &&
      other.offset == offset &&
      other.expression == expression &&
      other.display == display &&
      other.textStyle == textStyle;

  @override
  int get hashCode => Object.hash(
        editorId,
        nodeId,
        offset,
        expression,
        display,
        textStyle,
      );
}

class _MathPreviewCache {
  static const _capacity = 512;
  static const _sourceCharacterBudget = 64 * 1024;
  static final Expando<int> _editorIds = Expando();
  static int _nextEditorId = 0;
  static final LinkedHashMap<_MathPreviewCacheKey, Math> _widgets =
      LinkedHashMap();
  static int _sourceCharacters = 0;

  static int editorId(EditorState editorState) =>
      _editorIds[editorState] ??= _nextEditorId++;

  static Widget build({
    required _MathPreviewCacheKey cacheKey,
    required String expression,
    required String source,
    required bool display,
    required TextStyle? textStyle,
  }) {
    // flutter_math_fork's SyntaxTree is mutable during layout and stores
    // GlobalKeys. It is therefore unsafe to share one parsed AST between two
    // simultaneously mounted formula occurrences. Cache the complete Math
    // widget per document occurrence instead: the same occurrence can be
    // reused after viewport eviction, while duplicate expressions never share
    // an AST or its GlobalKeys.
    final cached = _widgets.remove(cacheKey);
    final parsed = cached ??
        Math.tex(
          expression,
          mathStyle: display ? MathStyle.display : MathStyle.text,
          textStyle: textStyle,
          onErrorFallback: (_) => Text(source, style: textStyle),
        );
    if (cached == null) _sourceCharacters += expression.length;
    _widgets[cacheKey] = parsed;
    while (_widgets.length > _capacity ||
        _sourceCharacters > _sourceCharacterBudget) {
      final oldest = _widgets.keys.first;
      _sourceCharacters -= oldest.expression.length;
      _widgets.remove(oldest);
    }

    return parsed;
  }
}

TextSpan markdownTextSpanDecorator(
  BuildContext context,
  Node node,
  int index,
  TextInsert text,
  TextSpan before,
  TextSpan after,
) {
  final editorState = context.read<EditorState>();
  final colors = editorState.editorStyle.colorScheme;
  final selection = editorState.selection;

  bool sameNode(List<int>? p1) {
    if (p1 == null) return false;
    if (p1.length != node.path.length) return false;
    for (int i = 0; i < p1.length; i++) {
      if (p1[i] != node.path[i]) return false;
    }

    return true;
  }

  bool overlaps(int matchStart, int matchEnd, {bool isLineLevel = false}) {
    if (selection == null) return false;
    bool sameNodeAsStart = sameNode(selection.start.path);
    bool sameNodeAsEnd = sameNode(selection.end.path);

    // 对于标题（isLineLevel），只要光标在当前节点（行）内，就始终显示源码
    if (isLineLevel && (sameNodeAsStart || sameNodeAsEnd)) return true;

    // 场景 A：普通光标移动（Collapsed Selection / Caret）
    if (selection.isCollapsed) {
      if (!sameNodeAsStart) return false;
      int offset = selection.start.offset;
      // 提前 1 个字符展开，确保光标进入符号时已是正常字号，消除“跳格”和“按两次”的错觉
      return offset >= matchStart - 1 && offset <= matchEnd + 1;
    }

    // 场景 B：区域选择（Selection Range）
    // 只有当选择范围的【起点】或【终点】落在区间内时才展开（通常是键盘选择或正在拖拽的端点）
    // 避免大面积鼠标滑动选择时，中间所有的 Markdown 符号全部炸开导致视觉干扰
    if (sameNodeAsStart) {
      int s = selection.start.offset;
      if (s >= matchStart && s <= matchEnd) return true;
    }
    if (sameNodeAsEnd) {
      int e = selection.end.offset;
      if (e >= matchStart && e <= matchEnd) return true;
    }

    return false;
  }

  final String content = text.text;
  TextStyle? baseStyle = before.style;
  final delta = node.delta;
  final decorationLimit =
      editorState.editorStyle.maxMarkdownDecorationCharacters;
  final paragraphLength = delta?.length ?? content.length;
  if (decorationLimit != null && paragraphLength > decorationLimit) {
    return TextSpan(text: content, style: baseStyle);
  }

  final hiddenStyle = baseStyle?.copyWith(
        fontSize: 0.1,
        height: 0.1,
        color: Colors.transparent,
      ) ??
      const TextStyle(fontSize: 0.1, height: 0.1, color: Colors.transparent);

  // 1: Bold, 2: Italic, 3: Strike, 4: Code, 5: Full Header Line,
  // 6: Checkbox (with optional list prefix), 7: Tag, 8: ListPrefix (Bullet),
  // 9: ListPrefix (Ordered), 10: DividerLine, 11: Display Math,
  // 12: Inline Math, 13: Highlight.
  final matches = _MarkdownMatchCache.matches(content);
  if (matches.isEmpty) {
    return TextSpan(text: content, style: baseStyle);
  }
  if (decorationLimit != null &&
      matches.length > _maxDecoratedMatchesPerParagraph) {
    return TextSpan(text: content, style: baseStyle);
  }

  List<InlineSpan> spans = [];
  int lastMatchEnd = 0;

  for (final match in matches) {
    if (match.start > lastMatchEnd) {
      spans.add(
        TextSpan(
          text: content.substring(lastMatchEnd, match.start),
          style: baseStyle,
        ),
      );
    }

    final fullMatchStr = match.group(0)!;
    final globalMatchStart = index + match.start;
    final globalMatchEnd = index + match.end;

    // 分别处理：如果是第 5 组（标题），开启全行显示模式
    bool isCaretIn = overlaps(
      globalMatchStart,
      globalMatchEnd,
      isLineLevel: match.group(5) != null ||
          match.group(10) != null ||
          match.group(11) != null,
    );

    // 11-12: LaTeX math. Keep the source visible while it is being edited,
    // and replace it with an atomic preview after the caret leaves the range.
    if (match.group(11) != null || match.group(12) != null) {
      final isDisplayMath = match.group(11) != null;
      final marker = isDisplayMath ? r'$$' : r'$';
      final isClosed = fullMatchStr.length > marker.length * 2 &&
          fullMatchStr.endsWith(marker);

      if (isCaretIn || !isClosed) {
        spans.add(TextSpan(text: fullMatchStr, style: baseStyle));
      } else {
        final expression = fullMatchStr.substring(
          marker.length,
          fullMatchStr.length - marker.length,
        );
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: editorState.editable
                  ? () {
                      editorState.updateSelectionWithReason(
                        Selection.collapsed(
                          Position(
                            path: node.path,
                            offset: globalMatchStart + marker.length,
                          ),
                        ),
                        reason: SelectionUpdateReason.uiEvent,
                      );
                    }
                  : null,
              child: RepaintBoundary(
                child: _MathPreviewCache.build(
                  cacheKey: _MathPreviewCacheKey(
                    editorId: _MathPreviewCache.editorId(editorState),
                    nodeId: node.id,
                    offset: globalMatchStart,
                    expression: expression,
                    display: isDisplayMath,
                    textStyle: baseStyle,
                  ),
                  expression: expression,
                  source: fullMatchStr,
                  display: isDisplayMath,
                  textStyle: baseStyle,
                ),
              ),
            ),
          ),
        );

        // A WidgetSpan occupies one text offset. Preserve the remaining source
        // offsets so selection, copy, and keyboard navigation stay aligned with
        // the document's original Markdown text.
        if (fullMatchStr.length > 1) {
          spans.add(
            TextSpan(text: fullMatchStr.substring(1), style: hiddenStyle),
          );
        }
      }
    }
    // 13: Highlight. Parse only paired bold markers inside this match.
    else if (match.group(13) != null) {
      final highlightStyle = (baseStyle ?? const TextStyle()).copyWith(
        backgroundColor: colors.highlightBackground,
      );
      if (isCaretIn) {
        spans.add(TextSpan(text: fullMatchStr, style: highlightStyle));
      } else {
        spans.add(TextSpan(text: '===', style: hiddenStyle));
        final inner = fullMatchStr.substring(3, fullMatchStr.length - 3);
        if (!_appendNestedInlineSpans(
          spans: spans,
          source: inner,
          marker: '**',
          baseStyle: highlightStyle,
          nestedFontWeight: FontWeight.bold,
          hiddenStyle: hiddenStyle,
          spanLimit:
              decorationLimit == null ? null : _maxDecoratedSpansPerParagraph,
        )) {
          return TextSpan(text: content, style: baseStyle);
        }
        spans.add(TextSpan(text: '===', style: hiddenStyle));
      }
    }
    // 1-4: Inline formats
    else if (match.group(1) != null ||
        match.group(2) != null ||
        match.group(3) != null ||
        match.group(4) != null) {
      String marker = '';
      TextStyle? styledMatch;
      if (match.group(1) != null) {
        marker = '**';
        styledMatch = baseStyle?.copyWith(fontWeight: FontWeight.bold);
      } else if (match.group(2) != null) {
        marker = '*';
        styledMatch = baseStyle?.copyWith(fontStyle: FontStyle.italic);
      } else if (match.group(3) != null) {
        marker = '~~';
        styledMatch = baseStyle?.copyWith(
          decoration: TextDecoration.lineThrough,
        );
      } else if (match.group(4) != null) {
        marker = '`';
        styledMatch = baseStyle?.copyWith(
          backgroundColor: colors.subtleBackground,
          fontFamily: 'monospace',
        );
      }

      // 判定是否闭合：首尾都有 marker 且长度足够
      bool isClosed = fullMatchStr.startsWith(marker) &&
          fullMatchStr.endsWith(marker) &&
          fullMatchStr.length >= marker.length * 2;

      // 如果未闭合，或者光标在区间内（包含 Buffer），则显示源码
      if (isCaretIn || !isClosed) {
        spans.add(
          TextSpan(text: fullMatchStr, style: styledMatch ?? baseStyle),
        );
      } else {
        // 已闭合且光标不在区间内：隐藏前后 marker
        spans.add(TextSpan(text: marker, style: hiddenStyle));
        final inner = fullMatchStr.substring(
          marker.length,
          fullMatchStr.length - marker.length,
        );
        if (match.group(1) != null) {
          final boldStyle = styledMatch ?? baseStyle ?? const TextStyle();
          if (!_appendNestedInlineSpans(
            spans: spans,
            source: inner,
            marker: '===',
            baseStyle: boldStyle,
            nestedBackgroundColor: colors.highlightBackground,
            hiddenStyle: hiddenStyle,
            spanLimit:
                decorationLimit == null ? null : _maxDecoratedSpansPerParagraph,
          )) {
            return TextSpan(text: content, style: baseStyle);
          }
        } else {
          spans.add(TextSpan(text: inner, style: styledMatch ?? baseStyle));
        }
        spans.add(TextSpan(text: marker, style: hiddenStyle));
      }
    }
    // 5: Header Line
    else if (match.group(5) != null) {
      final headerContent = match.group(5)!;
      final int hashCount =
          _headingHashesPattern.firstMatch(headerContent)?.group(0)?.length ??
              0;
      double fontSize = 16;
      if (hashCount == 1) {
        fontSize = 28;
      } else if (hashCount == 2) {
        fontSize = 24;
      } else if (hashCount == 3) {
        fontSize = 20;
      } else if (hashCount > 3) {
        fontSize = 18;
      }

      final headerStyle = baseStyle?.copyWith(
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
      );

      if (isCaretIn) {
        spans.add(TextSpan(text: headerContent, style: headerStyle));
      } else {
        // Hide only the prefix symbols like "### "
        final prefixMatch = _headingPrefixPattern.firstMatch(headerContent);
        if (prefixMatch != null) {
          final prefix = prefixMatch.group(0)!;
          spans.add(TextSpan(text: prefix, style: hiddenStyle));
          spans.add(
            TextSpan(
              text: headerContent.substring(prefix.length),
              style: headerStyle,
            ),
          );
        } else {
          spans.add(TextSpan(text: headerContent, style: headerStyle));
        }
      }
    }
    // 6: Checkbox
    else if (match.group(6) != null) {
      final isChecked = fullMatchStr.contains('[x]');
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SizedBox.square(
            dimension: (baseStyle?.fontSize ?? 16) * 1.35,
            child: Material(
              type: MaterialType.transparency,
              child: Checkbox(
                value: isChecked,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                splashRadius: 0,
                overlayColor:
                    const WidgetStatePropertyAll<Color>(Colors.transparent),
                activeColor: colors.primary,
                checkColor: colors.background,
                side: BorderSide(color: colors.border, width: 1.5),
                onChanged: editorState.editable
                    ? (checked) {
                        final checkboxMatch =
                            _checkboxPattern.firstMatch(fullMatchStr)!;
                        final prefix =
                            fullMatchStr.substring(0, checkboxMatch.start);
                        final newText =
                            '$prefix${checked == true ? '[x]' : '[ ]'}';
                        final transaction = editorState.transaction
                          ..replaceText(
                            node,
                            globalMatchStart,
                            fullMatchStr.length,
                            newText,
                          );
                        editorState.apply(transaction);
                      }
                    : null,
              ),
            ),
          ),
        ),
      );
      // Preserve the source offsets while always keeping the visual checkbox.
      if (fullMatchStr.length > 1) {
        spans.add(
          TextSpan(text: fullMatchStr.substring(1), style: hiddenStyle),
        );
      }
    }
    // 7: Tag
    else if (match.group(7) != null) {
      if (isCaretIn) {
        spans.add(
          TextSpan(
            text: fullMatchStr,
            style: baseStyle?.copyWith(color: colors.primary),
          ),
        );
      } else {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.tagBackground,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colors.tagBorder),
              ),
              child: Text(
                fullMatchStr,
                style: baseStyle?.copyWith(
                  color: colors.primary,
                  fontSize: (baseStyle.fontSize ?? 16) * 0.9,
                ),
              ),
            ),
          ),
        );
        // IMPORTANT: Pad with hidden characters to match original string length
        final int paddingLength = fullMatchStr.length - 1;
        if (paddingLength > 0) {
          final String paddingText = fullMatchStr.substring(1);
          spans.add(TextSpan(text: paddingText, style: hiddenStyle));
        }
      }
    }
    // 8: List Prefix (Bullet/Numbered)
    else if (match.group(8) != null || match.group(9) != null) {
      if (isCaretIn) {
        spans.add(TextSpan(text: fullMatchStr, style: baseStyle));
      } else {
        if (match.group(8) != null) {
          // Unordered list
          spans.add(
            TextSpan(
              text: '•',
              style: baseStyle?.copyWith(fontWeight: FontWeight.bold),
            ),
          );
          if (fullMatchStr.length > 1) {
            spans.add(
              TextSpan(text: fullMatchStr.substring(1), style: hiddenStyle),
            );
          }
        } else {
          // Ordered list
          spans.add(
            TextSpan(
              text: fullMatchStr,
              style: baseStyle?.copyWith(fontWeight: FontWeight.bold),
            ),
          );
        }
      }
    }
    // 10: Divider
    else if (match.group(10) != null) {
      if (isCaretIn) {
        spans.add(TextSpan(text: fullMatchStr, style: baseStyle));
      } else {
        spans.add(
          WidgetSpan(
            child: Container(
              height: 10,
              alignment: Alignment.center,
              child: Divider(height: 1, thickness: 1, color: colors.border),
            ),
          ),
        );
        if (fullMatchStr.length > 1) {
          spans.add(
            TextSpan(text: fullMatchStr.substring(1), style: hiddenStyle),
          );
        }
      }
    } else {
      spans.add(TextSpan(text: fullMatchStr, style: baseStyle));
    }

    if (decorationLimit != null &&
        spans.length > _maxDecoratedSpansPerParagraph) {
      return TextSpan(text: content, style: baseStyle);
    }
    lastMatchEnd = match.end;
  }

  if (lastMatchEnd < content.length) {
    spans.add(
      TextSpan(text: content.substring(lastMatchEnd), style: baseStyle),
    );
  }

  return TextSpan(children: spans, style: baseStyle);
}

/// Splits a formatted range around one kind of nested marker in linear time.
/// The total span budget also covers many nested pairs inside one regex match.
bool _appendNestedInlineSpans({
  required List<InlineSpan> spans,
  required String source,
  required String marker,
  required TextStyle baseStyle,
  Color? nestedBackgroundColor,
  FontWeight? nestedFontWeight,
  required TextStyle hiddenStyle,
  required int? spanLimit,
}) {
  var offset = 0;
  TextStyle? nestedStyle;
  while (offset < source.length) {
    final opening = source.indexOf(marker, offset);
    if (opening < 0) break;
    final closing = source.indexOf(marker, opening + marker.length);
    if (closing <= opening + marker.length) break;
    if (spanLimit != null && spans.length + 4 > spanLimit) return false;

    if (opening > offset) {
      spans.add(
        TextSpan(text: source.substring(offset, opening), style: baseStyle),
      );
    }
    spans.add(TextSpan(text: marker, style: hiddenStyle));
    spans.add(
      TextSpan(
        text: source.substring(opening + marker.length, closing),
        style: nestedStyle ??= baseStyle.copyWith(
          backgroundColor: nestedBackgroundColor,
          fontWeight: nestedFontWeight,
        ),
      ),
    );
    spans.add(TextSpan(text: marker, style: hiddenStyle));
    offset = closing + marker.length;
  }
  if (offset < source.length) {
    spans.add(TextSpan(text: source.substring(offset), style: baseStyle));
  }
  return spanLimit == null || spans.length <= spanLimit;
}
