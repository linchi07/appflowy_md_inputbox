import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import 'crdt_document_binding.dart';

/// Independent editor projections bound to an application-owned CRDT document.
/// The application owns sessions, windows, persistence and update transport.
class SharedEditorDocument {
  SharedEditorDocument({
    required Document document,
    String? documentId,
    required CrdtDocument crdtDocument,
    required CrdtDocumentFactory createReplica,
  })  : documentId = documentId ?? document.root.id,
        _backend = CrdtDocumentBinding(crdtDocument),
        _createReplica = createReplica {
    _indexNodes(document.root);
    _backend.initialize(document, this.documentId);
    _document = _backend.snapshot();
    validateTables(_document.root);
    _index = _indexNodes(_document.root);
  }

  SharedEditorDocument._restore(
    this.documentId,
    Uint8List update,
    List<Uint8List> pending,
    CrdtDocument crdtDocument,
    CrdtDocumentFactory createReplica,
  )   : _backend = CrdtDocumentBinding(crdtDocument),
        _createReplica = createReplica {
    _backend.store.applyUpdate(update);
    for (final packet in pending) {
      _backend.store.applyUpdate(packet);
    }
    _backend.validateIdentity(documentId);
    _document = _backend.snapshot();
    validateTables(_document.root);
    _index = _indexNodes(_document.root);
    _backend.drain();
  }

  /// Peers must share CRDT history, not independently import the same JSON/MD.
  /// The supplied runtime document remains owned by the application.
  factory SharedEditorDocument.fromUpdate({
    required String documentId,
    required Uint8List update,
    List<Uint8List> pendingUpdates = const [],
    required CrdtDocument crdtDocument,
    required CrdtDocumentFactory createReplica,
  }) =>
      SharedEditorDocument._restore(
        documentId,
        update,
        pendingUpdates,
        crdtDocument,
        createReplica,
      );

  factory SharedEditorDocument.fromJson(
    Map<String, dynamic> json, {
    required CrdtDocument crdtDocument,
    required CrdtDocumentFactory createReplica,
  }) {
    if (json['crdtState'] case final String state) {
      return SharedEditorDocument.fromUpdate(
        documentId: json['documentId'] as String,
        crdtDocument: crdtDocument,
        createReplica: createReplica,
        update: base64Decode(state),
        pendingUpdates: (json['crdtPendingUpdates'] as List? ?? const [])
            .map((packet) => base64Decode(packet as String))
            .toList(),
      );
    }
    final document = Document.fromJson(json);
    try {
      return SharedEditorDocument(
        document: document,
        documentId: json['documentId'] as String?,
        crdtDocument: crdtDocument,
        createReplica: createReplica,
      );
    } finally {
      document.dispose();
    }
  }

  final String documentId;
  final CrdtDocumentBinding _backend;
  final CrdtDocumentFactory _createReplica;
  CrdtDocumentBinding? _validator;
  late Document _document;
  late Map<String, Node> _index;
  final Map<EditorState, _View> _views = {};
  final StreamController<SharedDocumentChange> _changes =
      StreamController.broadcast();
  int _revision = 0;
  bool _closed = false;
  bool _committing = false;

  /// Local projection version, used only to reject stale editor path commands.
  int get revision => _revision;
  String get rootId => _document.root.id;
  Stream<SharedDocumentChange> get changes => _changes.stream;
  Document get snapshot => Document(root: _document.root.cloneForView());
  Node? nodeSnapshot(String nodeId) => _index[nodeId]?.cloneForView();
  Uint8List stateVector() {
    _checkOpen();
    return _backend.store.stateVector();
  }

  Uint8List encodeUpdate([Uint8List? stateVector]) {
    _checkOpen();
    return _backend.store.encodeUpdate(stateVector);
  }

  List<Uint8List> get pendingUpdates {
    _checkOpen();
    return _backend.store.pendingPackets;
  }

  Map<String, dynamic> toJson() => {
        ..._document.toJson(),
        'documentId': documentId,
        'crdtState': base64Encode(encodeUpdate()),
        if (pendingUpdates.isNotEmpty)
          'crdtPendingUpdates': pendingUpdates.map(base64Encode).toList(),
      };

  EditorState createEditorState({
    String? viewId,
    String? nodeId,
    bool editable = true,
    int maxHistoryItemSize = 200,
  }) {
    _checkOpen();
    if (viewId != null &&
        (viewId.isEmpty ||
            _views.values.any((view) => view.viewId == viewId))) {
      throw ArgumentError.value(
        viewId,
        'viewId',
        'View identity must be unique.',
      );
    }
    if (maxHistoryItemSize < 1) {
      throw ArgumentError.value(maxHistoryItemSize, 'maxHistoryItemSize');
    }
    if (nodeId == rootId) nodeId = null;
    if (nodeId != null && !_index.containsKey(nodeId)) {
      throw ArgumentError.value(nodeId, 'nodeId', 'Unknown node');
    }
    final view = _View(this, nodeId, maxHistoryItemSize, viewId: viewId);
    final state = EditorState(
      document: _projection(nodeId),
      transactionHost: view,
      maxHistoryItemSize: maxHistoryItemSize,
    )..editable = editable;
    view.state = state;
    view.reindex();
    _views[state] = view;
    return state;
  }

  Document _projection(String? nodeId) => nodeId == null
      ? snapshot
      : Document(
          root: Node(
            type: 'page',
            children: [
              if (_index[nodeId] case final node?) node.cloneForView(),
            ],
          ),
        );

  void _checkOpen() {
    if (_closed) throw StateError('The shared document is disposed.');
    if (_committing) {
      throw StateError('A document commit is already in progress.');
    }
  }

  Future<void> _apply(
    _View view,
    Transaction transaction,
    ApplyOptions options,
    bool withUpdateSelection,
  ) {
    _checkOpen();
    if (!identical(transaction.document, view.state.document)) {
      throw ArgumentError('Foreign editor transaction');
    }
    if (transaction.baseRevision != null &&
        transaction.baseRevision != revision) {
      throw StateError('Stale transaction: rebuild it from the current view.');
    }
    final operations = _prepare(view, transaction);
    if (operations.isEmpty) {
      if (withUpdateSelection) {
        view.state.selection = transaction.afterSelection;
      }
      return Future.value();
    }
    _validateBatch(operations);
    final userEdit = options.resolvedSource == TransactionSource.userEdit;
    final origin = userEdit ? view.viewId : 'binding:programmatic';
    // The runtime contract exposes whole-stack clear, so bound retained history
    // by clearing at the configured session limit.
    if (userEdit && (!view.undoGroupActive || !view.undoGroupHasEdit)) {
      view.undoScope.stopCapturing();
      if (view.undoScope.canUndo && view.undoLength >= view.historyLimit) {
        view.undoScope.clear();
      }
    }
    _commit(
      () {
        _backend.apply(operations, origin);
        // Mark before publication: callbacks may edit within the same session.
        if (userEdit && view.undoGroupActive) view.undoGroupHasEdit = true;
      },
      origin: view.viewId,
      source: view,
      transaction: transaction,
      options: options,
      withUpdateSelection: withUpdateSelection,
    );
    return Future.value();
  }

  void applyChange(SharedDocumentChange change) {
    _checkOpen();
    if (change.documentId != documentId) {
      throw ArgumentError('Foreign document update');
    }
    {
      // Keep a lazy validation replica. Catch domain-invalid merges before the
      // authoritative document changes; subsequent typing needs only a diff.
      final trial = _validator ??= _validationReplica();
      try {
        trial.store.applyUpdate(encodeUpdate(trial.store.stateVector()));
        for (final packet in pendingUpdates) {
          trial.store.applyUpdate(packet);
        }
        trial.drain();
        trial.store.applyUpdate(change.update);
        trial.validateIdentity(documentId);
        final events = trial.store.takeChanges();
        if (events.any((event) => event.delta == null)) {
          final candidate = trial.snapshot();
          try {
            validateTables(candidate.root);
          } finally {
            candidate.dispose();
          }
        }
        trial.drain();
      } on InvalidTableShape catch (error) {
        trial.dispose();
        _validator = null;
        throw SharedTableMergeConflict(error.tableId, change);
      } on InvalidHierarchy catch (error) {
        trial.dispose();
        _validator = null;
        throw SharedStructureMergeConflict(error.nodeIds, change);
      } catch (_) {
        trial.dispose();
        _validator = null;
        rethrow;
      }
    }
    _commit(
      () => _backend.store.applyUpdate(change.update),
      origin: change.origin,
      isRemote: true,
    );
  }

  CrdtDocumentBinding _validationReplica() {
    final runtime = _createReplica();
    if (identical(runtime, _backend.store)) {
      throw ArgumentError(
        'The replica factory must return an isolated CRDT document.',
      );
    }
    return CrdtDocumentBinding(runtime);
  }

  void _commit(
    void Function() write, {
    required String origin,
    bool isRemote = false,
    _View? source,
    Transaction? transaction,
    ApplyOptions options = const ApplyOptions(source: TransactionSource.none),
    bool withUpdateSelection = true,
  }) {
    final selections = {
      for (final view in _views.values) view: view.captureSelection(),
    };
    _committing = true;
    List<Uint8List> updates = const [];
    var structureChanged = false;
    try {
      if (source != null && transaction != null) {
        source.state.publishSharedTransaction(
          TransactionTime.before,
          transaction,
          options,
        );
      }
      write();
      final events = _backend.store.takeChanges();
      structureChanged = events.any(
        (event) =>
            _isStructuralChange(event) ||
            (_isAttributeChange(event) &&
                event.keys!.keys.any(
                  {
                    TableBlockKeys.colsLen,
                    TableBlockKeys.rowsLen,
                    TableCellBlockKeys.colPosition,
                    TableCellBlockKeys.rowPosition,
                  }.contains,
                )),
      );
      updates = _backend.store.takeUpdates();
      if (events.isNotEmpty) {
        final structural = events.any(_isStructuralChange);
        final operations = <SharedOperation>[];
        if (structural) {
          final previous = _document;
          _document = _backend.snapshot();
          _index = _indexNodes(_document.root);
          previous.dispose();
        } else {
          for (final event in events) {
            final id = event.path.first as String;
            final node = _index[id];
            if (node == null) continue;
            if (event.delta case final delta?) {
              final edit = Delta.fromJson(delta);
              node.updateAttributes({
                'delta': node.delta!.compose(edit).toJson(),
              });
              operations.add(SharedOperation.text(id, edit));
            } else if (event.keys case final keys?) {
              node.updateAttributes(keys);
              operations.add(SharedOperation.update(id, keys));
            }
          }
        }
        _revision++;
        for (final view in _views.values.toList()) {
          final projection = structural
              ? _buildProjection(
                  view.state.document,
                  _projection(view.referenceNodeId),
                )
              : _textProjection(view, operations);
          view.state.applySharedProjection(projection);
          if (structural) view.reindex();
          if (identical(view, source) &&
              withUpdateSelection &&
              transaction != null) {
            final after = transaction.afterSelection;
            view.state.updateSharedSelection(
              after != null &&
                      view.state.document.nodeAtPath(after.start.path) !=
                          null &&
                      view.state.document.nodeAtPath(after.end.path) != null
                  ? after
                  : null,
              localTransaction: transaction,
            );
          } else {
            view.state.updateSharedSelection(
              view.resolveSelection(selections[view]),
            );
          }
        }
      }
    } finally {
      _committing = false;
    }
    for (final update in updates) {
      if (!_changes.isClosed) {
        _changes.add(
          SharedDocumentChange(
            documentId: documentId,
            origin: origin,
            update: update,
            isRemote: isRemote,
            structureChanged: structureChanged,
          ),
        );
      }
    }
    if (source != null && transaction != null) {
      source.state.publishSharedTransaction(
        TransactionTime.after,
        transaction,
        options,
      );
    }
  }

  Transaction _textProjection(_View view, List<SharedOperation> operations) {
    final transaction = Transaction(document: view.state.document);
    for (final operation in operations) {
      final node = view.index[operation.nodeId];
      if (node == null) continue;
      transaction.add(
        operation.kind == 'text'
            ? UpdateTextOperation(node.path, operation.delta, Delta())
            : UpdateOperation(node.path, operation.attributes, node.attributes),
        transform: false,
      );
    }
    return transaction;
  }

  void _history(_View view, {required bool redo}) {
    _checkOpen();
    if (!view.state.editable ||
        view.state.isDisposed ||
        !(redo ? view.undoScope.canRedo : view.undoScope.canUndo)) {
      return;
    }
    _commit(
      () {
        if (redo) {
          view.undoScope.redo();
        } else {
          view.undoScope.undo();
        }
      },
      origin: view.viewId,
    );
    view.state.onInput?.call(view.state);
  }

  void _validateBatch(List<SharedOperation> operations) {
    for (final operation in operations) {
      validateValue(operation.toJson());
      _backend.store.validateValue(operation.toJson());
    }
    if (!operations.any(
      (op) =>
          op.kind == 'insert' ||
          op.kind == 'delete' ||
          (op.kind == 'update' &&
              op.attributes.keys.any(
                {
                  TableBlockKeys.colsLen,
                  TableBlockKeys.rowsLen,
                  TableCellBlockKeys.colPosition,
                  TableCellBlockKeys.rowPosition,
                }.contains,
              )),
    )) {
      return;
    }
    final trial = snapshot;
    try {
      final index = _indexNodes(trial.root);
      for (final op in operations) {
        _validateCommand(op, index);
      }
      _indexNodes(trial.root);
      validateTables(trial.root);
    } finally {
      trial.dispose();
    }
  }

  List<SharedOperation> _prepare(_View view, Transaction transaction) {
    final result = <SharedOperation>[];
    final structural = transaction.operations.any(
      (op) => op is InsertOperation || op is DeleteOperation,
    );
    final shadow = structural
        ? Document(root: view.state.document.root.cloneForView())
        : null;
    final touched = <String, Node>{};
    Node? resolve(Path path) {
      if (shadow != null) return shadow.nodeAtPath(path);
      final original = view.state.document.nodeAtPath(path);
      if (original == null) return null;
      return touched.putIfAbsent(
        original.id,
        () => Node(
          type: original.type,
          id: original.id,
          attributes: original.cloneForView().attributes,
        ),
      );
    }

    try {
      for (final op in transaction.operations) {
        if (op is InsertOperation) {
          final parent = resolve(op.path.parent);
          if (parent == null || op.path.isEmpty) {
            throw StateError('Invalid insertion parent.');
          }
          final nodes = op.nodes.map((node) => node.cloneForView()).toList();
          var parentId = parent.id;
          String? beforeId;
          if (view.referenceNodeId != null && op.path.length == 1) {
            // The virtual page may only replace the referenced root, not create
            // hidden siblings. Enter in a paragraph reference inserts a newline.
            if (nodes.length != 1 || nodes.single.id != view.referenceNodeId) {
              throw StateError(
                'An edit cannot insert outside a node reference.',
              );
            }
            final original = _index[view.referenceNodeId];
            if (original?.parent == null) {
              throw StateError('The referenced node no longer exists.');
            }
            parentId = original!.parent!.id;
            beforeId = original.next?.id;
          } else {
            final offset = op.path.last;
            if (offset < 0 || offset > parent.childCount) {
              throw StateError('Invalid insertion position.');
            }
            beforeId = parent.childAtIndexOrNull(offset)?.id;
          }
          result.add(
            SharedOperation.insert(
              parentId: parentId,
              beforeId: beforeId,
              nodes: nodes,
            ),
          );
          shadow!.insert(op.path, nodes);
        } else if (op is DeleteOperation) {
          if (op.path.isEmpty) {
            throw StateError('Cannot delete the document root.');
          }
          final parent = resolve(op.path.parent);
          if (parent == null) throw StateError('Invalid deletion parent.');
          final ids = <String>[];
          for (var i = 0; i < op.nodes.length; i++) {
            final node = parent.childAtIndexOrNull(op.path.last + i);
            if (node == null) throw StateError('Invalid deletion range.');
            ids.add(node.id);
          }
          result.add(SharedOperation.delete(ids));
          shadow!.delete(op.path, ids.length);
        } else {
          final node = resolve(op.path);
          if (node == null ||
              (view.referenceNodeId != null && op.path.isEmpty)) {
            throw StateError('Invalid update target.');
          }
          if (op is UpdateTextOperation) {
            _validateDelta(node.delta, op.delta);
            result.add(SharedOperation.text(node.id, op.delta));
            node.updateAttributes({
              'delta': node.delta!.compose(op.delta).toJson(),
            });
          } else if (op is UpdateOperation) {
            final attributes = {...op.attributes};
            if (attributes.containsKey('delta')) {
              final next = attributes.remove('delta');
              if (next == null || node.delta == null) {
                throw StateError(
                  'Text identity cannot be removed by an attribute edit.',
                );
              }
              final delta = node.delta!.diff(Delta.fromJson(next));
              if (delta.isNotEmpty) {
                result.add(SharedOperation.text(node.id, delta));
              }
            }
            final contentAttributes = sharedAttributes(node, attributes);
            if (contentAttributes.isNotEmpty) {
              result.add(SharedOperation.update(node.id, contentAttributes));
            }
            node.updateAttributes(op.attributes);
          }
        }
      }
      if (shadow != null) _indexNodes(shadow.root);
      return result;
    } finally {
      shadow?.dispose();
      for (final node in touched.values) {
        node.dispose();
      }
    }
  }

  void dispose() {
    if (_closed) return;
    _checkOpen();
    _closed = true;
    for (final state in _views.keys.toList()) {
      state.dispose();
    }
    _validator?.dispose();
    _document.dispose();
    _changes.close();
  }
}

class _View implements EditorTransactionHost {
  _View(this.owner, this.referenceNodeId, this.historyLimit, {String? viewId})
      : viewId = viewId ?? const Uuid().v7() {
    undoScope = owner._backend.undoManager(this.viewId);
  }
  final SharedEditorDocument owner;
  @override
  final String? referenceNodeId;
  final int historyLimit;
  @override
  final String viewId;
  late final CrdtUndoManager undoScope;
  bool undoGroupActive = false;
  bool undoGroupHasEdit = false;
  late EditorState state;
  late Map<String, Node> index;
  void reindex() => index = _indexNodes(state.document.root);
  int get undoLength => undoScope.undoLength;
  @override
  int get revision => owner.revision;
  @override
  bool get canUndo => undoScope.canUndo;
  @override
  bool get canRedo => undoScope.canRedo;
  @override
  void clearHistory() {
    undoScope.clear();
    undoGroupHasEdit = false;
  }

  @override
  void beginUndoGroup() {
    if (undoGroupActive) return;
    undoScope.stopCapturing();
    undoGroupActive = true;
    undoGroupHasEdit = false;
  }

  @override
  void endUndoGroup() {
    if (!undoGroupActive) return;
    undoScope.stopCapturing();
    undoGroupActive = false;
    undoGroupHasEdit = false;
  }

  @override
  EditorState createNodeView(String nodeId) => owner.createEditorState(
        nodeId: nodeId,
        editable: state.editable,
        maxHistoryItemSize: historyLimit,
      );
  @override
  Future<void> apply(
    Transaction transaction, {
    required ApplyOptions options,
    required bool withUpdateSelection,
  }) =>
      owner._apply(this, transaction, options, withUpdateSelection);
  @override
  void undo() => owner._history(this, redo: false);
  @override
  void redo() => owner._history(this, redo: true);
  @override
  void detach() {
    owner._views.remove(state);
    undoScope.dispose();
    index.clear();
  }

  _SelectionAnchor? captureSelection() {
    final selection = state.selection;
    if (selection == null) return null;
    final start = state.document.nodeAtPath(selection.start.path);
    final end = state.document.nodeAtPath(selection.end.path);
    if (start == null || end == null) return null;
    final offsets = <String, int>{};
    // Endpoints may be in the same text at different offsets.
    final startBytes = owner._backend.anchors({
      start.id: selection.start.offset.clamp(0, start.delta?.length ?? 0),
    })[start.id];
    offsets[end.id] = selection.end.offset.clamp(0, end.delta?.length ?? 0);
    final endBytes = owner._backend.anchors(offsets)[end.id];
    return _SelectionAnchor(start.id, startBytes, end.id, endBytes);
  }

  Selection? resolveSelection(_SelectionAnchor? anchor) {
    if (anchor == null) return null;
    final start = index[anchor.startId];
    final end = index[anchor.endId];
    if (start == null || end == null) return null;
    final startOffset = anchor.start == null
        ? 0
        : owner._backend.resolve(anchor.startId, anchor.start!);
    final endOffset = anchor.end == null
        ? 0
        : owner._backend.resolve(anchor.endId, anchor.end!);
    if (startOffset == null || endOffset == null) return null;
    return Selection(
      start: Position(path: start.path, offset: startOffset),
      end: Position(path: end.path, offset: endOffset),
    );
  }
}

class _SelectionAnchor {
  _SelectionAnchor(this.startId, this.start, this.endId, this.end);
  final String startId;
  final Uint8List? start;
  final String endId;
  final Uint8List? end;
}

Map<String, Node> _indexNodes(Node root) {
  final result = <String, Node>{};
  void visit(Node node) {
    if (node.id.isEmpty || result.containsKey(node.id)) {
      throw StateError('Every content node must have a unique, nonempty ID.');
    }
    result[node.id] = node;
    for (final child in node.children) {
      visit(child);
    }
  }

  visit(root);
  return result;
}

void _validateDelta(Delta? base, Delta edit) {
  if (base == null) throw StateError('The target has no text.');
  var consumed = 0;
  for (final operation in edit) {
    if (operation is! TextInsert) consumed += operation.length;
    if (consumed > base.length) {
      throw StateError('Text operation exceeds its base.');
    }
  }
}

void _validateCommand(SharedOperation operation, Map<String, Node> index) {
  if (operation.kind == 'insert') {
    final parent = index[operation.parentId];
    if (parent == null) throw StateError('Unknown insertion parent.');
    final before =
        operation.beforeId == null ? null : index[operation.beforeId];
    if (operation.beforeId != null && before?.parent != parent) {
      throw StateError('Invalid insertion anchor.');
    }
    final nodes = operation.nodes;
    for (final node in nodes) {
      final descendants = _indexNodes(node);
      if (descendants.keys.any(index.containsKey)) {
        throw StateError('An insertion would duplicate a content ID.');
      }
      index.addAll(descendants);
    }
    parent.insertAll(
      nodes,
      index:
          before == null ? parent.childCount : parent.children.indexOf(before),
    );
  } else if (operation.kind == 'delete') {
    for (final id in operation.nodeIds) {
      final node = index[id];
      if (node?.parent == null) {
        throw StateError('Unknown or root deletion target.');
      }
      for (final descendantId in _indexNodes(node!).keys) {
        index.remove(descendantId);
      }
      node.unlink();
      node.dispose();
    }
  } else {
    final node = index[operation.nodeId];
    if (node == null) throw StateError('Unknown update target.');
    if (operation.kind == 'text') {
      _validateDelta(node.delta, operation.delta);
      node.updateAttributes({
        'delta': node.delta!.compose(operation.delta).toJson(),
      });
    } else {
      node.updateAttributes(operation.attributes);
    }
  }
}

/// Structural edits are less frequent; diff a shadow while retaining unchanged
/// live nodes and render keys. Ordinary typing never clones the whole document.
Transaction _buildProjection(Document current, Document desired) {
  final shadow = Document(root: current.root.cloneForView());
  final transaction = Transaction(document: current);
  const equality = DeepCollectionEquality();
  void add(Operation operation) {
    transaction.add(operation, transform: false);
    if (operation is DeleteOperation) {
      shadow.delete(operation.path, operation.nodes.length);
    }
    if (operation is InsertOperation) {
      shadow.insert(
        operation.path,
        operation.nodes.map((node) => node.cloneForView()),
      );
    }
    if (operation is UpdateOperation) {
      shadow.update(operation.path, operation.attributes);
    }
    if (operation is UpdateTextOperation) {
      shadow.updateText(operation.path, operation.delta);
    }
  }

  void reconcile(Node oldNode, Node nextNode) {
    final oldAttributes = oldNode.attributes;
    final nextAttributes = nextNode.attributes;
    final attributes = <String, dynamic>{};
    for (final key in {...oldAttributes.keys, ...nextAttributes.keys}) {
      if (!equality.equals(oldAttributes[key], nextAttributes[key])) {
        attributes[key] = nextAttributes[key];
      }
    }
    if (attributes.isNotEmpty) {
      add(UpdateOperation(oldNode.path, attributes, oldAttributes));
    }
    final wanted = {for (final node in nextNode.children) node.id: node.type};
    for (var i = oldNode.childCount - 1; i >= 0; i--) {
      final node = oldNode.children[i];
      if (wanted[node.id] != node.type) add(DeleteOperation(node.path, [node]));
    }
    for (var i = 0; i < nextNode.childCount; i++) {
      final nextChild = nextNode.children[i];
      var child = oldNode.childAtIndexOrNull(i);
      if (child?.id != nextChild.id) {
        final existing = oldNode.children.firstWhereOrNull(
          (node) => node.id == nextChild.id,
        );
        if (existing != null) add(DeleteOperation(existing.path, [existing]));
        add(InsertOperation([...oldNode.path, i], [nextChild.cloneForView()]));
        child = oldNode.children[i];
      }
      reconcile(child!, nextChild);
    }
  }

  try {
    reconcile(shadow.root, desired.root);
    return transaction;
  } finally {
    shadow.dispose();
    desired.dispose();
  }
}

// Schema interpretation belongs to the binding, not the native ABI adapter.
bool _isTextChange(CrdtChange event) =>
    event.root == 'flamingo:texts' &&
    event.delta != null &&
    event.path.length == 1 &&
    event.path.first is String;
bool _isAttributeChange(CrdtChange event) =>
    event.root == 'flamingo:blocks' &&
    event.keys != null &&
    event.path.length == 2 &&
    event.path.first is String &&
    event.path.last == 'props';
bool _isStructuralChange(CrdtChange event) =>
    !_isTextChange(event) && !_isAttributeChange(event);
