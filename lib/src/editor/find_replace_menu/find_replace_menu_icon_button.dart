import 'package:flutter/material.dart';
import 'package:appflowy_editor/src/editor/editor_component/style/editor_color_scheme.dart';

const double _iconButtonSize = 30;
const double _iconSize = 15;

class FindAndReplaceMenuIconButton extends StatelessWidget {
  const FindAndReplaceMenuIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.iconSize,
    this.tooltip,
    this.iconButtonKey,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final double? iconSize;
  final String? tooltip;
  final Key? iconButtonKey;

  @override
  Widget build(BuildContext context) {
    final colors = EditorTheme.of(context);
    return SizedBox(
      width: _iconButtonSize,
      height: _iconButtonSize,
      child: IconButton(
        key: iconButtonKey,
        onPressed: onPressed,
        icon: icon,
        iconSize: iconSize ?? _iconSize,
        tooltip: tooltip,
        color: colors.onSurface,
        disabledColor: colors.mutedForeground,
        hoverColor: colors.hover,
        focusColor: colors.selection,
        highlightColor: colors.selection,
      ),
    );
  }
}
