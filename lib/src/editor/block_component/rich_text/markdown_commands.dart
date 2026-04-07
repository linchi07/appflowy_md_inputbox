import 'package:flutter/material.dart';
import '../../../../appflowy_editor.dart';
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

/// When hit shift + enter , create a new line
final CommandShortcutEvent newlineMarkdownShortcutEvent = CommandShortcutEvent(
  key: 'enter markdown continuation',
  command: 'shift+enter',
  handler: (editorState) {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      return KeyEventResult.ignored;
    }

    final node = editorState.getNodeAtPath(selection.start.path);
    final delta = node?.delta;
    if (node == null || delta == null) {
      return KeyEventResult.ignored;
    }

    final text = delta.toPlainText();
    final offset = selection.start.offset;

    // We will determine if the new line needs any prefix
    String nextPrefix = '';

    // Check for Lists/Quotes/Checkboxes Regex:
    // 1: Checkbox, 2: Bullet, 3: Numbered, 4: Quote
    final match =
    RegExp(r'^([-*]\s+\[[ x]]\s+)|^([-*]\s+)|^(\d+)\.\s+|^((>\s*)+)')
        .firstMatch(text);
    if (match != null) {
      final fullMatchStr = match.group(0)!;

      // Termination Check: if line is ONLY the prefix and we are at the end of it
      if (text.trim() == fullMatchStr.trim() && offset <= fullMatchStr.length) {
        final transaction = editorState.transaction;
        transaction.deleteText(node, 0, text.length);
        editorState.apply(transaction);
        return KeyEventResult.handled;
      }

      // Continuation Logic:
      if (match.group(1) != null) {
        // Checkbox: convert current (x or space) to empty [ ]
        final prefix = match.group(1)!;
        nextPrefix = '${prefix.substring(0, 2)}[ ] ';
      } else if (match.group(2) != null || match.group(4) != null) {
        // Unordered list or Quote
        nextPrefix = fullMatchStr;
      } else if (match.group(3) != null) {
        // Ordered list
        int currentNum = int.parse(match.group(3)!);
        nextPrefix = '${currentNum + 1}. ';
      }
    }

    // Perform manual split to guarantee a clean new Node.
    // This prevents the "tall caret" bug caused by Flutter's multiline inheritance.
    final transaction = editorState.transaction;
    final nextPath = selection.start.path.next;

    // Text after cursor moves to new node
    final remainingText = delta.slice(offset);

    // Remove remaining text from current node
    transaction.deleteText(node, offset, delta.length - offset);

    // Create new node with prefix + remaining text
    final newDelta = Delta()..insert(nextPrefix);
    for (final op in remainingText) {
      newDelta.add(op);
    }

    final newNode = paragraphNode(delta: newDelta);
    transaction.insertNode(nextPath, newNode);

    // SET CARET POSITION: right after the prefix
    transaction.afterSelection = Selection.collapsed(
      Position(path: nextPath, offset: nextPrefix.length),
    );

    editorState.apply(transaction);
    return KeyEventResult.handled;
  },
  getDescription: () =>
  'Continues list/quote or terminates it with correct caret placement',
);


/// When hit enter , create a new line
/// CANNOT BE USED WITH SEND SHORTCUT (USE NEWLINE INSTEAD)
final CommandShortcutEvent enterMarkdownShortcutEvent = CommandShortcutEvent(
  key: 'enter markdown continuation',
  command: 'Enter',
  handler: (editorState) {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      return KeyEventResult.ignored;
    }

    final node = editorState.getNodeAtPath(selection.start.path);
    final delta = node?.delta;
    if (node == null || delta == null) {
      return KeyEventResult.ignored;
    }

    final text = delta.toPlainText();
    final offset = selection.start.offset;

    // We will determine if the new line needs any prefix
    String nextPrefix = '';

    // Check for Lists/Quotes/Checkboxes Regex:
    // 1: Checkbox, 2: Bullet, 3: Numbered, 4: Quote
    final match =
        RegExp(r'^([-*]\s+\[[ x]]\s+)|^([-*]\s+)|^(\d+)\.\s+|^((>\s*)+)')
            .firstMatch(text);
    if (match != null) {
      final fullMatchStr = match.group(0)!;

      // Termination Check: if line is ONLY the prefix and we are at the end of it
      if (text.trim() == fullMatchStr.trim() && offset <= fullMatchStr.length) {
        final transaction = editorState.transaction;
        transaction.deleteText(node, 0, text.length);
        editorState.apply(transaction);
        return KeyEventResult.handled;
      }

      // Continuation Logic:
      if (match.group(1) != null) {
        // Checkbox: convert current (x or space) to empty [ ]
        final prefix = match.group(1)!;
        nextPrefix = '${prefix.substring(0, 2)}[ ] ';
      } else if (match.group(2) != null || match.group(4) != null) {
        // Unordered list or Quote
        nextPrefix = fullMatchStr;
      } else if (match.group(3) != null) {
        // Ordered list
        int currentNum = int.parse(match.group(3)!);
        nextPrefix = '${currentNum + 1}. ';
      }
    }

    // Perform manual split to guarantee a clean new Node.
    // This prevents the "tall caret" bug caused by Flutter's multiline inheritance.
    final transaction = editorState.transaction;
    final nextPath = selection.start.path.next;

    // Text after cursor moves to new node
    final remainingText = delta.slice(offset);

    // Remove remaining text from current node
    transaction.deleteText(node, offset, delta.length - offset);

    // Create new node with prefix + remaining text
    final newDelta = Delta()..insert(nextPrefix);
    for (final op in remainingText) {
      newDelta.add(op);
    }

    final newNode = paragraphNode(delta: newDelta);
    transaction.insertNode(nextPath, newNode);

    // SET CARET POSITION: right after the prefix
    transaction.afterSelection = Selection.collapsed(
      Position(path: nextPath, offset: nextPrefix.length),
    );

    editorState.apply(transaction);
    return KeyEventResult.handled;
  },
  getDescription: () =>
      'Continues list/quote or terminates it with correct caret placement',
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
    getName: () => 'Heading 1',
    icon: (editorState, isSelected, style) => Icon(
      Icons.filter_1,
      size: 20,
      color:  Colors.black,
    ),
    keywords: ['h1', 'heading'],
    handler: (editorState, _, __) => _insertMarkdown(editorState, '# '),
  ),
  SelectionMenuItem(
    getName: () => 'Heading 2',
    icon: (editorState, isSelected, style) => Icon(
      Icons.filter_2,
      size: 20,
      color:  Colors.black,
    ),
    keywords: ['h2', 'heading'],
    handler: (editorState, _, __) => _insertMarkdown(editorState, '## '),
  ),
  SelectionMenuItem(
    getName: () => 'Heading 3',
    icon: (editorState, isSelected, style) => Icon(
      Icons.filter_3,
      size: 20,
      color:  Colors.black,
    ),
    keywords: ['h3', 'heading'],
    handler: (editorState, _, __) => _insertMarkdown(editorState, '### '),
  ),
  SelectionMenuItem(
    getName: () => 'Bulleted List',
    icon: (editorState, isSelected, style) => Icon(
      Icons.format_list_bulleted,
      size: 20,
      color:  Colors.black,
    ),
    keywords: ['list', 'bullet'],
    handler: (editorState, _, __) => _insertMarkdown(editorState, '- '),
  ),
  SelectionMenuItem(
    getName: () => 'Numbered List',
    icon: (editorState, isSelected, style) => Icon(
      Icons.format_list_numbered,
      size: 20,
      color:  Colors.black,
    ),
    keywords: ['list', 'number'],
    handler: (editorState, _, __) => _insertMarkdown(editorState, '1. '),
  ),
  SelectionMenuItem(
    getName: () => 'Checkbox',
    icon: (editorState, isSelected, style) => Icon(
      Icons.check_box_outlined,
      size: 20,
      color:  Colors.black,
    ),
    keywords: ['todo', 'checkbox'],
    handler: (editorState, _, __) => _insertMarkdown(editorState, '- [ ] '),
  ),
  SelectionMenuItem(
    getName: () => 'Quote',
    icon: (editorState, isSelected, style) => Icon(
      Icons.format_quote,
      size: 20,
      color:  Colors.black,
    ),
    keywords: ['quote'],
    handler: (editorState, _, __) => _insertMarkdown(editorState, '> '),
  ),
  SelectionMenuItem(
    getName: () => 'Code Block',
    icon: (editorState, isSelected, style) => Icon(
      Icons.code,
      size: 20,
      color:  Colors.black,
    ),
    keywords: ['code', 'block'],
    handler: (editorState, _, __) =>
        _insertMarkdown(editorState, '```\n\n```', cursorOffset: -4),
  ),
  SelectionMenuItem(
    getName: () => 'Bold',
    icon: (editorState, isSelected, style) => Icon(
      Icons.format_bold,
      size: 20,
      color:  Colors.black,
    ),
    keywords: ['bold'],
    handler: (editorState, _, __) =>
        _insertMarkdown(editorState, '****', cursorOffset: -2),
  ),
  SelectionMenuItem(
    getName: () => 'Italic',
    icon: (editorState, isSelected, style) => Icon(
      Icons.format_italic,
      size: 20,
      color:  Colors.black,
    ),
    keywords: ['italic'],
    handler: (editorState, _, __) =>
        _insertMarkdown(editorState, '**', cursorOffset: -1),
  ),
  SelectionMenuItem(
    getName: () => 'Divider',
    icon: (editorState, isSelected, style) => Icon(
      Icons.horizontal_rule,
      size: 20,
      color:  Colors.black,
    ),
    keywords: ['divider', 'horizontal', 'rule', '---'],
    handler: (editorState, _, __) => _insertMarkdown(editorState, '---'),
  ),
];
