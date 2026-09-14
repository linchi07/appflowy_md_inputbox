import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// CursorOverlay renders the blinking cursor in a separate layer to avoid repainting blocks.
class CursorOverlay extends StatefulWidget {
  const CursorOverlay({super.key});

  @override
  State<CursorOverlay> createState() => _CursorOverlayState();
}

class _CursorOverlayState extends State<CursorOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _cursorController;
  late Animation<double> _cursorAnimation;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _cursorAnimation = CurvedAnimation(
      parent: _cursorController,
      curve: Curves.linear,
    );
    _cursorController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editorState = context.read<EditorState>();

    return ValueListenableBuilder<Selection?>(
      valueListenable: editorState.selectionNotifier,
      builder: (context, selection, child) {
        if (selection == null || !selection.isCollapsed) {
          return const SizedBox.shrink();
        }

        final node = editorState.getNodeAtPath(selection.start.path);
        if (node == null) {
          return const SizedBox.shrink();
        }

        // Use the node's layerLink to position the cursor.
        return CompositedTransformFollower(
          link: node.layerLink,
          showWhenUnlinked: false, // Don't show if the block is off-screen
          child: _IndependentCursor(
            editorState: editorState,
            selection: selection,
            node: node,
            animation: _cursorAnimation,
          ),
        );
      },
    );
  }
}

class _IndependentCursor extends StatelessWidget {
  const _IndependentCursor({
    required this.editorState,
    required this.selection,
    required this.node,
    required this.animation,
  });

  final EditorState editorState;
  final Selection selection;
  final Node node;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: CustomPaint(
        painter: _CursorPainter(
          node: node,
          selection: selection,
          editorState: editorState,
        ),
      ),
    );
  }
}

class _CursorPainter extends CustomPainter {
  final Node node;
  final Selection selection;
  final EditorState editorState;

  _CursorPainter({
    required this.node,
    required this.selection,
    required this.editorState,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final selectable = node.selectable;
    if (selectable == null) return;
    
    final rect = selectable.getCursorRectInPosition(selection.start);
    if (rect == null || rect.isEmpty) return;

    final cursorWidth = editorState.editorStyle.cursorWidth > 0 
        ? editorState.editorStyle.cursorWidth 
        : 2.0;

    final paint = Paint()
      ..color = editorState.editorStyle.cursorColor
      ..style = PaintingStyle.fill;
      
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, cursorWidth, rect.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CursorPainter oldDelegate) {
    return oldDelegate.node != node || oldDelegate.selection != selection;
  }
}
