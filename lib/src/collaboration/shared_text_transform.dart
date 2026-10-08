import 'package:appflowy_editor/appflowy_editor.dart';

/// Rebase local undo text against a later, already committed text delta.
Delta transformSharedDelta(
  Delta pending,
  Delta applied, {
  bool appliedHasPriority = true,
}) {
  final left = _Cursor(applied);
  final right = _Cursor(pending);
  final result = Delta();
  while (right.hasNext) {
    if (left.operation is TextInsert &&
        (appliedHasPriority || right.operation is! TextInsert)) {
      result.retain(left.remaining);
      left.consume(left.remaining);
    } else if (right.operation is TextInsert) {
      final insert = right.operation as TextInsert;
      result.insert(
        insert.text.substring(right.offset),
        attributes: insert.attributes,
      );
      right.consume(right.remaining);
    } else {
      final length =
          left.remaining < right.remaining ? left.remaining : right.remaining;
      if (left.operation is! TextDelete) {
        if (right.operation is TextDelete) {
          result.delete(length);
        } else {
          final attributes = right.operation?.attributes;
          if (appliedHasPriority) {
            for (final key in left.operation?.attributes?.keys ?? <String>[]) {
              attributes?.remove(key);
            }
          }
          result.retain(length, attributes: attributes);
        }
      }
      left.consume(length);
      right.consume(length);
    }
  }
  return result..chop();
}

int transformSharedOffset(int offset, Delta applied) {
  var position = 0;
  var result = offset;
  for (final operation in applied) {
    if (operation is TextInsert) {
      if (position <= offset) result += operation.length;
    } else if (operation is TextDelete) {
      if (position < offset) {
        result -= (offset - position).clamp(0, operation.length);
      }
      position += operation.length;
    } else {
      position += operation.length;
    }
  }
  return result;
}

class _Cursor {
  _Cursor(Delta delta) : operations = delta.toList();
  final List<TextOperation> operations;
  int index = 0;
  int offset = 0;
  bool get hasNext => index < operations.length;
  TextOperation? get operation => hasNext ? operations[index] : null;
  int get remaining => hasNext ? operation!.length - offset : 0x7fffffff;
  void consume(int length) {
    if (!hasNext) return;
    offset += length;
    if (offset == operation!.length) {
      index++;
      offset = 0;
    }
  }
}
