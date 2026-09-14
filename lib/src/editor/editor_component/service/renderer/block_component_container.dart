import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/editor_component/service/scroll/editor_height_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

/// BlockComponentContainer is a wrapper of block component
///
/// 1. used to update the child widget when node is changed
/// ~~2. used to show block component actions~~
/// 3. used to add the layer link to the child widget
class BlockComponentContainer extends StatelessWidget {
  const BlockComponentContainer({
    super.key,
    required this.configuration,
    required this.node,
    required this.builder,
  });

  final Node node;
  final BlockComponentConfiguration configuration;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final child = ChangeNotifierProvider<Node>.value(
      value: node,
      child: Consumer<Node>(
        builder: (_, __, ___) {
          return CompositedTransformTarget(
            link: node.layerLink,
            child: builder(context),
          );
        },
      ),
    );

    // Use RepaintBoundary to isolate block repaints (reduce CPU / Paint cost)
    // Use _SizeReporter to notify HeightService about the actual height.
    return RepaintBoundary(
      child: _SizeReporter(
        nodeId: node.id,
        heightService: context.read<EditorHeightService?>(),
        onSizeChanged: (size) {
          final service = context.read<EditorHeightService?>();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            service?.reportHeight(node.id, size.height);
          });
        },
        child: child,
      ),
    );
  }
}

class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({
    required this.nodeId,
    required this.heightService,
    required this.onSizeChanged,
    super.child,
  });

  final String nodeId;
  final EditorHeightService? heightService;
  final void Function(Size size) onSizeChanged;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSizeReporter(nodeId, heightService, onSizeChanged);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderSizeReporter renderObject,
  ) {
    renderObject.nodeId = nodeId;
    renderObject.heightService = heightService;
    renderObject.onSizeChanged = onSizeChanged;
  }
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.nodeId, this.heightService, this._onSizeChanged);

  String nodeId;
  EditorHeightService? heightService;
  void Function(Size size) _onSizeChanged;
  set onSizeChanged(void Function(Size size) value) {
    if (_onSizeChanged == value) return;
    _onSizeChanged = value;
  }

  Size? _lastSize;

  @override
  void detach() {
    _lastSize = null;
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    if (size != _lastSize) {
      final bool significant = _lastSize == null || (size.height - _lastSize!.height).abs() > 0.1;
      _lastSize = size;
      if (significant) {
        _onSizeChanged(size);
      }
    }
  }
}
