import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('UUIDv7 identity survives JSON and view cloning but duplication is new',
      () {
    final node = paragraphNode(text: 'hello');
    final table = Node(type: 'group', children: [node]);
    expect(
        node.id,
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',),),);
    final restored = Node.fromJson(table.toJson());
    expect(restored.id, table.id);
    expect(restored.children.single.id, node.id);
    final view = table.cloneForView();
    expect(view.id, table.id);
    expect(view.children.single.id, node.id);
    expect(view.children.single.key, isNot(same(node.key)));
    final duplicate = table.deepCopy();
    expect(duplicate.id, isNot(table.id));
    expect(duplicate.children.single.id, isNot(node.id));
    final legacy = Node.fromJson({'type': 'paragraph'});
    expect(legacy.id, isNotEmpty);
  });

  test(
      'a paragraph reference synchronizes both ways with independent selections',
      () async {
    final shared = fixture();
    addTearDown(shared.dispose);
    final full = shared.createEditorState();
    final original = full.document.root.children[1];
    final zoom = full.createNodeView(original.id);
    expect(zoom.document.root.children.single.id, original.id);
    expect(zoom.document.root.children.single, isNot(same(original)));
    full.selection = Selection.collapsed(Position(path: [1], offset: 2));
    zoom.selection = Selection.collapsed(Position(path: [0], offset: 3));
    await zoom.apply(zoom.transaction
      ..insertText(zoom.document.root.children.single, 0, '中😀'),);
    expect(full.document.root.children[1].delta!.toPlainText(), '中😀focus');
    expect(full.selection!.start.offset, 5);
    expect(zoom.selection!.start.offset, 3);
    await full.apply(
        full.transaction..insertText(full.document.root.children[1], 8, '!'),);
    expect(
        zoom.document.root.children.single.delta!.toPlainText(), '中😀focus!',);
    zoom.dispose();
    await full.apply(
        full.transaction..insertText(full.document.root.children[1], 9, '?'),);
    expect(
        shared.nodeSnapshot(original.id)!.delta!.toPlainText(), '中😀focus!?',);
  });

  test('insertions and moves do not redirect a live reference', () async {
    final shared = fixture();
    addTearDown(shared.dispose);
    final full = shared.createEditorState();
    final id = full.document.root.children[1].id;
    final zoom = full.createNodeView(id);
    zoom.selection = Selection.collapsed(Position(path: [0], offset: 2));
    await full
        .apply(full.transaction..insertNode([0], paragraphNode(text: 'new')));
    await zoom.apply(zoom.transaction
      ..insertText(zoom.document.root.children.single, 0, 'X'),);
    expect(full.document.root.children[2].id, id);
    expect(full.document.root.children[2].delta!.toPlainText(), 'Xfocus');
    final node = full.document.root.children[2];
    await full.apply(full.transaction..moveNode([0], node));
    expect(full.document.root.children.first.id, id);
    expect(zoom.document.root.children.single.id, id);
    expect(zoom.selection!.start.path, [0]);
    await zoom.apply(zoom.transaction
      ..insertText(zoom.document.root.children.single, 6, 'Y'),);
    expect(full.document.root.children.first.delta!.toPlainText(), 'XfocusY');
  });

  test('table references include cell identities and structural updates',
      () async {
    final table = TableNode.fromList<String>([
      ['a', 'b'],
      ['c', 'd'],
    ]).node;
    final shared = SharedEditorDocument(
        document: Document(
            root: Node(
                type: 'page',
                children: [paragraphNode(text: 'before'), table],),),);
    addTearDown(shared.dispose);
    final full = shared.createEditorState();
    final zoom = full.createNodeView(table.id);
    final localTable = TableNode(node: zoom.document.root.children.single);
    final text = localTable.getCell(1, 0).children.single;
    await zoom.apply(zoom.transaction..insertText(text, 1, '!'));
    expect(
        TableNode(node: full.document.root.children[1])
            .getCell(1, 0)
            .children
            .single
            .delta!
            .toPlainText(),
        'c!',);
    await full.apply(full.transaction
      ..updateNode(full.document.root.children[1], {'rowDefaultHeight': 80.0}),);
    expect(zoom.document.root.children.single.attributes['rowDefaultHeight'],
        80.0,);
    final newText = paragraphNode(text: 'nested');
    final cell = zoom.document.root.children.single.children.first;
    await zoom.apply(zoom.transaction..insertNode([...cell.path, 1], newText));
    expect(full.document.root.children[1].children.first.children.length, 2);
    expect(zoom.document.root.children.single.children.first.children[1].id,
        full.document.root.children[1].children.first.children[1].id,);
  });

  test('read-only views receive updates, but cannot send edits', () async {
    final shared = fixture();
    addTearDown(shared.dispose);
    final full = shared.createEditorState();
    final readOnly = shared.createEditorState(
        nodeId: full.document.root.children[1].id, editable: false,);
    await full.apply(
        full.transaction..insertText(full.document.root.children[1], 0, 'A'),);
    expect(
        readOnly.document.root.children.single.delta!.toPlainText(), 'Afocus',);
    await readOnly.apply(readOnly.transaction
      ..insertText(readOnly.document.root.children.single, 0, 'B'),);
    expect(full.document.root.children[1].delta!.toPlainText(), 'Afocus');
  });

  test('deletion empties references and undo restores the original identity',
      () async {
    final shared = fixture();
    addTearDown(shared.dispose);
    final full = shared.createEditorState();
    final id = full.document.root.children[1].id;
    final zoom = full.createNodeView(id);
    await full
        .apply(full.transaction..deleteNode(full.document.root.children[1]));
    expect(zoom.isReferenceMissing, isTrue);
    full.undoManager.undo();
    expect(zoom.isReferenceMissing, isFalse);
    expect(zoom.document.root.children.single.id, id);
    full.undoManager.redo();
    expect(zoom.isReferenceMissing, isTrue);
  });

  test('undo belongs to its view and preserves later edits from another view',
      () async {
    final shared = fixture();
    addTearDown(shared.dispose);
    final full = shared.createEditorState();
    final zoom = full.createNodeView(full.document.root.children[1].id);
    var callbacks = 0;
    zoom.onInput = (_) => callbacks++;
    await zoom.apply(zoom.transaction
      ..insertText(zoom.document.root.children.single, 0, 'A'),);
    await full.apply(
        full.transaction..insertText(full.document.root.children[1], 0, 'B'),);
    zoom.undoManager.undo();
    expect(callbacks, 2);
    expect(full.document.root.children[1].delta!.toPlainText(), 'Bfocus');
    zoom.undoManager.redo();
    expect(callbacks, 3);
    expect(full.document.root.children[1].delta!.toPlainText(), 'BAfocus');
    full.undoManager.undo();
    expect(zoom.document.root.children.single.delta!.toPlainText(), 'Afocus');
  });

  test('multiple own undo steps remain valid through another view edit',
      () async {
    final shared = fixture();
    addTearDown(shared.dispose);
    final full = shared.createEditorState();
    final zoom = full.createNodeView(full.document.root.children[1].id);
    await zoom.apply(zoom.transaction
      ..insertText(zoom.document.root.children.single, 0, 'A'),);
    await zoom.apply(zoom.transaction
      ..insertText(zoom.document.root.children.single, 1, 'C'),);
    await full.apply(
        full.transaction..insertText(full.document.root.children[1], 2, 'B'),);
    zoom.undoManager.undo();
    expect(zoom.document.root.children.single.delta!.toPlainText(), 'ABfocus');
    zoom.undoManager.undo();
    expect(zoom.document.root.children.single.delta!.toPlainText(), 'Bfocus');
    zoom.undoManager.redo();
    zoom.undoManager.redo();
    expect(zoom.document.root.children.single.delta!.toPlainText(), 'ACBfocus');
  });

  test('references keep Enter inside the same paragraph', () async {
    final shared = fixture();
    addTearDown(shared.dispose);
    final full = shared.createEditorState();
    final zoom = full.createNodeView(full.document.root.children[1].id);
    zoom.selection = Selection.collapsed(Position(path: [0], offset: 2));
    await zoom.insertNewLine();
    expect(zoom.document.root.children.single.delta!.toPlainText(), 'fo\ncus');
    expect(full.document.root.children.length, 3);
    expect(full.document.root.children[1].id, zoom.referenceNodeId);
    expect(insertMarkdownNewLine(zoom), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(full.document.root.children.length, 3);
  });

  test('paste, append and replacement keep a paragraph reference alive',
      () async {
    final shared = fixture();
    addTearDown(shared.dispose);
    final full = shared.createEditorState();
    final id = full.document.root.children[1].id;
    final zoom = full.createNodeView(id);
    zoom.selection = Selection.collapsed(Position(path: [0], offset: 0));
    await zoom.pastePlainText('one\ntwo\n');
    await zoom.append('\nthree');
    expect(full.document.root.children[1].id, id);
    expect(full.document.root.children[1].delta!.toPlainText(),
        'one\ntwo\nfocus\nthree',);
    await zoom.setText('replacement\nparagraph');
    expect(full.document.root.children[1].id, id);
    expect(full.document.root.children[1].delta!.toPlainText(),
        'replacement\nparagraph',);
    expect(zoom.undoManager.canUndo, isFalse);
  });

  test('one-node Markdown promotion preserves the reference identity',
      () async {
    final shared = SharedEditorDocument(
        document: Document(
            root: Node(
                type: 'page', children: [paragraphNode(text: '```dart')],),),);
    addTearDown(shared.dispose);
    final full = shared.createEditorState();
    final id = full.document.root.children.single.id;
    final zoom = full.createNodeView(id);
    final controller = MDEditorController.fromEditorState(zoom);
    addTearDown(controller.dispose);
    zoom.selection = Selection.collapsed(Position(path: [0], offset: 7));
    await zoom.insertNewLine();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(full.document.root.children.single.id, id);
    expect(full.document.root.children.single.type, CodeBlockKeys.type);
    expect(zoom.document.root.children.single.type, CodeBlockKeys.type);
    await zoom.apply(zoom.transaction
      ..insertText(zoom.document.root.children.single, 0, 'print(1);'),);
    expect(
        full.document.root.children.single.delta!.toPlainText(), 'print(1);',);
  });

  test('structural undo cannot erase another view edit inside a new node',
      () async {
    final shared = fixture();
    addTearDown(shared.dispose);
    final full = shared.createEditorState();
    await full
        .apply(full.transaction..insertNode([0], paragraphNode(text: 'new')));
    final zoom = full.createNodeView(full.document.root.children.first.id);
    await zoom.apply(zoom.transaction
      ..insertText(zoom.document.root.children.single, 3, ' edited'),);
    expect(full.undoManager.canUndo, isFalse);
    full.undoManager.undo();
    expect(
        full.document.root.children.first.delta!.toPlainText(), 'new edited',);
  });

  test('invalid incoming operations are atomic and cannot bypass the host',
      () async {
    final shared = fixture();
    addTearDown(shared.dispose);
    final full = shared.createEditorState();
    final before = jsonEncode(shared.toJson());
    expect(
        () => shared.applyChange(SharedDocumentChange(
                documentId: shared.documentId,
                origin: 'external',
                baseRevision: shared.revision,
                operations: [
                  SharedOperation.text(full.document.root.children[1].id,
                      Delta()..insert('valid'),),
                  SharedOperation.text('missing', Delta()..insert('invalid')),
                ],),),
        throwsStateError,);
    expect(jsonEncode(shared.toJson()), before);
    await expectLater(
        full.apply(
            full.transaction
              ..insertText(full.document.root.children[1], 0, 'bypass'),
            isRemote: true,),
        throwsStateError,);
    expect(jsonEncode(shared.toJson()), before);
  });

  test('invalid or stale transactions cannot partially mutate shared content',
      () async {
    final shared = fixture();
    addTearDown(shared.dispose);
    final full = shared.createEditorState();
    final zoom = full.createNodeView(full.document.root.children[1].id);
    final stale = zoom.transaction
      ..insertText(zoom.document.root.children.single, 0, 'old');
    await full
        .apply(full.transaction..insertNode([0], paragraphNode(text: 'new')));
    await expectLater(zoom.apply(stale), throwsStateError);
    final before = jsonEncode(shared.toJson());
    final invalid = zoom.transaction
      ..insertText(zoom.document.root.children.single, 0, 'bad')
      ..insertNode([1], paragraphNode(text: 'hidden'));
    await expectLater(zoom.apply(invalid), throwsStateError);
    expect(jsonEncode(shared.toJson()), before);
    expect(zoom.document.root.children.single.delta!.toPlainText(), 'focus');
  });

  test(
      'ID change stream can be serialized and replayed by a sequenced consumer',
      () async {
    final source = fixture();
    final receiver = SharedEditorDocument.fromJson(source.toJson());
    addTearDown(source.dispose);
    addTearDown(receiver.dispose);
    final full = source.createEditorState();
    final mirror = receiver.createEditorState();
    final changeFuture = source.changes.first;
    await full.apply(full.transaction
      ..insertText(full.document.root.children[1], 0, 'sync'),);
    final change = await changeFuture;
    receiver.applyChange(SharedDocumentChange.fromJson(
        jsonDecode(jsonEncode(change.toJson())) as Map<String, dynamic>,),);
    expect(mirror.document.root.children[1].delta!.toPlainText(), 'syncfocus');
    expect(receiver.toJson(), source.toJson());
    expect(() => receiver.applyChange(change), throwsStateError);
  });

  testWidgets(
      'two mounted views have independent render keys and editing services',
      (tester) async {
    final shared = fixture();
    final full = shared.createEditorState();
    final zoom = full.createNodeView(full.document.root.children[1].id);
    final fullController = MDEditorController.fromEditorState(full);
    final zoomController = MDEditorController.fromEditorState(zoom);
    await tester.pumpWidget(MaterialApp(
        home: Row(children: [
      Expanded(
          child: MDEditor(
              controller: fullController, multiLine: true, shrinkWrap: false,),),
      Expanded(
          child: MDEditor(
              controller: zoomController, multiLine: true, shrinkWrap: false,),),
    ],),),);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await zoom.apply(zoom.transaction
      ..insertText(zoom.document.root.children.single, 0, 'live '),);
    await tester.pumpAndSettle();
    expect(full.document.root.children[1].delta!.toPlainText(), 'live focus');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    fullController.dispose();
    zoomController.dispose();
    shared.dispose();
  });
}

SharedEditorDocument fixture() => SharedEditorDocument(
        document: Document(
            root: Node(type: 'page', children: [
      paragraphNode(text: 'before'),
      paragraphNode(text: 'focus'),
      paragraphNode(text: 'after'),
    ],),),);
