import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_col_border.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/util.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TableCol extends StatefulWidget {
  const TableCol({
    super.key,
    required this.tableNode,
    required this.editorState,
    required this.colIdx,
    required this.tableStyle,
    this.menuBuilder,
  });

  final int colIdx;
  final EditorState editorState;
  final TableNode tableNode;

  final TableBlockComponentMenuBuilder? menuBuilder;

  final TableStyle tableStyle;

  @override
  State<TableCol> createState() => _TableColState();
}

class _TableColState extends State<TableCol> {
  final Map<Node, (int, VoidCallback)> _listeners = {};

  @override
  void initState() {
    super.initState();
    _scheduleRowHeightUpdates();
  }

  @override
  void didUpdateWidget(TableCol oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tableNode.rowsLen != widget.tableNode.rowsLen ||
        oldWidget.tableNode.colsLen != widget.tableNode.colsLen) {
      _scheduleRowHeightUpdates();
    }
  }

  void _scheduleRowHeightUpdates() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (var i = 0; i < widget.tableNode.rowsLen; i++) {
        updateRowHeightCallback(i);
      }
    });
  }

  @override
  void dispose() {
    for (final entry in _listeners.entries) {
      entry.key.removeListener(entry.value.$2);
    }
    _listeners.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = EditorTheme.of(context);
    final borderColor = widget.tableStyle.borderColor ?? colors.border;
    final borderHoverColor =
        widget.tableStyle.borderHoverColor ?? colors.primary;
    List<Widget> children = [];
    if (widget.colIdx == 0) {
      children.add(
        TableColBorder(
          resizable: false,
          tableNode: widget.tableNode,
          editorState: widget.editorState,
          colIdx: widget.colIdx,
          borderColor: borderColor,
          borderHoverColor: borderHoverColor,
        ),
      );
    }

    children.addAll([
      SizedBox(
        width: context.select(
          (Node n) => getCellNode(n, widget.colIdx, 0)?.cellWidth,
        ),
        child: Column(children: _buildCells(context)),
      ),
      TableColBorder(
        resizable: false,
        tableNode: widget.tableNode,
        editorState: widget.editorState,
        colIdx: widget.colIdx,
        borderColor: borderColor,
        borderHoverColor: borderHoverColor,
      ),
    ]);

    return Row(children: children);
  }

  List<Widget> _buildCells(BuildContext context) {
    final rowsLen = widget.tableNode.rowsLen;
    final List<Widget> cells = [];
    final activeNodes = <Node>{};
    final Widget cellBorder = Container(
      height: widget.tableNode.config.borderWidth,
      color: widget.tableStyle.borderColor ?? EditorTheme.of(context).border,
    );

    for (var i = 0; i < rowsLen; i++) {
      final node = widget.tableNode.getCell(widget.colIdx, i);
      addListener(node, i);
      addListener(node.children.first, i);
      activeNodes.addAll([node, node.children.first]);

      final rowHeight = widget.tableNode.getRowHeight(i);
      cells.addAll([
        Container(
          constraints: BoxConstraints(
            minHeight: rowHeight,
          ),
          child: widget.editorState.renderer.build(
            context,
            node,
          ),
        ),
        cellBorder,
      ]);
    }

    for (final staleNode in _listeners.keys
        .where((node) => !activeNodes.contains(node))
        .toList()) {
      staleNode.removeListener(_listeners.remove(staleNode)!.$2);
    }

    return [
      cellBorder,
      ...cells,
    ];
  }

  void addListener(Node node, int row) {
    final existing = _listeners[node];
    if (existing?.$1 == row) {
      return;
    }
    if (existing != null) {
      node.removeListener(existing.$2);
    }

    void listener() => updateRowHeightCallback(row);
    _listeners[node] = (row, listener);
    node.addListener(listener);
  }

  void updateRowHeightCallback(int row) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || row >= widget.tableNode.rowsLen) {
          return;
        }

        final transaction = widget.editorState.transaction;
        widget.tableNode.updateRowHeight(
          row,
          editorState: widget.editorState,
          transaction: transaction,
        );
        if (transaction.operations.isNotEmpty) {
          transaction.afterSelection = transaction.beforeSelection;
          widget.editorState.apply(transaction);
        }
      });
}
