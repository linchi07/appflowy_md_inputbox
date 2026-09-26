import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/base_component/selection/selection_area_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('selection geometry updates are event-driven and coalesced',
      (tester) async {
    final editorState = EditorState.blank();
    final node = editorState.document.root.children.single;
    final key = GlobalKey<_SelectionHarnessState>();
    editorState.selection = Selection.single(path: [0], startOffset: 0);

    await tester.pumpWidget(
      MaterialApp(
        home: _SelectionHarness(
          key: key,
          editorState: editorState,
          node: node,
        ),
      ),
    );
    await tester.pump();
    final initialUpdates = key.currentState!.geometryUpdates;
    expect(initialUpdates, 1);

    // Manually produced idle frames must not restart geometry calculation.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(key.currentState!.geometryUpdates, initialUpdates);

    editorState.selection = Selection.single(path: [0], startOffset: 1);
    await tester.pump();
    expect(key.currentState!.geometryUpdates, initialUpdates + 1);

    node.updateAttributes({
      'delta': (Delta()..insert('updated')).toJson(),
    });
    await tester.pump();
    expect(key.currentState!.geometryUpdates, initialUpdates + 2);

    editorState.selection = Selection.single(path: [0], startOffset: 2);
    node.updateAttributes({
      'delta': (Delta()..insert('coalesced')).toJson(),
    });
    await tester.pump();
    expect(key.currentState!.geometryUpdates, initialUpdates + 3);

    await tester.pumpWidget(const SizedBox.shrink());
    editorState.dispose();
  });

  testWidgets('dragging keeps the previous selection painted until layout',
      (tester) async {
    final editorState = EditorState.blank();
    final node = editorState.document.root.children.single;
    editorState.selection =
        Selection.single(path: [0], startOffset: 0, endOffset: 2);
    await tester.pumpWidget(
      MaterialApp(
        home: _SelectionHarness(editorState: editorState, node: node),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SelectionAreaPaint), findsOneWidget);

    editorState.selection =
        Selection.single(path: [0], startOffset: 0, endOffset: 3);
    await tester.pump();
    expect(find.byType(SelectionAreaPaint), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    editorState.dispose();
  });
}

class _SelectionHarness extends StatefulWidget {
  const _SelectionHarness({
    super.key,
    required this.editorState,
    required this.node,
  });

  final EditorState editorState;
  final Node node;

  @override
  State<_SelectionHarness> createState() => _SelectionHarnessState();
}

class _SelectionHarnessState extends State<_SelectionHarness>
    with SelectableMixin<_SelectionHarness> {
  int geometryUpdates = 0;

  @override
  Widget build(BuildContext context) {
    return Provider.value(
      value: widget.editorState,
      child: SizedBox(
        width: 300,
        height: 100,
        child: Stack(
          children: [
            BlockSelectionArea(
              node: widget.node,
              delegate: this,
              listenable: widget.editorState.selectionNotifier,
              cursorColor: Colors.black,
              selectionColor: Colors.blue,
              blockColor: Colors.blue,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Rect getBlockRect({bool shiftWithBaseOffset = false}) =>
      const Rect.fromLTWH(0, 0, 300, 20);

  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    geometryUpdates++;
    return Rect.fromLTWH(position.offset.toDouble(), 0, 2, 20);
  }

  @override
  Position getPositionInOffset(Offset start) =>
      Position(path: widget.node.path, offset: start.dx.round());

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) =>
      const [Rect.fromLTWH(0, 0, 10, 20)];

  @override
  Selection getSelectionInRange(Offset start, Offset end) => Selection.single(
        path: widget.node.path,
        startOffset: start.dx.round(),
        endOffset: end.dx.round(),
      );

  @override
  Offset localToGlobal(
    Offset offset, {
    bool shiftWithBaseOffset = false,
  }) =>
      offset;

  @override
  Position start() => Position(path: widget.node.path, offset: 0);

  @override
  Position end() => Position(path: widget.node.path, offset: 7);
}
