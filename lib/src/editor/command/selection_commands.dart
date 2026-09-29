import 'package:appflowy_editor/appflowy_editor.dart';

enum SelectionMoveRange {
  character,
  word,
  line,
  block,
}

enum SelectionMoveDirection {
  forward,
  backward,
}

extension SelectionTransform on EditorState {
  /// backward delete one character
  Future<bool> deleteBackward() async {
    final selection = this.selection;
    if (selection == null || !selection.isCollapsed) {
      return false;
    }
    final node = getNodeAtPath(selection.start.path);
    final delta = node?.delta;
    if (node == null || delta == null) {
      return false;
    }
    final transaction = this.transaction;
    final index = delta.prevRunePosition(selection.startIndex);
    transaction.deleteText(node, index, selection.startIndex - index);
    await apply(transaction);

    return true;
  }

  /// Deletes the selection.
  ///
  /// If the selection is collapsed, this function does nothing.
  ///
  /// If the node contains a delta, this function deletes the text in the selection,
  ///   else the node does not contain a delta, this function deletes the node.
  ///
  /// If both the first node and last node contain a delta,
  ///   this function merges the delta of the last node into the first node,
  ///   and deletes the nodes in between.
  ///
  /// If only the first node contains a delta,
  ///   this function deletes the text in the first node,
  ///   and deletes the nodes expect for the first node.
  ///
  /// For the other cases, this function just deletes all the nodes.
  Future<bool> deleteSelection(
    Selection selection, {
    List<String> ignoreNodeTypes = const [],
  }) async {
    bool isProtectedContainer(Node? node) =>
        node != null &&
        (ignoreNodeTypes.contains(node.type) || preventsMergeAtStart(node));
    // Nothing to do if the selection is collapsed.
    if (selection.isCollapsed) {
      return false;
    }

    // Normalize the selection so that it is never reversed or extended.
    selection = selection.normalized;

    // Start a new transaction.
    final transaction = this.transaction;

    // Get the nodes that are fully or partially selected.
    final nodes = getNodesInSelection(selection);

    // Structured atomic blocks are deleted as a single top-level range.
    final startPath = selection.start.path;
    final endPath = selection.end.path;
    if (startPath.length == 1 &&
        endPath.length == 1 &&
        startPath.first >= 0 &&
        endPath.first < document.root.children.length &&
        startPath.first < endPath.first &&
        document.root.children
            .skip(startPath.first)
            .take(endPath.first - startPath.first + 1)
            .any(isAtomicBlock)) {
      final first = document.root.children[startPath.first];
      final last = document.root.children[endPath.first];
      if (first.delta != null && last.delta != null) {
        transaction.mergeText(
          first,
          last,
          leftOffset: selection.startIndex,
          rightOffset: selection.endIndex,
        );
        transaction.deleteNodesAtPath(
          [startPath.first + 1],
          endPath.first - startPath.first,
        );
      } else if (first.delta != null) {
        transaction.deleteText(
          first,
          selection.startIndex,
          first.delta!.length - selection.startIndex,
        );
        transaction.deleteNodesAtPath(
          [startPath.first + 1],
          endPath.first - startPath.first,
        );
      } else if (last.delta != null) {
        transaction.deleteText(last, 0, selection.endIndex);
        transaction.deleteNodesAtPath(
          [startPath.first],
          endPath.first - startPath.first,
        );
      } else {
        transaction.deleteNodesAtPath(
          [startPath.first],
          endPath.first - startPath.first + 1,
        );
      }
      transaction.afterSelection = Selection.collapsed(
        Position(
          path: [startPath.first],
          offset: first.delta == null ? 0 : selection.startIndex,
        ),
      );
      await apply(transaction);
      return true;
    }

    // If only one node is selected, then we can just delete the selected text
    // or node.
    if (nodes.length == 1) {
      // Clear a protected container's text child without deleting its structure.
      final node = isProtectedContainer(nodes.first)
          ? nodes.first.children.first
          : nodes.first;
      if (node.delta != null) {
        transaction.deleteText(
          node,
          selection.startIndex,
          selection.length,
        );
      } else if (!isProtectedContainer(node.parent)) {
        transaction.deleteNode(node);
      }
    }

    // Otherwise, multiple nodes are selected, so we have to do more work.
    else if (nodes.first.delta != null &&
        nodes.last.delta != null &&
        nodes.every(
          (node) => node.parent == document.root && node.children.isEmpty,
        )) {
      // A plain top-level range can be deleted as one operation. Adding one
      // DeleteOperation per block transforms it against every earlier delete.
      transaction.mergeText(
        nodes.first,
        nodes.last,
        leftOffset: selection.startIndex,
        rightOffset: selection.endIndex,
      );
      transaction.deleteNodesAtPath(nodes[1].path, nodes.length - 1);
    } else {
      // The nodes are guaranteed to be in order, so we can determine which
      // nodes are at the beginning, middle, and end of the selection.
      assert(nodes.first.path < nodes.last.path);
      for (var i = 0; i < nodes.length; i++) {
        final node = nodes[i];

        // The first node is at the beginning of the selection.
        // All other nodes can be deleted.
        if (i != 0) {
          // Keep children of protected structured containers.
          if (isProtectedContainer(node.parent)) {
            if (!nodes.any((n) => n.id == node.parent?.parent?.id)) {
              transaction.deleteText(
                node,
                0,
                selection.end.offset,
              );
            }
          }
          // If the first node is in a protected container it cannot be merged.
          // node, So we should not delete the last node. Just delete part of
          // the text inside selection
          else if (node.id == nodes.last.id &&
              isProtectedContainer(nodes.first.parent)) {
            transaction.deleteText(
              node,
              0,
              selection.end.offset,
            );
          } else if (!isProtectedContainer(node)) {
            transaction.deleteNode(node);
          }
          continue;
        }

        // If the last node is also a text node and not a node inside table cell,
        // and also the current node isn't inside table cell, then we can merge
        // the text between the two nodes.
        if (nodes.last.delta != null &&
            ![node.parent, nodes.last.parent].any(isProtectedContainer)) {
          transaction.mergeText(
            node,
            nodes.last,
            leftOffset: selection.startIndex,
            rightOffset: selection.endIndex,
          );

          // combine the children of the last node into the first node.
          final last = nodes.last;

          if (last.children.isNotEmpty) {
            if (indentableBlockTypes.contains(node.type)) {
              transaction.insertNodes(
                node.path + [0],
                last.children,
                deepCopy: true,
              );
            } else {
              transaction.insertNodes(
                node.path.next,
                last.children,
                deepCopy: true,
              );
            }
          }
        }

        // Otherwise, we can just delete the selected text.
        else {
          // Keep the text boundary of a protected structured container.
          if (isProtectedContainer(nodes.last.parent) ||
              isProtectedContainer(node.parent)) {
            transaction.deleteText(
              node,
              selection.startIndex,
              node.delta!.length - selection.startIndex,
            );
          } else {
            transaction.deleteText(
              node,
              selection.startIndex,
              selection.length,
            );
          }
        }
      }
    }

    // After the selection is deleted, we want to move the selection to the
    // beginning of the deleted selection.
    transaction.afterSelection = selection.collapse(atStart: true);
    AppFlowyEditorLog.editor.debugLazy(
      () => transaction.operations.map((e) => e.toString()).toString(),
    );

    // Apply the transaction.
    await apply(transaction);

    return true;
  }

  /// move the cursor forward.
  ///
  /// Don't hardcode the logic here.
  /// For example,
  ///   final position = node.selectable?.moveForward(selection.startIndex);
  ///   if (position == null) { ... // move to the previous node}
  ///   else { ... // move to the position }
  void moveCursorForward([
    SelectionMoveRange range = SelectionMoveRange.character,
  ]) {
    moveCursor(SelectionMoveDirection.forward, range);
  }

  /// move the cursor backward.
  void moveCursorBackward(SelectionMoveRange range) {
    moveCursor(SelectionMoveDirection.backward, range);
  }

  void moveCursor(
    SelectionMoveDirection direction, [
    SelectionMoveRange range = SelectionMoveRange.character,
  ]) {
    final selection = this.selection?.normalized;
    if (selection == null) {
      return;
    }

    // If the selection is not collapsed, then we want to collapse the selection
    if (!selection.isCollapsed && range != SelectionMoveRange.line) {
      // move the cursor to the start or end of the selection
      this.selection = selection.collapse(
        atStart: direction == SelectionMoveDirection.forward,
      );

      return;
    }

    final node = getNodeAtPath(selection.start.path);
    if (node == null) {
      return;
    }

    // Originally, I want to make this function as pure as possible,
    //  but I have to import the selectable here to compute the selection.
    final start = node.selectable?.start();
    final end = node.selectable?.end();
    final offset = direction == SelectionMoveDirection.forward
        ? selection.startIndex
        : selection.endIndex;
    {
      // the cursor is at the start of the node
      // move the cursor to the end of the previous node
      if (direction == SelectionMoveDirection.forward &&
          start != null &&
          start.offset >= offset) {
        final previousEnd = node
            .previousNodeWhere((element) => element.selectable != null)
            ?.selectable
            ?.end();
        if (previousEnd != null) {
          updateSelectionWithReason(
            Selection.collapsed(previousEnd),
            reason: SelectionUpdateReason.uiEvent,
          );
        }

        return;
      }
      // the cursor is at the end of the node
      // move the cursor to the start of the next node
      else if (direction == SelectionMoveDirection.backward &&
          end != null &&
          end.offset <= offset) {
        final nextStart = node
            .nextNodeWhere((element) => element.selectable != null)
            ?.selectable
            ?.start();
        if (nextStart != null) {
          updateSelectionWithReason(
            Selection.collapsed(nextStart),
            reason: SelectionUpdateReason.uiEvent,
          );
        }

        return;
      }
    }

    final delta = node.delta;
    switch (range) {
      case SelectionMoveRange.character:
        if (delta != null) {
          // move the cursor to the left or right by one character
          updateSelectionWithReason(
            Selection.collapsed(
              selection.start.copyWith(
                offset: direction == SelectionMoveDirection.forward
                    ? delta.prevRunePosition(offset)
                    : delta.nextRunePosition(offset),
              ),
            ),
            reason: SelectionUpdateReason.uiEvent,
          );
        } else {
          throw UnimplementedError();
        }
        break;

      case SelectionMoveRange.word:
        final delta = node.delta;
        if (delta != null) {
          final position = direction == SelectionMoveDirection.forward
              ? Position(
                  path: node.path,
                  offset: delta.prevRunePosition(offset),
                )
              : selection.start;
          // move the cursor to the left or right by one line
          final wordSelection =
              node.selectable?.getWordBoundaryInPosition(position);
          if (wordSelection != null) {
            updateSelectionWithReason(
              Selection.collapsed(
                direction == SelectionMoveDirection.forward
                    ? wordSelection.start
                    : wordSelection.end,
              ),
              reason: SelectionUpdateReason.uiEvent,
            );
          }
        } else {
          throw UnimplementedError();
        }

        break;

      case SelectionMoveRange.line:
        if (delta != null) {
          // move the cursor to the left or right by one line
          updateSelectionWithReason(
            Selection.collapsed(
              selection.start.copyWith(
                offset: direction == SelectionMoveDirection.forward
                    ? 0
                    : delta.length,
              ),
            ),
            reason: SelectionUpdateReason.uiEvent,
          );
        } else {
          throw UnimplementedError();
        }
        break;

      default:
        throw UnimplementedError();
    }
  }
}
