import 'package:appflowy_editor/src/editor/selection_menu/selection_menu_service.dart';
import 'package:appflowy_editor/src/editor/selection_menu/editor_menu_widgets.dart';
import 'package:appflowy_editor/src/editor/selection_menu/selection_menu_widget.dart';
import 'package:appflowy_editor/src/editor_state.dart';
import 'package:flutter/material.dart';

class SelectionMenuItemWidget extends StatefulWidget {
  const SelectionMenuItemWidget({
    super.key,
    required this.editorState,
    required this.menuService,
    required this.item,
    required this.isSelected,
    required this.selectionMenuStyle,
    this.width = 140.0,
  });

  final EditorState editorState;
  final SelectionMenuService menuService;
  final SelectionMenuItem item;
  final double width;
  final bool isSelected;
  final SelectionMenuStyle selectionMenuStyle;

  @override
  State<SelectionMenuItemWidget> createState() =>
      _SelectionMenuItemWidgetState();
}

class _SelectionMenuItemWidgetState extends State<SelectionMenuItemWidget> {
  var _onHover = false;

  @override
  Widget build(BuildContext context) {
    final style = widget.selectionMenuStyle;
    final isSelected = widget.isSelected || _onHover;

    return SizedBox(
      width: widget.width,
      child: EditorMenuItem(
        style: style,
        active: widget.isSelected,
        leading: widget.item.icon(
          widget.editorState,
          widget.isSelected || _onHover,
          widget.selectionMenuStyle,
        ),
        child: widget.item.nameBuilder
                ?.call(widget.item.name, style, isSelected) ??
            Text(
              widget.item.name,
              textAlign: TextAlign.left,
              style: TextStyle(
                color: (widget.isSelected || _onHover)
                    ? style.selectionMenuItemSelectedTextColor
                    : style.selectionMenuItemTextColor,
                fontSize: 12.0,
              ),
            ),
        onPressed: () {
          widget.item.handler(
            widget.editorState,
            widget.menuService,
            context,
          );
        },
        onHover: (value) {
          setState(() {
            _onHover = value;
          });
        },
      ),
    );
  }
}
