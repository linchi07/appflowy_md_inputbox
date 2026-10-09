import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/util.dart';

class TableActions {
  const TableActions._();

  static void toggleStyle(Node tableNode, EditorState editorState, String key) {
    if (!editorState.editable ||
        !{
          TableBlockKeys.shadeFirstRow,
          TableBlockKeys.shadeFirstColumn,
          TableBlockKeys.stripeRows,
        }.contains(key)) {
      return;
    }
    final transaction = editorState.transaction;
    transaction.updateNode(tableNode, {key: tableNode.attributes[key] != true});
    editorState.apply(transaction, withUpdateSelection: false);
  }

  static Future<void> add(
    Node node,
    int position,
    EditorState editorState,
    TableDirection dir,
  ) async {
    if (dir == TableDirection.col) {
      await _addCol(node, position, editorState);
    } else {
      await _addRow(node, position, editorState);
    }
  }

  static void delete(
    Node node,
    int position,
    EditorState editorState,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _deleteCol(node, position, editorState);
    } else {
      _deleteRow(node, position, editorState);
    }
  }

  static void duplicate(
    Node node,
    int position,
    EditorState editorState,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _duplicateCol(node, position, editorState);
    } else {
      _duplicateRow(node, position, editorState);
    }
  }

  static void clear(
    Node node,
    int position,
    EditorState editorState,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _clearCol(node, position, editorState);
    } else {
      _clearRow(node, position, editorState);
    }
  }

  static void setBgColor(
    Node node,
    int position,
    EditorState editorState,
    String? color,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _setColBgColor(node, position, editorState, color);
    } else {
      _setRowBgColor(node, position, editorState, color);
    }
  }
}

Future<void> _addCol(
  Node tableNode,
  int position,
  EditorState editorState,
) async {
  assert(position >= 0);

  final transaction = editorState.transaction;

  List<Node> cellNodes = [];
  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  if (position != colsLen) {
    for (var i = position; i < colsLen; i++) {
      for (var j = 0; j < rowsLen; j++) {
        final node = getCellNode(tableNode, i, j)!;
        transaction.updateNode(node, {TableCellBlockKeys.colPosition: i + 1});
      }
    }
  }

  for (var i = 0; i < rowsLen; i++) {
    final node = Node(
      type: TableCellBlockKeys.type,
      attributes: {
        TableCellBlockKeys.colPosition: position,
        TableCellBlockKeys.rowPosition: i,
      },
    );
    node.insert(paragraphNode());
    final firstCellInRow = getCellNode(tableNode, 0, i);
    if (firstCellInRow?.attributes.containsKey(
          TableCellBlockKeys.rowBackgroundColor,
        ) ??
        false) {
      node.updateAttributes({
        TableCellBlockKeys.rowBackgroundColor:
            firstCellInRow!.attributes[TableCellBlockKeys.rowBackgroundColor],
      });
    }

    cellNodes.add(newCellNode(tableNode, node));
  }

  late Path insertPath;
  if (position == 0) {
    insertPath = getCellNode(tableNode, 0, 0)!.path;
  } else {
    insertPath = getCellNode(tableNode, position - 1, rowsLen - 1)!.path.next;
  }
  // TODO(zoli): this calls notifyListener rowsLen+1 times. isn't there a better
  // way?
  transaction.insertNodes(insertPath, cellNodes);
  transaction.updateNode(tableNode, {TableBlockKeys.colsLen: colsLen + 1});

  await editorState.apply(transaction, withUpdateSelection: false);
}

Future<void> _addRow(
  Node tableNode,
  int position,
  EditorState editorState,
) async {
  final rows = tableNode.attributes[TableBlockKeys.rowsLen] as int;
  final cols = tableNode.attributes[TableBlockKeys.colsLen] as int;
  if (position < 0 || position > rows) {
    throw RangeError.range(position, 0, rows);
  }
  final transaction = editorState.transaction;
  _updateCellPositions(tableNode, transaction, 0, position, 0, 1);
  for (var col = 0; col < cols; col++) {
    final first = getCellNode(tableNode, col, 0)!;
    final node = Node(
      type: TableCellBlockKeys.type,
      attributes: {
        TableCellBlockKeys.colPosition: col,
        TableCellBlockKeys.rowPosition: position,
        if (first.attributes[TableCellBlockKeys.colBackgroundColor]
            case final color?)
          TableCellBlockKeys.colBackgroundColor: color,
      },
      children: [paragraphNode()],
    );
    final path = position == 0
        ? first.path
        : getCellNode(tableNode, col, position - 1)!.path.next;
    transaction.insertNode(path, node);
  }
  transaction.updateNode(tableNode, {TableBlockKeys.rowsLen: rows + 1});
  await editorState.apply(transaction, withUpdateSelection: false);
}

void _deleteCol(Node tableNode, int col, EditorState editorState) {
  final transaction = editorState.transaction;

  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  if (colsLen == 1) {
    if (editorState.document.root.children.length == 1) {
      final emptyParagraph = paragraphNode();
      transaction.insertNode(tableNode.path, emptyParagraph);
    }
    transaction.deleteNode(tableNode);
  } else {
    List<Node> nodes = [];
    for (var i = 0; i < rowsLen; i++) {
      nodes.add(getCellNode(tableNode, col, i)!);
    }
    transaction.deleteNodes(nodes);

    _updateCellPositions(tableNode, transaction, col + 1, 0, -1, 0);

    transaction.updateNode(tableNode, {TableBlockKeys.colsLen: colsLen - 1});
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

void _deleteRow(Node tableNode, int row, EditorState editorState) {
  final transaction = editorState.transaction;

  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  if (rowsLen == 1) {
    if (editorState.document.root.children.length == 1) {
      final emptyParagraph = paragraphNode();
      transaction.insertNode(tableNode.path, emptyParagraph);
    }
    transaction.deleteNode(tableNode);
  } else {
    List<Node> nodes = [];
    for (var i = 0; i < colsLen; i++) {
      nodes.add(getCellNode(tableNode, i, row)!);
    }
    transaction.deleteNodes(nodes);

    _updateCellPositions(tableNode, transaction, 0, row + 1, 0, -1);

    transaction.updateNode(tableNode, {TableBlockKeys.rowsLen: rowsLen - 1});
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

void _duplicateCol(Node tableNode, int col, EditorState editorState) {
  final transaction = editorState.transaction;

  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];
  List<Node> nodes = [];
  for (var i = 0; i < rowsLen; i++) {
    final node = getCellNode(tableNode, col, i)!;
    nodes.add(
      node.copyWith(
        attributes: {
          ...node.attributes,
          TableCellBlockKeys.colPosition: col + 1,
          TableCellBlockKeys.rowPosition: i,
        },
      ),
    );
  }
  transaction.insertNodes(
    getCellNode(tableNode, col, rowsLen - 1)!.path.next,
    nodes,
  );

  _updateCellPositions(tableNode, transaction, col + 1, 0, 1, 0);

  transaction.updateNode(tableNode, {TableBlockKeys.colsLen: colsLen + 1});

  editorState.apply(transaction, withUpdateSelection: false);
}

void _duplicateRow(Node tableNode, int row, EditorState editorState) {
  final transaction = editorState.transaction;
  final rows = tableNode.attributes[TableBlockKeys.rowsLen] as int;
  final cols = tableNode.attributes[TableBlockKeys.colsLen] as int;
  _updateCellPositions(tableNode, transaction, 0, row + 1, 0, 1);
  for (var col = 0; col < cols; col++) {
    final node = getCellNode(tableNode, col, row)!;
    transaction.insertNode(
      node.path.next,
      node.copyWith(
        attributes: {
          ...node.attributes,
          TableCellBlockKeys.rowPosition: row + 1,
          TableCellBlockKeys.colPosition: col,
        },
      ),
    );
  }
  transaction.updateNode(tableNode, {TableBlockKeys.rowsLen: rows + 1});
  editorState.apply(transaction, withUpdateSelection: false);
}

void _setColBgColor(
  Node tableNode,
  int col,
  EditorState editorState,
  String? color,
) {
  final transaction = editorState.transaction;

  final rowslen = tableNode.attributes[TableBlockKeys.rowsLen];
  for (var i = 0; i < rowslen; i++) {
    final node = getCellNode(tableNode, col, i)!;
    transaction.updateNode(node, {
      TableCellBlockKeys.colBackgroundColor: color,
    });
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

void _setRowBgColor(
  Node tableNode,
  int row,
  EditorState editorState,
  String? color,
) {
  final transaction = editorState.transaction;

  final colsLen = tableNode.attributes[TableBlockKeys.colsLen];
  for (var i = 0; i < colsLen; i++) {
    final node = getCellNode(tableNode, i, row)!;
    transaction.updateNode(node, {
      TableCellBlockKeys.rowBackgroundColor: color,
    });
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

void _clearCol(Node tableNode, int col, EditorState editorState) {
  final transaction = editorState.transaction;
  final rows = tableNode.attributes[TableBlockKeys.rowsLen] as int;
  for (var row = 0; row < rows; row++) {
    for (final text in getCellNode(tableNode, col, row)!.children) {
      if (text.delta != null) {
        transaction.deleteText(text, 0, text.delta!.length);
      }
    }
  }
  editorState.apply(transaction, withUpdateSelection: false);
}

void _clearRow(Node tableNode, int row, EditorState editorState) {
  final transaction = editorState.transaction;
  final cols = tableNode.attributes[TableBlockKeys.colsLen] as int;
  for (var col = 0; col < cols; col++) {
    for (final text in getCellNode(tableNode, col, row)!.children) {
      if (text.delta != null) {
        transaction.deleteText(text, 0, text.delta!.length);
      }
    }
  }
  editorState.apply(transaction, withUpdateSelection: false);
}

dynamic newCellNode(Node tableNode, n) {
  final row = n.attributes[TableCellBlockKeys.rowPosition] as int;
  final col = n.attributes[TableCellBlockKeys.colPosition] as int;
  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen];
  final int colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  if (!n.attributes.containsKey(TableCellBlockKeys.height)) {
    double nodeHeight = double.tryParse(
      tableNode.attributes[TableBlockKeys.rowDefaultHeight].toString(),
    )!;
    if (row < rowsLen) {
      nodeHeight = double.tryParse(
            getCellNode(
              tableNode,
              0,
              row,
            )!
                .attributes[TableCellBlockKeys.height]
                .toString(),
          ) ??
          nodeHeight;
    }
    n.updateAttributes({TableCellBlockKeys.height: nodeHeight});
  }

  if (!n.attributes.containsKey(TableCellBlockKeys.width)) {
    double nodeWidth = double.tryParse(
      tableNode.attributes[TableBlockKeys.colDefaultWidth].toString(),
    )!;
    if (col < colsLen) {
      nodeWidth = double.tryParse(
            getCellNode(
              tableNode,
              col,
              0,
            )!
                .attributes[TableCellBlockKeys.width]
                .toString(),
          ) ??
          nodeWidth;
    }
    n.updateAttributes({TableCellBlockKeys.width: nodeWidth});
  }

  return n;
}

void _updateCellPositions(
  Node tableNode,
  Transaction transaction,
  int fromCol,
  int fromRow,
  int addToCol,
  int addToRow,
) {
  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  for (var i = fromCol; i < colsLen; i++) {
    for (var j = fromRow; j < rowsLen; j++) {
      transaction.updateNode(getCellNode(tableNode, i, j)!, {
        TableCellBlockKeys.colPosition: i + addToCol,
        TableCellBlockKeys.rowPosition: j + addToRow,
      });
    }
  }
}
