import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy_editor/appflowy_editor.dart';

/// An immutable, node-ID-addressed operation, independent of any view path.
/// This is a local operation protocol, not a CRDT update encoding.
class SharedOperation {
  SharedOperation(Map<String, dynamic> json) : _json = _freeze(json);

  factory SharedOperation.insert({
    required String parentId,
    String? beforeId,
    required Iterable<Node> nodes,
  }) => SharedOperation({
    'op': 'insert',
    'parentId': parentId,
    'beforeId': beforeId,
    'nodes': nodes.map((node) => node.toJson()).toList(),
  });

  factory SharedOperation.delete(Iterable<String> nodeIds) =>
      SharedOperation({'op': 'delete', 'nodeIds': nodeIds.toList()});

  factory SharedOperation.update(String nodeId, Attributes attributes) =>
      SharedOperation({
        'op': 'update',
        'nodeId': nodeId,
        'attributes': attributes,
      });

  factory SharedOperation.text(String nodeId, Delta delta) => SharedOperation({
    'op': 'text',
    'nodeId': nodeId,
    'delta': delta.toJson(),
  });

  final Map<String, dynamic> _json;
  String get kind => _json['op'] as String;
  String? get nodeId => _json['nodeId'] as String?;
  String get parentId => _json['parentId'] as String;
  String? get beforeId => _json['beforeId'] as String?;
  List<String> get nodeIds => List<String>.from(_json['nodeIds'] as List);
  Attributes get attributes => Attributes.from(_json['attributes'] as Map);
  Delta get delta => Delta.fromJson(_json['delta']);
  Iterable<String> get insertedNodeIds sync* {
    Iterable<String> ids(Map node) sync* {
      yield node['id'] as String;
      for (final child in node['children'] as List? ?? const []) {
        yield* ids(child as Map);
      }
    }

    for (final node in _json['nodes'] as List) {
      yield* ids(node as Map);
    }
  }

  List<Node> get nodes => (_json['nodes'] as List)
      .map((node) => Node.fromJson(Map<String, Object>.from(node as Map)))
      .toList();
  Map<String, dynamic> toJson() => _json;
}

/// A real Yrs v1 update. Origin is application metadata, not a merge order.
/// Remote notifications allow persistence; transports should send local ones.
class SharedDocumentChange {
  SharedDocumentChange({
    required this.documentId,
    required this.origin,
    required Uint8List update,
    this.isRemote = false,
    this.structureChanged = true,
  }) : update = Uint8List.fromList(update).asUnmodifiableView();
  factory SharedDocumentChange.fromJson(Map<String, dynamic> json) =>
      SharedDocumentChange(
        documentId: json['documentId'] as String,
        origin: json['origin'] as String,
        update: base64Decode(json['update'] as String),
        isRemote: json['isRemote'] as bool? ?? false,
        structureChanged: json['structureChanged'] as bool? ?? true,
      );
  final String documentId;
  final String origin;
  final Uint8List update;
  final bool isRemote;

  /// Hint emitted by legal bindings; absent hints conservatively validate shape.
  final bool structureChanged;
  Map<String, dynamic> toJson() => {
    'documentId': documentId,
    'origin': origin,
    'update': base64Encode(update),
    'isRemote': isRemote,
    'structureChanged': structureChanged,
  };
}

/// The original update remains available for application conflict handling.
/// No part of this update has been applied to the live document.
class SharedTableMergeConflict implements Exception {
  SharedTableMergeConflict(this.tableId, this.change);
  final String tableId;
  final SharedDocumentChange change;
  @override
  String toString() =>
      'Concurrent table structure requires resolution: $tableId';
}

class SharedStructureMergeConflict implements Exception {
  SharedStructureMergeConflict(this.nodeIds, this.change);
  final Set<String> nodeIds;
  final SharedDocumentChange change;
  @override
  String toString() =>
      'Concurrent node hierarchy requires resolution: $nodeIds';
}

Map<String, dynamic> _freeze(Map<String, dynamic> json) {
  dynamic freeze(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.unmodifiable(
        value.map((key, item) => MapEntry(key as String, freeze(item))),
      );
    }
    if (value is List) return List<dynamic>.unmodifiable(value.map(freeze));
    return value;
  }

  return freeze(jsonDecode(jsonEncode(json))) as Map<String, dynamic>;
}
