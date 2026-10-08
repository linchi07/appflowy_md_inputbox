import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

ButtonStyle buildOverlayButtonStyle(BuildContext context) {
  final colors = EditorTheme.of(context);
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith<Color>(
      (Set<WidgetState> states) {
        if (states.contains(WidgetState.hovered)) {
          return colors.hover;
        }

        return Colors.transparent;
      },
    ),
  );
}

BoxDecoration buildOverlayDecoration(BuildContext context) =>
    EditorMenuSurface.decoration(context);

class EditorOverlayTitle extends StatelessWidget {
  const EditorOverlayTitle({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
        ).copyWith(color: EditorTheme.of(context).onSurface),
      ),
    );
  }
}

(double?, double?, double?) positionFromRect(
  Rect rect,
  EditorState editorState,
) {
  final left = rect.left + 10;
  double? top;
  double? bottom;
  final offset = rect.center;
  final editorOffset = editorState.renderBox!.localToGlobal(Offset.zero);
  final editorHeight = editorState.renderBox!.size.height;
  final threshold = editorOffset.dy + editorHeight - 200;
  if (offset.dy > threshold) {
    bottom = editorOffset.dy + editorHeight - rect.top - 5;
  } else {
    top = rect.bottom + 5;
  }

  return (top, bottom, left);
}

Widget basicOverlay(
  BuildContext context, {
  double? width,
  double? height,
  required List<Widget> children,
}) {
  return SizedBox(
    width: width,
    height: height,
    child: EditorMenuSurface(
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    ),
  );
}
