import 'package:appflowy_editor/appflowy_editor.dart';

final _listTypes = <String>[];

extension EditorCopyPaste on EditorState {
  /// Keep registered widget-node boundaries when pasting into text.
  Future<void> pasteNodesPreservingBoundaries(List<Node> nodes) async {
    final selection = await deleteSelectionIfNeeded();
    if (selection == null) return;
    final original = getNodeAtPath(selection.start.path);
    final delta = original?.delta;
    if (original == null || delta == null) return;

    final prefix = delta.slice(0, selection.startIndex);
    final suffix = delta.slice(selection.endIndex);
    if (prefix.isNotEmpty) {
      if (behaviorFor(nodes.first)?.isolateOnPaste == true ||
          nodes.first.delta == null) {
        nodes.insert(0, paragraphNode(delta: prefix));
      } else {
        nodes.first.insertDelta(prefix, insertAfter: false);
      }
    }
    final pastedLastIndex = nodes.length - 1;
    var caretOffset = nodes.last.delta?.length ?? 0;
    if (suffix.isNotEmpty) {
      if (behaviorFor(nodes.last)?.isolateOnPaste == true ||
          nodes.last.delta == null) {
        nodes.add(paragraphNode(delta: suffix));
      } else {
        nodes.last.insertDelta(suffix);
      }
    }
    if (original.children.isNotEmpty &&
        behaviorFor(nodes.last)?.isolateOnPaste == true) {
      nodes.add(paragraphNode());
    }
    for (final child in original.children) {
      nodes.last.insert(child);
    }
    final insertedPath = selection.start.path;
    final transaction = this.transaction
      ..insertNodes(insertedPath, nodes)
      ..deleteNode(original)
      ..afterSelection = Selection.collapsed(
        Position(
          path: [
            ...insertedPath.sublist(0, insertedPath.length - 1),
            insertedPath.last + pastedLastIndex,
          ],
          offset: caretOffset,
        ),
      );
    await apply(transaction);
  }

  Future<void> pasteSingleLineNode(Node insertedNode) async {
    final selection = await deleteSelectionIfNeeded();
    if (selection == null) {
      return;
    }
    final node = getNodeAtPath(selection.start.path);
    final delta = node?.delta;
    if (node == null || delta == null) {
      return;
    }
    final transaction = this.transaction;
    final insertedDelta = insertedNode.delta;
    // if the node is empty paragraph (default), replace it with the inserted node.
    if (delta.isEmpty && node.type == ParagraphBlockKeys.type) {
      final List<Node> combinedChildren = [
        ...insertedNode.children.map((e) => e.deepCopy()),
        // if the original node has children, copy them to the inserted node.
        ...node.children.map((e) => e.deepCopy()),
      ];
      insertedNode = insertedNode.copyWith(children: combinedChildren);
      transaction.insertNode(selection.end.path, insertedNode);
      transaction.deleteNode(node);
      transaction.afterSelection = Selection.collapsed(
        Position(
          path: selection.end.path,
          offset: insertedDelta?.length ?? 0,
        ),
      );
    } else if (insertedDelta != null) {
      // if the node is not empty, insert the delta from inserted node after the selection.
      transaction.insertTextDelta(node, selection.endIndex, insertedDelta);
      if (_listTypes.contains(node.type) && insertedNode.children.isNotEmpty) {
        transaction.insertNodes(node.path + [0], insertedNode.children);
      }
    }
    await apply(transaction);
  }

  Future<void> pasteMultiLineNodes(List<Node> nodes) async {
    assert(nodes.length > 1);

    final selection = await deleteSelectionIfNeeded();
    if (selection == null) {
      return;
    }
    final node = getNodeAtPath(selection.start.path);
    final delta = node?.delta;
    if (node == null || delta == null) {
      return;
    }

    final transaction = this.transaction;

    // check if the first node is a non-delta node,
    //  if so, insert the nodes after the current selection.
    final startWithNonDeltaBlock = nodes.first.delta == null;
    if (startWithNonDeltaBlock) {
      transaction.insertNodes(node.path.next, nodes);
      await apply(transaction);

      return;
    }

    final lastNodeLength = calculateLength(nodes);
    // merge the current selected node delta into the nodes.
    if (delta.isNotEmpty) {
      final firstNode = nodes.first;
      if (firstNode.delta != null) {
        nodes.first.insertDelta(
          delta.slice(0, selection.startIndex),
          insertAfter: false,
        );
      }

      final lastNode = nodes.last;
      if (lastNode.delta != null) {
        nodes.last.insertDelta(
          delta.slice(selection.endIndex),
          insertAfter: true,
        );
      }
    }

    if (delta.isEmpty && node.type != ParagraphBlockKeys.type) {
      nodes[0] = nodes.first.copyWith(
        type: node.type,
        attributes: {
          ...node.attributes,
          ...nodes.first.attributes,
        },
      );
    }

    for (final child in node.children) {
      nodes.last.insert(child);
    }

    transaction.insertNodes(selection.end.path, nodes);

    // delete the current node.
    transaction.deleteNode(node);

    final path = calculatePath(selection.start.path, nodes);
    transaction.afterSelection = Selection.collapsed(
      Position(
        path: path,
        offset: lastNodeLength,
      ),
    );

    await apply(transaction);
  }

  // delete the selection if it's not collapsed.
  Future<Selection?> deleteSelectionIfNeeded() async {
    final selection = this.selection;
    if (selection == null) {
      return null;
    }

    // delete the selection first.
    if (!selection.isCollapsed) {
      deleteSelection(selection);
    }

    // fetch selection again.selection = editorState.selection;
    assert(this.selection?.isCollapsed == true);

    return this.selection;
  }

  Path calculatePath(Path start, List<Node> nodes) {
    var path = start;
    for (var i = 0; i < nodes.length; i++) {
      path = path.next;
    }
    path = path.previous;
    if (nodes.last.children.isNotEmpty) {
      return [
        ...path,
        ...calculatePath([0], nodes.last.children.toList()),
      ];
    }

    return path;
  }

  int calculateLength(List<Node> nodes) {
    if (nodes.last.children.isNotEmpty) {
      return calculateLength(nodes.last.children.toList());
    }

    return nodes.last.delta?.length ?? 0;
  }
}

extension on Node {
  void insertDelta(Delta delta, {bool insertAfter = true}) {
    assert(delta.every((element) => element is TextInsert));
    if (this.delta == null) {
      updateAttributes({
        blockComponentDelta: delta.toJson(),
      });
    } else if (insertAfter) {
      updateAttributes(
        {
          blockComponentDelta: this
              .delta!
              .compose(
                Delta()
                  ..retain(this.delta!.length)
                  ..addAll(delta),
              )
              .toJson(),
        },
      );
    } else {
      updateAttributes(
        {
          blockComponentDelta: delta
              .compose(
                Delta()
                  ..retain(delta.length)
                  ..addAll(this.delta!),
              )
              .toJson(),
        },
      );
    }
  }
}
