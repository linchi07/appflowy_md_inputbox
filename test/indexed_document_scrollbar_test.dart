import 'package:appflowy_editor/src/editor/editor_component/entry/indexed_document_scrollbar.dart';
import 'package:appflowy_editor/src/flutter/scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('block extent index refines offsets with measured heights', () {
    final index = BlockExtentIndex(4);

    expect(index.totalExtent, 112);
    expect(index.indexAtOffset(27), 0);
    expect(index.indexAtOffset(28), 1);

    index.record(0, 20);
    index.record(1, 40);

    expect(index.totalExtent, 116);
    expect(index.offsetOf(1), 20);
    expect(index.offsetOf(2), 60);
    expect(index.indexAtOffset(19), 0);
    expect(index.indexAtOffset(20), 1);
    expect(index.indexAtOffset(59), 1);
    expect(index.indexAtOffset(60), 2);
  });

  test('block extent index preserves measurements when resized', () {
    final index = BlockExtentIndex(2)..record(0, 50);

    index.resize(4);
    expect(index.offsetOf(1), 50);
    expect(index.totalExtent, 134);

    index.resize(1);
    expect(index.totalExtent, 50);
  });

  testWidgets('thumb drag seeks directly to a distant item', (tester) async {
    final itemController = ItemScrollController();
    final positions = ItemPositionsListener.create();

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 300,
            child: IndexedDocumentScrollbar(
              itemCount: 500,
              itemScrollController: itemController,
              itemPositionsListener: positions,
              child: ScrollablePositionedList.builder(
                itemCount: 500,
                itemScrollController: itemController,
                itemPositionsListener: positions,
                itemBuilder: (_, index) => SizedBox(
                  height: 28,
                  child: Text('block $index'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(392, 12));
    await gesture.moveTo(const Offset(392, 285));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      positions.itemPositions.value.any((position) => position.index > 400),
      isTrue,
    );
  });
}
