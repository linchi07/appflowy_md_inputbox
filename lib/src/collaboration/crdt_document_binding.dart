import 'dart:typed_data';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:collection/collection.dart';

/// Editor schema binding over application-supplied CRDT primitives.
class CrdtDocumentBinding {
  CrdtDocumentBinding(this.store) {
    metadata = store.map('flamingo:metadata');
    blocks = store.map('flamingo:blocks');
    children = store.map('flamingo:children');
    texts = store.map('flamingo:texts');
  }

  final CrdtDocument store;
  late final CrdtMap metadata;
  late final CrdtMap blocks;
  late final CrdtMap children;
  late final CrdtMap texts;
  static const equality = DeepCollectionEquality();

  void initialize(Document document, String documentId) {
    validateNode(document.root);
    store.validateValue(document.root.toJson());
    validateTables(document.root);
    store.write('binding:import', (tx) {
      metadata.set(tx, 'schema', 1);
      metadata.set(tx, 'documentId', documentId);
      metadata.set(tx, 'rootId', document.root.id);
      _putNode(tx, document.root, null);
    });
    drain();
  }

  void drain() {
    store.takeChanges();
    store.takeUpdates();
  }

  String get rootId => store.read((tx) => metadata.get(tx, 'rootId') as String);
  String get documentId =>
      store.read((tx) => metadata.get(tx, 'documentId') as String);

  void validateIdentity(String expected) => store.read((tx) {
        if (metadata.get(tx, 'schema') != 1 ||
            metadata.get(tx, 'documentId') != expected ||
            metadata.get(tx, 'rootId') is! String) {
          throw FormatException(
            'Incompatible Flamingo document identity/schema.',
          );
        }
      });

  CrdtMap _record(CrdtTransaction tx, String id) =>
      blocks.get(tx, id) as CrdtMap;
  CrdtText? text(CrdtTransaction tx, String id) =>
      texts.get(tx, id) as CrdtText?;
  CrdtArray _order(CrdtTransaction tx, String id) {
    var order = children.get(tx, id) as CrdtArray?;
    if (order == null) {
      children.set(tx, id, const CrdtNewArray());
      order = children.get(tx, id) as CrdtArray;
    }
    return order;
  }

  void _set(CrdtTransaction tx, CrdtMap map, String key, Object? value) {
    if (!equality.equals(map.get(tx, key), value)) map.set(tx, key, value);
  }

  void _putNode(CrdtTransaction tx, Node node, String? parentId) {
    var record = blocks.get(tx, node.id) as CrdtMap?;
    if (record == null) {
      blocks.set(tx, node.id, const CrdtNewMap());
      record = _record(tx, node.id);
      record.set(tx, 'props', const CrdtNewMap());
    }
    _set(tx, record, 'type', node.type);
    _set(tx, record, 'parent', parentId);
    final props = record.get(tx, 'props') as CrdtMap;
    final next = sharedAttributes(node);
    for (final key in props.entries(tx).keys) {
      if (!next.containsKey(key)) props.remove(tx, key);
    }
    for (final entry in next.entries) {
      _set(tx, props, entry.key, entry.value);
    }
    if (node.delta != null) {
      var content = text(tx, node.id);
      if (content == null) {
        texts.set(tx, node.id, const CrdtNewText());
        content = text(tx, node.id)!;
      }
      final delta = Delta.fromJson(content.delta(tx)).diff(node.delta!);
      content.applyDelta(tx, _jsonDelta(delta));
    } else if (text(tx, node.id) != null) {
      texts.remove(tx, node.id);
    }
    final order = _order(tx, node.id);
    final wanted = node.children.map((child) => child.id).toList();
    final previous = order.values(tx);
    if (!equality.equals(previous, wanted)) {
      for (var i = previous.length - 1; i >= 0; i--) {
        order.remove(tx, i);
      }
      for (var i = 0; i < wanted.length; i++) {
        order.insert(tx, i, wanted[i]);
      }
    }
    for (final child in node.children) {
      _putNode(tx, child, node.id);
    }
  }

  void apply(List<SharedOperation> operations, String origin) {
    final reinserted = <String>{
      for (final op in operations.where((op) => op.kind == 'insert'))
        ...op.insertedNodeIds,
    };
    store.write(origin, (tx) {
      for (final op in operations) {
        if (op.kind == 'text') {
          text(tx, op.nodeId!)!.applyDelta(tx, _jsonDelta(op.delta));
        } else if (op.kind == 'update') {
          final props = _record(tx, op.nodeId!).get(tx, 'props') as CrdtMap;
          for (final entry in op.attributes.entries) {
            if (entry.value == null) {
              props.remove(tx, entry.key);
            } else {
              _set(tx, props, entry.key, entry.value);
            }
          }
        } else if (op.kind == 'delete') {
          for (final id in op.nodeIds) {
            final record = _record(tx, id);
            final parent = record.get(tx, 'parent') as String;
            _removePlacement(tx, parent, id);
            if (!reinserted.contains(id)) _deleteSubtree(tx, id, reinserted);
          }
        } else if (op.kind == 'insert') {
          final order = _order(tx, op.parentId);
          final values = order.values(tx);
          var index =
              op.beforeId == null ? values.length : values.indexOf(op.beforeId);
          if (index < 0) index = values.length;
          final nodes = op.nodes;
          try {
            for (final node in nodes) {
              _putNode(tx, node, op.parentId);
              order.insert(tx, index++, node.id);
            }
          } finally {
            for (final node in nodes) {
              node.dispose();
            }
          }
        }
      }
    });
  }

  void _removePlacement(CrdtTransaction tx, String parent, String id) {
    final order = _order(tx, parent);
    final values = order.values(tx);
    for (var i = values.length - 1; i >= 0; i--) {
      if (values[i] == id) order.remove(tx, i);
    }
  }

  void _deleteSubtree(CrdtTransaction tx, String id, Set<String> reinserted) {
    if (reinserted.contains(id)) return;
    for (final child in _order(tx, id).values(tx).cast<String>()) {
      if (_record(tx, child).get(tx, 'parent') == id) {
        _deleteSubtree(tx, child, reinserted);
      }
    }
    // The runtime retains deleted shared types only as needed for undo.
    // Do not keep every deleted node/text alive forever in an application map.
    texts.remove(tx, id);
    children.remove(tx, id);
    blocks.remove(tx, id);
  }

  Document snapshot() => store.read((tx) {
        final records = blocks.entries(tx).cast<String, CrdtMap>();
        final seen = <String>{};
        Node? build(String id, String? parent) {
          final record = records[id];
          if (record == null ||
              record.get(tx, 'deleted') == true ||
              record.get(tx, 'parent') != parent ||
              !seen.add(id)) {
            return null;
          }
          final props = (record.get(tx, 'props') as CrdtMap).entries(tx);
          final content = text(tx, id);
          if (content != null) props['delta'] = content.delta(tx);
          final order = children.get(tx, id) as CrdtArray?;
          return Node(
            type: record.get(tx, 'type') as String,
            id: id,
            attributes: props,
            children: [
              for (final child in order?.values(tx) ?? const [])
                if (child is String) ...[
                  if (build(child, id) case final node?) node,
                ],
            ],
          );
        }

        // Parent ownership filters concurrent moves and duplicate array placements.
        final root = metadata.get(tx, 'rootId') as String;
        final node = build(root, null);
        if (node == null) throw FormatException('Missing document root.');
        if (seen.length != records.length) {
          node.dispose();
          throw InvalidHierarchy(records.keys.toSet().difference(seen));
        }
        return Document(root: node);
      });

  Map<String, Uint8List> anchors(Map<String, int> offsets) => store.write(
        'binding:selection',
        (tx) => {
          for (final entry in offsets.entries)
            if (text(tx, entry.key) case final content?)
              entry.key: content.anchor(tx, entry.value),
        },
      );

  int? resolve(String id, Uint8List anchor) =>
      store.read((tx) => text(tx, id)?.resolve(tx, anchor));
  CrdtUndoManager undoManager(String origin) =>
      store.undoManager(origin, [blocks, children, texts]);
  void dispose() => store.dispose();
}

List<Map<String, dynamic>> _jsonDelta(Delta delta) =>
    delta.toJson().map((op) => Map<String, dynamic>.from(op)).toList();

/// Validate the editor schema before the runtime commits a command batch.
void validateValue(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw ArgumentError('Shared attribute keys must be strings.');
      }
      validateValue(entry.key);
      validateValue(entry.value);
    }
  } else if (value is List) {
    for (final item in value) {
      validateValue(item);
    }
  } else if (value is num && !value.isFinite) {
    throw ArgumentError('Shared numbers must be finite.');
  } else if (value != null &&
      value is! String &&
      value is! num &&
      value is! bool) {
    throw ArgumentError('Unsupported shared attribute ${value.runtimeType}');
  }
}

Attributes sharedAttributes(Node node, [Attributes? update]) {
  final result = Map<String, dynamic>.of(update ?? node.attributes)
    ..remove('delta');
  if (node.type == TableCellBlockKeys.type) {
    result.remove(TableCellBlockKeys.height);
  }
  if (node.type == TableBlockKeys.type) {
    result.remove(TableBlockKeys.colsHeight);
  }
  return result;
}

void validateNode(Node node) {
  validateValue(node.id);
  validateValue(node.type);
  validateValue(node.attributes);
  for (final child in node.children) {
    validateNode(child);
  }
}

/// The legacy table representation has redundant dimensions and coordinates.
/// A valid CRDT merge alone does not guarantee this domain invariant.
void validateTables(Node root) {
  if (root.type == TableBlockKeys.type) {
    final cols = root.attributes[TableBlockKeys.colsLen];
    final rows = root.attributes[TableBlockKeys.rowsLen];
    if (cols is! int ||
        rows is! int ||
        cols < 1 ||
        rows < 1 ||
        root.childCount != cols * rows) {
      throw InvalidTableShape(root.id);
    }
    final positions = <(int, int)>{};
    for (final cell in root.children) {
      final col = cell.attributes[TableCellBlockKeys.colPosition];
      final row = cell.attributes[TableCellBlockKeys.rowPosition];
      if (cell.type != TableCellBlockKeys.type ||
          col is! int ||
          row is! int ||
          col < 0 ||
          col >= cols ||
          row < 0 ||
          row >= rows ||
          !positions.add((col, row))) {
        throw InvalidTableShape(root.id);
      }
    }
  }
  for (final child in root.children) {
    validateTables(child);
  }
}

class InvalidTableShape implements Exception {
  InvalidTableShape(this.tableId);
  final String tableId;
}

class InvalidHierarchy implements Exception {
  InvalidHierarchy(this.nodeIds);
  final Set<String> nodeIds;
}
