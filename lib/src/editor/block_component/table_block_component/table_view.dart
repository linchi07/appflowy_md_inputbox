import 'dart:math' as math;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_action_menu.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_col.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class TableView extends StatefulWidget {
  const TableView({
    super.key,
    required this.editorState,
    required this.tableNode,
    required this.tableStyle,
    this.menuBuilder,
  });

  final EditorState editorState;
  final TableNode tableNode;
  final TableBlockComponentMenuBuilder? menuBuilder;
  final TableStyle tableStyle;

  @override
  State<TableView> createState() => _TableViewState();
}

class _TableViewState extends State<TableView> {
  static const double SIDE_HEADER_WIDTH = 26.0;
  static const double TOP_HEADER_HEIGHT = 26.0;
  static const double ADD_COL_WIDTH = 20.0;
  static const double ADD_ROW_HEIGHT = 20.0;
  static const double SPACING = 4.0;
  static const double HIT_DIVIDER_THRESHOLD = 8.0;

  static const Color DEFAULT_INDICATOR_COLOR = Color(0xFF9E9E9E);
  static const Color DEFAULT_INDICATOR_HOVER_COLOR = Color(0xFF616161);
  static const Color DEFAULT_ADD_BUTTON_HOVER_BG = Color(0xFFF3F4F6);

  int? _hoveredCol;
  int? _hoveredRow;
  int? _hoveredColDivider;
  int? _hoveredRowDivider;
  bool _hoveringAddCol = false;
  bool _hoveringAddRow = false;

  @override
  void initState() {
    super.initState();
    widget.tableNode.node.addListener(_onTableNodeChanged);
  }

  @override
  void didUpdateWidget(TableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tableNode.node != widget.tableNode.node) {
      oldWidget.tableNode.node.removeListener(_onTableNodeChanged);
      widget.tableNode.node.addListener(_onTableNodeChanged);
    }
  }

  @override
  void dispose() {
    widget.tableNode.node.removeListener(_onTableNodeChanged);
    super.dispose();
  }

  void _onTableNodeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final table = widget.tableNode;
    final isEditable = widget.editorState.editable;
    final geo = _computeGeometry(table);

    final totalWidth = SIDE_HEADER_WIDTH +
        geo.totalTableWidth +
        (isEditable ? SPACING + ADD_COL_WIDTH : 0.0);
    final totalHeight = TOP_HEADER_HEIGHT +
        geo.totalTableHeight +
        (isEditable ? SPACING + ADD_ROW_HEIGHT : 0.0);

    return MouseRegion(
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

            if (isEditable) ...[
              // 左上角样式编辑按钮 (不侵入表格)
              Positioned(
                left: (SIDE_HEADER_WIDTH - 20) / 2,
                top: (TOP_HEADER_HEIGHT - 20) / 2,
                width: 20,
                height: 20,
                child: _buildStyleButton(table),
              ),

              // 列 handle (表格外，浅灰色图标，无 fill / shape)
              if (_hoveredCol != null && _hoveredColDivider == null)
                Positioned(
                  key: ValueKey('table-col-handle-$_hoveredCol'),
                  left: SIDE_HEADER_WIDTH +
                      geo.colLefts[_hoveredCol!] +
                      geo.colWidths[_hoveredCol!] / 2 -
                      10,
                  top: (TOP_HEADER_HEIGHT - 18) / 2,
                  width: 20,
                  height: 18,
                  child: _buildColHandle(_hoveredCol!),
                ),

              // 行 handle (表格外，浅灰色图标，无 fill / shape)
              if (_hoveredRow != null && _hoveredRowDivider == null)
                Positioned(
                  key: ValueKey('table-row-handle-$_hoveredRow'),
                  left: (SIDE_HEADER_WIDTH - 18) / 2,
                  top: TOP_HEADER_HEIGHT +
                      geo.rowTops[_hoveredRow!] +
                      geo.rowHeights[_hoveredRow!] / 2 -
                      10,
                  width: 18,
                  height: 20,
                  child: _buildRowHandle(_hoveredRow!),
                ),

              // 两列之间的插入三角形
              if (_hoveredColDivider != null)
                Positioned(
                  key: ValueKey('table-insert-col-divider-$_hoveredColDivider'),
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
                  key: ValueKey('table-insert-row-divider-$_hoveredRowDivider'),
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
    );
  }

  Widget _buildStyleButton(TableNode table) {
    return PopupMenuButton<String>(
      key: const ValueKey('table-style-button'),
      tooltip: '表格样式',
      icon: const Icon(
        Icons.tune_outlined,
        size: 16,
        color: DEFAULT_INDICATOR_COLOR,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      splashRadius: 12,
      onSelected: (key) => TableActions.toggleStyle(
        table.node,
        widget.editorState,
        key,
      ),
      itemBuilder: (context) => [
        for (final (key, label) in [
          (TableBlockKeys.shadeFirstRow, '首行灰色'),
          (TableBlockKeys.shadeFirstColumn, '首列灰色'),
          (TableBlockKeys.stripeRows, '交替行底色'),
        ])
          CheckedPopupMenuItem<String>(
            value: key,
            checked: table.node.attributes[key] == true,
            child: Text(label),
          ),
      ],
    );
  }

  Widget _buildColHandle(int colIdx) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => showActionMenu(
          context,
          widget.tableNode.node,
          widget.editorState,
          colIdx,
          TableDirection.col,
        ),
        child: Center(
          child: Transform.rotate(
            angle: math.pi / 2,
            child: const Icon(
              Icons.drag_indicator,
              size: 16,
              color: DEFAULT_INDICATOR_COLOR,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRowHandle(int rowIdx) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => showActionMenu(
          context,
          widget.tableNode.node,
          widget.editorState,
          rowIdx,
          TableDirection.row,
        ),
        child: const Center(
          child: Icon(
            Icons.drag_indicator,
            size: 16,
            color: DEFAULT_INDICATOR_COLOR,
          ),
        ),
      ),
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
        child: const Tooltip(
          message: '在此处插入列',
          child: Center(
            child: Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: DEFAULT_INDICATOR_HOVER_COLOR,
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
        child: const Tooltip(
          message: '在此处插入行',
          child: Center(
            child: Icon(
              Icons.arrow_right,
              size: 18,
              color: DEFAULT_INDICATOR_HOVER_COLOR,
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
                ? DEFAULT_ADD_BUTTON_HOVER_BG
                : Colors.transparent,
            border: Border.all(
              color: _hoveringAddCol
                  ? widget.tableStyle.borderHoverColor
                  : widget.tableStyle.borderColor.withValues(alpha: 0.6),
              width: widget.tableStyle.borderWidth,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Center(
            child: Icon(
              Icons.add,
              size: 14,
              color: _hoveringAddCol
                  ? DEFAULT_INDICATOR_HOVER_COLOR
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
                ? DEFAULT_ADD_BUTTON_HOVER_BG
                : Colors.transparent,
            border: Border.all(
              color: _hoveringAddRow
                  ? widget.tableStyle.borderHoverColor
                  : widget.tableStyle.borderColor.withValues(alpha: 0.6),
              width: widget.tableStyle.borderWidth,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Center(
            child: Icon(
              Icons.add,
              size: 14,
              color: _hoveringAddRow
                  ? DEFAULT_INDICATOR_HOVER_COLOR
                  : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }

  void _handleHover(PointerHoverEvent event, _TableLayoutGeometry geo) {
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
