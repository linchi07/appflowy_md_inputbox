import 'dart:async';
import 'dart:math';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

abstract class SelectionMenuService {
  Offset get offset;

  Alignment get alignment;

  SelectionMenuStyle get style;

  double get menuHeight;

  double get menuWidth;

  Future<void> show();

  void dismiss();

  (double? left, double? top, double? right, double? bottom) getPosition();
}

class SelectionMenu extends SelectionMenuService {
  SelectionMenu({
    required this.context,
    required this.editorState,
    required this.selectionMenuItems,
    this.deleteSlashByDefault = true,
    this.deleteKeywordsByDefault = false,
    SelectionMenuStyle? style,
    this.itemCountFilter = 0,
    this.singleColumn = false,
    this.menuHeight = 300,
    this.menuWidth = 300,
  }) : style = style ??
            editorState.editorStyle.selectionMenuStyle ??
            SelectionMenuStyle.light;

  final BuildContext context;
  final EditorState editorState;
  final List<SelectionMenuItem> selectionMenuItems;
  final bool deleteSlashByDefault;
  final bool deleteKeywordsByDefault;
  final bool singleColumn;
  @override
  final double menuHeight;
  @override
  final double menuWidth;

  @override
  final SelectionMenuStyle style;

  OverlayEntry? _selectionMenuEntry;
  bool _selectionUpdateByInner = false;
  Offset _offset = Offset.zero;
  Alignment _alignment = Alignment.topLeft;
  int itemCountFilter;

  @override
  void dismiss() {
    if (_selectionMenuEntry != null) {
      editorState.service.keyboardService?.enable();
      editorState.service.scrollService?.enable();
    }

    _selectionMenuEntry?.remove();
    _selectionMenuEntry = null;

    // workaround: SelectionService has been released after hot reload.
    final isSelectionDisposed =
        editorState.service.selectionServiceKey.currentState == null;
    if (!isSelectionDisposed) {
      final selectionService = editorState.service.selectionService;
      // focus to reload the selection after the menu dismissed.
      editorState.selection = editorState.selection;
      selectionService.currentSelection.removeListener(_onSelectionChange);
    }
  }

  @override
  Future<void> show() async {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      _show();
      completer.complete();
    });

    return completer.future;
  }

  void _show() {
    dismiss();

    final selectionService = editorState.service.selectionService;
    final selectionRects = selectionService.selectionRects;
    if (selectionRects.isEmpty) {
      return;
    }

    var showAbove = calculateSelectionMenuOffset(selectionRects.first);
    final (left, top, right, bottom) = getPosition();
    _selectionMenuEntry = OverlayEntry(
      builder: (context) {
        return Material(
          type: MaterialType.transparency,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              dismiss();
            },
            child: Stack(
              children: [
                Positioned(
                  top: top,
                  bottom: bottom,
                  left: left,
                  right: right,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectionMenuWidget(
                      reverse: showAbove,
                      selectionMenuStyle: style,
                      singleColumn: singleColumn,
                      items: selectionMenuItems
                        ..forEach((element) {
                          element.deleteSlash = deleteSlashByDefault;
                          element.deleteKeywords = deleteKeywordsByDefault;
                          element.onSelected = () {
                            dismiss();
                          };
                        }),
                      maxItemInRow: 5,
                      editorState: editorState,
                      itemCountFilter: itemCountFilter,
                      menuService: this,
                      onExit: () {
                        dismiss();
                      },
                      onSelectionUpdate: () {
                        _selectionUpdateByInner = true;
                      },
                      deleteSlashByDefault: deleteSlashByDefault,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_selectionMenuEntry!);

    editorState.service.keyboardService?.disable(showCursor: true);
    editorState.service.scrollService?.disable();
    selectionService.currentSelection.addListener(_onSelectionChange);
  }

  @override
  Alignment get alignment {
    return _alignment;
  }

  @override
  Offset get offset {
    return _offset;
  }

  void _onSelectionChange() {
    // workaround: SelectionService has been released after hot reload.
    final isSelectionDisposed =
        editorState.service.selectionServiceKey.currentState == null;
    if (!isSelectionDisposed) {
      final selectionService = editorState.service.selectionService;
      if (selectionService.currentSelection.value == null) {
        return;
      }
    }

    if (_selectionUpdateByInner) {
      _selectionUpdateByInner = false;

      return;
    }

    dismiss();
  }

  @override
  (double? left, double? top, double? right, double? bottom) getPosition() {
    double? left, top, right, bottom;
    switch (alignment) {
      case Alignment.topLeft:
        left = offset.dx;
        top = offset.dy;
        break;

      case Alignment.bottomLeft:
        left = offset.dx;
        bottom = offset.dy;
        break;

      case Alignment.topRight:
        right = offset.dx;
        top = offset.dy;
        break;

      case Alignment.bottomRight:
        right = offset.dx;
        bottom = offset.dy;
        break;
    }

    return (left, top, right, bottom);
  }

  // now returns if show above or below
  bool calculateSelectionMenuOffset(Rect rect) {
    const menuOffset = Offset(0, 10);

    // Use the actual overlay size as the safe boundary
    final overlayRenderBox = Overlay.of(context, rootOverlay: true)
        .context
        .findRenderObject() as RenderBox;
    final overlaySize = overlayRenderBox.size;

    _alignment = Alignment.topLeft;

    // Default: show below
    var top = rect.bottom + menuOffset.dy;
    var left = rect.left;
    var showAbove = false;

    // If bottom space is not enough, show above the selection
    if (top + menuHeight > overlaySize.height) {
      final potentialTop = rect.top - menuHeight - menuOffset.dy;
      if (potentialTop >= 0) {
        showAbove = true;
      }
    }

    if (showAbove) {
      // Anchoring to bottom for Above mode to ensure correct shrinking direction
      _alignment = Alignment.bottomLeft;
      _offset = Offset(left, overlaySize.height - rect.top + menuOffset.dy);
    } else {
      // Anchoring to top for Below mode
      _alignment = Alignment.topLeft;
      _offset = Offset(left, top);
    }

    // Horizontal check: if the menu would overflow the right edge of the overlay
    if (left + menuWidth > overlaySize.width) {
      // Align the right edge of the menu with the right edge of the selection rect
      final rightOffset = overlaySize.width - rect.right;
      if (showAbove) {
        _alignment = Alignment.bottomRight;
        _offset = Offset(rightOffset, _offset.dy);
      } else {
        _alignment = Alignment.topRight;
        _offset = Offset(rightOffset, _offset.dy);
      }
    } else {
      // Align to the left (ensure it doesn't overflow the left edge)
      _offset = Offset(max(0.0, _offset.dx), _offset.dy);
    }

    return showAbove;
  }
}

final List<SelectionMenuItem> standardSelectionMenuItems = [
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.text,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'text',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['text'],
    handler: (editorState, _, __) {
      insertNodeAfterSelection(editorState, paragraphNode());
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.heading1,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'h1',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['heading 1, h1'],
    handler: (editorState, _, __) {
      insertHeadingAfterSelection(editorState, 1);
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.heading2,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'h2',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['heading 2, h2'],
    handler: (editorState, _, __) {
      insertHeadingAfterSelection(editorState, 2);
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.heading3,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'h3',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['heading 3, h3'],
    handler: (editorState, _, __) {
      insertHeadingAfterSelection(editorState, 3);
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.quote,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'quote',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['quote', 'refer'],
    handler: (editorState, _, __) {
      insertQuoteAfterSelection(editorState);
    },
  ),
  dividerMenuItem,
  tableMenuItem,
];

final List<SelectionMenuItem> singleColumnVisibleMenuItems = [
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.text,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'text',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['text'],
    handler: (editorState, _, __) {
      insertNodeAfterSelection(editorState, paragraphNode());
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.heading1,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'h1',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['heading 1, h1'],
    handler: (editorState, _, __) {
      insertHeadingAfterSelection(editorState, 1);
    },
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.heading2,
    icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
      name: 'h2',
      isSelected: isSelected,
      style: style,
    ),
    keywords: ['heading 2, h2'],
    handler: (editorState, _, __) {
      insertHeadingAfterSelection(editorState, 2);
    },
  ),
];
