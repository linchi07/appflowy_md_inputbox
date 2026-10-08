import 'package:appflowy_editor/src/editor/l10n/appflowy_editor_l10n.dart';
import 'package:appflowy_editor/src/editor_state.dart';
import 'package:flutter/material.dart';

import '../internal_key_event_handlers/copy_paste_handler.dart';
import 'context_menu.dart';

Widget defaultContextMenuBuilder(
  BuildContext context,
  Offset position,
  EditorState editorState,
  VoidCallback onPressed,
) =>
    ContextMenu(
      position: position,
      editorState: editorState,
      items: standardContextMenuItems,
      onPressed: onPressed,
    );

final standardContextMenuItems = [
  [
    // cut
    ContextMenuItem(
      getName: () => AppFlowyEditorL10n.current.cut,
      icon: Icons.content_cut,
      isApplicable: (state) =>
          state.editable && state.selection?.isCollapsed == false,
      onPressed: (editorState) {
        handleCut(editorState);
      },
    ),
    // copy
    ContextMenuItem(
      getName: () => AppFlowyEditorL10n.current.copy,
      icon: Icons.content_copy,
      isApplicable: (state) => state.selection?.isCollapsed == false,
      onPressed: (editorState) {
        handleCopy(editorState);
      },
    ),
    // Paste
    ContextMenuItem(
      getName: () => AppFlowyEditorL10n.current.paste,
      icon: Icons.content_paste,
      isApplicable: (state) => state.editable,
      onPressed: (editorState) {
        handlePaste(editorState);
      },
    ),
  ],
];
