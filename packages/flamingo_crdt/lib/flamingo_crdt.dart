import 'dart:typed_data';

/// Implemented by the application runtime; this contract has no native ABI.
/// The application owns the supplied document and disposes it after bindings.
abstract interface class CrdtDocument {
  CrdtMap map(String name);
  T read<T>(T Function(CrdtTransaction) action);
  T write<T>(String origin, T Function(CrdtTransaction) action);
  Uint8List stateVector();
  Uint8List encodeUpdate([Uint8List? stateVector]);
  void applyUpdate(Uint8List update);

  /// Reject adapter-specific values before a non-rollback write transaction.
  void validateValue(Object? value);
  List<Uint8List> get pendingPackets;
  List<Uint8List> takeUpdates();
  List<CrdtChange> takeChanges();
  CrdtUndoManager undoManager(String origin, Iterable<CrdtMap> scopes);
  void dispose();
}

/// Creates an isolated validation replica. Its caller releases that replica.
typedef CrdtDocumentFactory = CrdtDocument Function();

abstract interface class CrdtTransaction {}

abstract interface class CrdtMap {
  dynamic get(CrdtTransaction tx, String key);
  void set(CrdtTransaction tx, String key, Object? value);
  void remove(CrdtTransaction tx, String key);
  Map<String, dynamic> entries(CrdtTransaction tx);
}

abstract interface class CrdtArray {
  List<dynamic> values(CrdtTransaction tx);
  void insert(CrdtTransaction tx, int index, String value);
  void remove(CrdtTransaction tx, int index);
}

abstract interface class CrdtText {
  List<Map<String, dynamic>> delta(CrdtTransaction tx);
  void applyDelta(CrdtTransaction tx, List<Map<String, dynamic>> delta);
  Uint8List anchor(CrdtTransaction tx, int offset, {int assoc = 0});
  int? resolve(CrdtTransaction tx, Uint8List anchor);
}

abstract interface class CrdtUndoManager {
  bool get canUndo;
  bool get canRedo;
  int get undoLength;
  void clear();
  bool undo();
  bool redo();
  void dispose();
}

/// Owned Dart values, copied by the application adapter from engine events.
class CrdtChange {
  CrdtChange(this.root, this.path, {this.delta, this.keys});
  final String root;
  final List<Object> path;
  final List<Map<String, dynamic>>? delta;
  final Map<String, dynamic>? keys;
}

/// Preliminary shared types to integrate once into a map.
class CrdtNewMap {
  const CrdtNewMap();
}

class CrdtNewArray {
  const CrdtNewArray();
}

class CrdtNewText {
  const CrdtNewText();
}
