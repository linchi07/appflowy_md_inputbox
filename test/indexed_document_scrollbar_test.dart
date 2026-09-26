import 'package:appflowy_editor/src/editor/editor_component/entry/indexed_document_scrollbar.dart';
import 'package:appflowy_editor/src/flutter/scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('block extent index refines offsets with measured heights', () {
    final index = BlockExtentIndex(['a', 'b', 'c', 'd']);

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

  test('block extent index keeps heights with IDs after insert and reorder',
      () {
    final index = BlockExtentIndex(['a', 'b'])..record(0, 50);

    index.updateItems(['new', 'b', 'a', 'last']);
    expect(index.offsetOf(2), 56);
    expect(index.offsetOf(3), 106);
    expect(index.totalExtent, 134);

    index.updateItems(['b']);
    expect(index.totalExtent, 28);

    index.updateItems(['a', 'b']);
    expect(index.totalExtent, 56);
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
              itemIds: List<Object>.generate(500, (index) => 'block $index'),
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

  testWidgets('editing blocks above the viewport preserves its anchor',
      (tester) async {
    final itemController = ItemScrollController();
    final positions = ItemPositionsListener.create();
    var ids = List<Object>.generate(200, (index) => 'block $index');
    late StateSetter update;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return SizedBox(
              width: 400,
              height: 300,
              child: ScrollablePositionedList.builder(
                itemCount: ids.length,
                itemIds: ids,
                itemScrollController: itemController,
                itemPositionsListener: positions,
                itemBuilder: (_, index) => SizedBox(
                  height: 28,
                  child: Text(ids[index].toString()),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    itemController.jumpTo(index: 120);
    await tester.pumpAndSettle();

    final before = positions.itemPositions.value
        .where((position) => position.itemTrailingEdge > 0)
        .reduce((a, b) => a.index < b.index ? a : b);
    final anchorId = ids[before.index];
    update(() => ids = [for (var i = 0; i < 5; i++) 'inserted $i', ...ids]);
    await tester.pumpAndSettle();

    final after = positions.itemPositions.value
        .where((position) => position.itemTrailingEdge > 0)
        .reduce((a, b) => a.index < b.index ? a : b);
    expect(ids[after.index], anchorId);
    expect(after.itemLeadingEdge, closeTo(before.itemLeadingEdge, 0.01));

    update(() => ids = ids.sublist(5));
    await tester.pumpAndSettle();
    final restored = positions.itemPositions.value
        .where((position) => position.itemTrailingEdge > 0)
        .reduce((a, b) => a.index < b.index ? a : b);
    expect(ids[restored.index], anchorId);
    expect(restored.itemLeadingEdge, closeTo(before.itemLeadingEdge, 0.01));
  });

  testWidgets('virtual editor seeks through a large pasted document',
      (tester) async {
    final controller = MDEditorController.largeDocument();
    await tester.runAsync(
      () => controller.setText(
        List.generate(1200, (index) => 'paragraph $index').join('\n'),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MDEditor(
          controller: controller,
          shrinkWrap: false,
          maxHeight: 300,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final drag = await tester.startGesture(const Offset(792, 12));
    await drag.moveTo(const Offset(792, 285));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
