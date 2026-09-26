import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('debug messages are evaluated only when fine logging is enabled', () {
    final configuration = AppFlowyLogConfiguration();
    final oldLevel = configuration.level;
    var evaluations = 0;
    try {
      configuration.level = AppFlowyEditorLogLevel.off;
      AppFlowyEditorLog.editor.debugLazy(() {
        evaluations++;
        return 'large operation';
      });
      expect(evaluations, 0);

      configuration.level = AppFlowyEditorLogLevel.debug;
      AppFlowyEditorLog.editor.debugLazy(() {
        evaluations++;
        return 'large operation';
      });
      expect(evaluations, 1);
    } finally {
      configuration.level = oldLevel;
    }
  });

  test('transactional text length matches serialization', () async {
    final counter = ValueNotifier<int>(0);
    final controller = MDEditorController(characterCounter: counter);
    final state = controller.editorState;
    final first = state.document.root.children.single;

    await state.apply(state.transaction..insertText(first, 0, 'hello'));
    expect(state.textLength, 5);
    expect(counter.value, 5);

    final insert = state.transaction;
    insert.insertNodes(
      const [1],
      [
        paragraphNode(text: 'world'),
        dividerNode(),
      ],
    );
    await state.apply(insert);
    expect(state.textLength, state.text.length);
    expect(counter.value, state.textLength);

    await state.apply(state.transaction..deleteNodesAtPath(const [1]));
    expect(state.textLength, state.text.length);
    expect(counter.value, state.textLength);

    final remaining = state.document.root.children.first;
    await state.apply(state.transaction..deleteText(remaining, 0, 2));
    expect(state.textLength, state.text.length);
    expect(counter.value, state.textLength);

    controller.dispose();
    counter.dispose();
  });

  test('nested table edits update serialized text length', () async {
    final table = TableNode.fromList([
      ['A', '1'],
      ['B', '2'],
    ]);
    final state = EditorState(
      document: Document(root: pageNode(children: [table.node])),
    );
    final cellText = table.node.children.first.children.first;
    final originalLength = state.textLength;

    await state.apply(state.transaction..insertText(cellText, 1, '!'));
    expect(state.textLength, originalLength + 1);
    expect(state.textLength, state.text.length);
    state.dispose();
  });
}
