import 'package:appflowy_editor/appflowy_editor.dart';

final _dividerPattern = RegExp(r'^([-*_])\1{2,}$|^—-$|^——-$');

final dividerPromotionRule = TextNodePromotionRule(
  sourceType: ParagraphBlockKeys.type,
  promote: (node) {
    final source = node.delta?.toPlainText() ?? '';
    if (!_dividerPattern.hasMatch(source)) return null;
    return TextNodePromotion(
      nodes: [dividerNode(), paragraphNode()],
      caretNodeIndex: 1,
      caretOffset: (_) => 0,
    );
  },
);
