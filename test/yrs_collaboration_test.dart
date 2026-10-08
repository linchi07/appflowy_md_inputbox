import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SharedEditorDocument fixture() => SharedEditorDocument(
    document: Document(
      root: pageNode(
        children: [
          paragraphNode(text: '中😀base'),
          TableNode.fromList([
            ['a', 'b'],
            ['c', 'd'],
          ]).node,
          codeBlockNode(code: 'value = 1;\n', language: 'dart'),
        ],
      ),
    ),
  );

  test(
    'independent replicas converge with reversed and duplicated updates',
    () async {
      final a = fixture();
      final b = SharedEditorDocument.fromUpdate(
        documentId: a.documentId,
        update: a.encodeUpdate(),
      );
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final va = a.createEditorState(viewId: 'a');
      final vb = b.createEditorState(viewId: 'b');
      final fromA = <SharedDocumentChange>[];
      final fromB = <SharedDocumentChange>[];
      final sa = a.changes.listen((update) {
        if (!update.isRemote) fromA.add(update);
      });
      final sb = b.changes.listen((update) {
        if (!update.isRemote) fromB.add(update);
      });
      addTearDown(sa.cancel);
      addTearDown(sb.cancel);
      await va.apply(
        va.transaction..insertText(va.document.root.children.first, 3, 'A'),
      );
      await va.apply(
        va.transaction..insertText(va.document.root.children.first, 4, 'C'),
      );
      await vb.apply(
        vb.transaction..insertText(vb.document.root.children.first, 3, 'B'),
      );
      await Future<void>.delayed(Duration.zero);
      for (final update in fromA.reversed) {
        b.applyChange(update);
        b.applyChange(update);
      }
      for (final update in fromB.reversed) {
        a.applyChange(update);
        a.applyChange(update);
      }
      expect(a.snapshot.toJson(), b.snapshot.toJson());
      expect(
        va.document.root.children.first.delta!.toPlainText(),
        contains('AC'),
      );
      va.undoManager.undo();
      va.undoManager.undo();
      expect(va.document.root.children.first.delta!.toPlainText(), '中😀Bbase');
      final vector = b.stateVector();
      b.applyChange(
        SharedDocumentChange(
          documentId: a.documentId,
          origin: 'a',
          update: a.encodeUpdate(vector),
        ),
      );
      expect(a.snapshot.toJson(), b.snapshot.toJson());
    },
  );

  test(
    'table row/column changes are atomic, rectangular and selective undo works',
    () async {
      final shared = fixture();
      addTearDown(shared.dispose);
      final full = shared.createEditorState();
      final reference = full.createNodeView(full.document.root.children[1].id);
      var changes = 0;
      final sub = shared.changes.listen((_) => changes++);
      addTearDown(sub.cancel);
      Node table() => reference.document.root.children.single;
      await TableActions.add(table(), 1, reference, TableDirection.row);
      await Future<void>.delayed(Duration.zero);
      expect(changes, 1);
      expect(TableNode(node: table()).rowsLen, 3);
      reference.undoManager.undo();
      expect(TableNode(node: table()).rowsLen, 2);
      TableActions.duplicate(table(), 0, reference, TableDirection.row);
      await Future<void>.delayed(Duration.zero);
      expect(TableNode(node: table()).rowsLen, 3);
      await TableActions.add(table(), 1, reference, TableDirection.col);
      expect(TableNode(node: table()).colsLen, 3);
      TableActions.delete(table(), 1, reference, TableDirection.col);
      await Future<void>.delayed(Duration.zero);
      expect(TableNode(node: table()).colsLen, 2);
      TableActions.delete(table(), 1, reference, TableDirection.row);
      await Future<void>.delayed(Duration.zero);
      expect(TableNode(node: table()).rowsLen, 2);
      TableActions.duplicate(table(), 0, reference, TableDirection.col);
      await Future<void>.delayed(Duration.zero);
      expect(TableNode(node: table()).colsLen, 3);
      final cell = TableNode(node: table()).getCell(0, 0).children.single;
      final id = cell.id;
      TableActions.clear(table(), 0, reference, TableDirection.row);
      await Future<void>.delayed(Duration.zero);
      expect(TableNode(node: table()).getCell(0, 0).children.single.id, id);
      expect(
        TableNode(
          node: table(),
        ).getCell(0, 0).children.single.delta!.toPlainText(),
        '',
      );
      expect(full.document.root.children[1].toJson(), table().toJson());
    },
  );

  test(
    'legacy flat table rejects corrupt concurrent structure without applying it',
    () async {
      final a = fixture();
      final b = SharedEditorDocument.fromUpdate(
        documentId: a.documentId,
        update: a.encodeUpdate(),
      );
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final va = a.createEditorState();
      final vb = b.createEditorState();
      final updateA = a.changes.first;
      final updateB = b.changes.first;
      await TableActions.add(
        va.document.root.children[1],
        1,
        va,
        TableDirection.row,
      );
      await TableActions.add(
        vb.document.root.children[1],
        1,
        vb,
        TableDirection.col,
      );
      final beforeA = a.snapshot.toJson();
      final beforeB = b.snapshot.toJson();
      final incomingA = await updateB;
      final incomingB = await updateA;
      expect(
        () => a.applyChange(incomingA),
        throwsA(isA<SharedTableMergeConflict>()),
      );
      expect(
        () => b.applyChange(incomingB),
        throwsA(isA<SharedTableMergeConflict>()),
      );
      expect(a.snapshot.toJson(), beforeA);
      expect(b.snapshot.toJson(), beforeB);
      // The packet is retained in the error; the application can resolve/retry.
      // Sequential structural updates still replicate normally.
      final c = SharedEditorDocument.fromUpdate(
        documentId: a.documentId,
        update: a.encodeUpdate(),
      );
      addTearDown(c.dispose);
      final update = a.changes.firstWhere((event) => !event.isRemote);
      await TableActions.add(
        va.document.root.children[1],
        0,
        va,
        TableDirection.col,
      );
      c.applyChange(await update);
      expect(c.snapshot.toJson(), a.snapshot.toJson());
    },
  );

  test(
    'concurrent table cell text and code body/meta merge across live references',
    () async {
      final a = fixture();
      final b = SharedEditorDocument.fromUpdate(
        documentId: a.documentId,
        update: a.encodeUpdate(),
      );
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final full = a.createEditorState(viewId: 'full');
      final table = full.createNodeView(full.document.root.children[1].id);
      final code = full.createNodeView(full.document.root.children[2].id);
      final peer = b.createEditorState(viewId: 'peer');
      final updatesA = <SharedDocumentChange>[];
      final updatesB = <SharedDocumentChange>[];
      final sa = a.changes.listen((e) {
        if (!e.isRemote) updatesA.add(e);
      });
      final sb = b.changes.listen((e) {
        if (!e.isRemote) updatesB.add(e);
      });
      addTearDown(sa.cancel);
      addTearDown(sb.cancel);
      final cellA = TableNode(
        node: table.document.root.children.single,
      ).getCell(1, 1).children.single;
      final cellB = TableNode(
        node: peer.document.root.children[1],
      ).getCell(1, 1).children.single;
      await table.apply(table.transaction..insertText(cellA, 0, 'A'));
      await peer.apply(peer.transaction..insertText(cellB, 0, 'B'));
      final codeA = code.document.root.children.single;
      final codeB = peer.document.root.children[2];
      await code.apply(code.transaction..insertText(codeA, 0, '// A\n'));
      await peer.apply(
        peer.transaction
          ..insertText(codeB, 0, '// B\n')
          ..updateNode(codeB, {
            CodeBlockKeys.language: 'python',
            CodeBlockKeys.openingFence: '```python',
          }),
      );
      await Future<void>.delayed(Duration.zero);
      for (final update in updatesB) {
        a.applyChange(update);
      }
      for (final update in updatesA.reversed) {
        b.applyChange(update);
      }
      expect(a.snapshot.toJson(), b.snapshot.toJson());
      expect(
        code.document.root.children.single.attributes[CodeBlockKeys.language],
        'python',
      );
      expect(
        code.document.root.children.single.delta!.toPlainText(),
        contains('// B\n'),
      );
      expect(
        insertParagraphAfterCode(code, code.document.root.children.single),
        isFalse,
      );
      code.undoManager.undo();
      expect(
        code.document.root.children.single.delta!.toPlainText(),
        '// B\nvalue = 1;\n',
      );
      expect(
        code.document.root.children.single.attributes[CodeBlockKeys.language],
        'python',
      );
    },
  );

  test(
    'measured table height is view state and does not publish Yrs updates',
    () async {
      final shared = fixture();
      addTearDown(shared.dispose);
      final full = shared.createEditorState();
      final table = full.document.root.children[1];
      final before = shared.encodeUpdate();
      await full.apply(
        full.transaction
          ..updateNode(table, {TableBlockKeys.colsHeight: 999.0})
          ..updateNode(table.children.first, {
            TableCellBlockKeys.height: 500.0,
          }),
      );
      expect(shared.encodeUpdate(), before);
      expect(full.undoManager.canUndo, isFalse);
    },
  );

  test(
    'concurrent subtree moves cannot silently form an invisible cycle',
    () async {
      final a = SharedEditorDocument(
        document: Document(
          root: pageNode(
            children: [
              Node(
                type: 'group',
                children: [paragraphNode(text: 'A')],
              ),
              Node(
                type: 'group',
                children: [paragraphNode(text: 'B')],
              ),
            ],
          ),
        ),
      );
      final b = SharedEditorDocument.fromUpdate(
        documentId: a.documentId,
        update: a.encodeUpdate(),
      );
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final va = a.createEditorState();
      final vb = b.createEditorState();
      final update = a.changes.first;
      await va.apply(
        va.transaction..moveNode([1, 0], va.document.root.children.first),
      );
      await vb.apply(
        vb.transaction..moveNode([0, 0], vb.document.root.children.last),
      );
      final before = b.snapshot.toJson();
      final incoming = await update;
      expect(
        () => b.applyChange(incoming),
        throwsA(isA<SharedStructureMergeConflict>()),
      );
      expect(b.snapshot.toJson(), before);
    },
  );
  test(
    'snapshots preserve native pending updates when dependencies arrive later',
    () async {
      final a = fixture();
      final b = SharedEditorDocument.fromUpdate(
        documentId: a.documentId,
        update: a.encodeUpdate(),
      );
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final va = a.createEditorState();
      final updates = <SharedDocumentChange>[];
      final sub = a.changes.listen(updates.add);
      addTearDown(sub.cancel);
      await va.apply(
        va.transaction..insertText(va.document.root.children.first, 0, 'A'),
      );
      await va.apply(
        va.transaction..insertText(va.document.root.children.first, 1, 'C'),
      );
      await Future<void>.delayed(Duration.zero);
      b.applyChange(updates.last);
      b.applyChange(updates.last);
      expect(b.pendingUpdates, hasLength(1));
      final c = SharedEditorDocument.fromJson(b.toJson());
      addTearDown(c.dispose);
      expect(c.pendingUpdates, hasLength(1));
      b.applyChange(updates.first);
      c.applyChange(updates.first);
      expect(b.pendingUpdates, isEmpty);
      expect(c.pendingUpdates, isEmpty);
      expect(c.snapshot.toJson(), a.snapshot.toJson());
      expect(b.snapshot.toJson(), a.snapshot.toJson());
    },
  );
}
