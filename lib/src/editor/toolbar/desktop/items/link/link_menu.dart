import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/toolbar/desktop/items/utils/overlay_util.dart';
import 'package:appflowy_editor/src/editor/util/link_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LinkMenu extends StatefulWidget {
  const LinkMenu({
    super.key,
    this.linkText,
    this.editorState,
    required this.onSubmitted,
    required this.onOpenLink,
    required this.onCopyLink,
    required this.onRemoveLink,
    required this.onDismiss,
  });

  final String? linkText;
  final EditorState? editorState;
  final void Function(String text) onSubmitted;
  final VoidCallback onOpenLink;
  final VoidCallback onCopyLink;
  final VoidCallback onRemoveLink;
  final VoidCallback onDismiss;

  @override
  State<LinkMenu> createState() => _LinkMenuState();
}

class _LinkMenuState extends State<LinkMenu> {
  final _textEditingController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _textEditingController.text = widget.linkText ?? '';
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _textEditingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: EditorMenuSurface(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EditorOverlayTitle(
              text: AppFlowyEditorL10n.current.addYourLink,
            ),
            const SizedBox(height: 16.0),
            _buildInput(),
            const SizedBox(height: 16.0),
            if (widget.linkText != null) ...[
              _buildIconButton(
                iconName: 'link',
                text: AppFlowyEditorL10n.current.openLink,
                onPressed: widget.onOpenLink,
              ),
              _buildIconButton(
                iconName: 'copy',
                text: AppFlowyEditorL10n.current.copyLink,
                onPressed: widget.onCopyLink,
              ),
              _buildIconButton(
                iconName: 'delete',
                text: AppFlowyEditorL10n.current.removeLink,
                onPressed: widget.onRemoveLink,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInput() {
    return Focus(
      onKeyEvent: (focus, key) {
        if (key is KeyDownEvent &&
            key.logicalKey == LogicalKeyboardKey.escape) {
          widget.onDismiss();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextSelectionTheme(
        data: TextSelectionThemeData(
          cursorColor: EditorTheme.of(context).primary,
          selectionColor: EditorTheme.of(context).selection,
          selectionHandleColor: EditorTheme.of(context).primary,
        ),
        child: TextFormField(
          style:
              TextStyle(fontSize: 12, color: EditorTheme.of(context).onSurface),
          cursorColor: EditorTheme.of(context).primary,
          contextMenuBuilder: EditorMenuTextField.buildContextMenu,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          focusNode: _focusNode,
          textAlign: TextAlign.left,
          controller: _textEditingController,
          onFieldSubmitted: widget.onSubmitted,
          decoration: EditorMenuTextField.inputDecoration(
            context,
            hintText: AppFlowyEditorL10n.current.urlHint,
            trailing: IconButton(
              padding: const EdgeInsets.all(4),
              color: EditorTheme.of(context).mutedForeground,
              hoverColor: EditorTheme.of(context).hover,
              icon: EditorSvg(
                name: 'clear',
                width: 18,
                height: 18,
                color: EditorTheme.of(context).mutedForeground,
              ),
              onPressed: _textEditingController.clear,
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty || !isUri(value)) {
              return AppFlowyEditorL10n.current.incorrectLink;
            }

            return null;
          },
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required String iconName,
    required String text,
    required VoidCallback onPressed,
  }) {
    return EditorMenuItem(
      leading: EditorSvg(
        name: iconName,
        color: EditorTheme.of(context).onSurface,
      ),
      onPressed: onPressed,
      child: Text(text),
    );
  }
}
