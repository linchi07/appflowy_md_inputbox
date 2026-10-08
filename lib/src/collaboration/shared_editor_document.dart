import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import 'shared_text_transform.dart';

/// One local content authority, with independent editor states for live views.
/// Operations are ordered in this isolate; this class does not merge CRDT peers.
class SharedEditorDocument {
  SharedEditorDocument({required Document document, String? documentId})
      : documentId = documentId ?? document.root.id,
        _document = Document(root: document.root.cloneForView()) {
    _index = _indexNodes(_document.root);
  }

  factory SharedEditorDocument.fromJson(Map<String, dynamic> json) {
    final result = SharedEditorDocument(
      document: Document.fromJson(json),
      documentId: json['documentId'] as String?,
    );
    result._revision = json['revision'] as int? ?? 0;
    return result;
  }

  final String documentId;
  Document _document;
  late Map<String, Node> _index;
  final Map<EditorState, _View> _views = {};
  final StreamController<SharedDocumentChange> _changes =
      StreamController.broadcast();
  int _revision = 0;
  bool _closed = false;
  bool _committing = false;

  int get revision => _revision;
  String get rootId => _document.root.id;
  Stream<SharedDocumentChange> get changes => _changes.stream;
  Document get snapshot => Document(root: _document.root.cloneForView());
  Node? nodeSnapshot(String nodeId) => _index[nodeId]?.cloneForView();

  Map<String, dynamic> toJson() => {
        ..._document.toJson(),
        'documentId': documentId,
        'revision': revision,
      };

  /// A null nodeId opens the whole document. A node ID opens that live subtree.
  EditorState createEditorState({
    String? nodeId,
    bool editable = true,
    int maxHistoryItemSize = 200,
  }) {
    _checkOpen();
    if (maxHistoryItemSize < 1) {
      throw ArgumentError.value(maxHistoryItemSize, 'maxHistoryItemSize');
    }
    if (nodeId == rootId) nodeId = null;
    if (nodeId != null && !_index.containsKey(nodeId)) {
      throw ArgumentError.value(nodeId, 'nodeId', 'Unknown node');
    }
    final view = _View(this, nodeId, maxHistoryItemSize);
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
      throw ArgumentError('The transaction belongs to a different editor.');
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
    final beforeSelection = view.captureSelection();
    _commit(
      SharedDocumentChange(
        documentId: documentId,
        origin: view.id,
        baseRevision: revision,
        operations: operations,
      ),
      source: view,
      transaction: transaction,
      options: options,
      withUpdateSelection: withUpdateSelection,
      beforePublication: (inverse) {
        if (options.resolvedSource == TransactionSource.userEdit) {
          view.redoHistory.clear();
          view.undoHistory.add(_History(inverse, beforeSelection));
          if (view.undoHistory.length > view.historyLimit) {
            view.undoHistory.removeAt(0);
          }
        }
      },
    );
    return Future.value();
  }

  /// Replays an externally sequenced ID change. Concurrent/stale changes fail.
  /// A future CRDT adapter must perform merging before publishing projections.
  void applyChange(SharedDocumentChange change) {
    _checkOpen();
    _commit(change);
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
            node.updateAttributes(
              {'delta': node.delta!.compose(op.delta).toJson()},
            );
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
            if (attributes.isNotEmpty) {
              result.add(SharedOperation.update(node.id, attributes));
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

  List<SharedOperation> _commit(
    SharedDocumentChange change, {
    _View? source,
    Transaction? transaction,
    ApplyOptions options = const ApplyOptions(source: TransactionSource.none),
    bool withUpdateSelection = true,
    void Function(List<SharedOperation>)? beforePublication,
  }) {
    if (change.documentId != documentId || change.baseRevision != revision) {
      throw StateError('Document identity or revision does not match.');
    }
    final structural = change.operations.any(
      (op) => op.kind == 'insert' || op.kind == 'delete',
    );
    // Validate the entire commit before changing any live state.
    final trial = structural ? snapshot : null;
    final trialIndex =
        trial == null ? <String, Node>{} : _indexNodes(trial.root);
    if (trial == null) {
      for (final operation in change.operations) {
        final id = operation.nodeId!;
        final original = _index[id];
        if (original == null) throw StateError('Unknown update target: $id');
        trialIndex.putIfAbsent(id, () => original.cloneForView());
      }
    }
    final inverse = <SharedOperation>[];
    try {
      for (final operation in change.operations) {
        inverse.insertAll(0, _execute(operation, trialIndex));
      }
      if (trial != null) _indexNodes(trial.root);
    } catch (_) {
      trial?.dispose();
      if (trial == null) {
        for (final node in trialIndex.values) {
          node.dispose();
        }
      }
      rethrow;
    }

    _committing = true;
    try {
      if (source != null && transaction != null) {
        source.state.publishSharedTransaction(
          TransactionTime.before,
          transaction,
          options,
        );
      }
      final selections = {
        for (final view in _views.values) view: view.captureSelection(),
      };
      if (trial != null) {
        final previous = _document;
        _document = trial;
        _index = trialIndex;
        previous.dispose();
      } else {
        for (final operation in change.operations) {
          _execute(operation, _index);
        }
      }
      _revision++;
      for (final view in _views.values.toList()) {
        _rebaseHistory(view, change);
        final projection = structural
            ? _buildProjection(
                view.state.document,
                _projection(view.referenceNodeId),
              )
            : _textProjection(view, change.operations);
        view.state.applySharedProjection(projection);
        if (structural) view.reindex();
        final anchor = selections[view];
        if (anchor != null) {
          for (final operation in change.operations) {
            anchor.transform(operation);
          }
        }
        final selection = view.resolveSelection(anchor);
        if (identical(view, source) &&
            withUpdateSelection &&
            transaction != null) {
          final after = transaction.afterSelection;
          view.state.updateSharedSelection(after != null &&
                  view.state.document.nodeAtPath(after.start.path) != null &&
                  view.state.document.nodeAtPath(after.end.path) != null
              ? after
              : null, localTransaction: transaction,);
        } else {
          view.state.updateSharedSelection(selection);
        }
      }
    } finally {
      _committing = false;
      if (trial == null) {
        for (final node in trialIndex.values) {
          node.dispose();
        }
      }
    }
    beforePublication?.call(inverse);
    if (!_changes.isClosed) _changes.add(change);
    if (source != null && transaction != null) {
      source.state.publishSharedTransaction(
        TransactionTime.after,
        transaction,
        options,
      );
    }
    return inverse;
  }

  Transaction _textProjection(_View view, List<SharedOperation> operations) {
    final transaction = Transaction(document: view.state.document);
    for (final operation in operations) {
      final node = view.index[operation.nodeId];
      if (node == null) continue;
      if (operation.kind == 'text') {
        transaction.add(
          UpdateTextOperation(node.path, operation.delta, Delta()),
          transform: false,
        );
      } else {
        transaction.add(
          UpdateOperation(node.path, operation.attributes, node.attributes),
          transform: false,
        );
      }
    }
    return transaction;
  }

  void _history(_View view, {required bool redo}) {
    _checkOpen();
    if (!view.state.editable || view.state.isDisposed) return;
    final from = redo ? view.redoHistory : view.undoHistory;
    final to = redo ? view.undoHistory : view.redoHistory;
    if (from.isEmpty) return;
    final item = from.removeLast();
    final selection = view.captureSelection();
    final inverse = _commit(
      SharedDocumentChange(
        documentId: documentId,
        origin: view.id,
        baseRevision: revision,
        operations: item.operations,
      ),
    );
    view.state.selection = view.resolveSelection(item.selection);
    to.add(_History(inverse, selection));
    view.state.onInput?.call(view.state);
  }

  void _rebaseHistory(_View view, SharedDocumentChange change) {
    if (change.origin != view.id) {
      for (final stack in [view.undoHistory, view.redoHistory]) {
        // A local inverse must not erase a subtree another view has edited.
        stack.removeWhere((history) => history.operations.any((pending) {
              if (pending.kind != 'delete') return false;
              final roots = pending.nodeIds.toSet();
              for (final operation in change.operations) {
                final id = operation.nodeId ??
                    (operation.kind == 'insert' ? operation.parentId : null);
                for (var node = _index[id]; node != null; node = node.parent) {
                  if (roots.contains(node.id)) return true;
                }
              }
              return false;
            }),);
        for (final operation in change.operations) {
          var applied = operation;
          for (final history in stack.reversed) {
            final next = <SharedOperation>[];
            for (final pending in history.operations) {
              if (pending.nodeId != applied.nodeId) {
                next.add(pending);
              } else if (pending.kind == 'text' && applied.kind == 'text') {
                final oldPending = pending.delta;
                next.add(
                  SharedOperation.text(
                    pending.nodeId!,
                    transformSharedDelta(oldPending, applied.delta),
                  ),
                );
                applied = SharedOperation.text(
                  applied.nodeId!,
                  transformSharedDelta(
                    applied.delta,
                    oldPending,
                    appliedHasPriority: false,
                  ),
                );
              } else if (pending.kind == 'update' && applied.kind == 'update') {
                final attributes = pending.attributes;
                for (final key in applied.attributes.keys) {
                  attributes.remove(key);
                }
                next.add(SharedOperation.update(pending.nodeId!, attributes));
              } else {
                next.add(pending);
              }
            }
            history.operations = next;
            history.selection?.transform(applied);
          }
        }
      }
    }
    for (final stack in [view.undoHistory, view.redoHistory]) {
      for (final history in stack) {
        history.operations.removeWhere((operation) =>
            (operation.kind == 'text' && operation.delta.isEmpty) ||
            (operation.kind == 'update' && operation.attributes.isEmpty),);
      }
      stack.removeWhere((history) => history.operations.isEmpty);
    }
    if (!change.operations.any((operation) =>
        operation.kind == 'insert' || operation.kind == 'delete',)) {
      return;
    }
    // Structural undo cannot resurrect a subtree changed by another view.
    // Retain text history across unrelated insertion/reorder, but discard entries
    // whose targets no longer exist. CRDT selective undo is a separate backend.
    bool valid(_History history) {
      final restored = <String>{};
      for (final operation in history.operations) {
        if (operation.nodeId != null && !_index.containsKey(operation.nodeId)) {
          return false;
        }
        if (operation.kind == 'delete' &&
            operation.nodeIds.any(
                (id) => !_index.containsKey(id) && !restored.contains(id),)) {
          return false;
        }
        if (operation.kind == 'insert') {
          if (!_index.containsKey(operation.parentId) &&
              !restored.contains(operation.parentId)) {
            return false;
          }
          final anchor = operation.beforeId;
          if (anchor != null &&
              !_index.containsKey(anchor) &&
              !restored.contains(anchor)) {
            return false;
          }
          restored.addAll(operation.insertedNodeIds);
        }
      }
      return true;
    }

    view.undoHistory.removeWhere((history) => !valid(history));
    view.redoHistory.removeWhere((history) => !valid(history));
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    for (final state in _views.keys.toList()) {
      state.dispose();
    }
    _document.dispose();
    _changes.close();
  }
}

class _View implements EditorTransactionHost {
  _View(this.owner, this.referenceNodeId, this.historyLimit);
  final SharedEditorDocument owner;
  @override
  final String? referenceNodeId;
  final int historyLimit;
  final String id = const Uuid().v7();
  late EditorState state;
  late Map<String, Node> index;
  final List<_History> undoHistory = [];
  final List<_History> redoHistory = [];

  void reindex() => index = _indexNodes(state.document.root);
  @override
  int get revision => owner.revision;
  @override
  bool get canUndo => undoHistory.isNotEmpty;
  @override
  bool get canRedo => redoHistory.isNotEmpty;
  @override
  void clearHistory() {
    undoHistory.clear();
    redoHistory.clear();
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
    clearHistory();
    index.clear();
  }

  _SelectionAnchor? captureSelection() {
    final selection = state.selection;
    if (selection == null) return null;
    final start = state.document.nodeAtPath(selection.start.path);
    final end = state.document.nodeAtPath(selection.end.path);
    if (start == null || end == null) return null;
    return _SelectionAnchor(
      start.id,
      selection.start.offset,
      end.id,
      selection.end.offset,
    );
  }

  Selection? resolveSelection(_SelectionAnchor? anchor) {
    if (anchor == null) return null;
    final start = index[anchor.startId];
    final end = index[anchor.endId];
    if (start == null || end == null) return null;
    return Selection(
      start: Position(
        path: start.path,
        offset: anchor.startOffset.clamp(0, start.delta?.length ?? 0),
      ),
      end: Position(
        path: end.path,
        offset: anchor.endOffset.clamp(0, end.delta?.length ?? 0),
      ),
    );
  }
}

class _SelectionAnchor {
  _SelectionAnchor(this.startId, this.startOffset, this.endId, this.endOffset);
  final String startId;
  int startOffset;
  final String endId;
  int endOffset;
  void transform(SharedOperation operation) {
    if (operation.kind != 'text') return;
    if (operation.nodeId == startId) {
      startOffset = transformSharedOffset(startOffset, operation.delta);
    }
    if (operation.nodeId == endId) {
      endOffset = transformSharedOffset(endOffset, operation.delta);
    }
  }
}

class _History {
  _History(this.operations, this.selection);
  List<SharedOperation> operations;
  final _SelectionAnchor? selection;
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

List<SharedOperation> _execute(
  SharedOperation operation,
  Map<String, Node> index,
) {
  final inverse = <SharedOperation>[];
  if (operation.kind == 'insert') {
    final parent = index[operation.parentId];
    if (parent == null) throw StateError('Unknown insertion parent.');
    final before =
        operation.beforeId == null ? null : index[operation.beforeId];
    if (operation.beforeId != null && before?.parent != parent) {
      throw StateError('Insertion anchor is no longer a child of its parent.');
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
    inverse.add(SharedOperation.delete(nodes.map((node) => node.id)));
  } else if (operation.kind == 'delete') {
    for (final id in operation.nodeIds) {
      final node = index[id];
      if (node?.parent == null) {
        throw StateError('Unknown or root deletion target.');
      }
      inverse.insert(
        0,
        SharedOperation.insert(
          parentId: node!.parent!.id,
          beforeId: node.next?.id,
          nodes: [node],
        ),
      );
      for (final descendantId in _indexNodes(node).keys) {
        index.remove(descendantId);
      }
      node.unlink();
    }
  } else {
    final node = index[operation.nodeId];
    if (node == null) throw StateError('Unknown update target.');
    if (operation.kind == 'text') {
      final delta = operation.delta;
      _validateDelta(node.delta, delta);
      inverse.add(SharedOperation.text(node.id, delta.invert(node.delta!)));
      node.updateAttributes({'delta': node.delta!.compose(delta).toJson()});
    } else if (operation.kind == 'update') {
      if (operation.attributes.containsKey('delta')) {
        throw StateError('Use a text operation for text changes.');
      }
      inverse.add(
        SharedOperation.update(node.id, {
          for (final key in operation.attributes.keys)
            key: node.attributes[key],
        }),
      );
      node.updateAttributes(operation.attributes);
    } else {
      throw FormatException('Unknown shared operation: ${operation.kind}');
    }
  }
  return inverse;
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
        final existing = oldNode.children
            .firstWhereOrNull((node) => node.id == nextChild.id);
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
