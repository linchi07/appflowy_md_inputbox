import 'dart:math' as math;

import 'package:appflowy_editor/src/editor/editor_component/style/editor_color_scheme.dart';
import 'package:flutter/material.dart';

import 'editor_menu_style.dart';

const double editorMenuItemHeight = 38;
const double editorMenuDividerHeight = 9;
const double editorMenuSearchHeight = 44;

/// Shared chrome for dropdowns, search results, slash menus, and context menus.
class EditorMenuSurface extends StatelessWidget {
  const EditorMenuSurface({
    super.key,
    required this.child,
    this.style,
    this.padding = const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
  });

  final Widget child;
  final SelectionMenuStyle? style;
  final EdgeInsetsGeometry padding;

  static BoxDecoration decoration(
    BuildContext context, {
    SelectionMenuStyle? style,
  }) {
    final colors =
        EditorTheme.maybeOf(context) ?? const EditorColorScheme.light();
    return BoxDecoration(
      color: style?.selectionMenuBackgroundColor ?? colors.surface,
      borderRadius: BorderRadius.circular(6),
      boxShadow: [
        BoxShadow(
          blurRadius: 5,
          spreadRadius: 1,
          color: colors.foreground.withValues(alpha: 0.1),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors =
        EditorTheme.maybeOf(context) ?? const EditorColorScheme.light();
    return DefaultTextStyle(
      style: TextStyle(
        fontSize: 12,
        color: style?.selectionMenuItemTextColor ?? colors.onSurface,
      ),
      child: IconTheme(
        data: IconThemeData(
          size: 18,
          color: style?.selectionMenuItemIconColor ?? colors.onSurface,
        ),
        child: DecoratedBox(
          decoration: decoration(context, style: style),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A menu row with explicit hover, keyboard selection, and disabled colors.
class EditorMenuItem extends StatefulWidget {
  const EditorMenuItem({
    super.key,
    required this.child,
    required this.onPressed,
    this.leading,
    this.trailing,
    this.style,
    this.active = false,
    this.selected = false,
    this.enabled = true,
    this.reserveLeadingSpace = true,
    this.onHover,
    this.semanticLabel,
  });

  final Widget child;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onPressed;
  final SelectionMenuStyle? style;
  final bool active;
  final bool selected;
  final bool enabled;
  final bool reserveLeadingSpace;
  final ValueChanged<bool>? onHover;
  final String? semanticLabel;

  @override
  State<EditorMenuItem> createState() => _EditorMenuItemState();
}

class _EditorMenuItemState extends State<EditorMenuItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors =
        EditorTheme.maybeOf(context) ?? const EditorColorScheme.light();
    final style = widget.style ?? SelectionMenuStyle.fromScheme(colors);
    final active = widget.enabled && (widget.active || _hovered);
    final foreground = widget.enabled
        ? active
            ? style.selectionMenuItemSelectedTextColor
            : style.selectionMenuItemTextColor
        : colors.mutedForeground;
    final iconColor = widget.enabled
        ? active
            ? style.selectionMenuItemSelectedIconColor
            : style.selectionMenuItemIconColor
        : colors.mutedForeground;
    return MouseRegion(
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onHover?.call(true);
      },
      onExit: (_) {
        setState(() => _hovered = false);
        widget.onHover?.call(false);
      },
      child: Semantics(
        button: true,
        enabled: widget.enabled,
        selected: widget.selected,
        label: widget.semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onPressed : null,
          child: Container(
            height: editorMenuItemHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: active
                  ? style.selectionMenuItemSelectedColor
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: DefaultTextStyle(
              style: TextStyle(fontSize: 12, color: foreground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              child: IconTheme(
                data: IconThemeData(size: 18, color: iconColor),
                child: Row(
                  children: [
                    if (widget.leading != null ||
                        widget.reserveLeadingSpace) ...[
                      SizedBox(width: 20, child: Center(child: widget.leading)),
                      const SizedBox(width: 8),
                    ],
                    Expanded(child: widget.child),
                    if (widget.trailing != null) ...[
                      const SizedBox(width: 12),
                      widget.trailing!,
                    ] else if (widget.selected)
                      const Icon(Icons.check, size: 15),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EditorMenuDivider extends StatelessWidget {
  const EditorMenuDivider({super.key, this.style});

  final SelectionMenuStyle? style;

  @override
  Widget build(BuildContext context) {
    final colors =
        EditorTheme.maybeOf(context) ?? const EditorColorScheme.light();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SizedBox(
        height: 1,
        child: ColoredBox(
          color: style?.selectionMenuDividerColor ?? colors.border,
        ),
      ),
    );
  }
}

/// Compact inputs share editor colors instead of a host InputDecorationTheme.
class EditorMenuTextField extends StatelessWidget {
  const EditorMenuTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.hintText,
    this.labelText,
    this.leading,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? hintText;
  final String? labelText;
  final Widget? leading;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  static InputDecoration inputDecoration(
    BuildContext context, {
    String? hintText,
    String? labelText,
    Widget? leading,
    Widget? trailing,
  }) {
    final colors =
        EditorTheme.maybeOf(context) ?? const EditorColorScheme.light();
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: color),
        );
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: colors.subtleSurface,
      hoverColor: colors.hover,
      focusColor: colors.subtleSurface,
      hintText: hintText,
      labelText: labelText,
      labelStyle: TextStyle(fontSize: 12, color: colors.mutedForeground),
      floatingLabelStyle: TextStyle(fontSize: 12, color: colors.primary),
      hintStyle: TextStyle(fontSize: 12, color: colors.mutedForeground),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      prefixIcon: leading,
      suffixIcon: trailing,
      suffixIconColor: colors.mutedForeground,
      prefixIconColor: colors.mutedForeground,
      prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 30),
      border: border(colors.border),
      enabledBorder: border(colors.border),
      focusedBorder: border(colors.primary),
      disabledBorder: border(colors.border),
      errorBorder: border(colors.error),
      focusedErrorBorder: border(colors.error),
      errorStyle: TextStyle(fontSize: 12, color: colors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors =
        EditorTheme.maybeOf(context) ?? const EditorColorScheme.light();
    return TextSelectionTheme(
      data: TextSelectionThemeData(
        cursorColor: colors.primary,
        selectionColor: colors.selection,
        selectionHandleColor: colors.primary,
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        cursorColor: colors.primary,
        style: TextStyle(fontSize: 12, height: 1.2, color: colors.onSurface),
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        // A stable callback preserves EditableText's selection overlay on rebuild.
        contextMenuBuilder: buildContextMenu,
        decoration: inputDecoration(
          context,
          hintText: hintText,
          labelText: labelText,
          leading: leading,
        ),
      ),
    );
  }

  static Widget buildContextMenu(
    BuildContext context,
    EditableTextState editableText, {
    EditorColorScheme? colors,
  }) {
    final effectiveColors = colors ??
        EditorTheme.maybeOf(editableText.context) ??
        const EditorColorScheme.light();
    final entries = editableText.contextMenuButtonItems;
    final anchors = editableText.contextMenuAnchors;
    final overlayBox =
        Overlay.of(context, rootOverlay: true).context.findRenderObject();
    final anchor = overlayBox is RenderBox
        ? overlayBox.globalToLocal(anchors.primaryAnchor)
        : anchors.primaryAnchor;
    return EditorTheme(
      colors: effectiveColors,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width =
              math.min(220.0, math.max(0.0, constraints.maxWidth - 16));
          final height = math.min(
            entries.length * editorMenuItemHeight + 12,
            math.max(0.0, constraints.maxHeight - 16),
          );
          final left = anchor.dx
              .clamp(8.0, math.max(8.0, constraints.maxWidth - width - 8));
          final below = anchor.dy + 5;
          final top = (below + height <= constraints.maxHeight - 8
                  ? below
                  : anchor.dy - height - 5)
              .clamp(8.0, math.max(8.0, constraints.maxHeight - height - 8));
          return Stack(
            children: [
              Positioned(
                left: left.toDouble(),
                top: top.toDouble(),
                width: width,
                height: height,
                child: Material(
                  type: MaterialType.transparency,
                  child: EditorMenuSurface(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final entry in entries)
                            EditorMenuItem(
                              reserveLeadingSpace: false,
                              enabled: entry.onPressed != null,
                              onPressed: entry.onPressed,
                              child: Text(
                                AdaptiveTextSelectionToolbar.getButtonLabel(
                                  context,
                                  entry,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
