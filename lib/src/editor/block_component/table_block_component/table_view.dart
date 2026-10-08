import 'dart:math' as math;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_action_menu.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_col.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TableView extends StatefulWidget {
  const TableView({
    super.key,
    required this.editorState,
    required this.tableNode,
    required this.tableStyle,
    this.menuBuilder,
    this.menuEntriesBuilder,
  });

  final EditorState editorState;
  final TableNode tableNode;
  final TableBlockComponentMenuBuilder? menuBuilder;
  final TableMenuEntriesBuilder? menuEntriesBuilder;
  final TableStyle tableStyle;

  @override
  State<TableView> createState() => _TableViewState();
}

class _TableViewState extends State<TableView>
    implements RangeSelectionHandler {
  static const double SIDE_HEADER_WIDTH = 48.0;
  static const double TOP_HEADER_HEIGHT = 26.0;
  static const double ADD_COL_WIDTH = 20.0;
  static const double ADD_ROW_HEIGHT = 20.0;
  static const double SPACING = 4.0;
  static const double HIT_DIVIDER_THRESHOLD = 8.0;

  final FocusNode _keyboardFocusNode = FocusNode();

  int? _hoveredCol;
  int? _hoveredRow;
  int? _hoveredColDivider;
  int? _hoveredRowDivider;
  bool _hoveringAddCol = false;
  bool _hoveringAddRow = false;

  TableSelection? _tableSelection;
  (int col, int row)? _dragStartCell;
  Offset? _lastGlobalPointerPosition;
  bool _wholeTableWasSelected = false;
  bool _customMenuOpen = false;

  void _setTableSelection(TableSelection? selection) {
    if (_tableSelection != selection) {
      setState(() {
        _tableSelection = selection;
      });
    }
    if (selection != null) {
      widget.editorState.activeRangeSelectionHandler = this;
    } else if (widget.editorState.activeRangeSelectionHandler == this) {
      widget.editorState.activeRangeSelectionHandler = null;
    }
  }

  @override
  String? getSelectedText() {
    final sel = _tableSelection;
    if (sel == null) {
      return null;
    }
    if (sel.minCol == sel.maxCol && sel.minRow == sel.maxRow) {
      final cell = widget.tableNode.getCell(sel.minCol, sel.minRow);
      return cell.children.firstOrNull?.delta?.toPlainText() ?? '';
    }
    return widget.tableNode.toMarkdown(
      minCol: sel.minCol,
      minRow: sel.minRow,
      maxCol: sel.maxCol,
      maxRow: sel.maxRow,
    );
  }

  @override
  Future<void> clearSelectedContent() async {
    final sel = _tableSelection;
    if (sel == null || !widget.editorState.editable) {
      return;
    }
    final transaction = widget.editorState.transaction;
    final table = widget.tableNode;
    for (var r = sel.minRow; r <= sel.maxRow; r++) {
      for (var c = sel.minCol; c <= sel.maxCol; c++) {
        final cell = table.getCell(c, r);
        final paragraph = cell.children.firstOrNull;
        if (paragraph != null) {
          final length = paragraph.delta?.length ?? 0;
          if (length > 0) {
            transaction.replaceText(paragraph, 0, length, '');
          }
        }
      }
    }
    if (transaction.operations.isNotEmpty) {
      await widget.editorState.apply(transaction);
    }
  }

  @override
  void cancelSelection() {
    _setTableSelection(null);
  }

  Future<void> _cutSelectedCells() async {
    final text = getSelectedText();
    if (text != null && text.isNotEmpty) {
      await AppFlowyClipboard.setData(text: text);
      await clearSelectedContent();
    }
  }

  Future<void> _copySelectedCells() async {
    final text = getSelectedText();
    if (text != null && text.isNotEmpty) {
      await AppFlowyClipboard.setData(text: text);
    }
  }

  @override
  void initState() {
    super.initState();
    _wholeTableWasSelected =
        _isWholeTableSelected(widget.editorState.selection);
    widget.tableNode.node.addListener(_onTableNodeChanged);
    widget.editorState.selectionNotifier.addListener(_onGlobalSelectionChanged);
    widget.editorState
        .addScrollViewScrolledListener(_handleAutoScrollWhileDragging);
  }

  @override
  void didUpdateWidget(TableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _wholeTableWasSelected =
        _isWholeTableSelected(widget.editorState.selection);
    if (oldWidget.tableNode.node != widget.tableNode.node) {
      oldWidget.tableNode.node.removeListener(_onTableNodeChanged);
      widget.tableNode.node.addListener(_onTableNodeChanged);
    }
    if (oldWidget.editorState != widget.editorState) {
      if (oldWidget.editorState.activeRangeSelectionHandler == this) {
        oldWidget.editorState.activeRangeSelectionHandler = null;
      }
      oldWidget.editorState.selectionNotifier
          .removeListener(_onGlobalSelectionChanged);
      oldWidget.editorState
          .removeScrollViewScrolledListener(_handleAutoScrollWhileDragging);
      widget.editorState.selectionNotifier
          .addListener(_onGlobalSelectionChanged);
      widget.editorState
          .addScrollViewScrolledListener(_handleAutoScrollWhileDragging);
      if (_tableSelection != null) {
        widget.editorState.activeRangeSelectionHandler = this;
      }
    }
  }

  @override
  void dispose() {
    if (widget.editorState.activeRangeSelectionHandler == this) {
      widget.editorState.activeRangeSelectionHandler = null;
    }
    if (_dragStartCell != null) {
      widget.editorState.autoScroller?.stopAutoScroll();
    }
    widget.editorState
        .removeScrollViewScrolledListener(_handleAutoScrollWhileDragging);
    widget.tableNode.node.removeListener(_onTableNodeChanged);
    widget.editorState.selectionNotifier
        .removeListener(_onGlobalSelectionChanged);
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _onTableNodeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onGlobalSelectionChanged() {
    if (!mounted) return;
    final sel = widget.editorState.selection;
    final wholeTableSelected = _isWholeTableSelected(sel);
    final shouldClearLocal = _tableSelection != null &&
        sel != null &&
        (wholeTableSelected ||
            _dragStartCell == null ||
            sel.start.path.firstOrNull !=
                widget.tableNode.node.path.firstOrNull ||
            sel.end.path.firstOrNull != widget.tableNode.node.path.firstOrNull);
    if (shouldClearLocal || wholeTableSelected != _wholeTableWasSelected) {
      if (shouldClearLocal) {
        _setTableSelection(null);
      }
      setState(() {
        _wholeTableWasSelected = wholeTableSelected;
      });
    }
  }

  bool _isWholeTableSelected(Selection? selection) =>
      selection != null &&
      !selection.isCollapsed &&
      widget.tableNode.node.path.inSelection(selection);

  @override
  Widget build(BuildContext context) {
    final table = widget.tableNode;
    final isEditable = widget.editorState.editable;
    final geo = _computeGeometry(table);
    final selection = _tableSelection ??
        (_isWholeTableSelected(widget.editorState.selection)
            ? TableSelection(
                startCol: 0,
                startRow: 0,
                endCol: table.colsLen - 1,
                endRow: table.rowsLen - 1,
              )
            : null);

    final totalWidth = SIDE_HEADER_WIDTH +
        geo.totalTableWidth +
        (isEditable ? SPACING + ADD_COL_WIDTH : 0.0);
    final totalHeight = TOP_HEADER_HEIGHT +
        geo.totalTableHeight +
        (isEditable ? SPACING + ADD_ROW_HEIGHT : 0.0);

    final focus = Focus(
      focusNode: _keyboardFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: TableSelectionScope(
        selection: selection,
        child: Listener(
          onPointerDown: (event) => _handlePointerDown(event, geo),
          onPointerMove: (event) => _handlePointerMove(event, geo),
          onPointerUp: (event) => _handlePointerUp(event),
          onPointerCancel: (event) => _handlePointerCancel(event),
          child: MouseRegion(
            onHover: (event) => _handleHover(event, geo),
            onExit: (_) => _handleExit(),
            child: SizedBox(
              width: totalWidth,
              height: totalHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 表格主体网格
                  Positioned(
                    left: SIDE_HEADER_WIDTH,
                    top: TOP_HEADER_HEIGHT,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: _buildColumns(context),
                    ),
                  ),

                  // 二维单元格选区外围高亮边框
                  if (selection != null)
                    _buildSelectionBorder(context, geo, selection),

                  if (isEditable) ...[
                    // 左上角样式编辑按钮 (不侵入表格)
                    Positioned(
                      left: (SIDE_HEADER_WIDTH - 20) / 2,
                      top: (TOP_HEADER_HEIGHT - 20) / 2,
                      width: 20,
                      height: 20,
                      child: _buildStyleButton(table),
                    ),

                    // 列操作按钮 (表格外，调色板与删除 x 按钮)
                    if (_hoveredCol != null && _hoveredColDivider == null)
                      Positioned(
                        key: ValueKey('table-col-handle-$_hoveredCol'),
                        left: SIDE_HEADER_WIDTH +
                            geo.colLefts[_hoveredCol!] +
                            (geo.colWidths[_hoveredCol!] - 40) / 2,
                        top: (TOP_HEADER_HEIGHT - 20) / 2,
                        width: 40,
                        height: 20,
                        child: _buildColHandle(_hoveredCol!),
                      ),

                    // 行操作按钮 (表格外，调色板与删除 x 按钮)
                    if (_hoveredRow != null && _hoveredRowDivider == null)
                      Positioned(
                        key: ValueKey('table-row-handle-$_hoveredRow'),
                        left: (SIDE_HEADER_WIDTH - 40) / 2,
                        top: TOP_HEADER_HEIGHT +
                            geo.rowTops[_hoveredRow!] +
                            (geo.rowHeights[_hoveredRow!] - 20) / 2,
                        width: 40,
                        height: 20,
                        child: _buildRowHandle(_hoveredRow!),
                      ),

                    // 两列之间的插入三角形
                    if (_hoveredColDivider != null)
                      Positioned(
                        key: ValueKey(
                          'table-insert-col-divider-$_hoveredColDivider',
                        ),
                        left: SIDE_HEADER_WIDTH +
                            geo.colDividerX[_hoveredColDivider!] -
                            8,
                        top: TOP_HEADER_HEIGHT - 18,
                        width: 16,
                        height: 18,
                        child: _buildColDividerTriangle(_hoveredColDivider!),
                      ),

                    // 两行之间的插入三角形
                    if (_hoveredRowDivider != null)
                      Positioned(
                        key: ValueKey(
                          'table-insert-row-divider-$_hoveredRowDivider',
                        ),
                        left: SIDE_HEADER_WIDTH - 18,
                        top: TOP_HEADER_HEIGHT +
                            geo.rowDividerY[_hoveredRowDivider!] -
                            8,
                        width: 18,
                        height: 16,
                        child: _buildRowDividerTriangle(_hoveredRowDivider!),
                      ),

                    // 右侧加列横框（和列同高，同设计样式）
                    Positioned(
                      key: const ValueKey('table-add-col-button'),
                      left: SIDE_HEADER_WIDTH + geo.totalTableWidth + SPACING,
                      top: TOP_HEADER_HEIGHT,
                      width: ADD_COL_WIDTH,
                      height: geo.totalTableHeight,
                      child: _buildAddColButton(geo.totalTableHeight),
                    ),

                    // 下方加行横框（和行同宽，同设计样式）
                    Positioned(
                      key: const ValueKey('table-add-row-button'),
                      left: SIDE_HEADER_WIDTH,
                      top: TOP_HEADER_HEIGHT + geo.totalTableHeight + SPACING,
                      width: geo.totalTableWidth,
                      height: ADD_ROW_HEIGHT,
                      child: _buildAddRowButton(geo.totalTableWidth),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return TapRegion(
      onTapOutside: (_) {
        if (_tableSelection != null) {
          _setTableSelection(null);
        }
      },
      child: focus,
    );
  }

  Widget _buildSelectionBorder(
    BuildContext context,
    _TableLayoutGeometry geo,
    TableSelection sel,
  ) {
    final left = SIDE_HEADER_WIDTH + geo.colLefts[sel.minCol] - geo.borderWidth;
    final top = TOP_HEADER_HEIGHT + geo.rowTops[sel.minRow] - geo.borderWidth;
    final right = SIDE_HEADER_WIDTH +
        geo.colLefts[sel.maxCol] +
        geo.colWidths[sel.maxCol] +
        geo.borderWidth;
    final bottom = TOP_HEADER_HEIGHT +
        geo.rowTops[sel.maxRow] +
        geo.rowHeights[sel.maxRow] +
        geo.borderWidth;

    return Positioned(
      key: const ValueKey('table-selection-border'),
      left: left,
      top: top,
      width: math.max(0.0, right - left),
      height: math.max(0.0, bottom - top),
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: EditorTheme.of(context).primary,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  void _handlePointerDown(PointerDownEvent event, _TableLayoutGeometry geo) {
    final hit = _hitTestCell(event.localPosition, geo);
    if (_tableSelection != null) {
      _setTableSelection(null);
    }
    _dragStartCell = hit;
    _lastGlobalPointerPosition = event.position;
    if (hit != null) {
      _keyboardFocusNode.requestFocus();
    }
  }

  void _handlePointerMove(PointerMoveEvent event, _TableLayoutGeometry geo) {
    if (_dragStartCell == null) {
      return;
    }
    _lastGlobalPointerPosition = event.position;
    widget.editorState.service.scrollService?.startAutoScroll(
      event.position,
      edgeOffset: 200,
      duration: const Duration(milliseconds: 2),
    );

    final relX = event.localPosition.dx - SIDE_HEADER_WIDTH;
    final relY = event.localPosition.dy - TOP_HEADER_HEIGHT;
    final isWithinTableBounds = relX >= -20 &&
        relX <= geo.totalTableWidth + 40 &&
        relY >= -20 &&
        relY <= geo.totalTableHeight + 40;

    if (!isWithinTableBounds) {
      if (_tableSelection != null) {
        _setTableSelection(null);
      }
      return;
    }

    final hit = _clampCell(event.localPosition, geo);
    if (hit != _dragStartCell || _tableSelection != null) {
      final newSelection = TableSelection(
        startCol: _dragStartCell!.$1,
        startRow: _dragStartCell!.$2,
        endCol: hit.$1,
        endRow: hit.$2,
      );
      if (_tableSelection != newSelection) {
        _setTableSelection(newSelection);
        widget.editorState.updateSelectionWithReason(null);
      }
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    widget.editorState.service.scrollService?.stopAutoScroll();
    _dragStartCell = null;
    _lastGlobalPointerPosition = null;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    widget.editorState.service.scrollService?.stopAutoScroll();
    _dragStartCell = null;
    _lastGlobalPointerPosition = null;
  }

  void _handleAutoScrollWhileDragging() {
    if (_dragStartCell == null ||
        _lastGlobalPointerPosition == null ||
        !mounted) {
      return;
    }
    widget.editorState.autoScroller?.continueToAutoScroll();
    final renderBox = context.findRenderObject();
    if (renderBox is RenderBox) {
      final localPos = renderBox.globalToLocal(_lastGlobalPointerPosition!);
      final geo = _computeGeometry(widget.tableNode);
      final hit = _clampCell(localPos, geo);
      final newSelection = TableSelection(
        startCol: _dragStartCell!.$1,
        startRow: _dragStartCell!.$2,
        endCol: hit.$1,
        endRow: hit.$2,
      );
      if (_tableSelection != newSelection) {
        _setTableSelection(newSelection);
        widget.editorState.updateSelectionWithReason(null);
      }
    }
  }

  (int col, int row) _clampCell(Offset pos, _TableLayoutGeometry geo) {
    final relX = pos.dx - SIDE_HEADER_WIDTH;
    final relY = pos.dy - TOP_HEADER_HEIGHT;

    int hitCol;
    if (relX <= 0) {
      hitCol = 0;
    } else if (relX >= geo.totalTableWidth) {
      hitCol = widget.tableNode.colsLen - 1;
    } else {
      hitCol = 0;
      for (var c = 0; c < widget.tableNode.colsLen; c++) {
        if (relX >= geo.colLefts[c] &&
            relX <= geo.colLefts[c] + geo.colWidths[c] + geo.borderWidth) {
          hitCol = c;
          break;
        }
      }
    }

    int hitRow;
    if (relY <= 0) {
      hitRow = 0;
    } else if (relY >= geo.totalTableHeight) {
      hitRow = widget.tableNode.rowsLen - 1;
    } else {
      hitRow = 0;
      for (var r = 0; r < widget.tableNode.rowsLen; r++) {
        if (relY >= geo.rowTops[r] &&
            relY <= geo.rowTops[r] + geo.rowHeights[r] + geo.borderWidth) {
          hitRow = r;
          break;
        }
      }
    }

    return (hitCol, hitRow);
  }

  (int col, int row)? _hitTestCell(Offset pos, _TableLayoutGeometry geo) {
    final relX = pos.dx - SIDE_HEADER_WIDTH;
    final relY = pos.dy - TOP_HEADER_HEIGHT;
    if (relX < 0 ||
        relX > geo.totalTableWidth ||
        relY < 0 ||
        relY > geo.totalTableHeight) {
      return null;
    }

    int? hitCol;
    for (var c = 0; c < widget.tableNode.colsLen; c++) {
      if (relX >= geo.colLefts[c] &&
          relX <= geo.colLefts[c] + geo.colWidths[c] + geo.borderWidth) {
        hitCol = c;
        break;
      }
    }

    int? hitRow;
    for (var r = 0; r < widget.tableNode.rowsLen; r++) {
      if (relY >= geo.rowTops[r] &&
          relY <= geo.rowTops[r] + geo.rowHeights[r] + geo.borderWidth) {
        hitRow = r;
        break;
      }
    }

    if (hitCol != null && hitRow != null) {
      return (hitCol, hitRow);
    }
    return null;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (_tableSelection != null) {
      if (event.logicalKey == LogicalKeyboardKey.delete ||
          event.logicalKey == LogicalKeyboardKey.backspace) {
        clearSelectedContent();
        return KeyEventResult.handled;
      }

      if (event.logicalKey == LogicalKeyboardKey.escape) {
        cancelSelection();
        return KeyEventResult.handled;
      }

      final isMetaOrControl = HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed;

      if (event.logicalKey == LogicalKeyboardKey.keyC && isMetaOrControl) {
        _copySelectedCells();
        return KeyEventResult.handled;
      }

      if (event.logicalKey == LogicalKeyboardKey.keyX && isMetaOrControl) {
        _cutSelectedCells();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  Widget _buildStyleButton(TableNode table) {
    return Builder(
      builder: (buttonContext) => _TableActionButton(
        key: const ValueKey('table-style-button'),
        icon: Icons.tune_outlined,
        tooltip: '表格样式',
        onTap: () => showTableStyleMenu(
          buttonContext,
          table.node,
          widget.editorState,
        ),
      ),
    );
  }

  void _deleteCol(int colIdx) {
    if (!widget.editorState.editable) {
      return;
    }
    _setTableSelection(null);
    setState(() {
      _hoveredCol = null;
      _hoveredRow = null;
      _hoveredColDivider = null;
      _hoveredRowDivider = null;
    });
    TableActions.delete(
      widget.tableNode.node,
      colIdx,
      widget.editorState,
      TableDirection.col,
    );
  }

  void _deleteRow(int rowIdx) {
    if (!widget.editorState.editable) {
      return;
    }
    _setTableSelection(null);
    setState(() {
      _hoveredCol = null;
      _hoveredRow = null;
      _hoveredColDivider = null;
      _hoveredRowDivider = null;
    });
    TableActions.delete(
      widget.tableNode.node,
      rowIdx,
      widget.editorState,
      TableDirection.row,
    );
  }

  Widget _buildColHandle(int colIdx) {
    if (widget.menuBuilder case final builder?) {
      return builder(
        widget.tableNode.node,
        widget.editorState,
        colIdx,
        TableDirection.col,
        () => setState(() => _customMenuOpen = true),
        () => setState(() => _customMenuOpen = false),
      );
    }
    return Builder(
      builder: (btnContext) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _TableActionButton(
              key: ValueKey('table-col-color-$colIdx'),
              icon: Icons.palette_outlined,
              tooltip: '设置列颜色',
              onTap: () {
                showTableColorMenu(
                  btnContext,
                  widget.tableNode.node,
                  widget.editorState,
                  colIdx,
                  TableDirection.col,
                );
              },
              onSecondaryTap: () => showActionMenu(
                btnContext,
                widget.tableNode.node,
                widget.editorState,
                colIdx,
                TableDirection.col,
                menuEntriesBuilder: widget.menuEntriesBuilder,
              ),
            ),
            const SizedBox(width: 3),
            _TableActionButton(
              key: ValueKey('table-col-delete-$colIdx'),
              icon: Icons.close,
              tooltip: '删除此列',
              hoverBgColor:
                  EditorTheme.of(context).error.withValues(alpha: 0.1),
              hoverIconColor: EditorTheme.of(context).error,
              onTap: () => _deleteCol(colIdx),
              onSecondaryTap: () => showActionMenu(
                btnContext,
                widget.tableNode.node,
                widget.editorState,
                colIdx,
                TableDirection.col,
                menuEntriesBuilder: widget.menuEntriesBuilder,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRowHandle(int rowIdx) {
    if (widget.menuBuilder case final builder?) {
      return builder(
        widget.tableNode.node,
        widget.editorState,
        rowIdx,
        TableDirection.row,
        () => setState(() => _customMenuOpen = true),
        () => setState(() => _customMenuOpen = false),
      );
    }
    return Builder(
      builder: (btnContext) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _TableActionButton(
              key: ValueKey('table-row-color-$rowIdx'),
              icon: Icons.palette_outlined,
              tooltip: '设置行颜色',
              onTap: () {
                showTableColorMenu(
                  btnContext,
                  widget.tableNode.node,
                  widget.editorState,
                  rowIdx,
                  TableDirection.row,
                );
              },
              onSecondaryTap: () => showActionMenu(
                btnContext,
                widget.tableNode.node,
                widget.editorState,
                rowIdx,
                TableDirection.row,
                menuEntriesBuilder: widget.menuEntriesBuilder,
              ),
            ),
            const SizedBox(width: 3),
            _TableActionButton(
              key: ValueKey('table-row-delete-$rowIdx'),
              icon: Icons.close,
              tooltip: '删除此行',
              hoverBgColor:
                  EditorTheme.of(context).error.withValues(alpha: 0.1),
              hoverIconColor: EditorTheme.of(context).error,
              onTap: () => _deleteRow(rowIdx),
              onSecondaryTap: () => showActionMenu(
                btnContext,
                widget.tableNode.node,
                widget.editorState,
                rowIdx,
                TableDirection.row,
                menuEntriesBuilder: widget.menuEntriesBuilder,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildColDividerTriangle(int colIdx) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          TableActions.add(
            widget.tableNode.node,
            colIdx,
            widget.editorState,
            TableDirection.col,
          );
        },
        child: Tooltip(
          message: '在此处插入列',
          child: Center(
            child: Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: EditorTheme.of(context).primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRowDividerTriangle(int rowIdx) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          TableActions.add(
            widget.tableNode.node,
            rowIdx,
            widget.editorState,
            TableDirection.row,
          );
        },
        child: Tooltip(
          message: '在此处插入行',
          child: Center(
            child: Icon(
              Icons.arrow_right,
              size: 18,
              color: EditorTheme.of(context).primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddColButton(double height) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveringAddCol = true),
      onExit: (_) => setState(() => _hoveringAddCol = false),
      child: GestureDetector(
        onTap: () {
          TableActions.add(
            widget.tableNode.node,
            widget.tableNode.colsLen,
            widget.editorState,
            TableDirection.col,
          );
        },
        child: Container(
          width: ADD_COL_WIDTH,
          height: height,
          decoration: BoxDecoration(
            color: _hoveringAddCol
                ? EditorTheme.of(context).hover
                : Colors.transparent,
            border: Border.all(
              color: _hoveringAddCol
                  ? (widget.tableStyle.borderHoverColor ??
                      EditorTheme.of(context).primary)
                  : (widget.tableStyle.borderColor ??
                          EditorTheme.of(context).border)
                      .withValues(alpha: 0.6),
              width: widget.tableStyle.borderWidth,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Center(
            child: Icon(
              Icons.add,
              size: 14,
              color: _hoveringAddCol
                  ? EditorTheme.of(context).primary
                  : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddRowButton(double width) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveringAddRow = true),
      onExit: (_) => setState(() => _hoveringAddRow = false),
      child: GestureDetector(
        onTap: () {
          TableActions.add(
            widget.tableNode.node,
            widget.tableNode.rowsLen,
            widget.editorState,
            TableDirection.row,
          );
        },
        child: Container(
          width: width,
          height: ADD_ROW_HEIGHT,
          decoration: BoxDecoration(
            color: _hoveringAddRow
                ? EditorTheme.of(context).hover
                : Colors.transparent,
            border: Border.all(
              color: _hoveringAddRow
                  ? (widget.tableStyle.borderHoverColor ??
                      EditorTheme.of(context).primary)
                  : (widget.tableStyle.borderColor ??
                          EditorTheme.of(context).border)
                      .withValues(alpha: 0.6),
              width: widget.tableStyle.borderWidth,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Center(
            child: Icon(
              Icons.add,
              size: 14,
              color: _hoveringAddRow
                  ? EditorTheme.of(context).primary
                  : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }

  void _handleHover(PointerHoverEvent event, _TableLayoutGeometry geo) {
    if (_customMenuOpen) return;
    final pos = event.localPosition;
    final relX = pos.dx - SIDE_HEADER_WIDTH;
    final relY = pos.dy - TOP_HEADER_HEIGHT;

    int? nextColDivider;
    int? nextRowDivider;
    int? nextCol;
    int? nextRow;

    // 检查列分割线
    for (var c = 1; c < widget.tableNode.colsLen; c++) {
      if ((relX - geo.colDividerX[c]).abs() <= HIT_DIVIDER_THRESHOLD &&
          relY >= -TOP_HEADER_HEIGHT &&
          relY <= geo.totalTableHeight) {
        nextColDivider = c;
        break;
      }
    }

    // 检查行分割线
    for (var r = 1; r < widget.tableNode.rowsLen; r++) {
      if ((relY - geo.rowDividerY[r]).abs() <= HIT_DIVIDER_THRESHOLD &&
          relX >= -SIDE_HEADER_WIDTH &&
          relX <= geo.totalTableWidth) {
        nextRowDivider = r;
        break;
      }
    }

    // 检查列 handle
    if (nextColDivider == null) {
      for (var c = 0; c < widget.tableNode.colsLen; c++) {
        if (relX >= geo.colLefts[c] &&
            relX < geo.colLefts[c] + geo.colWidths[c] &&
            relY >= -TOP_HEADER_HEIGHT &&
            relY <= geo.totalTableHeight) {
          nextCol = c;
          break;
        }
      }
    }

    // 检查行 handle
    if (nextRowDivider == null) {
      for (var r = 0; r < widget.tableNode.rowsLen; r++) {
        if (relY >= geo.rowTops[r] &&
            relY < geo.rowTops[r] + geo.rowHeights[r] &&
            relX >= -SIDE_HEADER_WIDTH &&
            relX <= geo.totalTableWidth) {
          nextRow = r;
          break;
        }
      }
    }

    if (nextColDivider != _hoveredColDivider ||
        nextRowDivider != _hoveredRowDivider ||
        nextCol != _hoveredCol ||
        nextRow != _hoveredRow) {
      setState(() {
        _hoveredColDivider = nextColDivider;
        _hoveredRowDivider = nextRowDivider;
        _hoveredCol = nextCol;
        _hoveredRow = nextRow;
      });
    }
  }

  void _handleExit() {
    if (_customMenuOpen) return;
    if (_hoveredCol != null ||
        _hoveredRow != null ||
        _hoveredColDivider != null ||
        _hoveredRowDivider != null) {
      setState(() {
        _hoveredCol = null;
        _hoveredRow = null;
        _hoveredColDivider = null;
        _hoveredRowDivider = null;
      });
    }
  }

  _TableLayoutGeometry _computeGeometry(TableNode table) {
    final colsLen = table.colsLen;
    final rowsLen = table.rowsLen;
    final borderWidth = table.config.borderWidth;

    final colWidths =
        List<double>.generate(colsLen, (i) => table.getColWidth(i));
    final rowHeights =
        List<double>.generate(rowsLen, (i) => table.getRowHeight(i));

    final colLefts = List<double>.filled(colsLen, 0.0);
    final colDividerX = List<double>.filled(colsLen, 0.0);
    colLefts[0] = borderWidth;
    for (var c = 1; c < colsLen; c++) {
      colDividerX[c] = colLefts[c - 1] + colWidths[c - 1] + borderWidth / 2;
      colLefts[c] = colLefts[c - 1] + colWidths[c - 1] + borderWidth;
    }
    final totalWidth =
        colLefts[colsLen - 1] + colWidths[colsLen - 1] + borderWidth;

    final rowTops = List<double>.filled(rowsLen, 0.0);
    final rowDividerY = List<double>.filled(rowsLen, 0.0);
    rowTops[0] = borderWidth;
    for (var r = 1; r < rowsLen; r++) {
      rowDividerY[r] = rowTops[r - 1] + rowHeights[r - 1] + borderWidth / 2;
      rowTops[r] = rowTops[r - 1] + rowHeights[r - 1] + borderWidth;
    }
    final totalHeight =
        rowTops[rowsLen - 1] + rowHeights[rowsLen - 1] + borderWidth;

    return _TableLayoutGeometry(
      colWidths: colWidths,
      rowHeights: rowHeights,
      colLefts: colLefts,
      rowTops: rowTops,
      colDividerX: colDividerX,
      rowDividerY: rowDividerY,
      totalTableWidth: totalWidth,
      totalTableHeight: totalHeight,
      borderWidth: borderWidth,
    );
  }

  List<Widget> _buildColumns(BuildContext context) {
    return List.generate(
      widget.tableNode.colsLen,
      (i) => TableCol(
        key: ValueKey('table-col-$i'),
        colIdx: i,
        editorState: widget.editorState,
        tableNode: widget.tableNode,
        menuBuilder: widget.menuBuilder,
        tableStyle: widget.tableStyle,
      ),
    );
  }
}

class _TableLayoutGeometry {
  const _TableLayoutGeometry({
    required this.colWidths,
    required this.rowHeights,
    required this.colLefts,
    required this.rowTops,
    required this.colDividerX,
    required this.rowDividerY,
    required this.totalTableWidth,
    required this.totalTableHeight,
    required this.borderWidth,
  });

  final List<double> colWidths;
  final List<double> rowHeights;
  final List<double> colLefts;
  final List<double> rowTops;
  final List<double> colDividerX;
  final List<double> rowDividerY;
  final double totalTableWidth;
  final double totalTableHeight;
  final double borderWidth;
}

class _TableActionButton extends StatefulWidget {
  const _TableActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.onSecondaryTap,
    this.hoverBgColor,
    this.hoverIconColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final VoidCallback? onSecondaryTap;
  final Color? hoverBgColor;
  final Color? hoverIconColor;

  @override
  State<_TableActionButton> createState() => _TableActionButtonState();
}

class _TableActionButtonState extends State<_TableActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTap: widget.onSecondaryTap,
        child: Tooltip(
          message: widget.tooltip,
          child: Center(
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: _isHovered
                    ? (widget.hoverBgColor ?? EditorTheme.of(context).hover)
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  widget.icon,
                  size: 13,
                  color: _isHovered
                      ? (widget.hoverIconColor ??
                          EditorTheme.of(context).primary)
                      : EditorTheme.of(context).mutedForeground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
