import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy_editor/src/flutter/scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

typedef ItemExtentEstimator = double? Function(Object itemId, double width);

/// A scrollbar for variable-height virtual documents that seeks by item index.
///
/// A regular [Scrollbar] writes a distant pixel offset into the underlying
/// sliver. For a document whose off-screen block heights are still unknown,
/// that can force expensive extent estimation. This scrollbar maps the thumb
/// to a block index and uses [ItemScrollController.jumpTo] instead.
class IndexedDocumentScrollbar extends StatefulWidget {
  const IndexedDocumentScrollbar({
    super.key,
    required this.itemIds,
    required this.itemScrollController,
    required this.itemPositionsListener,
    required this.child,
    this.scrollOffsetController,
    this.estimateItemExtent,
    this.color = const Color(0x667A7D85),
  });

  final List<Object> itemIds;
  final ItemScrollController itemScrollController;
  final ScrollOffsetController? scrollOffsetController;
  final ItemPositionsListener itemPositionsListener;
  final ItemExtentEstimator? estimateItemExtent;
  final Widget child;
  final Color color;

  @override
  State<IndexedDocumentScrollbar> createState() =>
      _IndexedDocumentScrollbarState();
}

class _IndexedDocumentScrollbarState extends State<IndexedDocumentScrollbar> {
  static const _trackWidth = 16.0;
  static const _thumbWidth = 6.0;
  static const _minimumThumbExtent = 36.0;

  late BlockExtentIndex _extents;
  double? _dragFraction;
  double _grabOffset = 0;
  int? _pendingIndex;
  double _pendingIntraItemOffset = 0;
  double _pendingViewportExtent = 0;
  bool _jumpScheduled = false;
  int _jumpRevision = 0;
  bool _estimatesDirty = true;
  double? _estimateWidth;
  Timer? _settleTimer;

  @override
  void initState() {
    super.initState();
    _extents = BlockExtentIndex(widget.itemIds);
    widget.itemPositionsListener.itemPositions.addListener(_onPositionsChanged);
  }

  @override
  void didUpdateWidget(covariant IndexedDocumentScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemPositionsListener != widget.itemPositionsListener) {
      oldWidget.itemPositionsListener.itemPositions
          .removeListener(_onPositionsChanged);
      widget.itemPositionsListener.itemPositions
          .addListener(_onPositionsChanged);
    }
    _extents.updateItems(widget.itemIds);
    _estimatesDirty = true;
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    widget.itemPositionsListener.itemPositions
        .removeListener(_onPositionsChanged);
    super.dispose();
  }

  void _onPositionsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportExtent = constraints.maxHeight;
        final width = constraints.maxWidth;
        if (width.isFinite &&
            width > 0 &&
            (_estimatesDirty || _estimateWidth != width)) {
          _extents.updateEstimates(
            [
              for (final id in widget.itemIds)
                widget.estimateItemExtent?.call(id, width),
            ],
            invalidateMeasurements:
                _estimateWidth != null && _estimateWidth != width,
          );
          _estimateWidth = width;
          _estimatesDirty = false;
        }
        final positions = widget.itemPositionsListener.itemPositions.value
            .toList(growable: false);
        if (viewportExtent.isFinite && viewportExtent > 0) {
          for (final position in positions) {
            _extents.record(
              position.index,
              (position.itemTrailingEdge - position.itemLeadingEdge) *
                  viewportExtent,
            );
          }
        }

        final metrics = _calculateMetrics(
          viewportExtent: viewportExtent,
          positions: positions,
        );

        final scrollbarsDisabled = ScrollConfiguration.of(context).copyWith(
          scrollbars: false,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: ScrollConfiguration(
                behavior: scrollbarsDisabled,
                child: widget.child,
              ),
            ),
            if (metrics != null)
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                width: _trackWidth,
                child: MouseRegion(
                  cursor: SystemMouseCursors.basic,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapDown: (details) =>
                        _startDrag(details.localPosition.dy, metrics),
                    onVerticalDragStart: (details) =>
                        _startDrag(details.localPosition.dy, metrics),
                    onVerticalDragUpdate: (details) =>
                        _updateDrag(details.localPosition.dy, metrics),
                    onVerticalDragEnd: (_) => _endDrag(),
                    onVerticalDragCancel: _endDrag,
                    child: Stack(
                      children: [
                        Positioned(
                          top: metrics.thumbOffset,
                          right: (_trackWidth - _thumbWidth) / 2,
                          width: _thumbWidth,
                          height: metrics.thumbExtent,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: widget.color,
                              borderRadius: BorderRadius.circular(
                                _thumbWidth / 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  _ScrollbarMetrics? _calculateMetrics({
    required double viewportExtent,
    required List<ItemPosition> positions,
  }) {
    if (!viewportExtent.isFinite ||
        viewportExtent <= 0 ||
        widget.itemIds.isEmpty ||
        positions.isEmpty) {
      return null;
    }

    final totalExtent = _extents.totalExtent;
    if (totalExtent <= viewportExtent) return null;

    final first = positions
        .where((position) => position.itemTrailingEdge > 0)
        .fold<ItemPosition?>(
          null,
          (current, position) =>
              current == null || position.index < current.index
                  ? position
                  : current,
        );
    if (first == null) return null;

    final estimatedOffset = (_extents.offsetOf(first.index) -
            first.itemLeadingEdge * viewportExtent)
        .clamp(0.0, totalExtent - viewportExtent);
    final scrollFraction =
        _dragFraction ?? estimatedOffset / (totalExtent - viewportExtent);
    final thumbExtent = math
        .max(
          _minimumThumbExtent,
          viewportExtent * viewportExtent / totalExtent,
        )
        .clamp(0.0, viewportExtent);

    return _ScrollbarMetrics(
      viewportExtent: viewportExtent,
      thumbExtent: thumbExtent,
      thumbOffset: scrollFraction * (viewportExtent - thumbExtent),
      totalExtent: totalExtent,
    );
  }

  void _startDrag(double localY, _ScrollbarMetrics metrics) {
    _settleTimer?.cancel();
    final insideThumb = localY >= metrics.thumbOffset &&
        localY <= metrics.thumbOffset + metrics.thumbExtent;
    _grabOffset =
        insideThumb ? localY - metrics.thumbOffset : metrics.thumbExtent / 2;
    _updateDrag(localY, metrics);
  }

  void _updateDrag(double localY, _ScrollbarMetrics metrics) {
    final availableTrack = metrics.viewportExtent - metrics.thumbExtent;
    if (availableTrack <= 0) return;
    final fraction = ((localY - _grabOffset) / availableTrack).clamp(0.0, 1.0);
    setState(() => _dragFraction = fraction);

    final targetOffset =
        fraction * (metrics.totalExtent - metrics.viewportExtent);
    final index = _extents.indexAtOffset(targetOffset);
    _scheduleJump(
      index,
      targetOffset - _extents.offsetOf(index),
      metrics.viewportExtent,
    );
  }

  void _scheduleJump(
    int index,
    double intraItemOffset,
    double viewportExtent,
  ) {
    _pendingIndex = index.clamp(0, math.max(0, widget.itemIds.length - 1));
    _pendingIntraItemOffset = intraItemOffset;
    _pendingViewportExtent = viewportExtent;
    ++_jumpRevision;
    if (_jumpScheduled) return;
    _jumpScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _jumpScheduled = false;
      final target = _pendingIndex;
      final intraItemOffset = _pendingIntraItemOffset;
      final viewportExtent = _pendingViewportExtent;
      final revision = _jumpRevision;
      _pendingIndex = null;
      if (!mounted || target == null) return;
      if (widget.itemScrollController.isAttached) {
        final visibleTarget = widget.itemPositionsListener.itemPositions.value
            .where((position) => position.index == target)
            .firstOrNull;
        if (visibleTarget != null && widget.scrollOffsetController != null) {
          widget.scrollOffsetController!.jumpBy(
            offset: visibleTarget.itemLeadingEdge * viewportExtent +
                intraItemOffset,
          );
          return;
        }
        widget.itemScrollController.jumpTo(index: target);
        if (intraItemOffset > 0 && widget.scrollOffsetController != null) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted && revision == _jumpRevision) {
              widget.scrollOffsetController!.jumpBy(offset: intraItemOffset);
            }
          });
        }
      }
    });
  }

  void _endDrag() {
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 80), () {
      if (mounted) setState(() => _dragFraction = null);
    });
  }
}

class _ScrollbarMetrics {
  const _ScrollbarMetrics({
    required this.viewportExtent,
    required this.thumbExtent,
    required this.thumbOffset,
    required this.totalExtent,
  });

  final double viewportExtent;
  final double thumbExtent;
  final double thumbOffset;
  final double totalExtent;
}

/// Prefix-sum index for measured block heights. Measurements belong to stable
/// block IDs, so inserting or removing an earlier block cannot move a height
/// onto a different block. Reordering rebuilds the prefix sums in O(n); height
/// updates and offset lookups take O(log n).
class BlockExtentIndex {
  BlockExtentIndex(List<Object> itemIds) {
    updateItems(itemIds);
  }

  static const double _estimatedExtent = 28;
  List<Object> _itemIds = const [];
  List<double> _tree = const [];
  final Map<Object, double> _measured = {};
  final Map<Object, double> _estimated = {};

  double get totalExtent => offsetOf(_itemIds.length);

  void updateItems(List<Object> itemIds) {
    if (_itemIds.length == itemIds.length) {
      var unchanged = true;
      for (var i = 0; i < itemIds.length; i++) {
        if (_itemIds[i] != itemIds[i]) {
          unchanged = false;
          break;
        }
      }
      if (unchanged) return;
    }

    _itemIds = List<Object>.of(itemIds, growable: false);
    final liveIds = _itemIds.toSet();
    _measured.removeWhere((id, _) => !liveIds.contains(id));
    _estimated.removeWhere((id, _) => !liveIds.contains(id));
    _rebuildTree();
  }

  void updateEstimates(
    List<double?> extents, {
    bool invalidateMeasurements = false,
  }) {
    assert(extents.length == _itemIds.length);
    if (invalidateMeasurements) _measured.clear();
    var changed = invalidateMeasurements;
    for (var i = 0; i < _itemIds.length; i++) {
      final id = _itemIds[i];
      final extent = extents[i];
      final next = extent != null && extent.isFinite && extent > 0
          ? extent
          : _estimatedExtent;
      if (_estimated[id] == next) continue;
      _estimated[id] = next;
      _measured.remove(id);
      changed = true;
    }
    if (changed) _rebuildTree();
  }

  double extentAt(int index) {
    if (index < 0 || index >= _itemIds.length) return 0;
    final id = _itemIds[index];
    return _measured[id] ?? _estimated[id] ?? _estimatedExtent;
  }

  void _rebuildTree() {
    _tree = List<double>.filled(_itemIds.length + 1, 0);
    for (var i = 1; i < _tree.length; i++) {
      _tree[i] += extentAt(i - 1);
      final parent = i + (i & -i);
      if (parent < _tree.length) _tree[parent] += _tree[i];
    }
  }

  void record(int index, double extent) {
    if (index < 0 ||
        index >= _itemIds.length ||
        !extent.isFinite ||
        extent <= 0) {
      return;
    }
    final normalized = extent;
    final id = _itemIds[index];
    final oldExtent = extentAt(index);
    if ((oldExtent - normalized).abs() < 0.5) return;
    _measured[id] = normalized;
    _add(index, normalized - oldExtent);
  }

  double offsetOf(int index) {
    return _prefixExtent(index.clamp(0, _itemIds.length));
  }

  int indexAtOffset(double offset) {
    if (_itemIds.isEmpty) return 0;
    var index = 0;
    var sum = 0.0;
    var bit = 1;
    while (bit < _tree.length) {
      bit <<= 1;
    }
    for (bit >>= 1; bit > 0; bit >>= 1) {
      final next = index + bit;
      if (next < _tree.length && sum + _tree[next] <= offset) {
        index = next;
        sum += _tree[next];
      }
    }
    return index.clamp(0, _itemIds.length - 1);
  }

  void _add(int index, double delta) {
    for (var cursor = index + 1;
        cursor < _tree.length;
        cursor += cursor & -cursor) {
      _tree[cursor] += delta;
    }
  }

  double _prefixExtent(int length) {
    var result = 0.0;
    for (var cursor = length; cursor > 0; cursor -= cursor & -cursor) {
      result += _tree[cursor];
    }
    return result;
  }
}
