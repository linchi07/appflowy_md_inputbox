import 'package:appflowy_editor/appflowy_editor.dart';
import '../rich_text/markdown_block_syntax.dart';

/// Promotes a typed Markdown fence after its text transaction completes.
final codeFencePromotionRule = TextNodePromotionRule(
  sourceType: ParagraphBlockKeys.type,
  promote: (node) {
    final source = node.delta?.toPlainText() ?? '';
    if (source.length > 64 * 1024 || !source.contains('\n')) return null;
    final fence = parseMarkdownFencedBlock(source);
    if (fence?.kind != MarkdownFencedBlockKind.code) return null;
    final body = source.substring(fence!.openingEnd, fence.contentEnd);
    return TextNodePromotion(
      nodes: [
        codeBlockNode(
          code: body,
          language: fence.language ?? '',
          openingFence: source.substring(0, source.indexOf('\n')),
          closed: fence.isClosed,
        ),
      ],
      caretNodeIndex: 0,
      caretOffset: (oldOffset) =>
          (oldOffset - fence.openingEnd).clamp(0, body.length),
    );
  },
);
