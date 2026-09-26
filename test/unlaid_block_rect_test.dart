import 'package:appflowy_editor/src/editor/block_component/rich_text/default_selectable_mixin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SelectableBlock with DefaultSelectableMixin {
  _SelectableBlock(this.containerKey, this.blockComponentKey);

  @override
  final GlobalKey containerKey;

  @override
  final GlobalKey blockComponentKey;

  @override
  GlobalKey get forwardKey => blockComponentKey;
}

void main() {
  testWidgets('reading a block rect before layout returns no geometry',
      (tester) async {
    final containerKey = GlobalKey();
    final blockKey = GlobalKey();
    final selectable = _SelectableBlock(containerKey, blockKey);
    Rect? beforeLayout;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          key: containerKey,
          children: [
            SizedBox(key: blockKey, width: 40, height: 20),
            Builder(
              builder: (_) {
                beforeLayout = selectable.getBlockRect();
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );

    expect(beforeLayout, Rect.zero);
    expect(selectable.getBlockRect(), isNot(Rect.zero));
    expect(tester.takeException(), isNull);
  });
}
