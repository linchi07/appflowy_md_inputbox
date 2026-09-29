import 'dart:math' as math;

import 'package:appflowy_editor/src/editor/selection_menu/selection_menu_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A compact menu shared by editor controls. It uses the same colors and
/// surface treatment as the slash menu, without Material popup widgets.
class EditorMenuEntry {
  const EditorMenuEntry({
    required this.label,
    required this.onSelected,
    this.icon,
    this.leading,
    this.selected = false,
  });

  final String label;
  final VoidCallback onSelected;
  final IconData? icon;
  final Widget? leading;
  final bool selected;
}

class EditorPopoverMenu {
  EditorPopoverMenu._(this._overlay);

  static final Expando<EditorPopoverMenu> _active = Expando();

  final OverlayState _overlay;
  OverlayEntry? _entry;

  static Rect? anchorRect(BuildContext context) {
    final object = context.findRenderObject();
    if (object is! RenderBox || !object.attached) return null;
    return object.localToGlobal(Offset.zero) & object.size;
  }

  static EditorPopoverMenu? show({
    required BuildContext context,
    required Rect anchor,
    required List<EditorMenuEntry> entries,
    OverlayState? overlayState,
    SelectionMenuStyle? style,
    double width = 220,
    double maxHeight = 320,
    double footerHeight = 0,
    Widget Function(BuildContext, VoidCallback)? footerBuilder,
  }) {
    final overlay = overlayState ?? Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return null;
    _active[overlay]?.dismiss();
    final menu = EditorPopoverMenu._(overlay);
    final box = overlay.context.findRenderObject();
    if (box is! RenderBox) return null;
    _active[overlay] = menu;
    final viewport = box.size;
    final localAnchor = Rect.fromPoints(
      box.globalToLocal(anchor.topLeft),
      box.globalToLocal(anchor.bottomRight),
    );
    final double menuWidth =
        math.min(width, math.max(0.0, viewport.width - 16));
    final double menuHeight = math.min(
      entries.length * 38.0 + 12 + footerHeight,
      math.min(maxHeight, math.max(0.0, viewport.height - 16)),
    );
    final left = localAnchor.left
        .clamp(8.0, math.max(8.0, viewport.width - menuWidth - 8));
    final below = localAnchor.bottom + 5;
    final above = localAnchor.top - menuHeight - 5;
    final fallbackTop = below.clamp(
      8.0,
      math.max(8.0, viewport.height - menuHeight - 8),
    );
    final top = (below + menuHeight <= viewport.height - 8
            ? below
            : above >= 8
                ? above
                : fallbackTop)
        .toDouble();
    final effectiveStyle = style ??
        (Theme.of(context).brightness == Brightness.dark
            ? SelectionMenuStyle.dark
            : SelectionMenuStyle.light);

    menu._entry = OverlayEntry(
      builder: (overlayContext) => Positioned.fill(
        child: Material(
          type: MaterialType.transparency,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: menu.dismiss,
            onSecondaryTap: menu.dismiss,
            child: Stack(
              children: [
                Positioned(
                  left: left.toDouble(),
                  top: top,
                  width: menuWidth,
                  height: menuHeight,
                  child: _EditorMenuList(
                    entries: entries,
                    style: effectiveStyle,
                    dismiss: menu.dismiss,
                    footerBuilder: footerBuilder,
                    footerHeight: footerHeight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    overlay.insert(menu._entry!);
    return menu;
  }

  void dismiss() {
    final entry = _entry;
    _entry = null;
    if (entry != null) {
      entry.remove();
      entry.dispose();
    }
    if (identical(_active[_overlay], this)) _active[_overlay] = null;
  }
}

class _EditorMenuList extends StatefulWidget {
  const _EditorMenuList({
    required this.entries,
    required this.style,
    required this.dismiss,
    required this.footerBuilder,
    required this.footerHeight,
  });

  final List<EditorMenuEntry> entries;
  final SelectionMenuStyle style;
  final VoidCallback dismiss;
  final Widget Function(BuildContext, VoidCallback)? footerBuilder;
  final double footerHeight;

  @override
  State<_EditorMenuList> createState() => _EditorMenuListState();
}

class _EditorMenuListState extends State<_EditorMenuList> {
  int _activeIndex = 0;

  void _select(int index) {
    widget.dismiss();
    widget.entries[index].onSelected();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || widget.entries.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.dismiss();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _activeIndex = (_activeIndex + 1) % widget.entries.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _activeIndex =
            (_activeIndex + widget.entries.length - 1) % widget.entries.length;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _select(_activeIndex);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: DefaultTextStyle(
        style: TextStyle(color: style.selectionMenuItemTextColor, fontSize: 12),
        child: DecoratedBox(
          key: const ValueKey('editor-popover-menu'),
          decoration: BoxDecoration(
            color: style.selectionMenuBackgroundColor,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                blurRadius: 5,
                spreadRadius: 1,
                color: Colors.black.withValues(alpha: 0.1),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: widget.entries.length,
                    itemBuilder: (context, index) {
                      final entry = widget.entries[index];
                      return MouseRegion(
                        onEnter: (_) => setState(() => _activeIndex = index),
                        child: Semantics(
                          button: true,
                          selected: entry.selected,
                          label: entry.label,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _select(index),
                            child: Container(
                              height: 38,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: _activeIndex == index
                                    ? style.selectionMenuItemSelectedColor
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 20,
                                    child: entry.leading ??
                                        (entry.icon == null
                                            ? null
                                            : Icon(
                                                entry.icon,
                                                size: 17,
                                                color: _activeIndex == index
                                                    ? style
                                                        .selectionMenuItemSelectedIconColor
                                                    : style
                                                        .selectionMenuItemIconColor,
                                              )),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      entry.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _activeIndex == index
                                            ? style
                                                .selectionMenuItemSelectedTextColor
                                            : style.selectionMenuItemTextColor,
                                      ),
                                    ),
                                  ),
                                  if (entry.selected)
                                    Icon(
                                      Icons.check,
                                      size: 15,
                                      color: _activeIndex == index
                                          ? style
                                              .selectionMenuItemSelectedIconColor
                                          : style.selectionMenuItemIconColor,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (widget.footerBuilder case final footerBuilder?)
                  SizedBox(
                    height: widget.footerHeight,
                    child: footerBuilder(context, widget.dismiss),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
