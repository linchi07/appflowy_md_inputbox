import 'dart:typed_data';
import 'package:appflowy_editor/appflowy_editor.dart';

/// The ordinary editor still supports web; shared Yrs documents require FFI.
class SharedEditorDocument {
  SharedEditorDocument({required Document document, String? documentId}) {
    _unsupported();
  }
  factory SharedEditorDocument.fromJson(Map<String, dynamic> json) =>
      _unsupported();
  factory SharedEditorDocument.fromUpdate({
    required String documentId,
    required Uint8List update,
    List<Uint8List> pendingUpdates = const [],
  }) => _unsupported();
  Never _get() => _unsupported();
  String get documentId => _get();
  String get rootId => _get();
  int get revision => _get();
  Document get snapshot => _get();
  Stream<SharedDocumentChange> get changes => _get();
  Node? nodeSnapshot(String nodeId) => _get();
  EditorState createEditorState({
    String? viewId,
    String? nodeId,
    bool editable = true,
    int maxHistoryItemSize = 200,
  }) => _get();
  Uint8List encodeUpdate([Uint8List? stateVector]) => _get();
  Uint8List stateVector() => _get();
  List<Uint8List> get pendingUpdates => _get();
  Map<String, dynamic> toJson() => _get();
  void applyChange(SharedDocumentChange change) => _get();
  void dispose() {}
}

Never _unsupported() => throw UnsupportedError(
  'SharedEditorDocument needs native yffi. Web needs a separate Yjs/Wasm backend.',
);
