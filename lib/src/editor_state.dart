// ignore_for_file: newline_before_return
import 'dart:async';
import 'dart:collection';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/standard_node_behaviors.dart';
import 'package:appflowy_editor/src/editor/editor_component/service/scroll/auto_scroller.dart';
import 'package:appflowy_editor/src/editor/util/platform_extension.dart';
import 'package:appflowy_editor/src/history/undo_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextEditingDelta;

import 'service/markdown_parser.dart';

typedef EditorTransactionValue = (
  TransactionTime time,
  Transaction transaction,
  ApplyOptions options,
);

typedef OnPasteCallback = FutureOr<bool> Function();

abstract class SelectionCoordinator {
  Selection coordinateSelection(EditorState editorState, Selection selection);

  /// Text for an atomic block in a copied document selection.
  String? textForCopy(Node node) => null;

  /// Whether a descendant's normal text highlight is covered by an atomic
  /// block highlight.
  bool suppressSelectionPaint(Node node, Selection selection) => false;
}

abstract class RangeSelectionHandler {
  String? getSelectedText();
  Future<void> clearSelectedContent();
  void cancelSelection();
}

class EditorStateDebugInfo {
  EditorStateDebugInfo({
    this.debugPaintSizeEnabled = false,
  });

  /// Enable the debug paint size for selection handle.
  ///
  /// It only available on mobile.
  bool debugPaintSizeEnabled;
}

/// the type of this value is bool.
///
/// set true to this key to prevent attaching the text service when selection is changed.
const selectionExtraInfoDoNotAttachTextService =
    'selectionExtraInfoDoNotAttachTextService';
const _selectionDragModeKey = 'selection_drag_mode';

class ApplyOptions {
  const ApplyOptions({
    this.recordUndo = true,
    this.recordRedo = false,
    this.source,
    this.inMemoryUpdate = false,
  });

  /// Whether the transaction should be recorded into the undo stack.
  @Deprecated('Use [source] instead')
  final bool recordUndo;

  @Deprecated('Use [source] instead')
  final bool recordRedo;

  /// The source of the transaction. When set, takes precedence over
  /// the legacy `recordUndo` and `recordRedo` flags for determining
  /// how the transaction is recorded in the undo/redo history.
  final TransactionSource? source;

  /// This flag used to determine whether the transaction is in-memory update.
  final bool inMemoryUpdate;

  /// Returns the resolved [TransactionSource].
  /// Prefers explicit [source], falls back to legacy boolean flags.
  ///
  /// Legacy mapping (for backward compatibility):
  /// - `recordRedo: true` → [TransactionSource.undo] (records *to* redo stack)
  /// - `recordUndo: true` → [TransactionSource.userEdit]
  /// - both false → [TransactionSource.none]
  TransactionSource get resolvedSource {
    if (source != null) return source!;
    // ignore: deprecated_member_use_from_same_package
    if (recordRedo) return TransactionSource.undo;
    // ignore: deprecated_member_use_from_same_package
    if (recordUndo) return TransactionSource.userEdit;

    return TransactionSource.none;
  }
}

@Deprecated('use SelectionUpdateReason instead')
enum CursorUpdateReason {
  uiEvent,
  others,
}

enum SelectionUpdateReason {
  uiEvent, // like mouse click, keyboard event
  transaction, // like insert, delete, format
  remote, // like remote selection
  selectAll,
  searchHighlight, // Highlighting search results
}

enum SelectionType {
  inline,
  block,
}

enum TransactionTime {
  before,
  after,
}

final RegExp _hrefRegex = RegExp(
  r'https?://(?:www\.)?[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}(?:/[^\s]*)?',
);

final RegExp _phoneRegex = RegExp(r'^\+?' // Optional '+' at start
    r'(?:[0-9][\s-.]?)+' // Sequence of digits with optional separators
    r'[0-9]$' // Ensure it ends with a digit
    );

/// The state of the editor.
///
/// The state includes:
/// - The document to render
/// - The state of the selection
///
/// [EditorState] also includes the services of the editor:
/// - Selection service
/// - Scroll service
/// - Keyboard service
/// - Input service
/// - Toolbar service
///
/// In consideration of collaborative editing,
/// all the mutations should be applied through [Transaction].
///
/// Mutating the document with document's API is not recommended.
class EditorState {
  EditorState({
    required this.document,
    this.transactionHost,
    this.minHistoryItemDuration = const Duration(milliseconds: 50),
    int? maxHistoryItemSize,
  }) {
    undoManager = UndoManager(maxHistoryItemSize ?? 200);
    undoManager.state = this;
  }

  @Deprecated('use EditorState.blank() instead')
  EditorState.empty()
      : this(
          document: Document.blank(),
        );

  EditorState.blank({
    bool withInitialText = true,
    int? maxHistoryItemSize,
  }) : this(
          document: Document.blank(
            withInitialText: withInitialText,
          ),
          maxHistoryItemSize: maxHistoryItemSize,
        );

  final Document document;

  /// Supplied by SharedEditorDocument; applications do not need a binding layer.
  final EditorTransactionHost? transactionHost;

  String? get viewId => transactionHost?.viewId;

  String? get referenceNodeId => transactionHost?.referenceNodeId;

  bool get isNodeReference => referenceNodeId != null;

  bool get isReferenceMissing =>
      isNodeReference && document.root.children.isEmpty;

  /// Opens the same content with independent selection, focus and render nodes.
  EditorState createNodeView(String nodeId) {
    final host = transactionHost;
    if (host == null) {
      throw StateError(
        'Create this editor through SharedEditorDocument first.',
      );
    }
    return host.createNodeView(nodeId);
  }

  // the minimum duration for saving the history item.
  final Duration minHistoryItemDuration;

  /// Whether the editor is editable.
  ValueNotifier<bool> editableNotifier = ValueNotifier(true);

  /// Tracks temporary overlays that should preserve focus for this editor.
  ///
  /// This must be editor-scoped: a process-wide counter makes closing an
  /// overlay in one editor request focus in every other mounted editor.
  final KeepEditorFocusNotifier keepEditorFocusNotifier =
      KeepEditorFocusNotifier();

  /// Whether this editor's keyboard focus scope currently owns focus.
  /// Local cursor painting listens to this notifier so inactive editors can
  /// retain a selection without displaying an active caret.
  final ValueNotifier<bool> focusNotifier = IndexedValueNotifier(false);

  bool get hasFocus => focusNotifier.value;

  bool get editable => editableNotifier.value;

  set editable(bool value) {
    if (value == editable) {
      return;
    }
    editableNotifier.value = value;
  }

  /// Whether the editor should disable auto scroll.
  bool disableAutoScroll = false;

  /// The edge offset of the auto scroll.
  double autoScrollEdgeOffset = appFlowyEditorAutoScrollEdgeOffset;

  /// The callback that will be triggered when the user pastes content.
  OnPasteCallback? onPaste;

  /// The style of the editor.
  EditorStyle editorStyle = EditorStyle.desktop();

  /// The selection notifier of the editor.
  final PropertyValueNotifier<Selection?> selectionNotifier =
      IndexedPropertyValueNotifier<Selection?>(null);

  /// The selection of the editor.
  Selection? get selection => selectionNotifier.value;

  /// Remote selection is the selection from other users.
  final PropertyValueNotifier<List<RemoteSelection>> remoteSelections =
      IndexedPropertyValueNotifier<List<RemoteSelection>>([]);

  /// Active block-owned range selection handler.
  RangeSelectionHandler? activeRangeSelectionHandler;

  final List<SelectionCoordinator> _selectionCoordinators = [];
  final Map<SelectionCoordinator, int> _selectionCoordinatorReferences = {};

  void registerSelectionCoordinator(SelectionCoordinator coordinator) {
    final references = _selectionCoordinatorReferences[coordinator] ?? 0;
    _selectionCoordinatorReferences[coordinator] = references + 1;
    if (references == 0) {
      _selectionCoordinators.add(coordinator);
    }
  }

  void unregisterSelectionCoordinator(SelectionCoordinator coordinator) {
    final references = _selectionCoordinatorReferences[coordinator];
    if (references == null) return;
    if (references > 1) {
      _selectionCoordinatorReferences[coordinator] = references - 1;
    } else {
      _selectionCoordinatorReferences.remove(coordinator);
      _selectionCoordinators.remove(coordinator);
    }
  }

  String? textForAtomicSelectionCopy(Node node) {
    for (final coordinator in _selectionCoordinators) {
      final text = coordinator.textForCopy(node);
      if (text != null) return text;
    }
    return null;
  }

  bool suppressSelectionPaint(Node node, Selection selection) =>
      _selectionCoordinators.any(
        (coordinator) => coordinator.suppressSelectionPaint(node, selection),
      );

  Selection? coordinateSelection(Selection? selection) {
    if (selection == null || selection.isCollapsed) {
      return selection;
    }
    var result = selection;
    for (final coordinator in _selectionCoordinators) {
      result = coordinator.coordinateSelection(this, result);
    }
    return result;
  }

  /// Sets the selection of the editor.
  set selection(Selection? value) {
    final coordinated = coordinateSelection(value);
    // clear the toggled style when the selection is changed.
    if (selectionNotifier.value != coordinated) {
      _toggledStyle.clear();
    }

    // reset slice flag
    sliceUpcomingAttributes = true;

    selectionNotifier.value = coordinated;
  }

  SelectionType? _selectionType;

  set selectionType(SelectionType? value) {
    if (value == _selectionType) {
      return;
    }
    _selectionType = value;
  }

  SelectionType? get selectionType => _selectionType;

  SelectionUpdateReason _selectionUpdateReason = SelectionUpdateReason.uiEvent;

  SelectionUpdateReason get selectionUpdateReason => _selectionUpdateReason;

  Map? selectionExtraInfo;

  // Service reference.
  final service = EditorService();

  AppFlowyScrollService? get scrollService => service.scrollService;

  AppFlowySelectionService get selectionService => service.selectionService;

  BlockComponentRendererService get renderer => service.rendererService;

  set renderer(BlockComponentRendererService value) {
    service.rendererService = value;
  }

  /// Customize the debug info for the editor state.
  ///
  /// Refer to [EditorStateDebugInfo] for more details.
  EditorStateDebugInfo debugInfo = EditorStateDebugInfo();

  /// store the auto scroller instance in here temporarily.
  AutoScroller? autoScroller;
  ScrollableState? scrollableState;

  /// Configures log output parameters,
  /// such as log level and log output callbacks,
  /// with this variable.
  AppFlowyLogConfiguration get logConfiguration => AppFlowyLogConfiguration();

  /// Stores the selection menu items.
  List<SelectionMenuItem> selectionMenuItems = [];

  /// Stores the toolbar items.
  @Deprecated('use floating toolbar or mobile toolbar instead')
  List<ToolbarItem> toolbarItems = [];

  /// The callback that will be triggered when the document is changed.
  void Function(EditorState editorState)? onInput;

  /// The notifier that will be updated when the document is changed.
  ///
  /// If it is not null, the editor state will update the character count
  /// after applying a transaction.
  ValueNotifier<int>? characterCounter;

  /// Returns the plain text of the document.
  ///
  /// Each block is separated by a newline character.
  String get text {
    final cached = _cachedText;
    if (cached != null) {
      return cached;
    }
    if (document.root.children.isEmpty) {
      return '';
    }
    return _cachedText = document.root.children.map(_textForBlock).join('\n');
  }

  /// The serialized length, maintained by document transactions.
  int get textLength => _totalTextLength ??= _calculateTextLength();

  final Map<Node, String> _blockTextCache = {};
  int? _totalTextLength;

  int _calculateTextLength() {
    final blocks = document.root.children;
    var length = blocks.isEmpty ? 0 : blocks.length - 1;
    for (final block in blocks) {
      length += _textForBlock(block).length;
    }
    return length;
  }

  String _textForBlock(Node block) => _blockTextCache.putIfAbsent(block, () {
        final serialize = behaviorFor(block)?.serialize;
        if (serialize != null) return serialize(block);
        if (block.type == DividerBlockKeys.type) {
          return '---';
        }
        return block.delta?.toPlainText() ?? '';
      });

  String? _cachedText;
  int _textRevision = 0;
  int _documentRevision = 0;

  /// Sets the plain text of the document.
  ///
  /// This will clear the existing document and insert the new text.
  /// The undo/redo history will be cleared.
  set text(String value) => unawaited(setText(value));

  /// Replaces the document and completes after parsing and applying it.
  Future<void> setText(String value) async {
    if (isDisposed) return;
    if (isNodeReference) {
      final node = document.root.children.firstOrNull;
      if (node == null || node.delta == null) {
        throw StateError('This reference has no replaceable text.');
      }
      await apply(
        this.transaction
          ..replaceText(node, 0, node.delta!.length, value)
          ..afterSelection = Selection.collapsed(
            Position(path: node.path, offset: value.length),
          ),
      );
      transactionHost?.clearHistory();
      return;
    }
    final revision = ++_textRevision;
    final documentRevision = _documentRevision;

    final List<Node> nodes;
    if (value.length >= 1000) {
      nodes = await compute(parseMarkdownToNodes, value);
    } else {
      nodes = parseMarkdownToNodes(value);
    }
    if (isDisposed ||
        revision != _textRevision ||
        documentRevision != _documentRevision) {
      return;
    }

    final transaction = this.transaction;

    // Delete all existing nodes.
    if (document.root.children.isNotEmpty) {
      transaction.deleteNodesAtPath(
        const [0],
        document.root.children.length,
      );
    }

    transaction.insertNodes(const [0], nodes);

    // Reset selection to the end.
    transaction.afterSelection = Selection.collapsed(
      Position(
        path: [nodes.length - 1],
        offset: nodes.last.delta?.length ?? 0,
      ),
    );
    transaction.reason = SelectionUpdateReason.uiEvent;

    await apply(transaction);

    // Clear undo history.
    undoManager.undoStack.clear();
    undoManager.redoStack.clear();
    transactionHost?.clearHistory();
  }

  /// Appends markdown text to the end of the document.
  Future<void> append(String value) async {
    if (isDisposed || value.isEmpty) return;
    if (isReferenceMissing) return;

    // Move cursor to the end
    final lastNode = document.root.children.last;
    selection = Selection.collapsed(
      Position(
        path: [document.root.children.length - 1],
        offset: lastNode.delta?.length ?? 0,
      ),
    );

    // Call robust insertion logic
    await pastePlainText(value);
  }

  /// Pastes plain text (parsed as markdown) into the document.
  Future<void> pastePlainText(String plainText) async {
    if (isDisposed || isReferenceMissing) return;
    // Optional nodes may own the literal paste behavior for their contents.
    final literalSelection = selection;
    final literalNode = literalSelection == null || !literalSelection.isSingle
        ? null
        : getNodeAtPath(literalSelection.start.path);
    final pasteBehavior = behaviorFor(literalNode);
    final literalText = literalNode != null && literalSelection != null
        ? pasteBehavior?.literalPaste
            ?.call(this, literalNode, literalSelection, plainText)
        : null;
    final liveParagraph = literalNode?.id == referenceNodeId &&
        referenceNodeId != null &&
        literalNode?.delta != null;
    if (pasteBehavior?.pasteAsPlainText == true ||
        literalText != null ||
        liveParagraph) {
      final collapsed = await deleteSelectionIfNeeded();
      final currentNode =
          collapsed == null ? null : getNodeAtPath(collapsed.start.path);
      if (currentNode != null && currentNode.type == literalNode?.type) {
        final insertedText = literalText ?? plainText;
        await apply(
          transaction
            ..insertText(currentNode, collapsed!.start.offset, insertedText)
            ..afterSelection = Selection.collapsed(
              Position(
                path: currentNode.path,
                offset: collapsed.start.offset + insertedText.length,
              ),
            ),
        );
      }
      return;
    }
    final documentRevision = _documentRevision;
    final originalSelection = selection;
    final selectionAttributes = getDeltaAttributesInSelectionStart();

    if (await maybeConvertToUrlOrPhone(plainText)) {
      return;
    }
    if (isDisposed ||
        documentRevision != _documentRevision ||
        selection != originalSelection) {
      return;
    }

    final List<Node> nodes;
    if (plainText.length >= 1000) {
      nodes = await compute(
        parseMarkdownToNodesCompute,
        (plainText, selectionAttributes),
      );
    } else {
      nodes =
          parseMarkdownToNodes(plainText, baseAttributes: selectionAttributes);
    }

    if (nodes.isEmpty) {
      return;
    }
    // A background parse belongs to the document and selection that started
    // it. If either changed, cancel instead of pasting at a stale location.
    if (isDisposed ||
        documentRevision != _documentRevision ||
        selection != originalSelection) {
      return;
    }
    // Keep the current selection intact while a large payload is parsed in an
    // isolate. The paste helpers begin changing the document only after this
    // revision and selection check.
    if (nodes.any((node) => behaviorFor(node)?.isolateOnPaste == true)) {
      await pasteNodesPreservingBoundaries(nodes.toList());
    } else if (nodes.length == 1) {
      await pasteSingleLineNode(nodes.first);
    } else {
      await pasteMultiLineNodes(nodes.toList());
    }
  }

  /// Inserts markdown text into the document at current selection.
  Future<void> insertMarkdown(String markdown) => pastePlainText(markdown);

  Future<bool> maybeConvertToUrlOrPhone(String plainText) async {
    final selection = this.selection;
    if (selection == null ||
        !selection.isSingle ||
        selection.isCollapsed ||
        (!_hrefRegex.hasMatch(plainText) && !_phoneRegex.hasMatch(plainText))) {
      return false;
    }

    final node = getNodeAtPath(selection.start.path);
    if (node == null) {
      return false;
    }

    final transaction = this.transaction;
    final isPhone = _phoneRegex.hasMatch(plainText);
    transaction.formatText(node, selection.startIndex, selection.length, {
      AppFlowyRichTextKeys.href: isPhone ? 'tel:$plainText' : plainText,
    });
    await apply(transaction);

    return true;
  }

  /// listen to this stream to get notified when the transaction applies.
  Stream<EditorTransactionValue> get transactionStream => _observer.stream;
  final StreamController<EditorTransactionValue> _observer =
      StreamController.broadcast(sync: true);
  final StreamController<EditorTransactionValue> _asyncObserver =
      StreamController.broadcast();

  /// Store the toggled format style, like bold, italic, etc.
  /// All the values must be the key from [AppFlowyRichTextKeys.supportToggled].
  ///
  /// Use the method [updateToggledStyle] to update key-value pairs
  ///
  /// NOTES: It only works once;
  ///   after the selection is changed, the toggled style will be cleared.
  UnmodifiableMapView<String, dynamic> get toggledStyle =>
      UnmodifiableMapView<String, dynamic>(_toggledStyle);
  final _toggledStyle = Attributes();
  late final toggledStyleNotifier = ValueNotifier<Attributes>(toggledStyle);

  void updateToggledStyle(String key, dynamic value) {
    _toggledStyle[key] = value;
    toggledStyleNotifier.value = {..._toggledStyle};
  }

  /// Whether the upcoming attributes should be sliced.
  ///
  /// If the value is true, the upcoming attributes will be sliced.
  /// If the value is false, the upcoming attributes will be skipped.
  bool _sliceUpcomingAttributes = true;

  bool get sliceUpcomingAttributes => _sliceUpcomingAttributes;

  set sliceUpcomingAttributes(bool value) {
    if (value == _sliceUpcomingAttributes) {
      return;
    }
    AppFlowyEditorLog.input.debug('sliceUpcomingAttributes: $value');
    _sliceUpcomingAttributes = value;
  }

  late final UndoManager undoManager;

  Transaction get transaction {
    final transaction = Transaction(
      document: document,
      baseRevision: transactionHost?.revision,
    );
    transaction.beforeSelection = selection;

    return transaction;
  }

  bool showHeader = false;
  bool showFooter = false;

  bool enableAutoComplete = false;
  AppFlowyAutoCompleteTextProvider? autoCompleteTextProvider;

  /// Optional node-local input behavior, keyed by [Node.type].
  Map<String, NodeBehavior> get nodeBehaviors => _nodeBehaviors;
  Map<String, NodeBehavior> _nodeBehaviors = {...standardNodeBehaviors};

  set nodeBehaviors(Map<String, NodeBehavior> value) {
    final merged = {...standardNodeBehaviors, ...value};
    if (mapEquals(_nodeBehaviors, merged)) return;
    _nodeBehaviors = merged;
    _blockTextCache.clear();
    _cachedText = null;
    _totalTextLength = null;
  }

  NodeBehavior? behaviorFor(Node? node) =>
      node == null ? null : _nodeBehaviors[node.type];

  bool isAtomicBlock(Node node) => behaviorFor(node)?.atomic == true;

  Node? atomicAncestorOf(Node node) =>
      node.findParent((ancestor) => isAtomicBlock(ancestor));

  bool preventsMergeAtStart(Node? node) =>
      behaviorFor(node)?.preventMergeAtStart == true;

  Iterable<CommandShortcutEvent> commandShortcutsFor(Node? node) sync* {
    for (var current = node; current != null; current = current.parent) {
      yield* behaviorFor(current)?.commandShortcuts ??
          const <CommandShortcutEvent>[];
    }
  }

  // only used for testing
  bool disableSealTimer = false;

  /// The rules to apply to the document.
  List<DocumentRule> get documentRules => _documentRules;
  List<DocumentRule> _documentRules = [];

  set documentRules(List<DocumentRule> value) {
    if (listEquals(_documentRules, value)) return;
    _documentRules = value;

    _subscription?.cancel();
    _subscription = _asyncObserver.stream.listen((value) async {
      if (isDisposed || isReferenceMissing) return;
      final base = value.$2.baseRevision;
      if (base != null &&
          transactionHost != null &&
          base + 1 < transactionHost!.revision) {
        return;
      }
      for (final rule in _documentRules) {
        if (rule.shouldApply(editorState: this, value: value)) {
          await rule.apply(editorState: this, value: value);
        }
      }
    });
  }

  StreamSubscription? _subscription;

  @Deprecated('use editorState.selection instead')
  Selection? _cursorSelection;

  @Deprecated('use editorState.selection instead')
  Selection? get cursorSelection {
    return _cursorSelection;
  }

  final Set<VoidCallback> _onScrollViewScrolledListeners = {};

  void addScrollViewScrolledListener(VoidCallback callback) =>
      _onScrollViewScrolledListeners.add(callback);

  void removeScrollViewScrolledListener(VoidCallback callback) =>
      _onScrollViewScrolledListeners.remove(callback);

  void _notifyScrollViewScrolledListeners() {
    for (final listener in Set.of(_onScrollViewScrolledListeners)) {
      listener.call();
    }
  }

  RenderBox? get renderBox {
    final renderObject =
        service.scrollServiceKey.currentContext?.findRenderObject();
    if (renderObject != null && renderObject is RenderBox) {
      return renderObject;
    }

    return null;
  }

  Future<void> updateSelectionWithReason(
    Selection? selection, {
    SelectionUpdateReason reason = SelectionUpdateReason.transaction,
    Map? extraInfo,
    SelectionType? customSelectionType,
  }) async {
    final completer = Completer<void>();

    if (reason == SelectionUpdateReason.uiEvent) {
      _selectionType = customSelectionType ?? SelectionType.inline;
      WidgetsBinding.instance.addPostFrameCallback(
        (timeStamp) => completer.complete(),
      );
    } else if (customSelectionType != null) {
      _selectionType = customSelectionType;
    }

    // broadcast to other users here
    selectionExtraInfo = extraInfo;
    _selectionUpdateReason = reason;

    this.selection = selection;

    if (!completer.isCompleted && reason != SelectionUpdateReason.uiEvent) {
      completer.complete();
    }

    return completer.future;
  }

  @Deprecated('use updateSelectionWithReason or editorState.selection instead')
  Future<void> updateCursorSelection(
    Selection? cursorSelection, [
    CursorUpdateReason reason = CursorUpdateReason.others,
  ]) {
    final completer = Completer<void>();

    // broadcast to other users here
    if (reason != CursorUpdateReason.uiEvent) {
      service.selectionService.updateSelection(cursorSelection);
    }
    _cursorSelection = cursorSelection;
    selection = cursorSelection;
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      completer.complete();
    });

    return completer.future;
  }

  Timer? _debouncedSealHistoryItemTimer;
  bool _imeUndoGroupActive = false;
  int _imeCompositionGeneration = 0;
  bool imeProjectionInProgress = false;
  final ValueNotifier<int> imeRefreshNotifier = ValueNotifier(0);
  final ValueNotifier<int> imeResetNotifier = ValueNotifier(0);
  bool get isImeComposing => _imeUndoGroupActive;
  int get imeCompositionGeneration => _imeCompositionGeneration;

  /// The whole IME preedit -> committed text sequence is one user intention.
  void beginImeUndoGroup([TextEditingDelta? delta]) {
    if (isDisposed || _imeUndoGroupActive) return;
    _debouncedSealHistoryItemTimer?.cancel();
    _imeUndoGroupActive = true;
    _imeCompositionGeneration++;
    if (transactionHost case final host?) {
      host.beginUndoGroup(delta: delta);
    } else if (undoManager.undoStack.isNonEmpty) {
      undoManager.undoStack.last.seal();
    }
  }

  void endImeUndoGroup([bool refreshInput = true]) {
    if (isDisposed || !_imeUndoGroupActive) return;
    _imeUndoGroupActive = false;
    _imeCompositionGeneration++;
    _debouncedSealHistoryItemTimer?.cancel();
    if (transactionHost case final host?) {
      imeProjectionInProgress = true;
      try {
        host.endUndoGroup();
      } finally {
        imeProjectionInProgress = false;
      }
    } else if (undoManager.undoStack.isNonEmpty) {
      undoManager.undoStack.last.seal();
    }
    if (refreshInput) imeRefreshNotifier.value++;
  }

  /// A conflicting shared edit invalidated this local draft, never the peer edit.
  @internal
  void resetImeComposition() {
    _imeUndoGroupActive = false;
    _imeCompositionGeneration++;
    _debouncedSealHistoryItemTimer?.cancel();
    imeResetNotifier.value++;
  }

  final bool _enableCheckIntegrity = false;

  // the value of the notifier is meaningless, just for triggering the callbacks.
  final ValueNotifier<int> onDispose = ValueNotifier(0);

  bool isDisposed = false;

  void dispose() {
    if (isDisposed) return;
    isDisposed = true;
    transactionHost?.detach();
    _textRevision++;
    _observer.close();
    _asyncObserver.close();
    _debouncedSealHistoryItemTimer?.cancel();
    onDispose.value += 1;
    onDispose.dispose();
    _blockTextCache.clear();
    _cachedText = null;
    document.dispose();
    selectionNotifier.dispose();
    remoteSelections.dispose();
    editableNotifier.dispose();
    keepEditorFocusNotifier.dispose();
    focusNotifier.dispose();
    toggledStyleNotifier.dispose();
    undoManager.dispose();
    imeRefreshNotifier.dispose();
    imeResetNotifier.dispose();
    autoScroller?.stopAutoScroll();
    autoScroller = null;
    scrollableState = null;
    _subscription?.cancel();
    _onScrollViewScrolledListeners.clear();
  }

  /// Apply the transaction to the state.
  ///
  /// The options can be used to determine whether the editor
  /// should record the transaction in undo/redo stack.
  ///
  /// The maximumRuleApplyLoop is used to prevent infinite loop.
  ///
  /// The withUpdateSelection is used to determine whether the editor
  /// should update the selection after applying the transaction.
  Future<void> apply(
    Transaction transaction, {
    bool isRemote = false,
    ApplyOptions options = const ApplyOptions(recordUndo: true),
    bool withUpdateSelection = true,
    bool skipHistoryDebounce = false,
  }) async {
    if ((!editable && !isRemote) || isDisposed) {
      return;
    }

    final host = transactionHost;
    if (host != null) {
      if (isRemote) {
        throw StateError('Apply ID changes through SharedEditorDocument.');
      }
      await host.apply(
        transaction,
        options: options,
        withUpdateSelection: withUpdateSelection,
      );
      return;
    }

    if (transaction.operations.isNotEmpty) _documentRevision++;

    // it's a time consuming task, only enable it if necessary.
    if (_enableCheckIntegrity) {
      document.root.checkDocumentIntegrity();
    }

    final completer = Completer<void>();

    if (isRemote) {
      _selectionUpdateReason = SelectionUpdateReason.remote;
      selection = _applyTransactionFromRemote(transaction);
    } else {
      // broadcast to other users here, before applying the transaction
      if (!_observer.isClosed) {
        _observer.add((TransactionTime.before, transaction, options));
      }

      if (!_asyncObserver.isClosed) {
        _asyncObserver.add((TransactionTime.before, transaction, options));
      }

      _applyTransactionInLocal(transaction);

      // broadcast to other users here, after applying the transaction
      if (!_observer.isClosed) {
        _observer.add((TransactionTime.after, transaction, options));
      }

      if (!_asyncObserver.isClosed) {
        _asyncObserver.add((TransactionTime.after, transaction, options));
      }

      _recordRedoOrUndo(options, transaction, skipHistoryDebounce);

      if (withUpdateSelection) {
        _selectionUpdateReason =
            transaction.reason ?? SelectionUpdateReason.transaction;
        _selectionType = transaction.customSelectionType;
        if (transaction.selectionExtraInfo != null) {
          selectionExtraInfo = transaction.selectionExtraInfo;
        }
        selection = transaction.afterSelection;
      }

      onInput?.call(this);
      if (characterCounter != null) {
        characterCounter!.value = textLength;
      }
    }

    completer.complete();

    return completer.future;
  }

  /// Force rebuild the editor.
  void reload() {
    document.root.notify();
  }

  /// Applies a host-prepared projection without history or outgoing callbacks.
  @internal
  void applySharedProjection(Transaction transaction) {
    if (isDisposed) return;
    if (transaction.operations.isNotEmpty) _documentRevision++;
    _applyTransactionInLocal(transaction);
    if (characterCounter != null) characterCounter!.value = textLength;
  }

  @internal
  void updateSharedSelection(
    Selection? value, {
    Transaction? localTransaction,
  }) {
    _selectionUpdateReason = localTransaction?.reason ??
        (localTransaction == null
            ? SelectionUpdateReason.remote
            : SelectionUpdateReason.transaction);
    if (localTransaction != null) {
      _selectionType = localTransaction.customSelectionType;
      if (localTransaction.selectionExtraInfo != null) {
        selectionExtraInfo = localTransaction.selectionExtraInfo;
      }
    }
    selection = value;
  }

  /// Publishes only the originating edit after every attached view is current.
  @internal
  void publishSharedTransaction(
    TransactionTime time,
    Transaction transaction,
    ApplyOptions options,
  ) {
    if (isDisposed) return;
    if (!_observer.isClosed) _observer.add((time, transaction, options));
    if (!_asyncObserver.isClosed) {
      _asyncObserver.add((time, transaction, options));
    }
    if (time == TransactionTime.after) onInput?.call(this);
  }

  /// get nodes in selection
  ///
  /// if selection is backward, return nodes in order
  /// if selection is forward, return nodes in reverse order
  ///
  List<Node> getNodesInSelection(Selection selection) {
    // Normalize the selection.
    final normalized = selection.normalized;

    // Get the start and end nodes.
    final startNode = document.nodeAtPath(normalized.start.path);
    final endNode = document.nodeAtPath(normalized.end.path);

    // If we have both nodes, we can find the nodes in the selection.
    if (startNode != null && endNode != null) {
      final nodes = NodeIterator(
        document: document,
        startNode: startNode,
        endNode: endNode,
      ).toList();

      return selection.isForward ? nodes.reversed.toList() : nodes;
    }

    // If we don't have both nodes, we can't find the nodes in the selection.
    return [];
  }

  List<Node> getSelectedNodes({
    Selection? selection,
    bool withCopy = true,
  }) {
    List<Node> res = [];
    selection ??= this.selection;
    if (selection == null) {
      return res;
    }
    final nodes = getNodesInSelection(selection);
    for (final node in nodes) {
      if (res.any((element) => element.isParentOf(node))) {
        continue;
      }
      res.add(node);
    }

    if (withCopy) {
      res = res.map((e) => e.copyWith()).toList();
    }

    if (res.isNotEmpty) {
      var delta = res.first.delta;
      if (delta != null) {
        res.first.updateAttributes(
          {
            ...res.first.attributes,
            blockComponentDelta: delta
                .slice(
                  selection.startIndex,
                  selection.isSingle ? selection.endIndex : delta.length,
                )
                .toJson(),
          },
        );
      }

      var node = res.last;
      while (node.children.isNotEmpty) {
        node = node.children.last;
      }
      delta = node.delta;
      if (delta != null && !selection.isSingle) {
        if (node.parent != null) {
          node.insertBefore(
            node.copyWith(
              attributes: {
                ...node.attributes,
                blockComponentDelta: delta
                    .slice(
                      0,
                      selection.endIndex,
                    )
                    .toJson(),
              },
            ),
          );
          node.unlink();
        } else {
          node.updateAttributes(
            {
              ...node.attributes,
              blockComponentDelta: delta
                  .slice(
                    0,
                    selection.endIndex,
                  )
                  .toJson(),
            },
          );
        }
      }
    }

    return res;
  }

  Node? getNodeAtPath(Path path) {
    return document.nodeAtPath(path);
  }

  /// The current selection areas's rect in editor.
  List<Rect> selectionRects() {
    final selection = this.selection;
    if (selection == null) {
      return [];
    }

    final nodes = getNodesInSelection(selection);
    final rects = <Rect>[];

    if (selection.isCollapsed && nodes.length == 1) {
      final selectable = nodes.first.selectable;
      if (selectable != null) {
        final rect = selectable.getCursorRectInPosition(
          selection.end,
          shiftWithBaseOffset: true,
        );
        if (rect != null) {
          rects.add(
            selectable.transformRectToGlobal(
              rect,
              shiftWithBaseOffset: true,
            ),
          );
        }
      }
    } else {
      for (final node in nodes) {
        final selectable = node.selectable;
        if (selectable == null) {
          continue;
        }
        final nodeRects = selectable.getRectsInSelection(
          selection,
          shiftWithBaseOffset: true,
        );
        if (nodeRects.isEmpty) {
          continue;
        }
        final renderBox = node.renderBox;
        if (renderBox == null) {
          continue;
        }
        for (final rect in nodeRects) {
          final globalOffset = renderBox.localToGlobal(rect.topLeft);
          rects.add(globalOffset & rect.size);
        }
      }
    }

    return rects;
  }

  void cancelSubscription() {
    _observer.close();
  }

  void updateAutoScroller(
    ScrollableState scrollableState,
  ) {
    if (this.scrollableState != scrollableState) {
      autoScroller?.stopAutoScroll();
      final bool isDesktopOrWeb = PlatformExtension.isDesktopOrWeb;
      late AutoScroller scroller;
      scroller = AutoScroller(
        scrollableState,
        velocityScalar: 0.15,
        minimumAutoScrollDelta: 0.07,
        maxAutoScrollDelta: 3.5,
        animationDuration: Duration.zero,
        onScrollViewScrolled: () {
          _notifyScrollViewScrolledListeners();
          if (!isDesktopOrWeb) {
            final dynamic dragMode = selectionExtraInfo?[_selectionDragModeKey];
            final bool isDraggingSelection = dragMode != null &&
                dragMode.toString() != 'MobileSelectionDragMode.none';
            if (!isDraggingSelection) {
              return;
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (autoScroller == scroller) {
                scroller.continueToAutoScroll();
              }
            });
          }
        },
      );
      autoScroller = scroller;
      this.scrollableState = scrollableState;
    }
  }

  void _recordRedoOrUndo(
    ApplyOptions options,
    Transaction transaction,
    bool skipDebounce,
  ) {
    final source = options.resolvedSource;
    undoManager.record(transaction, source);

    // Only debounce-seal for user edits (grouping consecutive keystrokes).
    if (source == TransactionSource.userEdit) {
      if (_imeUndoGroupActive) return;
      if (skipDebounce && undoManager.undoStack.isNonEmpty) {
        AppFlowyEditorLog.editor.debug('Seal history item');
        final last = undoManager.undoStack.last;
        last.seal();
      } else {
        _debouncedSealHistoryItem();
      }
    }
  }

  void _debouncedSealHistoryItem() {
    if (disableSealTimer) {
      return;
    }
    _debouncedSealHistoryItemTimer?.cancel();
    _debouncedSealHistoryItemTimer = Timer(minHistoryItemDuration, () {
      if (undoManager.undoStack.isNonEmpty) {
        AppFlowyEditorLog.editor.debug('Seal history item');
        final last = undoManager.undoStack.last;
        last.seal();
      }
    });
  }

  void _applyTransactionInLocal(Transaction transaction) {
    _cachedText = null;
    for (final op in transaction.operations) {
      AppFlowyEditorLog.editor.debugLazy(
        () => 'apply op (local): ${op.toJson()}',
      );
      _applyDocumentOperation(op);
    }
  }

  void _applyDocumentOperation(Operation op) {
    final root = document.root;
    final beforeCount = root.childCount;
    final previousLength = textLength;

    // Ordinary text edits change serialized length by exactly the delta's
    // inserted/deleted UTF-16 units. Avoid reserializing a long paragraph on
    // each keystroke. Structured blocks use their registered serializer.
    if (op is UpdateTextOperation && op.path.length == 1) {
      final block = root.childAtIndexOrNull(op.path.first);
      if (block != null &&
          block.hasDelta &&
          behaviorFor(block)?.serialize == null &&
          block.type != DividerBlockKeys.type) {
        if (document.updateText(op.path, op.delta)) {
          var lengthDelta = 0;
          for (final edit in op.delta) {
            if (edit is TextInsert) lengthDelta += edit.length;
            if (edit is TextDelete) lengthDelta -= edit.length;
          }
          _totalTextLength = previousLength + lengthDelta;
          _blockTextCache.remove(block);
        }
        return;
      }
    }

    final beforeBlocks = <Node>[];
    if (op.path.isNotEmpty) {
      if (op is DeleteOperation && op.path.length == 1) {
        final children = root.children;
        final start = op.path.first.clamp(0, children.length);
        final end = (start + op.nodes.length).clamp(start, children.length);
        beforeBlocks.addAll(children.getRange(start, end));
      } else if (op is! InsertOperation || op.path.length != 1) {
        final block = root.childAtIndexOrNull(op.path.first);
        if (block != null) beforeBlocks.add(block);
      }
    }
    var oldLength = 0;
    for (final block in beforeBlocks) {
      oldLength += _textForBlock(block).length;
      _blockTextCache.remove(block);
    }

    if (op is InsertOperation) {
      document.insert(op.path, op.nodes);
    } else if (op is UpdateOperation) {
      if (!mapEquals(op.attributes, op.oldAttributes)) {
        document.update(op.path, op.attributes);
      }
    } else if (op is DeleteOperation) {
      document.delete(op.path, op.nodes.length);
    } else if (op is UpdateTextOperation) {
      document.updateText(op.path, op.delta);
    }

    final afterBlocks = <Node>[];
    if (op.path.isNotEmpty) {
      if (op is InsertOperation && op.path.length == 1) {
        afterBlocks.addAll(op.nodes.where((node) => node.parent == root));
      } else if (op is! DeleteOperation || op.path.length != 1) {
        final block = root.childAtIndexOrNull(op.path.first);
        if (block != null) afterBlocks.add(block);
      }
    }
    var newLength = 0;
    for (final block in afterBlocks) {
      newLength += _textForBlock(block).length;
    }
    final afterCount = root.childCount;
    _totalTextLength = previousLength +
        newLength -
        oldLength +
        (afterCount > 0 ? afterCount - 1 : 0) -
        (beforeCount > 0 ? beforeCount - 1 : 0);
  }

  Selection? _applyTransactionFromRemote(Transaction transaction) {
    _cachedText = null;
    var selection = this.selection;

    for (final op in transaction.operations) {
      AppFlowyEditorLog.editor.debugLazy(
        () => 'apply op (remote): ${op.toJson()}',
      );

      _applyDocumentOperation(op);
      if (op is InsertOperation) {
        if (selection != null) {
          if (op.path <= selection.start.path) {
            selection = Selection(
              start: selection.start.copyWith(
                path: selection.start.path.nextNPath(op.nodes.length),
              ),
              end: selection.end.copyWith(
                path: selection.end.path.nextNPath(op.nodes.length),
              ),
            );
          }
        }
      } else if (op is DeleteOperation) {
        if (selection != null) {
          if (op.path <= selection.start.path) {
            selection = Selection(
              start: selection.start.copyWith(
                path: selection.start.path.previous,
              ),
              end: selection.end.copyWith(
                path: selection.end.path.previous,
              ),
            );
          }
        }
      }
    }

    return selection;
  }
}

extension EditorStateNodeMarkdownExtension on Node {
  void insertMarkdownDelta(Delta delta, {bool insertAfter = true}) {
    assert(delta.every((element) => element is TextInsert));
    if (this.delta == null) {
      updateAttributes({
        blockComponentDelta: delta.toJson(),
      });
    } else if (insertAfter) {
      updateAttributes(
        {
          blockComponentDelta: this
              .delta!
              .compose(
                Delta()
                  ..retain(this.delta!.length)
                  ..addAll(delta),
              )
              .toJson(),
        },
      );
    } else {
      updateAttributes(
        {
          blockComponentDelta: delta
              .compose(
                Delta()
                  ..retain(delta.length)
                  ..addAll(this.delta!),
              )
              .toJson(),
        },
      );
    }
  }
}
