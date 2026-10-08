# Flamingo 的原生 Yrs binding

Flamingo 内部把编辑器 Transaction 转成官方 yffi/Yrs 事务。EverNote 持有
SharedEditorDocument、窗口和每个窗口的 EditorState；编辑器包不管理应用窗口、
网络或磁盘。SharedOperation 只用于本地合法性检查和绑定转换，不能作为同步协议。

`packages/flamingo_yffi/vendor/y-crdt` 是独立的官方源码子模块，固定在 v0.28.0
的 `23b7f5693bbf9e7d26340c521ee8647f79bdfba2`。原生 Cargo manifest 直接编译
该提交的 yffi 源码，并依赖同一提交的 yrs。没有自写 Rust 同步算法或业务 ABI。
生成的 Dart 声明来自同一提交的 C header；Cargo.lock 固定其余 Rust 依赖。

## 编辑器实例与身份

```dart
final shared = SharedEditorDocument(document: imported, documentId: documentId);
final full = shared.createEditorState(viewId: 'window:1');
final zoom = shared.createEditorState(viewId: 'window:2', nodeId: paragraphId);
```

nodeID 是持久化内容身份，默认 UUIDv7。EditorState、GlobalKey、焦点、选区、
布局和菜单是每个视图自己的对象。UUIDv7 不负责冲突合并：那由 Yrs 的 clientID、
时钟和共享类型完成。文档的 revision 只保护本地路径事务，不限制远端更新顺序。

底层为节点记录/属性使用 YMap，为子节点顺序使用 YArray，为段落、表格内的
段落、代码正文使用 YText。文字提交保持增量；普通输入不复制全文。
远端观察事件在 C 回调内复制成 Dart 值，再更新各视图。光标通过 Yrs
StickyIndex 编码和解析，文字长度采用 UTF-16。

每个可编辑视图使用单独的原生 UndoManager，只跟踪自己的 origin。结构撤销遵循
Yrs 的语义：撤销创建节点会让该节点的引用缺失；redo 恢复原有身份。

## 同步与存档

新副本必须从相同的 CRDT 历史启动，不能分别解析同一份 Markdown 创建副本。

```dart
final peer = SharedEditorDocument.fromUpdate(
  documentId: shared.documentId,
  update: shared.encodeUpdate(),
  pendingUpdates: shared.pendingUpdates,
);
final subscription = shared.changes.listen((change) {
  if (!change.isRemote) peer.applyChange(change);
});
```

change.update 是真实的 Yrs v1 二进制更新，支持重复、乱序和离线并发。
`stateVector()` 与 `encodeUpdate(stateVector)` 用于补齐缺失历史，包括删除集。
changes 也通知远端变化以供应用保存；转发器应只发送 isRemote=false 的变化。
origin 是应用通知信息，接收端以 remote origin 应用，不污染本地撤销。

这个版本的 yffi state_diff 不编码尚未整合的 pending update/delete set。
乱序包缺少依赖时，pendingUpdates 保留原始二进制包，并在依赖补齐后释放。
复制正在等待依赖的副本时，也要传 pendingUpdates。

`toJson()` 包含可恢复的 crdtState 和 crdtPendingUpdates，`fromJson()` 优先恢复它们；旧 JSON/Markdown
只作为首次导入。Markdown 是导出/检索快照，不能替代同步状态存档。
更新的 envelope、传输、认证、文件保存以及连接重试均属于应用层。

## 表格与代码块

旧表格把单元格放在一维 children 中，另外维护 rowsLen/colsLen 和每格的
rowPosition/colPosition。Yrs 合并成功并不意味着这套冗余表示仍是矩形。
增删和复制整行、整列现已在一个编辑器/Yrs 事务中完成；清空保留文字节点 ID。
布局测量得到的高度留在视图中，不广播，也不进入撤销栈；用户列宽仍是文档属性。

接收端使用懒创建的独立 Yrs 验证副本预检更新。它先补齐当前权威文档的差量，
再应用来包；文字事件不重建文档，结构事件检查矩形、坐标、身份与树可达性。
如果并发结构导致表格缺格/重复坐标，会抛 SharedTableMergeConflict，并携带原包；
循环或孤立的节点层级抛 SharedStructureMergeConflict。权威文档和已挂载视图
保持原状。应用需要保留冲突包并处理冲突，不能当作接收成功或直接丢弃。

这不是完整的二维表格 CRDT，也不会自动解决所有结构冲突。长期应改成稳定
rowID/columnID 的顺序数组和按 (rowID, columnID) 索引的 cellID 映射；行列数、
显示坐标及一维渲染投影从它们计算，并定义并发新增行/列交点的空格身份。
目前表格文字可以并发合并，结构冲突先显式阻止，不能宣称并发行列操作总能收敛。

代码块正文是独立 YText，语言/fence 是节点属性，高亮和补全是显示层。正文输入、
粘贴、缩进和语言菜单走 Transaction。代码节点引用保持同一个 ID；放大视图不能
通过 Continue writing 在引用范围外创建段落。现有高亮器缓存同一 source，超过
64 KiB 停止整段语法分析；超大代码块仍需要进一步评估 TextPainter/输入延迟。

## 资源、构建与验证

关闭视图释放它的 UndoManager，关闭文档注销观察器、关闭 NativeCallable 并销毁
YDoc。返回的字符串、更新包、路径、delta 和输出使用各自的 yffi destroy API。
已删除节点从 native map 删除，交给 Yrs/UndoManager 保留和回收。

maxHistoryItemSize 约束每个视图的历史保留量。官方 yffi 没有裁剪单个旧 stack item
的接口，因此达到上限后下一次编辑清空旧栈，并保留新一步；它不是滚动历史队列。
接收过远端更新的文档会多持有一个验证 YDoc；本地多视图不创建验证副本。
PDF 文件和页面位图不应写进 CRDT，后续只共享资源身份、状态和批注模型。

要求 Dart 3.11 / Flutter 3.41 和 Rust 1.95.0。Dart native-assets build hook 构建并
打包动态库，不手工加载相对路径，也不提交 dylib/target/build 文件。
当前 rust-toolchain.toml 只启用已验证的 Apple Silicon macOS 目标；其他原生目标
需添加 target 并单独验证 SDK、交叉编译与打包。普通编辑器仍可用于 Web，但
SharedEditorDocument 在 Web 明确抛 UnsupportedError，未冒充提供 Yjs/Wasm 后端。

```sh
git submodule update --init --recursive
flutter pub get
flutter test
cd packages/flamingo_yffi
dart pub get
dart test
dart run ffigen --config ffigen.yaml
```

AppFlowy 参考代码只用于事务、通知和资源边界的理解；没有拷贝其 Dispatcher、
Protobuf 事件系统、Rust runtime 或完整业务 SDK。
