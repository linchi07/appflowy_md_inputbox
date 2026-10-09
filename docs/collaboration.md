# Flamingo 的 CRDT binding 边界

Flamingo 负责编辑行为、nodeID、EditorState、Transaction/Delta 的合法转换以及
多视图投影。它只依赖 packages/flamingo_crdt 的纯 Dart 抽象接口，不依赖 yffi、
Rust、原生库或应用的构建脚本。SharedOperation 是本地编辑命令，不能作为同步协议。

应用选择 CRDT 实现并创建主文档，将 CrdtDocument 和独立验证副本工厂注入 binding。
应用负责窗口、会话、原生运行时、网络、存档和主文档的最终销毁。

```dart
final shared = SharedEditorDocument(
  document: imported,
  documentId: documentId,
  crdtDocument: appOwnedRuntime,
  createReplica: appRuntimeFactory,
);
final full = shared.createEditorState(viewId: 'window:1');
final zoom = shared.createEditorState(viewId: 'window:2', nodeId: paragraphId);
```

CrdtDocument 接口提供 map/array/text、事务、事件、更新、撤销和相对位置。它不暴露
C 指针、动态库、平台 target 或 yffi 构造器，也不实现另一套合并算法。适配器实现
validateValue 来检查自身限制；binding 在写事务前调用它，避免部分提交。

nodeID 是持久化内容身份，默认 UUIDv7。EditorState、GlobalKey、焦点、选区、布局、
菜单是视图自己的对象。CRDT runtime 负责合并；UUIDv7 不承担这项职责。revision
只保护本地路径事务，不限制远端更新顺序。

## 数据转换与投影

binding 为节点记录和属性使用 map，为子节点顺序使用 array，为段落、表格内的
段落和代码正文使用 text。普通输入保持增量，不复制全文。适配器交付已拥有的
Dart 事件值；binding 将它们投影到各视图。光标通过 runtime 的相对位置编码和解析。
当前编辑器的文字偏移采用 UTF-16。

每个视图通过 runtime 获得按 origin 区分的 UndoManager。撤销只跟踪该视图的
用户编辑。maxHistoryItemSize 达到上限后，下一次编辑清空旧栈并保留新一步；
目前契约提供的是整栈清理，不是裁剪单个旧 stack item。

## 同步与存档

新副本必须从相同的 CRDT 历史启动，不能分别解析同一份 Markdown 创建副本。
fromUpdate/fromJson 都要求应用提供主 runtime 和验证副本工厂。

```dart
final peer = SharedEditorDocument.fromUpdate(
  documentId: shared.documentId,
  update: shared.encodeUpdate(),
  pendingUpdates: shared.pendingUpdates,
  crdtDocument: appOwnedPeerRuntime,
  createReplica: appRuntimeFactory,
);
final subscription = shared.changes.listen((change) {
  if (!change.isRemote) peer.applyChange(change);
});
```

change.update 是 runtime 的不透明二进制编码。stateVector/encodeUpdate 提供差量，
pendingUpdates 保留尚缺依赖的包。toJson 保存 crdtState/crdtPendingUpdates；
fromJson 优先恢复这些数据，旧 JSON/Markdown 仅作为首次导入。Markdown 是快照，
不能替代 CRDT 存档。传输器只转发 isRemote=false 的通知，避免回声。

## 表格与代码块

旧表格使用一维 children 加 rowsLen/colsLen 和 rowPosition/colPosition，CRDT 合并
成功不保证仍是矩形。增删、复制行列在一个事务中完成；清空保留文字节点 ID。
测量行高是视图状态，不广播、不进入撤销；用户列宽仍是文档属性。

binding 通过应用注入的工厂懒创建验证副本，预检远端结构变化。表格缺格或坐标重复
抛 SharedTableMergeConflict；循环或孤立的层级抛 SharedStructureMergeConflict。
异常携带原包，主文档保持原状。应用需要保留冲突包并处理它，不能当作接收成功。
后续二维模型应使用稳定 rowID/columnID 及 (rowID, columnID) 到 cellID 的映射；
当前没有宣称任意并发行列编辑都能自动收敛。

代码正文是 text，语言/fence 是属性，高亮和补全是显示层。输入、粘贴、缩进和语言
菜单走 Transaction。代码节点引用保留同一 ID，不能通过 Continue writing 在引用
外创建段落。现有高亮器缓存同一 source，超过 64 KiB 停止整段语法分析。

## 生命周期与验证

shared.dispose 释放视图、撤销 scope、验证副本及编辑器缓存，保留应用传入的
主 CrdtDocument。应用先释放 binding，再销毁主 runtime。验证副本由工厂提供，
其所有权转交给 binding 的验证作用域。主文档不被编辑器隐式创建或隐式销毁。

Flamingo 和 flamingo_crdt 本身不需要 Rust。单独运行编辑器测试：

```sh
flutter pub get
flutter test
```

Web 也使用相同抽象接口；具体运行时由宿主提供。EverNote 当前选择官方 yffi/Yrs，
原生构建和集成测试都在 EverNote 仓库；未实现 Web 协同适配器。
