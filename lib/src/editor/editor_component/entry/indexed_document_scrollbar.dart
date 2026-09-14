import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy_editor/src/flutter/scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A scrollbar for variable-height virtual documents that seeks by item index.
///
/// A regular [Scrollbar] writes a distant pixel offset into the underlying
/// sliver. For a document whose off-screen block heights are still unknown,
/// that can force expensive extent estimation. This scrollbar maps the thumb
/// to a block index and uses [ItemScrollController.jumpTo] instead.
class IndexedDocumentScrollbar extends StatefulWidget {
  const IndexedDocumentScrollbar({
    super.key,
    required this.itemCount,
    required this.itemScrollController,
    required this.itemPositionsListener,
    required this.child,
    this.color = const Color(0x667A7D85),
  });

  final int itemCount;
  final ItemScrollController itemScrollController;
  final ItemPositionsListener itemPositionsListener;
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
  bool _jumpScheduled = false;
  Timer? _settleTimer;

  @override
  void initState() {
    super.initState();
    _extents = BlockExtentIndex(widget.itemCount);
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
    if (oldWidget.itemCount != widget.itemCount) {
      _extents.resize(widget.itemCount);
    }
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
        widget.itemCount <= 0 ||
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
    _scheduleJump(_extents.indexAtOffset(targetOffset));
  }

  void _scheduleJump(int index) {
    _pendingIndex = index.clamp(0, math.max(0, widget.itemCount - 1));
    if (_jumpScheduled) return;
    _jumpScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _jumpScheduled = false;
      final target = _pendingIndex;
      _pendingIndex = null;
      if (!mounted || target == null) return;
      if (widget.itemScrollController.isAttached) {
        widget.itemScrollController.jumpTo(index: target);
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

/// Prefix-sum index for measured block heights. Unknown blocks use a stable
/// estimate, while every visited block adds a correction to the Fenwick tree.
class BlockExtentIndex {
  BlockExtentIndex(int count) : _count = count {
    _tree = List.filled(count + 1, 0);
    _measured = List.filled(count, null);
  }

  static const double _estimatedExtent = 28;
  int _count;
  late List<double> _tree;
  late List<double?> _measured;

  double get totalExtent => offsetOf(_count);

  void resize(int count) {
    if (count == _count) return;
    final previous = _measured;
    _count = count;
    _tree = List.filled(count + 1, 0);
    _measured = List.filled(count, null);
    for (var index = 0; index < math.min(count, previous.length); index++) {
      final extent = previous[index];
      if (extent != null) record(index, extent);
    }
  }

  void record(int index, double extent) {
    if (index < 0 || index >= _count || !extent.isFinite || extent <= 0) return;
    final normalized = extent.clamp(1.0, 10000.0);
    final oldExtent = _measured[index] ?? _estimatedExtent;
    if ((oldExtent - normalized).abs() < 0.5) return;
    _measured[index] = normalized;
    _add(index, normalized - oldExtent);
  }

  double offsetOf(int index) {
    final bounded = index.clamp(0, _count);
    return bounded * _estimatedExtent + _prefixCorrection(bounded);
  }

  int indexAtOffset(double offset) {
    if (_count == 0) return 0;
    var low = 0;
    var high = _count;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (offsetOf(middle + 1) <= offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low.clamp(0, _count - 1);
  }

  void _add(int index, double delta) {
    for (var cursor = index + 1;
        cursor < _tree.length;
        cursor += cursor & -cursor) {
      _tree[cursor] += delta;
    }
  }

  double _prefixCorrection(int length) {
    var result = 0.0;
    for (var cursor = length; cursor > 0; cursor -= cursor & -cursor) {
      result += _tree[cursor];
    }
    return result;
  }
}
