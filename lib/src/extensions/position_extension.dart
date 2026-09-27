import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

enum SelectionRange {
  character,
  word,
}

extension PositionExtension on Position {
  Position? moveHorizontal(
    EditorState editorState, {
    bool forward = true,
    SelectionRange selectionRange = SelectionRange.character,
  }) {
    final node = editorState.document.nodeAtPath(path);
    if (node == null) {
      return null;
    }

    if (forward && offset == 0) {
      final previousEnd = node.previous?.selectable?.end();
      if (previousEnd != null) {
        return previousEnd;
      }

      return null;
    } else if (!forward) {
      final end = node.selectable?.end();
      if (end != null && offset >= end.offset) {
        return node.next?.selectable?.start();
      }
    }

    switch (selectionRange) {
      case SelectionRange.character:
        final delta = node.delta;
        if (delta != null) {
          return Position(
            path: path,
            offset: forward
                ? delta.prevRunePosition(offset)
                : delta.nextRunePosition(offset),
          );
        }

        return Position(path: path, offset: offset);

      case SelectionRange.word:
        final delta = node.delta;
        if (delta != null) {
          final result = forward
              ? node.selectable?.getWordBoundaryInPosition(
                  Position(
                    path: path,
                    offset: delta.prevRunePosition(offset),
                  ),
                )
              : node.selectable?.getWordBoundaryInPosition(this);
          if (result != null) {
            return forward ? result.start : result.end;
          }
        }

        return Position(path: path, offset: offset);
    }
  }

  Position? moveVertical(
    EditorState editorState, {
    bool upwards = true,
  }) {
    final node = editorState.document.nodeAtPath(path);
    final nodeSelectable = node?.selectable;
    if (node == null || nodeSelectable == null) {
      return this;
    }

    final editorSelection = editorState.selection;
    final rects = editorState.selectionRects();
    if (rects.isEmpty || editorSelection == null) {
      return null;
    }

    final caretRect = rects.last;
    final x = caretRect.center.dx;

    // Hit-test the adjacent visual line directly. A one-pixel scan through a
    // tall block costs O(block height) and can land on another character in
    // the same line, particularly with mixed font sizes and line spacing.
    for (final distance in [1.0, caretRect.height / 2 + 1.0]) {
      final y =
          upwards ? caretRect.top - distance : caretRect.bottom + distance;
      final candidate = nodeSelectable.getPositionInOffset(Offset(x, y));
      if (candidate == this) {
        continue;
      }
      final localRect = nodeSelectable.getCursorRectInPosition(
        candidate,
        shiftWithBaseOffset: true,
      );
      if (localRect == null) {
        continue;
      }
      final candidateRect = nodeSelectable.transformRectToGlobal(
        localRect,
        shiftWithBaseOffset: true,
      );
      if (upwards
          ? candidateRect.center.dy < caretRect.center.dy - 1
          : candidateRect.center.dy > caretRect.center.dy + 1) {
        return candidate;
      }
    }

    final neighbour = upwards
        ? node.previousNodeWhere(
            (candidate) =>
                editorState.renderer.blockComponentSelectable(candidate.type) !=
                null,
          )
        : node.nextNodeWhere(
            (candidate) =>
                editorState.renderer.blockComponentSelectable(candidate.type) !=
                null,
          );
    if (neighbour != null) {
      final selectable = neighbour.selectable;
      if (selectable != null) {
        final edge = upwards ? selectable.end() : selectable.start();
        final localRect = selectable.getCursorRectInPosition(
          edge,
          shiftWithBaseOffset: true,
        );
        if (localRect != null) {
          final edgeRect = selectable.transformRectToGlobal(
            localRect,
            shiftWithBaseOffset: true,
          );
          return selectable.getPositionInOffset(
            Offset(x, edgeRect.center.dy),
          );
        }
        return edge;
      }
      return Position(
        path: neighbour.path,
        offset: upwards ? neighbour.delta?.length ?? 0 : 0,
      );
    }

    final delta = node.delta;
    if (delta != null) {
      if (upwards) {
        return Position(path: path, offset: 0);
      } else {
        final length = delta.length;
        // move the cursor to the end of the node
        return Position(path: path, offset: length);
      }
    }

    // The cursor is already at the top or bottom of the document.
    return this;
  }
}
