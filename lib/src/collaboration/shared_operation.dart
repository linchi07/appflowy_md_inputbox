import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';

/// An immutable, node-ID-addressed operation, independent of any view path.
/// This is a local operation protocol, not a CRDT update encoding.
class SharedOperation {
  SharedOperation(Map<String, dynamic> json) : _json = _freeze(json);

  factory SharedOperation.insert({
    required String parentId,
    String? beforeId,
    required Iterable<Node> nodes,
  }) =>
      SharedOperation({
        'op': 'insert',
        'parentId': parentId,
        'beforeId': beforeId,
        'nodes': nodes.map((node) => node.toJson()).toList(),
      });

  factory SharedOperation.delete(Iterable<String> nodeIds) => SharedOperation({
        'op': 'delete',
        'nodeIds': nodeIds.toList(),
      });

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

/// One atomic, ordered commit. Consumers must match document and base revision.
class SharedDocumentChange {
  SharedDocumentChange({
    required this.documentId,
    required this.origin,
    required this.baseRevision,
    required Iterable<SharedOperation> operations,
  }) : operations = List.unmodifiable(operations);

  factory SharedDocumentChange.fromJson(Map<String, dynamic> json) =>
      SharedDocumentChange(
        documentId: json['documentId'] as String,
        origin: json['origin'] as String,
        baseRevision: json['baseRevision'] as int,
        operations: (json['operations'] as List).map(
          (op) => SharedOperation(Map<String, dynamic>.from(op as Map)),
        ),
      );

  final String documentId;
  final String origin;
  final int baseRevision;
  final List<SharedOperation> operations;
  int get revision => baseRevision + 1;

  Map<String, dynamic> toJson() => {
        'documentId': documentId,
        'origin': origin,
        'baseRevision': baseRevision,
        'operations':
            operations.map((operation) => operation.toJson()).toList(),
      };
}

Map<String, dynamic> _freeze(Map<String, dynamic> json) {
  dynamic freeze(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.unmodifiable(
        value.map(
          (key, item) => MapEntry(key as String, freeze(item)),
        ),
      );
    }
    if (value is List) return List<dynamic>.unmodifiable(value.map(freeze));
    return value;
  }

  return freeze(jsonDecode(jsonEncode(json))) as Map<String, dynamic>;
}
