import 'package:appflowy_editor/appflowy_editor.dart';
import '../rich_text/markdown_block_syntax.dart';

/// While a fence is still a paragraph, its body owns literal paste. Parsing
/// the clipboard by itself would split the body before the promotion rule can
/// see the complete fence.
final codeFenceDraftParagraphBehavior = NodeBehavior(
  literalPaste: (state, node, selection, text) {
    if (!selection.isCollapsed || !selection.isSingle) return null;
    final source = node.delta?.toPlainText() ?? '';
    final fence = parseMarkdownFencedBlock(source);
    if (fence?.kind != MarkdownFencedBlockKind.code) return null;
    final offset = selection.start.offset;
    if (offset < fence!.openingEnd || offset > fence.contentEnd) return null;
    if (!source.contains('\n') && !text.startsWith('\n')) return '\n$text';
    return text;
  },
);

/// Promotes a typed Markdown fence after its text transaction completes.
final codeFencePromotionRule = TextNodePromotionRule(
  sourceType: ParagraphBlockKeys.type,
  promote: (node) {
    final source = node.delta?.toPlainText() ?? '';
    if (source.length > 64 * 1024 || !source.contains('\n')) return null;
    final fence = parseMarkdownFencedBlock(source);
    if (fence?.hasMultipleCodeLines != true) return null;
    final body = source.substring(fence!.openingEnd, fence.contentEnd);
    final closingLineEnd = fence.closingStart == null
        ? -1
        : source.indexOf('\n', fence.closingStart!);
    final suffixStart = closingLineEnd < 0 ? -1 : closingLineEnd + 1;
    final hasSuffix = suffixStart >= 0;
    final suffix = hasSuffix ? source.substring(suffixStart) : '';
    return TextNodePromotion(
      nodes: [
        codeBlockNode(
          code: body,
          language: fence.language ?? '',
          openingFence: source.substring(0, source.indexOf('\n')),
          closed: fence.isClosed,
        ),
        if (hasSuffix) paragraphNode(delta: Delta()..insert(suffix)),
      ],
      caretNodeIndex: 0,
      caretNodeIndexForOffset:
          hasSuffix ? (oldOffset) => oldOffset >= suffixStart ? 1 : 0 : null,
      caretOffset: (oldOffset) => hasSuffix && oldOffset >= suffixStart
          ? (oldOffset - suffixStart).clamp(0, suffix.length)
          : (oldOffset - fence.openingEnd).clamp(0, body.length),
    );
  },
);
