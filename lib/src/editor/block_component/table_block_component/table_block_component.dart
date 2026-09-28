import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'table_view.dart';

class TableBlockKeys {
  const TableBlockKeys._();

  static const String type = 'table';

  static const String colDefaultWidth = 'colDefaultWidth';

  static const String rowDefaultHeight = 'rowDefaultHeight';

  static const String colMinimumWidth = 'colMinimumWidth';

  static const String borderWidth = 'borderWidth';

  static const String colsLen = 'colsLen';

  static const String rowsLen = 'rowsLen';

  static const String colsHeight = 'colsHeight';

  static const String shadeFirstRow = 'shadeFirstRow';

  static const String shadeFirstColumn = 'shadeFirstColumn';

  static const String stripeRows = 'stripeRows';
}

class TableStyle {
  final double colWidth;
  final double rowHeight;
  final double colMinimumWidth;
  final double borderWidth;
  final Widget addIcon;
  final Widget handlerIcon;
  final Color borderColor;
  final Color borderHoverColor;

  const TableStyle({
    this.colWidth = 160,
    this.rowHeight = 38,
    this.colMinimumWidth = 40,
    this.borderWidth = 1.0,
    this.addIcon = TableDefaults.DEFAULT_ADD_ICON,
    this.handlerIcon = TableDefaults.DEFAULT_HANDLER_ICON,
    this.borderColor = TableDefaults.DEFAULT_BORDER_COLOR,
    this.borderHoverColor = TableDefaults.DEFAULT_BORDER_HOVER_COLOR,
  });
}

class TableDefaults {
  const TableDefaults._();

  static const double DEFAULT_COL_WIDTH = 160.0;
  static const double DEFAULT_ROW_HEIGHT = 38.0;
  static const double DEFAULT_COL_MINIMUM_WIDTH = 40.0;
  static const double DEFAULT_BORDER_WIDTH = 1.0;
  static const Color DEFAULT_BORDER_COLOR = Color(0xFFE2E4E8);
  static const Color DEFAULT_BORDER_HOVER_COLOR = Color(0xFFB0B4BA);
  static const Widget DEFAULT_ADD_ICON = Icon(Icons.add, size: 16);
  static const Widget DEFAULT_HANDLER_ICON = Icon(Icons.drag_indicator, size: 16);

  static double colWidth = DEFAULT_COL_WIDTH;
  static double rowHeight = DEFAULT_ROW_HEIGHT;
  static double colMinimumWidth = DEFAULT_COL_MINIMUM_WIDTH;
  static double borderWidth = DEFAULT_BORDER_WIDTH;
  static Color borderColor = DEFAULT_BORDER_COLOR;
  static Color borderHoverColor = DEFAULT_BORDER_HOVER_COLOR;
  static Widget get addIcon => DEFAULT_ADD_ICON;
  static Widget get handlerIcon => DEFAULT_HANDLER_ICON;
}

enum TableDirection { row, col }

typedef TableBlockComponentMenuBuilder = Widget Function(
  Node,
  EditorState,
  int,
  TableDirection,
  VoidCallback?,
  VoidCallback?,
);

class TableBlockComponentBuilder extends BlockComponentBuilder {
  TableBlockComponentBuilder({
    super.configuration,
    this.tableStyle = const TableStyle(),
    this.menuBuilder,
  });

  final TableBlockComponentMenuBuilder? menuBuilder;
  final TableStyle tableStyle;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    TableDefaults.colWidth = tableStyle.colWidth;
    TableDefaults.rowHeight = tableStyle.rowHeight;
    TableDefaults.colMinimumWidth = tableStyle.colMinimumWidth;
    TableDefaults.borderWidth = tableStyle.borderWidth;

    return TableBlockComponentWidget(
      key: node.key,
      tableNode: TableNode(node: node),
      node: node,
      configuration: configuration,
      menuBuilder: menuBuilder,
      tableStyle: tableStyle,
      showActions: showActions(node),
      actionBuilder: (context, state) => actionBuilder(
        blockComponentContext,
        state,
      ),
      actionTrailingBuilder: (context, state) => actionTrailingBuilder(
        blockComponentContext,
        state,
      ),
    );
  }

  @override
  BlockComponentValidate get validate => (node) {
        // check the node is valid
        if (node.attributes.isEmpty) {
          AppFlowyEditorLog.editor
              .debug('TableBlockComponentBuilder: node is empty');

          return false;
        }

        // check the node has rowPosition and colPosition
        if (!node.attributes.containsKey(TableBlockKeys.colsLen) ||
            !node.attributes.containsKey(TableBlockKeys.rowsLen)) {
          AppFlowyEditorLog.editor.debug(
            'TableBlockComponentBuilder: node has no colsLen or rowsLen',
          );

          return false;
        }

        final colsLen = node.attributes[TableBlockKeys.colsLen];
        final rowsLen = node.attributes[TableBlockKeys.rowsLen];

        // check its children
        final children = node.children;
        if (children.isEmpty) {
          AppFlowyEditorLog.editor
              .debug('TableBlockComponentBuilder: children is empty');

          return false;
        }

        if (children.length != colsLen * rowsLen) {
          AppFlowyEditorLog.editor.debug(
            'TableBlockComponentBuilder: children length(${children.length}) is not equal to colsLen * rowsLen($colsLen * $rowsLen)',
          );

          return false;
        }

        // all children should contain rowPosition and colPosition
        for (var i = 0; i < colsLen; i++) {
          for (var j = 0; j < rowsLen; j++) {
            final child = children.where(
              (n) =>
                  n.attributes[TableCellBlockKeys.colPosition] == i &&
                  n.attributes[TableCellBlockKeys.rowPosition] == j,
            );
            if (child.isEmpty) {
              AppFlowyEditorLog.editor.debug(
                'TableBlockComponentBuilder: child($i, $j) is empty',
              );

              return false;
            }

            // should only contains one child
            if (child.length != 1) {
              AppFlowyEditorLog.editor.debug(
                'TableBlockComponentBuilder: child($i, $j) is not unique',
              );

              return false;
            }
          }
        }

        return true;
      };
}

class TableBlockComponentWidget extends BlockComponentStatefulWidget {
  const TableBlockComponentWidget({
    super.key,
    required this.tableNode,
    required super.node,
    this.tableStyle = const TableStyle(),
    this.menuBuilder,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  final TableNode tableNode;

  final TableBlockComponentMenuBuilder? menuBuilder;
  final TableStyle tableStyle;

  @override
  State<TableBlockComponentWidget> createState() =>
      _TableBlockComponentWidgetState();
}

class _TableBlockComponentWidgetState extends State<TableBlockComponentWidget>
    with SelectableMixin, BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  late final editorState = Provider.of<EditorState>(context, listen: false);
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        child: TableView(
          tableNode: widget.tableNode,
          editorState: editorState,
          menuBuilder: widget.menuBuilder,
          tableStyle: widget.tableStyle,
        ),
      ),
    );

    child = Padding(
      key: tableKey,
      padding: padding,
      child: child,
    );

    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [
        BlockSelectionType.block,
      ],
      child: child,
    );

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    return child;
  }

  final tableKey = GlobalKey();

  RenderBox get _renderBox => context.findRenderObject() as RenderBox;

  @override
  Position start() => Position(path: widget.node.path, offset: 0);

  @override
  Position end() => Position(path: widget.node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) {
    final parentBox = context.findRenderObject();
    final tableBox = tableKey.currentContext?.findRenderObject();
    if (parentBox is RenderBox && tableBox is RenderBox) {
      return [
        (shiftWithBaseOffset
                ? tableBox.localToGlobal(Offset.zero, ancestor: parentBox)
                : Offset.zero) &
            tableBox.size,
      ];
    }

    return [Offset.zero & _renderBox.size];
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) => Selection.single(
        path: widget.node.path,
        startOffset: 0,
        endOffset: 1,
      );

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;

  @override
  Offset localToGlobal(
    Offset offset, {
    bool shiftWithBaseOffset = false,
  }) =>
      _renderBox.localToGlobal(offset);

  @override
  Rect getBlockRect({
    bool shiftWithBaseOffset = false,
  }) {
    return getRectsInSelection(Selection.invalid()).first;
  }

  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    final size = _renderBox.size;

    return Rect.fromLTWH(-size.width / 2.0, 0, size.width, size.height);
  }
}

SelectionMenuItem tableMenuItem = SelectionMenuItem(
  getName: () => AppFlowyEditorL10n.current.table,
  icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
    icon: Icons.table_view,
    isSelected: isSelected,
    style: style,
  ),
  keywords: ['table'],
  handler: (editorState, _, __) {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }

    final currentNode = editorState.getNodeAtPath(selection.end.path);
    if (currentNode == null) {
      return;
    }

    final tableNode = TableNode.fromList([
      ['', ''],
      ['', ''],
    ]);

    final transaction = editorState.transaction;
    final delta = currentNode.delta;
    if (delta != null && delta.isEmpty) {
      transaction
        ..insertNode(selection.end.path, tableNode.node)
        ..deleteNode(currentNode);
      transaction.afterSelection = Selection.collapsed(
        Position(
          path: selection.end.path + [0, 0],
          offset: 0,
        ),
      );
    } else {
      transaction.insertNode(selection.end.path.next, tableNode.node);
      transaction.afterSelection = Selection.collapsed(
        Position(
          path: selection.end.path.next + [0, 0],
          offset: 0,
        ),
      );
    }

    editorState.apply(transaction);
  },
);
