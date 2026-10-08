import 'package:appflowy_editor/appflowy_editor.dart';

/// Internal commit boundary. A view owns UI state; its host owns shared content.
abstract class EditorTransactionHost {
  String get viewId;
  int get revision;
  String? get referenceNodeId;
  bool get canUndo;
  bool get canRedo;

  Future<void> apply(
    Transaction transaction, {
    required ApplyOptions options,
    required bool withUpdateSelection,
  });

  EditorState createNodeView(String nodeId);
  void undo();
  void redo();
  void clearHistory();
  void detach();
}
