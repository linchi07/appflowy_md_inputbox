import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/toolbar/desktop/items/utils/overlay_util.dart';
import 'package:flutter/material.dart';

class ColorPicker extends StatefulWidget {
  const ColorPicker({
    super.key,
    required this.title,
    required this.selectedColorHex,
    required this.onSubmittedColorHex,
    required this.colorOptions,
    this.resetText,
    this.customColorHex,
    this.resetIconName,
    this.showClearButton = false,
  });

  final String title;
  final String? selectedColorHex;
  final String? customColorHex;
  final void Function(String? color, bool isCustomColor) onSubmittedColorHex;
  final String? resetText;
  final String? resetIconName;
  final bool showClearButton;

  final List<ColorOption> colorOptions;

  @override
  State<ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<ColorPicker> {
  final TextEditingController _colorHexController = TextEditingController();
  final TextEditingController _colorOpacityController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final selectedColorHex = widget.selectedColorHex,
        customColorHex = widget.customColorHex;
    _colorHexController.text =
        _extractColorHex(customColorHex ?? selectedColorHex) ?? 'FFFFFF';
    _colorOpacityController.text =
        _convertHexToOpacity(customColorHex ?? selectedColorHex) ?? '100';
  }

  @override
  void dispose() {
    _colorHexController.dispose();
    _colorOpacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return basicOverlay(
      context,
      width: 300,
      height: 250,
      children: [
        EditorOverlayTitle(text: widget.title),
        const SizedBox(height: 6),
        widget.showClearButton &&
                widget.resetText != null &&
                widget.resetIconName != null
            ? ResetColorButton(
                resetText: widget.resetText!,
                resetIconName: widget.resetIconName!,
                onPressed: (color) =>
                    widget.onSubmittedColorHex.call(color, false),
              )
            : const SizedBox.shrink(),
        CustomColorItem(
          colorController: _colorHexController,
          opacityController: _colorOpacityController,
          onSubmittedColorHex: (color) =>
              widget.onSubmittedColorHex.call(color, true),
        ),
        _buildColorItems(
          widget.colorOptions,
          widget.selectedColorHex,
        ),
      ],
    );
  }

  Widget _buildColorItems(
    List<ColorOption> options,
    String? selectedColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.start,
      children: options
          .map((e) => _buildColorItem(e, e.colorHex == selectedColor))
          .toList(),
    );
  }

  Widget _buildColorItem(ColorOption option, bool isChecked) {
    return EditorMenuItem(
      leading: SizedBox.square(
        dimension: 12,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: option.colorHex.tryToColor(),
            shape: BoxShape.circle,
          ),
        ),
      ),
      selected: isChecked,
      onPressed: () => widget.onSubmittedColorHex(option.colorHex, false),
      child: Text(option.name),
    );
  }

  String? _convertHexToOpacity(String? colorHex) {
    if (colorHex == null) return null;
    final opacityHex = colorHex.substring(2, 4);
    final opacity = int.parse(opacityHex, radix: 16) / 2.55;

    return opacity.toStringAsFixed(0);
  }

  String? _extractColorHex(String? colorHex) {
    if (colorHex == null) return null;

    return colorHex.substring(4);
  }
}

class ResetColorButton extends StatelessWidget {
  const ResetColorButton({
    super.key,
    required this.resetText,
    required this.resetIconName,
    required this.onPressed,
  });

  final Function(String? color) onPressed;
  final String resetText;
  final String resetIconName;

  @override
  Widget build(BuildContext context) => EditorMenuItem(
        onPressed: () => onPressed(null),
        leading: EditorSvg(
          name: resetIconName,
          width: 13,
          height: 13,
          color: EditorTheme.of(context).onSurface,
        ),
        child: Text(resetText),
      );
}

class CustomColorItem extends StatefulWidget {
  const CustomColorItem({
    super.key,
    required this.colorController,
    required this.opacityController,
    required this.onSubmittedColorHex,
  });

  final TextEditingController colorController;
  final TextEditingController opacityController;
  final void Function(String color) onSubmittedColorHex;

  @override
  State<CustomColorItem> createState() => _CustomColorItemState();
}

class _CustomColorItemState extends State<CustomColorItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        EditorMenuItem(
          onPressed: () => setState(() => _expanded = !_expanded),
          leading: SizedBox.square(
            dimension: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(
                  int.tryParse(
                        _combineColorHexAndOpacity(
                          widget.colorController.text,
                          widget.opacityController.text,
                        ),
                      ) ??
                      0xFFFFFFFF,
                ),
                shape: BoxShape.circle,
              ),
            ),
          ),
          trailing:
              Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 16),
          child: Text(AppFlowyEditorL10n.current.customColor),
        ),
        if (_expanded) ...[
          const SizedBox(height: 6),
          _customColorDetailsTextField(
            labelText: AppFlowyEditorL10n.current.hexValue,
            controller: widget.colorController,
            onChanged: (_) => setState(() {}),
            onSubmitted: _submitCustomColorHex,
          ),
          const SizedBox(height: 10),
          _customColorDetailsTextField(
            labelText: AppFlowyEditorL10n.current.opacity,
            controller: widget.opacityController,
            onChanged: (_) => setState(() {}),
            onSubmitted: _submitCustomColorHex,
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _customColorDetailsTextField({
    required String labelText,
    required TextEditingController controller,
    Function(String)? onChanged,
    Function(String)? onSubmitted,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: EditorMenuTextField(
        controller: controller,
        labelText: labelText,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      ),
    );
  }

  String _combineColorHexAndOpacity(String colorHex, String opacity) {
    colorHex = _fixColorHex(colorHex);
    opacity = _fixOpacity(opacity);
    final opacityHex = (int.parse(opacity) * 2.55).round().toRadixString(16);

    return '0x$opacityHex$colorHex';
  }

  String _fixColorHex(String colorHex) {
    if (colorHex.length > 6) {
      colorHex = colorHex.substring(0, 6);
    }
    if (int.tryParse(colorHex, radix: 16) == null) {
      colorHex = 'FFFFFF';
    }

    return colorHex;
  }

  String _fixOpacity(String opacity) {
    // if opacity is 0 - 99, return it
    // otherwise return 100
    RegExp regex = RegExp('^(0|[1-9][0-9]?)');
    if (regex.hasMatch(opacity)) {
      return opacity;
    } else {
      return '100';
    }
  }

  void _submitCustomColorHex(String value) {
    final String color = _combineColorHexAndOpacity(
      widget.colorController.text,
      widget.opacityController.text,
    );
    widget.onSubmittedColorHex(color);
  }
}
