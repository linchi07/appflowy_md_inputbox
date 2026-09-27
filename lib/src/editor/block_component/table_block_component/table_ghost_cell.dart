import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/util.dart';
import 'package:flutter/material.dart';

/// An editable preview that has no document node until text is committed.
class TableGhostCell extends StatefulWidget {
  const TableGhostCell({
    super.key,
    required this.table,
    required this.editorState,
    required this.col,
    required this.row,
    required this.width,
    required this.height,
    required this.label,
  });

  final Node table;
  final EditorState editorState;
  final int col;
  final int row;
  final double width;
  final double height;
  final String? label;

  @override
  State<TableGhostCell> createState() => _TableGhostCellState();
}

class _TableGhostCellState extends State<TableGhostCell> {
  final _controller = TextEditingController();
  bool _committing = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final value = _controller.value;
    if (_committing ||
        value.text.isEmpty ||
        (value.composing.isValid && !value.composing.isCollapsed)) {
      return;
    }
    _committing = true;
    _commit(value.text);
  }

  Future<void> _commit(String text) async {
    final table = widget.table;
    final editorState = widget.editorState;
    final col = widget.col;
    final row = widget.row;
    await TableActions.materializeGhostCell(
      table,
      editorState,
      col: col,
      row: row,
      text: text,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (editorState.isDisposed || table.parent == null) {
        return;
      }
      final cell = getCellNode(table, col, row);
      final paragraph = cell?.children.firstOrNull;
      if (paragraph == null) {
        return;
      }
      editorState.service.keyboardService?.enable();
      editorState.updateSelectionWithReason(
        Selection.collapsed(
          Position(path: paragraph.path, offset: text.length),
        ),
        reason: SelectionUpdateReason.uiEvent,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Material(
        type: MaterialType.transparency,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.onSurface.withValues(alpha: 0.035),
            border: Border.all(
              color: colors.outline.withValues(alpha: 0.5),
            ),
          ),
          child: TextField(
            controller: _controller,
            maxLines: 1,
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: widget.label,
              hintStyle: Theme.of(context).textTheme.bodySmall,
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 10,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
