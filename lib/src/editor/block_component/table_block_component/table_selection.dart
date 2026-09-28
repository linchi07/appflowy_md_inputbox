import 'dart:math' as math;
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
