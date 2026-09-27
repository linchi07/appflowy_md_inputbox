import 'package:flutter/material.dart';
import '../../../../appflowy_editor.dart';
import 'markdown_block_syntax.dart';
import 'package:node_code_editor/node_code_editor.dart';

bool _insertLiteralNewlineInFencedBlock(
  EditorState editorState,
  Node node,
  int offset,
) {
  final source = node.delta?.toPlainText();
  if (source == null || !shouldInsertNewlineInFencedBlock(source, offset)) {
    return false;
  }

  final transaction = editorState.transaction
    ..insertText(node, offset, '\n')
    ..afterSelection = Selection.collapsed(
      Position(path: node.path, offset: offset + 1),
    );
  editorState.apply(transaction);
  return true;
}

CommandShortcutEvent sendShortcutEvent({
  required VoidCallback onSend,
}) =>
    CommandShortcutEvent(
      key: 'send message',
      command: 'Enter',
      handler: (editorState) {
        onSend();

        return KeyEventResult.handled;
      },
      getDescription: () => 'Send the message',
    );

/// Continue a Markdown line. The IME path only calls this for Markdown syntax;
/// ordinary paragraphs keep using the editor's normal block-splitting logic.
bool insertMarkdownNewLine(
  EditorState editorState, {
  bool includePlainParagraph = true,
}) {
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) return false;

  final node = editorState.getNodeAtPath(selection.start.path);
  final delta = node?.delta;
  if (node == null || delta == null) return false;
  if (node.findParent((ancestor) => ancestor.type == TableBlockKeys.type) !=
      null) {
    return false;
  }

  final text = delta.toPlainText();
  final offset = selection.start.offset;
  if (node.type == CodeBlockKeys.type) {
    final edit = codeEditForInsertion(
      text,
      offset,
      '\n',
      node.attributes[CodeBlockKeys.language] as String? ?? '',
    );
    if (edit == null) return false;
    editorState.apply(
      editorState.transaction
        ..insertText(node, edit.offset, edit.text)
        ..afterSelection = Selection.collapsed(
          Position(
            path: node.path,
            offset: edit.caretOffset,
          ),
        ),
    );
    return true;
  }
  if (_insertLiteralNewlineInFencedBlock(editorState, node, offset)) {
    return true;
  }

  String nextPrefix = '';
  // 1: Checkbox, 2: Bullet, 3: Numbered, 4: Quote.
  final match =
      RegExp(r'^([-*]\s+\[[ x]]\s+)|^([-*]\s+)|^(\d+)\.\s+|^((>\s*)+)')
          .firstMatch(text);
  if (match == null && !includePlainParagraph) return false;

  if (match != null) {
    final prefix = match.group(0)!;
    if (text.trim() == prefix.trim() && offset <= prefix.length) {
      final transaction = editorState.transaction
        ..deleteText(node, 0, text.length)
        ..afterSelection = Selection.collapsed(
          Position(path: node.path, offset: 0),
        );
      editorState.apply(transaction);
      return true;
    }

    if (match.group(1) != null) {
      nextPrefix = '${match.group(1)!.substring(0, 2)}[ ] ';
    } else if (match.group(2) != null || match.group(4) != null) {
      nextPrefix = prefix;
    } else if (match.group(3) != null) {
      nextPrefix = '${int.parse(match.group(3)!) + 1}. ';
    }
  }

  // Split into a new node so Flutter does not inherit a multiline caret.
  final transaction = editorState.transaction;
  final nextPath = selection.start.path.next;
  final remainingText = delta.slice(offset);
  transaction.deleteText(node, offset, delta.length - offset);
  final newDelta = Delta()..insert(nextPrefix);
  for (final op in remainingText) {
    newDelta.add(op);
  }
  transaction.insertNode(nextPath, paragraphNode(delta: newDelta));
  transaction.afterSelection = Selection.collapsed(
    Position(path: nextPath, offset: nextPrefix.length),
  );
  editorState.apply(transaction);
  return true;
}

/// Shift+Enter creates a new line when Enter is reserved for sending.
final CommandShortcutEvent newlineMarkdownShortcutEvent = CommandShortcutEvent(
  key: 'shift+enter markdown continuation',
  command: 'shift+enter',
  handler: (editorState) => insertMarkdownNewLine(editorState)
      ? KeyEventResult.handled
      : KeyEventResult.ignored,
  getDescription: () => 'Continue a Markdown line',
);

/// Enter creates a new Markdown line in editors without a send shortcut.
final CommandShortcutEvent enterMarkdownShortcutEvent = CommandShortcutEvent(
  key: 'enter markdown continuation',
  command: 'Enter',
  handler: (editorState) => insertMarkdownNewLine(editorState)
      ? KeyEventResult.handled
      : KeyEventResult.ignored,
  getDescription: () => 'Continue a Markdown line',
);

/// —— Markdown Slash Menu ——

final CharacterShortcutEvent markdownSlashCommand = CharacterShortcutEvent(
  key: 'show the markdown slash menu',
  character: '/',
  handler: (editorState) async {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      return false;
    }

    // Insert the slash character first (SelectionMenu service will handle deleting it)
    await editorState.insertTextAtPosition('/', position: selection.start);

    // Show the slash menu
    final context = editorState.getNodeAtPath(selection.start.path)?.context;
    if (context != null && context.mounted) {
      final menuService = SelectionMenu(
        context: context,
        editorState: editorState,
        selectionMenuItems: markdownSelectionMenuItems,
        deleteSlashByDefault: true,
        singleColumn: true,
        menuHeight: 300,
        menuWidth: 240,
      );
      await menuService.show();
    }

    return true;
  },
);

void _insertMarkdown(
  EditorState editorState,
  String markdown, {
  int cursorOffset = 0,
}) {
  final selection = editorState.selection;
  if (selection == null) return;

  final node = editorState.getNodeAtPath(selection.start.path);
  if (node == null) return;

  final transaction = editorState.transaction;
  transaction.insertText(node, selection.start.offset, markdown);
  transaction.afterSelection = Selection.collapsed(
    Position(
      path: selection.start.path,
      offset: selection.start.offset + markdown.length + cursorOffset,
    ),
  );
  editorState.apply(transaction);
}

final List<SelectionMenuItem> markdownSelectionMenuItems = [
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.heading1,
    icon: (editorState, isSelected, style) => Icon(
      Icons.filter_1,
      size: 20,
      color: isSelected
          ? style.selectionMenuItemSelectedIconColor
          : style.selectionMenuItemIconColor,
    ),
    keywords: ['h1', 'heading'],
    handler: (editorState, _, __) => _insertMarkdown(editorState, '# '),
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.heading2,
    icon: (editorState, isSelected, style) => Icon(
      Icons.filter_2,
      size: 20,
      color: isSelected
          ? style.selectionMenuItemSelectedIconColor
          : style.selectionMenuItemIconColor,
    ),
    keywords: ['h2', 'heading'],
    handler: (editorState, _, __) => _insertMarkdown(editorState, '## '),
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.heading3,
    icon: (editorState, isSelected, style) => Icon(
      Icons.filter_3,
      size: 20,
      color: isSelected
          ? style.selectionMenuItemSelectedIconColor
          : style.selectionMenuItemIconColor,
    ),
    keywords: ['h3', 'heading'],
    handler: (editorState, _, __) => _insertMarkdown(editorState, '### '),
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.bulletedList,
    icon: (editorState, isSelected, style) => Icon(
      Icons.format_list_bulleted,
      size: 20,
      color: isSelected
          ? style.selectionMenuItemSelectedIconColor
          : style.selectionMenuItemIconColor,
    ),
    keywords: ['list', 'bullet'],
    handler: (editorState, _, __) => _insertMarkdown(editorState, '- '),
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.numberedList,
    icon: (editorState, isSelected, style) => Icon(
      Icons.format_list_numbered,
      size: 20,
      color: isSelected
          ? style.selectionMenuItemSelectedIconColor
          : style.selectionMenuItemIconColor,
    ),
    keywords: ['list', 'number'],
    handler: (editorState, _, __) => _insertMarkdown(editorState, '1. '),
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.checkbox,
    icon: (editorState, isSelected, style) => Icon(
      Icons.check_box_outlined,
      size: 20,
      color: isSelected
          ? style.selectionMenuItemSelectedIconColor
          : style.selectionMenuItemIconColor,
    ),
    keywords: ['todo', 'checkbox'],
    handler: (editorState, _, __) => _insertMarkdown(editorState, '- [ ] '),
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.quote,
    icon: (editorState, isSelected, style) => Icon(
      Icons.format_quote,
      size: 20,
      color: isSelected
          ? style.selectionMenuItemSelectedIconColor
          : style.selectionMenuItemIconColor,
    ),
    keywords: ['quote'],
    handler: (editorState, _, __) => _insertMarkdown(editorState, '> '),
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.embedCode,
    icon: (editorState, isSelected, style) => Icon(
      Icons.code,
      size: 20,
      color: isSelected
          ? style.selectionMenuItemSelectedIconColor
          : style.selectionMenuItemIconColor,
    ),
    keywords: ['code', 'block'],
    handler: (editorState, _, __) =>
        _insertMarkdown(editorState, '```\n\n```', cursorOffset: -4),
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.bold,
    icon: (editorState, isSelected, style) => Icon(
      Icons.format_bold,
      size: 20,
      color: isSelected
          ? style.selectionMenuItemSelectedIconColor
          : style.selectionMenuItemIconColor,
    ),
    keywords: ['bold'],
    handler: (editorState, _, __) =>
        _insertMarkdown(editorState, '****', cursorOffset: -2),
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.italic,
    icon: (editorState, isSelected, style) => Icon(
      Icons.format_italic,
      size: 20,
      color: isSelected
          ? style.selectionMenuItemSelectedIconColor
          : style.selectionMenuItemIconColor,
    ),
    keywords: ['italic'],
    handler: (editorState, _, __) =>
        _insertMarkdown(editorState, '**', cursorOffset: -1),
  ),
  SelectionMenuItem(
    getName: () => AppFlowyEditorL10n.current.divider,
    icon: (editorState, isSelected, style) => Icon(
      Icons.horizontal_rule,
      size: 20,
      color: isSelected
          ? style.selectionMenuItemSelectedIconColor
          : style.selectionMenuItemIconColor,
    ),
    keywords: ['divider', 'horizontal', 'rule', '---'],
    handler: (editorState, _, __) => _insertMarkdown(editorState, '---'),
  ),
];
