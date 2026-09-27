import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_col.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_ghost_cell.dart';
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
  @override
  Widget build(BuildContext context) {
    final table = widget.tableNode;
    final borderWidth = table.config.borderWidth;
    final ghostWidth = table.config.colDefaultWidth.clamp(96.0, 160.0);
    final ghostHeight = table.config.rowDefaultHeight.clamp(36.0, 56.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._buildColumns(context),
            if (widget.editorState.editable)
              Column(
                children: [
                  SizedBox(height: borderWidth),
                  for (var row = 0; row < table.rowsLen; row++) ...[
                    TableGhostCell(
                      key: ValueKey('table-ghost-col-$row'),
                      table: table.node,
                      editorState: widget.editorState,
                      col: table.colsLen,
                      row: row,
                      width: ghostWidth,
                      height: table.getRowHeight(row),
                      label: '新列',
                    ),
                    SizedBox(height: borderWidth),
                  ],
                ],
              ),
          ],
        ),
        if (widget.editorState.editable)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: borderWidth),
              for (var col = 0; col < table.colsLen; col++) ...[
                TableGhostCell(
                  key: ValueKey('table-ghost-row-$col'),
                  table: table.node,
                  editorState: widget.editorState,
                  col: col,
                  row: table.rowsLen,
                  width: table.getColWidth(col),
                  height: ghostHeight,
                  label: '新行',
                ),
                SizedBox(width: borderWidth),
              ],
            ],
          ),
      ],
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
