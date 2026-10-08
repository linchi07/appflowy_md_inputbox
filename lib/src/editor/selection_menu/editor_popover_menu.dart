import 'dart:math' as math;

import 'package:appflowy_editor/src/editor/editor_component/style/editor_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor_menu_style.dart';
import 'editor_menu_widgets.dart';

/// An action shared by dropdowns, searchable pickers, and context menus.
class EditorMenuEntry {
  const EditorMenuEntry({
    required this.label,
    required this.onSelected,
    this.icon,
    this.leading,
    this.selected = false,
    this.enabled = true,
    this.dividerBefore = false,
    this.shortcut,
    this.searchKeywords = const [],
  });

  final String label;
  final VoidCallback onSelected;
  final IconData? icon;
  final Widget? leading;
  final bool selected;
  final bool enabled;
  final bool dividerBefore;
  final String? shortcut;
  final List<String> searchKeywords;

  bool matches(String query) =>
      label.toLowerCase().contains(query) ||
      searchKeywords.any((keyword) => keyword.toLowerCase().contains(query));
}

/// Anchored editor menus with one surface, item style, and keyboard behavior.
class EditorPopoverMenu {
  EditorPopoverMenu._(this._overlay, this._previousFocus, this._onDismiss);

  static final Expando<EditorPopoverMenu> _active = Expando();

  final OverlayState _overlay;
  final FocusNode? _previousFocus;
  final VoidCallback? _onDismiss;
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
    EditorColorScheme? colors,
    double width = 220,
    double maxHeight = 320,
    String? searchHint,
    String emptyLabel = 'No results',
    double footerHeight = 0,
    Widget Function(BuildContext, VoidCallback)? footerBuilder,
    VoidCallback? onDismiss,
  }) {
    final overlay = overlayState ?? Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return null;
    final box = overlay.context.findRenderObject();
    if (box is! RenderBox) return null;
    final previousFocus =
        _active[overlay]?._previousFocus ?? FocusManager.instance.primaryFocus;
    _active[overlay]?.dismiss();
    final menu = EditorPopoverMenu._(overlay, previousFocus, onDismiss);
    _active[overlay] = menu;
    final viewport = box.size;
    final localAnchor = Rect.fromPoints(
      box.globalToLocal(anchor.topLeft),
      box.globalToLocal(anchor.bottomRight),
    );
    final double menuWidth =
        math.min(width, math.max(0.0, viewport.width - 16));
    final double menuHeight = math.min(
      EditorMenuList.contentHeight(entries, searchable: searchHint != null) +
          footerHeight,
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
    final effectiveColors = colors ??
        EditorTheme.maybeOf(context) ??
        const EditorColorScheme.light();
    final capturedThemes =
        InheritedTheme.capture(from: context, to: overlay.context);

    menu._entry = OverlayEntry(
      builder: (overlayContext) => capturedThemes.wrap(
        EditorTheme(
          colors: effectiveColors,
          child: Positioned.fill(
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
                      child: EditorMenuList(
                        entries: entries,
                        style: style,
                        dismiss: menu.dismiss,
                        searchHint: searchHint,
                        emptyLabel: emptyLabel,
                        footerBuilder: footerBuilder,
                        footerHeight: footerHeight,
                      ),
                    ),
                  ],
                ),
              ),
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
    if (entry == null) return;
    _entry = null;
    entry.remove();
    entry.dispose();
    if (identical(_active[_overlay], this)) _active[_overlay] = null;
    _onDismiss?.call();
    final previousFocus = _previousFocus;
    if (previousFocus?.context != null && previousFocus!.canRequestFocus) {
      previousFocus.requestFocus();
    }
  }
}

/// Menu contents usable by both anchored popovers and pointer context menus.
class EditorMenuList extends StatefulWidget {
  const EditorMenuList({
    super.key,
    required this.entries,
    required this.dismiss,
    this.style,
    this.searchHint,
    this.emptyLabel = 'No results',
    this.footerBuilder,
    this.footerHeight = 0,
    this.surfaceKey = const ValueKey('editor-popover-menu'),
  });

  final List<EditorMenuEntry> entries;
  final SelectionMenuStyle? style;
  final VoidCallback dismiss;
  final String? searchHint;
  final String emptyLabel;
  final Widget Function(BuildContext, VoidCallback)? footerBuilder;
  final double footerHeight;
  final Key surfaceKey;

  static double contentHeight(
    List<EditorMenuEntry> entries, {
    bool searchable = false,
  }) =>
      math.max(1, entries.length) * editorMenuItemHeight +
      entries.skip(1).where((entry) => entry.dividerBefore).length *
          editorMenuDividerHeight +
      12 +
      (searchable ? editorMenuSearchHeight : 0);

  @override
  State<EditorMenuList> createState() => _EditorMenuListState();
}

class _EditorMenuListState extends State<EditorMenuList> {
  final _scrollController = ScrollController();
  final _focusNode = FocusNode(debugLabel: 'editor_menu');
  final _searchFocusNode = FocusNode(debugLabel: 'editor_menu_search');
  String _query = '';
  int _activeIndex = 0;

  List<EditorMenuEntry> get _entries => widget.entries
      .where((entry) => entry.matches(_query))
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    final selected =
        widget.entries.indexWhere((entry) => entry.selected && entry.enabled);
    _activeIndex = selected >= 0
        ? selected
        : widget.entries.indexWhere((entry) => entry.enabled);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.searchHint == null) _focusNode.requestFocus();
    });
    _scrollToActive();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _focusNode.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _select(int index) {
    final entries = _entries;
    if (index < 0 || index >= entries.length || !entries[index].enabled) return;
    final action = entries[index].onSelected;
    widget.dismiss();
    action();
  }

  void _move(int direction) {
    final entries = _entries;
    if (entries.isEmpty) return;
    for (var step = 1; step <= entries.length; step++) {
      final index = (_activeIndex + step * direction) % entries.length;
      if (entries[index].enabled) {
        setState(() => _activeIndex = index);
        _scrollToActive();
        return;
      }
    }
  }

  void _scrollToActive() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients || _activeIndex < 0) return;
      final entries = _entries;
      final rowTop = _activeIndex * editorMenuItemHeight +
          entries
                  .take(_activeIndex + 1)
                  .skip(1)
                  .where((entry) => entry.dividerBefore)
                  .length *
              editorMenuDividerHeight;
      final position = _scrollController.position;
      final offset = rowTop < position.pixels
          ? rowTop
          : rowTop + editorMenuItemHeight >
                  position.pixels + position.viewportDimension
              ? rowTop + editorMenuItemHeight - position.viewportDimension
              : position.pixels;
      _scrollController.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.dismiss();
      return KeyEventResult.handled;
    }
    if (!_focusNode.hasPrimaryFocus && !_searchFocusNode.hasFocus) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _move(-1);
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
    final entries = _entries;
    final colors = EditorTheme.of(context);
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      child: EditorMenuSurface(
        key: widget.surfaceKey,
        style: widget.style,
        child: Column(
          children: [
            if (widget.searchHint != null)
              SizedBox(
                height: editorMenuSearchHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
                  child: EditorMenuTextField(
                    key: const ValueKey('editor-menu-search'),
                    focusNode: _searchFocusNode,
                    autofocus: true,
                    hintText: widget.searchHint,
                    leading: const Icon(Icons.search, size: 15),
                    onChanged: (query) {
                      setState(() {
                        _query = query.toLowerCase().trim();
                        _activeIndex =
                            _entries.indexWhere((entry) => entry.enabled);
                      });
                      _scrollToActive();
                    },
                    onSubmitted: (_) => _select(_activeIndex),
                  ),
                ),
              ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        widget.emptyLabel,
                        style: TextStyle(color: colors.mutedForeground),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.zero,
                      itemCount: entries.length,
                      itemExtentBuilder: (index, dimensions) =>
                          editorMenuItemHeight +
                          (index > 0 && entries[index].dividerBefore
                              ? editorMenuDividerHeight
                              : 0),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (index > 0 && entry.dividerBefore)
                              EditorMenuDivider(style: widget.style),
                            EditorMenuItem(
                              key: ValueKey('editor-menu-item-${entry.label}'),
                              style: widget.style,
                              active: _activeIndex == index,
                              selected: entry.selected,
                              enabled: entry.enabled,
                              semanticLabel: entry.label,
                              leading: entry.leading ??
                                  (entry.icon == null
                                      ? null
                                      : Icon(entry.icon, size: 17)),
                              trailing: entry.shortcut == null
                                  ? null
                                  : Text(
                                      entry.shortcut!,
                                      style: TextStyle(
                                        color: colors.mutedForeground,
                                      ),
                                    ),
                              onHover: (hovered) {
                                if (hovered && entry.enabled) {
                                  setState(() => _activeIndex = index);
                                }
                              },
                              onPressed: () => _select(index),
                              child: Text(entry.label),
                            ),
                          ],
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
    );
  }
}
