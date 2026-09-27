import 'dart:math' as math;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// A cheap offscreen estimate for nodes without their own extent estimator.
/// Text uses the editor's actual font metrics and the available wrap width.
/// The extent index replaces these estimates with measured viewport heights.
class BlockHeightOracle {
  BlockHeightOracle(
    EditorStyle style,
    double availableWidth, {
    TextStyle? resolvedTextStyle,
  }) : _padding = style.padding.vertical {
    final textStyle =
        (resolvedTextStyle ?? style.textStyleConfiguration.text).copyWith(
      height: style.textStyleConfiguration.lineHeight,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: 'abcdefghijklmnopqrstuvwxyz0123456789',
        style: textStyle,
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(style.textScaleFactor),
    )..layout();
    lineHeight = math.max(1, painter.height);
    final charWidth = math.max(1, painter.width / 36);
    final width = math.min(
          availableWidth,
          style.maxWidth ?? availableWidth,
        ) -
        style.padding.horizontal;
    columns = math.max(1, (width / charWidth).floor());
    painter.dispose();
  }

  static const _sampleLimit = 16 * 1024;
  final double _padding;
  late final double lineHeight;
  late final int columns;

  double estimate(Node node) {
    final delta = node.delta;
    if (delta != null) {
      final source = delta.toPlainText();
      var rows = 1;
      var column = 0;
      var sampled = 0;
      for (final rune in source.runes) {
        if (sampled >= _sampleLimit) break;
        sampled++;
        if (rune == 0x0A) {
          rows++;
          column = 0;
          continue;
        }
        final width = rune == 0x09
            ? 4
            : rune >= 0x2E80
                ? 2
                : 1;
        if (column + width > columns) {
          rows++;
          column = 0;
        }
        column += width;
      }
      if (source.length > sampled && sampled > 0) {
        rows = math.max(rows, (rows * source.length / sampled).ceil());
      }
      return _padding + rows * lineHeight;
    }
    // A child-bearing widget is more likely to grow in two dimensions than a
    // plain text line. The measured nodes of its type calibrate this seed.
    final childRows = math.max(1, math.sqrt(node.childCount).ceil());
    return _padding + childRows * lineHeight;
  }
}
