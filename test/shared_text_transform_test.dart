import 'dart:math';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/collaboration/shared_text_transform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rebased text edits converge across inserts, deletions and replacements',
      () {
    final random = Random(42);
    final base = Delta()..insert('abcdef');
    Delta edit() {
      final start = random.nextInt(7);
      final deleted = random.nextInt(7 - start);
      final inserted = List.generate(
        random.nextInt(4),
        (_) => String.fromCharCode(65 + random.nextInt(26)),
      ).join();
      return Delta()
        ..retain(start)
        ..delete(deleted)
        ..insert(inserted)
        ..chop();
    }

    for (var i = 0; i < 300; i++) {
      final pending = edit();
      final applied = edit();
      final left =
          base.compose(applied).compose(transformSharedDelta(pending, applied));
      final right = base.compose(pending).compose(
        transformSharedDelta(applied, pending, appliedHasPriority: false),
      );
      expect(
        left,
        right,
        reason: 'pending=${pending.toJson()}, applied=${applied.toJson()}',
      );
    }
  });

  test('formatting conflicts preserve the already committed style', () {
    final base = Delta()..insert('abcdef');
    final pending = Delta()
      ..retain(6, attributes: {'bold': false, 'italic': true});
    final applied = Delta()..retain(3, attributes: {'bold': true});
    final left =
        base.compose(applied).compose(transformSharedDelta(pending, applied));
    final right = base.compose(pending).compose(
      transformSharedDelta(applied, pending, appliedHasPriority: false),
    );
    expect(left, right);
    expect(left.first.attributes, {'bold': true, 'italic': true});
  });
}
