import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/util.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TableCellBlockKeys {
  const TableCellBlockKeys._();

  static const String type = 'table/cell';

  static const String rowPosition = 'rowPosition';

  static const String colPosition = 'colPosition';

  static const String height = 'height';

  static const String width = 'width';

  static const String rowBackgroundColor = 'rowBackgroundColor';

  static const String colBackgroundColor = 'colBackgroundColor';
}

typedef TableBlockCellComponentColorBuilder = Color? Function(
  BuildContext context,
  Node node,
);

Node tableCellNode(String text, int rowPosition, int colPosition) {
  return Node(
    type: TableCellBlockKeys.type,
    attributes: {
      TableCellBlockKeys.rowPosition: rowPosition,
      TableCellBlockKeys.colPosition: colPosition,
    },
    children: [
      paragraphNode(text: text),
    ],
  );
}

class TableCellBlockComponentBuilder extends BlockComponentBuilder {
  TableCellBlockComponentBuilder({
    super.configuration,
    this.menuBuilder,
    this.colorBuilder,
  });

  final TableBlockComponentMenuBuilder? menuBuilder;
  final TableBlockCellComponentColorBuilder? colorBuilder;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;

    return TableCelBlockWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      menuBuilder: menuBuilder,
      colorBuilder: colorBuilder,
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
  BlockComponentValidate get validate => (node) =>
      node.attributes.isNotEmpty &&
      node.attributes.containsKey(TableCellBlockKeys.rowPosition) &&
      node.attributes.containsKey(TableCellBlockKeys.colPosition);
}

class TableCelBlockWidget extends BlockComponentStatefulWidget {
  const TableCelBlockWidget({
    super.key,
    required super.node,
    this.menuBuilder,
    this.colorBuilder,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  final TableBlockComponentMenuBuilder? menuBuilder;
  final TableBlockCellComponentColorBuilder? colorBuilder;

  @override
  State<TableCelBlockWidget> createState() => _TableCeBlockWidgetState();
}

class _TableCeBlockWidgetState extends State<TableCelBlockWidget> {
  late final editorState = Provider.of<EditorState>(context, listen: false);

  @override
  Widget build(BuildContext context) {
    final cellHeight = context.select((Node n) => n.cellHeight);
    final explicitColor = context.select(
      (Node n) =>
          widget.colorBuilder?.call(context, n) ??
          (n.attributes[TableCellBlockKeys.colBackgroundColor] as String?)
              ?.tryToColor() ??
          (n.attributes[TableCellBlockKeys.rowBackgroundColor] as String?)
              ?.tryToColor(),
    );
    final col =
        widget.node.attributes[TableCellBlockKeys.colPosition] as int? ?? 0;
    final row =
        widget.node.attributes[TableCellBlockKeys.rowPosition] as int? ?? 0;
    final tableNode = widget.node.parent!;
    final tableSelection = TableSelectionScope.of(context);
    final isSelected = tableSelection?.contains(col, row) ?? false;
    final colors = EditorTheme.of(context);
    final baseColor = explicitColor ??
        tableStyleCellColor(
          tableNode,
          widget.node,
          colors,
        );
    final effectiveColor = isSelected
        ? Color.alphaBlend(
            colors.selection,
            baseColor ?? colors.background,
          )
        : baseColor;

    return AnimatedBuilder(
      animation: tableNode,
      builder: (context, child) => Container(
        constraints: BoxConstraints(
          minHeight: cellHeight,
        ),
        color: effectiveColor,
        child: child,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: editorState.renderer.build(
            context,
            widget.node.children.first,
          ),
        ),
      ),
    );
  }
}

Color? tableStyleCellColor(
  Node table,
  Node cell,
  EditorColorScheme colors,
) {
  final row = cell.attributes[TableCellBlockKeys.rowPosition];
  final col = cell.attributes[TableCellBlockKeys.colPosition];
  final isHeader = (row == 0 &&
          table.attributes[TableBlockKeys.shadeFirstRow] == true) ||
      (col == 0 && table.attributes[TableBlockKeys.shadeFirstColumn] == true);
  if (isHeader) {
    return colors.subtleSurface;
  }
  if (row is int &&
      row.isOdd &&
      table.attributes[TableBlockKeys.stripeRows] == true) {
    return colors.tableStripeBackground;
  }
  return null;
}
