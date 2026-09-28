import 'dart:math' as math;
import 'package:appflowy_editor/src/core/location/position.dart';
import 'package:appflowy_editor/src/core/location/selection.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_block_component.dart';
import 'package:appflowy_editor/src/editor_state.dart';
import 'package:flutter/widgets.dart';

/// Represents a 2D rectangular cell range selection in a table.
class TableSelection {
  const TableSelection({
    required this.startCol,
    required this.startRow,
    required this.endCol,
    required this.endRow,
  });

  final int startCol;
  final int startRow;
  final int endCol;
  final int endRow;

  int get minCol => math.min(startCol, endCol);
  int get maxCol => math.max(startCol, endCol);
  int get minRow => math.min(startRow, endRow);
  int get maxRow => math.max(startRow, endRow);

  bool get isMultiCell => (minCol != maxCol) || (minRow != maxRow);

  int get cellCount => (maxCol - minCol + 1) * (maxRow - minRow + 1);

  bool contains(int col, int row) {
    return col >= minCol && col <= maxCol && row >= minRow && row <= maxRow;
  }

  TableSelection copyWith({
    int? startCol,
    int? startRow,
    int? endCol,
    int? endRow,
  }) {
    return TableSelection(
      startCol: startCol ?? this.startCol,
      startRow: startRow ?? this.startRow,
      endCol: endCol ?? this.endCol,
      endRow: endRow ?? this.endRow,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TableSelection &&
          runtimeType == other.runtimeType &&
          startCol == other.startCol &&
          startRow == other.startRow &&
          endCol == other.endCol &&
          endRow == other.endRow;

  @override
  int get hashCode =>
      startCol.hashCode ^
      startRow.hashCode ^
      endCol.hashCode ^
      endRow.hashCode;
}

/// InheritedWidget that provides the active [TableSelection] down the widget tree.
class TableSelectionScope extends InheritedWidget {
  const TableSelectionScope({
    super.key,
    required this.selection,
    required super.child,
  });

  final TableSelection? selection;

  static TableSelection? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<TableSelectionScope>()
        ?.selection;
  }

  @override
  bool updateShouldNotify(TableSelectionScope oldWidget) {
    return selection != oldWidget.selection;
  }
}

/// Coordinates cross-block selections to treat [TableNode] as an atomic block.
///
/// When a selection spans across blocks and enters or exits a table, the table
/// is normalized to be selected as a whole unit, matching Obsidian's atomic table behavior.
class TableSelectionCoordinator implements SelectionCoordinator {
  const TableSelectionCoordinator();

  @override
  Selection coordinateSelection(EditorState editorState, Selection selection) {
    if (selection.isCollapsed) {
      return selection;
    }

    final start = selection.start;
    final end = selection.end;
    if (start.path.isEmpty || end.path.isEmpty) {
      return selection;
    }

    final startTopIndex = start.path.first;
    final endTopIndex = end.path.first;

    // Both endpoints are in the same top-level block -> not cross-block
    if (startTopIndex == endTopIndex) {
      return selection;
    }

    final rootChildren = editorState.document.root.children;
    Position newStart = start;
    Position newEnd = end;

    // 1. Check if the start of selection is inside or on a table block
    if (startTopIndex >= 0 && startTopIndex < rootChildren.length) {
      final startBlock = rootChildren[startTopIndex];
      if (startBlock.type == TableBlockKeys.type) {
        if (endTopIndex > startTopIndex) {
          // Dragging downwards out of table -> include entire table from its start
          newStart = Position(path: [startTopIndex], offset: 0);
        } else {
          // Dragging upwards out of table -> include entire table from its end
          newStart = Position(path: [startTopIndex], offset: 1);
        }
      }
    }

    // 2. Check if the end of selection is inside or on a table block
    if (endTopIndex >= 0 && endTopIndex < rootChildren.length) {
      final endBlock = rootChildren[endTopIndex];
      if (endBlock.type == TableBlockKeys.type) {
        if (startTopIndex < endTopIndex) {
          // Dragging downwards into table -> include entire table to its end
          newEnd = Position(path: [endTopIndex], offset: 1);
        } else {
          // Dragging upwards into table -> include entire table to its start
          newEnd = Position(path: [endTopIndex], offset: 0);
        }
      }
    }

    if (newStart != start || newEnd != end) {
      return Selection(start: newStart, end: newEnd);
    }

    return selection;
  }
}
