import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// EditorHeightService tracks and estimates the height of all blocks in the document.
/// It helps in implementing auto-expanding editors without using [IntrinsicHeight].
class EditorHeightService extends ChangeNotifier {
  EditorHeightService({required this.editorState}) {
    totalHeightNotifier = ValueNotifier(_calculateInitialTotalHeight());
    editorState.transactionStream.listen((_) {
      _calculateTotalHeight();
    });
  }

  double _calculateInitialTotalHeight() {
    double total = 0;
    final nodes = editorState.document.root.children;
    final double verticalPadding = editorState.editorStyle.padding.vertical;
    for (final node in nodes) {
      total += _estimateNodeHeight(node) + verticalPadding;
    }
    return total;
  }

  final EditorState editorState;

  /// Cached heights of nodes that have been rendered.
  final Map<String, double> _cachedHeights = {};

  late final ValueNotifier<double> totalHeightNotifier;
  double get totalHeight => totalHeightNotifier.value;

  /// Reports the actual height of a node after it has been laid out.
  void reportHeight(String nodeKey, double height) {
    if (_cachedHeights[nodeKey] == height) return;
    _cachedHeights[nodeKey] = height;
    _calculateTotalHeight();
  }

  /// Removes a cached height when a node is deleted.
  void removeHeight(String nodeKey) {
    if (_cachedHeights.remove(nodeKey) != null) {
      _calculateTotalHeight();
    }
  }

  bool _isCalculating = false;

  /// Calculates the total height by summing cached heights and estimating others.
  void _calculateTotalHeight() {
    if (_isCalculating) return;
    _isCalculating = true;

    // We can use a microtask to avoid immediate recursive calls or build phase issues.
    Future.microtask(() {
      _isCalculating = false;
      double total = 0;
      final nodes = editorState.document.root.children;
      final double verticalPadding = editorState.editorStyle.padding.vertical;

      for (final node in nodes) {
        final cached = _cachedHeights[node.id];
        if (cached != null) {
          total += cached + verticalPadding;
        } else {
          total += _estimateNodeHeight(node) + verticalPadding;
        }
      }

      if (totalHeightNotifier.value != total) {
        totalHeightNotifier.value = total;
      }
    });
  }

  double _estimateNodeHeight(Node node) {
    if (node.type == 'paragraph') {
      final text = node.delta?.toPlainText() ?? '';
      if (text.isEmpty) return 24.0;
      final lines = (text.length / 40).ceil();
      return lines * 24.0;
    }

    if (node.type == 'heading') {
      final level = node.attributes['heading']?[0] as int? ?? 1; // Assuming 'heading' is a list like [1] or attribute `level` depending on delta.
      final text = node.delta?.toPlainText() ?? '';
      final fontSizes = [32.0, 32.0, 28.0, 24.0, 18.0, 18.0, 18.0];
      final fontSize = fontSizes[level.clamp(0, 6)];
      if (text.isEmpty) return fontSize * 1.5;
      final lines = (text.length / (40 * (16 / fontSize))).ceil();
      return lines * (fontSize * 1.5); // Estimate 1.5 line height.
    }

    if (node.type == 'divider') {
      return 20.0;
    }

    if (node.type == 'image' || node.type == 'video') {
      return 200.0; // Placeholder for media
    }

    return 30.0;
  }

  void forceRecalculate() {
    _calculateTotalHeight();
  }

  @override
  void dispose() {
    _cachedHeights.clear();
    super.dispose();
  }
}
