import 'dart:math' as math;

import 'package:appflowy_editor/src/editor/editor_component/style/editor_color_scheme.dart';
import 'package:appflowy_editor/src/editor/selection_menu/editor_popover_menu.dart';
import 'package:appflowy_editor/src/editor_state.dart';
import 'package:flutter/material.dart';

typedef ContextMenuWidgetBuilder = Widget Function(
  BuildContext context,
  Offset position,
  EditorState editorState,
  VoidCallback onPressed,
);

class ContextMenuItem {
  ContextMenuItem({
    required String Function() getName,
    required this.onPressed,
    this.isApplicable,
    this.icon,
    this.shortcut,
  }) : _getName = getName;

  final String Function() _getName;
  final void Function(EditorState editorState) onPressed;
  final bool Function(EditorState editorState)? isApplicable;

  final IconData? icon;
  final String? shortcut;

  String get name => _getName();
}

class ContextMenu extends StatelessWidget {
  const ContextMenu({
    super.key,
    required this.position,
    required this.editorState,
    required this.items,
    required this.onPressed,
  });

  final Offset position;
  final EditorState editorState;
  final List<List<ContextMenuItem>> items;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final entries = <EditorMenuEntry>[];
    for (final group in items) {
      final applicable = group.where(
        (item) => item.isApplicable?.call(editorState) ?? true,
      );
      var firstInGroup = true;
      for (final item in applicable) {
        entries.add(
          EditorMenuEntry(
            label: item.name,
            icon: item.icon,
            shortcut: item.shortcut,
            dividerBefore: firstInGroup && entries.isNotEmpty,
            onSelected: () => item.onPressed(editorState),
          ),
        );
        firstInGroup = false;
      }
    }
    final box =
        Overlay.of(context, rootOverlay: true).context.findRenderObject();
    final viewport = box is RenderBox ? box.size : MediaQuery.sizeOf(context);
    final localPosition =
        box is RenderBox ? box.globalToLocal(position) : position;
    final width = math.min(220.0, math.max(0.0, viewport.width - 16));
    final height = math.min(
      EditorMenuList.contentHeight(entries),
      math.min(320.0, math.max(0.0, viewport.height - 16)),
    );
    return Positioned(
      left: localPosition.dx
          .clamp(8.0, math.max(8.0, viewport.width - width - 8)),
      top: localPosition.dy
          .clamp(8.0, math.max(8.0, viewport.height - height - 8)),
      width: width,
      height: height,
      child: EditorTheme(
        colors: editorState.editorStyle.colorScheme,
        child: Material(
          type: MaterialType.transparency,
          child: EditorMenuList(
            surfaceKey: const ValueKey('editor-context-menu'),
            entries: entries,
            style: editorState.editorStyle.selectionMenuStyle,
            dismiss: onPressed,
          ),
        ),
      ),
    );
  }
}
