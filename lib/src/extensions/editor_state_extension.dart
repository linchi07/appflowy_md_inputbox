import '../../appflowy_editor.dart';

extension EditorStateChatExt on EditorState {
  /// 获取编辑器的全文内容。
  /// 各个块之间以换行符分隔。
  String toPlainText() {
    return document.root.children
        .map((e) => e.delta?.toPlainText() ?? '')
        .join('\n');
  }

  /// 获取编辑器的全文内容（getter 形式）。
  String get fullText => toPlainText();

  /// 清空编辑器内容。
  ///
  /// [keepUndoHistory] 是否保留撤销/重做历史。默认为 false。
  /// 该操作会将文档重置为包含单个空段落的状态，并将光标置于起始位置。
  void clear({bool keepUndoHistory = false}) {
    if (isDisposed) return;

    final transaction = this.transaction;
    // 删除根节点下的所有子节点
    if (document.root.children.isNotEmpty) {
      transaction.deleteNodesAtPath(
        const [0],
        document.root.children.length,
      );
    }
    // 插入一个新的空段落节点
    transaction.insertNode(const [0], paragraphNode());

    // 重置光标到起始位置
    transaction.afterSelection = Selection.collapsed(
      Position(path: [0], offset: 0),
    );

    apply(transaction);

    // 如果不需要保留历史，清空 UndoManager 中的栈
    if (!keepUndoHistory) {
      undoManager.undoStack.clear();
      undoManager.redoStack.clear();
    }
  }

  /// 重置编辑器到初始状态（语义化接口）。
  void reset() => clear(keepUndoHistory: false);
}
