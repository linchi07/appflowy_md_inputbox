import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../appflowy_editor.dart';

TextSpan markdownTextSpanDecorator(
  BuildContext context,
  Node node,
  int index,
  TextInsert text,
  TextSpan before,
  TextSpan after,
) {
  final editorState = context.read<EditorState>();
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

  final hiddenStyle = baseStyle?.copyWith(
        fontSize: 0.1,
        height: 0.1,
        color: Colors.transparent,
      ) ??
      const TextStyle(fontSize: 0.1, height: 0.1, color: Colors.transparent);

  // 1: Bold, 2: Italic, 3: Strike, 4: Code, 5: Full Header Line, 6: Checkbox (with optional list prefix), 7: Tag, 8: ListPrefix (Bullet), 9: ListPrefix (Ordered), 10: DividerLine
  final RegExp exp = RegExp(
    r'(\*\*.*?(?:\*\*|$))|(\*.*?(?:\*|$))|(~~.*?(?:~~|$))|(`.*?(?:`|$))|^(#{1,6}\s+.*)$|((?:^[-*]\s+)?\[[ x]])|(#[\w\u4e00-\u9fa5]+)|^([-*]\s+)|^(\d+\.\s+)|^([-*_]{3,})$',
    multiLine: true,
  );

  if (!exp.hasMatch(content)) {
    return TextSpan(text: content, style: baseStyle);
  }

  List<InlineSpan> spans = [];
  int lastMatchEnd = 0;

  for (final match in exp.allMatches(content)) {
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
      isLineLevel: match.group(5) != null || match.group(10) != null,
    );

    // 1-4: Inline formats
    if (match.group(1) != null ||
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
          backgroundColor: Colors.grey.withValues(alpha: 0.2),
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
        spans.add(
          TextSpan(
            text: fullMatchStr.substring(
              marker.length,
              fullMatchStr.length - marker.length,
            ),
            style: styledMatch ?? baseStyle,
          ),
        );
        spans.add(TextSpan(text: marker, style: hiddenStyle));
      }
    }
    // 5: Header Line
    else if (match.group(5) != null) {
      final headerContent = match.group(5)!;
      final int hashCount =
          RegExp('^#+').firstMatch(headerContent)?.group(0)?.length ?? 0;
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
        final prefixMatch = RegExp(r'^#+\s+').firstMatch(headerContent);
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
      if (isCaretIn) {
        spans.add(TextSpan(text: fullMatchStr, style: baseStyle));
      } else {
        bool isChecked = fullMatchStr.contains('x');
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: GestureDetector(
              onTap: () {
                // Determine current checkbox content and preserve prefix if any
                final checkboxMatch =
                    RegExp(r'\[[ x]]').firstMatch(fullMatchStr)!;
                final prefix = fullMatchStr.substring(0, checkboxMatch.start);
                final newCheckbox = isChecked ? '[ ]' : '[x]';
                final newText = '$prefix$newCheckbox';

                final transaction = editorState.transaction
                  ..replaceText(
                    node,
                    globalMatchStart,
                    fullMatchStr.length,
                    newText,
                  );
                editorState.apply(transaction);
              },
              child: Icon(
                isChecked ? Icons.check_box : Icons.check_box_outline_blank,
                size: (baseStyle?.fontSize ?? 16) * 1.2,
                color: isChecked ? Colors.blue : Colors.grey,
              ),
            ),
          ),
        );
        // IMPORTANT: Pad with hidden characters to match original string length
        // WidgetSpan occupies 1 char, so we hide fullMatchStr.length - 1 chars
        if (fullMatchStr.length > 1) {
          spans.add(
            TextSpan(text: fullMatchStr.substring(1), style: hiddenStyle),
          );
        }
      }
    }
    // 7: Tag
    else if (match.group(7) != null) {
      if (isCaretIn) {
        spans.add(
          TextSpan(
            text: fullMatchStr,
            style: baseStyle?.copyWith(color: Colors.blue),
          ),
        );
      } else {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
              ),
              child: Text(
                fullMatchStr,
                style: baseStyle?.copyWith(
                  color: Colors.blue,
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
              child: const Divider(height: 1, thickness: 1, color: Colors.grey),
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

    lastMatchEnd = match.end;
  }

  if (lastMatchEnd < content.length) {
    spans.add(
      TextSpan(text: content.substring(lastMatchEnd), style: baseStyle),
    );
  }

  return TextSpan(children: spans, style: baseStyle);
}
