import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/util.dart';
import 'package:flutter/material.dart';

SelectionMenuStyle? _menuStyle(EditorState state) =>
    state.editorStyle.selectionMenuStyle;

void showTableStyleMenu(BuildContext context, Node node, EditorState state) {
  final anchor = EditorPopoverMenu.anchorRect(context);
  if (anchor == null) return;
  EditorPopoverMenu.show(
    context: context,
    anchor: anchor,
    colors: state.editorStyle.colorScheme,
    style: _menuStyle(state),
    entries: [
      for (final (key, label) in [
        (TableBlockKeys.shadeFirstRow, '首行灰色'),
        (TableBlockKeys.shadeFirstColumn, '首列灰色'),
        (TableBlockKeys.stripeRows, '交替行底色'),
      ])
        EditorMenuEntry(
          label: label,
          icon: Icons.format_paint_outlined,
          selected: node.attributes[key] == true,
          onSelected: () => TableActions.toggleStyle(node, state, key),
        ),
    ],
  );
}

void showTableColorMenu(
  BuildContext context,
  Node node,
  EditorState state,
  int position,
  TableDirection dir,
) {
  final anchor = EditorPopoverMenu.anchorRect(context);
  if (anchor == null) return;
  _showColorAt(context, anchor, node, state, position, dir);
}

void _showColorAt(
  BuildContext context,
  Rect anchor,
  Node node,
  EditorState state,
  int position,
  TableDirection dir, {
  OverlayState? overlayState,
}) {
  final cell = dir == TableDirection.col
      ? getCellNode(node, position, 0)
      : getCellNode(node, 0, position);
  final key = dir == TableDirection.col
      ? TableCellBlockKeys.colBackgroundColor
      : TableCellBlockKeys.rowBackgroundColor;
  final selected = cell?.attributes[key] as String?;
  void setColor(String? color) =>
      TableActions.setBgColor(node, position, state, color, dir);
  EditorPopoverMenu.show(
    context: context,
    anchor: anchor,
    overlayState: overlayState,
    colors: state.editorStyle.colorScheme,
    width: 238,
    maxHeight: 400,
    footerHeight: 52,
    style: _menuStyle(state),
    entries: [
      EditorMenuEntry(
        label: AppFlowyEditorL10n.current.clearHighlightColor,
        icon: Icons.format_color_reset_outlined,
        selected: selected == null,
        onSelected: () => setColor(null),
      ),
      for (final option in generateHighlightColorOptions())
        EditorMenuEntry(
          label: option.name,
          leading: DecoratedBox(
            decoration: BoxDecoration(
              color: option.colorHex.tryToColor(),
              shape: BoxShape.circle,
              border: Border.all(color: state.editorStyle.colorScheme.border),
            ),
            child: const SizedBox(width: 15, height: 15),
          ),
          selected: selected == option.colorHex,
          onSelected: () => setColor(option.colorHex),
        ),
    ],
    footerBuilder: (context, dismiss) => _CustomColorInput(
      initial: selected,
      onSubmitted: (color) {
        dismiss();
        setColor(color);
      },
    ),
  );
}

void showActionMenu(
  BuildContext context,
  Node node,
  EditorState state,
  int position,
  TableDirection dir, {
  TableMenuEntriesBuilder? menuEntriesBuilder,
}) {
  final anchor = EditorPopoverMenu.anchorRect(context);
  if (anchor == null) return;
  final rootOverlay = Overlay.maybeOf(context, rootOverlay: true);
  final overlayContext = rootOverlay?.context ?? context;
  final defaultEntries = <EditorMenuEntry>[
    EditorMenuEntry(
      label: dir == TableDirection.col
          ? AppFlowyEditorL10n.current.colAddBefore
          : AppFlowyEditorL10n.current.rowAddBefore,
      icon: dir == TableDirection.col
          ? Icons.first_page
          : Icons.vertical_align_top,
      onSelected: () => TableActions.add(node, position, state, dir),
    ),
    EditorMenuEntry(
      label: dir == TableDirection.col
          ? AppFlowyEditorL10n.current.colAddAfter
          : AppFlowyEditorL10n.current.rowAddAfter,
      icon: dir == TableDirection.col
          ? Icons.last_page
          : Icons.vertical_align_bottom,
      onSelected: () => TableActions.add(node, position + 1, state, dir),
    ),
    EditorMenuEntry(
      label: dir == TableDirection.col
          ? AppFlowyEditorL10n.current.colDuplicate
          : AppFlowyEditorL10n.current.rowDuplicate,
      icon: Icons.content_copy_outlined,
      onSelected: () => TableActions.duplicate(node, position, state, dir),
    ),
    EditorMenuEntry(
      label: AppFlowyEditorL10n.current.backgroundColor,
      icon: Icons.palette_outlined,
      onSelected: () => _showColorAt(
        overlayContext,
        anchor,
        node,
        state,
        position,
        dir,
        overlayState: rootOverlay,
      ),
    ),
    EditorMenuEntry(
      label: dir == TableDirection.col
          ? AppFlowyEditorL10n.current.colClear
          : AppFlowyEditorL10n.current.rowClear,
      icon: Icons.backspace_outlined,
      onSelected: () => TableActions.clear(node, position, state, dir),
    ),
    EditorMenuEntry(
      label: dir == TableDirection.col
          ? AppFlowyEditorL10n.current.colRemove
          : AppFlowyEditorL10n.current.rowRemove,
      icon: Icons.delete_outline,
      onSelected: () => TableActions.delete(node, position, state, dir),
    ),
  ];
  EditorPopoverMenu.show(
    context: context,
    anchor: anchor,
    colors: state.editorStyle.colorScheme,
    style: _menuStyle(state),
    entries:
        menuEntriesBuilder?.call(node, state, position, dir) ?? defaultEntries,
  );
}

class _CustomColorInput extends StatefulWidget {
  const _CustomColorInput({required this.initial, required this.onSubmitted});
  final String? initial;
  final ValueChanged<String> onSubmitted;

  @override
  State<_CustomColorInput> createState() => _CustomColorInputState();
}

class _CustomColorInputState extends State<_CustomColorInput> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial == null
        ? ''
        : '#${widget.initial!.replaceFirst('0x', '')}',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final hex = _controller.text.trim().replaceFirst('#', '').toUpperCase();
    if (!RegExp(r'^(?:[0-9A-F]{6}|[0-9A-F]{8})$').hasMatch(hex)) return;
    widget.onSubmitted('0x${hex.length == 6 ? 'FF' : ''}$hex');
  }

  @override
  Widget build(BuildContext context) {
    final color = EditorTheme.of(context).onSurface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 32,
              child: EditorMenuTextField(
                controller: _controller,
                onSubmitted: (_) => _submit(),
                hintText: '#RRGGBB / #AARRGGBB',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: '应用颜色',
            child: GestureDetector(
              onTap: _submit,
              child: Icon(Icons.check, size: 18, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
