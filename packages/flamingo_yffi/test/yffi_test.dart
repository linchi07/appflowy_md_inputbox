import 'dart:typed_data';
import 'package:flamingo_yffi/flamingo_yffi.dart';
import 'package:test/test.dart';

void main() {
  test(
    'official Yrs merges concurrent UTF16 text and native selective undo',
    () {
      final a = YDocument(clientId: 1);
      final b = YDocument(clientId: 2);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final ma = a.map('texts');
      final mb = b.map('texts');
      a.write('seed', (tx) {
        ma.set(tx, 'p', const YNewText());
        (ma.get(tx, 'p') as YText).applyDelta(tx, [
          {'insert': '中😀abc'},
        ]);
      });
      b.applyUpdate(a.encodeUpdate());
      a.takeUpdates();
      b.takeUpdates();
      a.takeChanges();
      b.takeChanges();
      final undo = a.undoManager('view-a', [ma]);
      final anchor = a.write(
        'binding:selection',
        (tx) => (ma.get(tx, 'p') as YText).anchor(tx, 3),
      );
      final end = a.write(
        'binding:selection',
        (tx) => (ma.get(tx, 'p') as YText).anchor(tx, 6),
      );
      expect(a.read((tx) => (ma.get(tx, 'p') as YText).resolve(tx, end)), 6);
      a.write(
        'view-a',
        (tx) => (ma.get(tx, 'p') as YText).applyDelta(tx, [
          {'retain': 3},
          {
            'insert': 'A',
            'attributes': {'bold': true},
          },
        ]),
      );
      b.write(
        'view-b',
        (tx) => (mb.get(tx, 'p') as YText).applyDelta(tx, [
          {'retain': 3},
          {'insert': 'B'},
        ]),
      );
      final updateA = a.takeUpdates().single;
      final updateB = b.takeUpdates().single;
      a.applyUpdate(updateB);
      b.applyUpdate(updateA);
      b.applyUpdate(updateA);
      expect(
        a.read((tx) => (ma.get(tx, 'p') as YText).delta(tx)),
        b.read((tx) => (mb.get(tx, 'p') as YText).delta(tx)),
      );
      expect(a.read((tx) => (ma.get(tx, 'p') as YText).resolve(tx, anchor)), 5);
      expect(undo.canUndo, isTrue);
      expect(undo.undo(), isTrue);
      final text = a
          .read((tx) => (ma.get(tx, 'p') as YText).delta(tx))
          .map((op) => op['insert'])
          .join();
      expect(text, '中😀Babc');
      expect(undo.redo(), isTrue);
      expect(a.takeChanges().where((e) => e.delta != null), isNotEmpty);
    },
  );

  test(
    'state vector diff, invalid updates and deterministic resource disposal',
    () {
      for (var i = 0; i < 20; i++) {
        final doc = YDocument();
        final map = doc.map('blocks');
        doc.write(
          'seed',
          (tx) => map.set(tx, 'props', {
            'int': 4,
            'bool': true,
            'list': [1, null],
          }),
        );
        expect(doc.read((tx) => map.get(tx, 'props')), {
          'int': 4,
          'bool': true,
          'list': [1, null],
        });
        expect(doc.encodeUpdate(doc.stateVector()), [0, 0]);
        expect(
          () => doc.applyUpdate(Uint8List.fromList([255])),
          throwsFormatException,
        );
        expect(() => doc.applyUpdate(Uint8List(0)), throwsFormatException);
        expect(
          () => doc.encodeUpdate(Uint8List.fromList([255])),
          throwsFormatException,
        );
        final undo = doc.undoManager('view', [map]);
        undo.dispose();
        undo.dispose();
        doc.dispose();
        doc.dispose();
        expect(() => doc.read((tx) {}), throwsStateError);
      }
    },
  );
}
