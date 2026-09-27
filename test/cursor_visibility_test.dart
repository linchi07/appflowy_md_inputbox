import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> mountEditor(
    WidgetTester tester,
    EditorState state, {
    EditorStyle? style,
    bool shrinkWrap = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 120,
            child: AppFlowyEditor(
              editorState: state,
              editorStyle:
                  style ?? EditorStyle.desktop(padding: EdgeInsets.zero),
              disableKeyboardService: true,
              shrinkWrap: shrinkWrap,
            ),
          ),
        ),
      ),
    );
  }

  void expectCaretInViewport(EditorState state) {
    final caret = state.selectionRects().single;
    final scrollable = state.scrollableState!;
    final box = scrollable.context.findRenderObject()! as RenderBox;
    final viewport = box.localToGlobal(Offset.zero) & box.size;
    expect(caret.top, greaterThanOrEqualTo(viewport.top - 0.1));
    expect(caret.bottom, lessThanOrEqualTo(viewport.bottom + 0.1));
  }

  testWidgets('caret follows edits within a block taller than the viewport',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final text = List.generate(60, (index) => 'line $index').join('\n');
    final state = EditorState(
      document: Document(root: pageNode(children: [paragraphNode(text: text)])),
    );
    await mountEditor(tester, state);

    state.updateSelectionWithReason(
      Selection.collapsed(Position(path: [0], offset: text.length)),
      reason: SelectionUpdateReason.uiEvent,
    );
    await tester.pump();
    await tester.pump();
    expectCaretInViewport(state);

    final node = state.document.root.children.single;
    await state.apply(
      state.transaction
        ..insertText(node, text.length, '\nextra')
        ..afterSelection = Selection.collapsed(
          Position(path: [0], offset: text.length + 6),
        ),
    );
    await tester.pump();
    await tester.pump();
    expectCaretInViewport(state);

    state.updateSelectionWithReason(
      Selection.collapsed(Position(path: [0], offset: 0)),
      reason: SelectionUpdateReason.uiEvent,
    );
    await tester.pump();
    await tester.pump();
    expectCaretInViewport(state);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('selection in an unlaid block is brought into the viewport',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final state = EditorState(
      document: Document(
        root: pageNode(
          children: List.generate(
            80,
            (index) => paragraphNode(text: 'paragraph $index'),
          ),
        ),
      ),
    );
    await mountEditor(tester, state);

    state.updateSelectionWithReason(
      Selection.collapsed(Position(path: [70], offset: 4)),
      reason: SelectionUpdateReason.uiEvent,
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expectCaretInViewport(state);

    state.updateSelectionWithReason(
      Selection.collapsed(Position(path: [3], offset: 4)),
      reason: SelectionUpdateReason.uiEvent,
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expectCaretInViewport(state);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('vertical movement targets visual lines and adjacent blocks',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final state = EditorState(
      document: Document(
        root: pageNode(
          children: [
            paragraphNode(text: 'abc\ndef\nghi'),
            paragraphNode(text: 'jkl'),
          ],
        ),
      ),
    );
    await mountEditor(tester, state);

    state.selection = Selection.collapsed(Position(path: [0], offset: 1));
    await tester.pump();
    final next = state.selection!.end.moveVertical(state, upwards: false);
    expect(next?.path, [0]);
    expect(next?.offset, inInclusiveRange(4, 7));

    state.selection = Selection.collapsed(Position(path: [0], offset: 9));
    await tester.pump();
    expect(state.selection!.end.moveVertical(state, upwards: false)?.path, [1]);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('mobile caret is revealed after the keyboard delay',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final text = List.generate(40, (index) => 'line $index').join('\n');
    final state = EditorState(
      document: Document(root: pageNode(children: [paragraphNode(text: text)])),
    );
    await mountEditor(
      tester,
      state,
      style: EditorStyle.mobile(padding: EdgeInsets.zero),
    );

    state.updateSelectionWithReason(
      Selection.collapsed(Position(path: [0], offset: text.length)),
      reason: SelectionUpdateReason.uiEvent,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expectCaretInViewport(state);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shrink-wrapped editor also reveals the final caret',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final text = List.generate(40, (index) => 'line $index').join('\n');
    final state = EditorState(
      document: Document(root: pageNode(children: [paragraphNode(text: text)])),
    );
    await mountEditor(tester, state, shrinkWrap: true);

    state.updateSelectionWithReason(
      Selection.collapsed(Position(path: [0], offset: text.length)),
      reason: SelectionUpdateReason.uiEvent,
    );
    await tester.pump();
    await tester.pump();
    expectCaretInViewport(state);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
