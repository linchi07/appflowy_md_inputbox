import 'dart:async';

import 'package:flutter/material.dart';

import '../appflowy_editor.dart';

class MDEditorController {
  MDEditorController({
    String? initialText,
    this.onInput,
    this.characterCounter,
    this.inputDebounce = Duration.zero,
    this.maxHistoryItemSize = 30,
  }) {
    editorState = EditorState.blank(
      maxHistoryItemSize: maxHistoryItemSize,
    );
    if (initialText != null) {
      editorState.text = initialText;
      characterCounter?.value = initialText.length;
    }
    editorState.onInput = _handleInput;
  }

  factory MDEditorController.largeDocument({
    String? initialText,
    void Function(String text)? onInput,
    ValueNotifier<int>? characterCounter,
    Duration inputDebounce = const Duration(milliseconds: 150),
    int maxHistoryItemSize = 200,
  }) =>
      MDEditorController(
        initialText: initialText,
        onInput: onInput,
        characterCounter: characterCounter,
        inputDebounce: inputDebounce,
        maxHistoryItemSize: maxHistoryItemSize,
      );

  late final EditorState editorState;

  /// 输入变动的回调
  final void Function(String text)? onInput;

  /// 外部传入的字数统计 Notifier
  final ValueNotifier<int>? characterCounter;

  /// Coalesces whole-document serialization for large documents.
  final Duration inputDebounce;

  /// Maximum number of undo groups retained by this controller.
  final int maxHistoryItemSize;

  Timer? _inputTimer;
  bool _isDisposed = false;

  void _handleInput(EditorState state) {
    _inputTimer?.cancel();
    if (inputDebounce == Duration.zero) {
      _emitInput(state);
    } else {
      _inputTimer = Timer(inputDebounce, () => _emitInput(state));
    }
  }

  void _emitInput(EditorState state) {
    if (_isDisposed) return;
    final currentText = state.text;
    characterCounter?.value = currentText.length;
    onInput?.call(currentText);
  }

  /// 获取当前纯文本
  String get text => editorState.text;

  /// 设置当前纯文本（会清空历史记录并重置光标）
  set text(String value) => editorState.text = value;

  /// Sets text and completes after large-document parsing has finished.
  Future<void> setText(String value) => editorState.setText(value);

  /// 清空编辑器
  void clear() {
    editorState.text = '';
  }

  /// Releases the document, undo history, streams, timers, and notifiers.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _inputTimer?.cancel();
    editorState.onInput = null;
    editorState.dispose();
  }
}

class MDEditor extends StatefulWidget {
  const MDEditor({
    super.key,
    required this.controller,
    this.multiLine = false,
    this.editable = true,
    this.autoFocus = false,
    this.shrinkWrap = true,
    this.minCacheExtent,
    this.maxHeight,
    this.minHeight,
    this.hintText,
    this.onSend,
    this.onDisposeCallback,
    this.focusNode,
    this.frontGroundColor = Colors.black,
    this.backgroundColor = Colors.white,
    this.colorScheme,
    this.decoration,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
  });
  final bool multiLine;
  final bool editable;
  final bool autoFocus;
  final bool shrinkWrap;
  final double? minCacheExtent;
  final MDEditorController controller;
  final double? maxHeight;
  final double? minHeight;
  final String? hintText;
  final FocusNode? focusNode;
  final void Function()? onDisposeCallback;
  final void Function(String)? onSend;
  final Color frontGroundColor;
  final Color backgroundColor;
  final MDEditorColorScheme? colorScheme;
  final Decoration? decoration;
  final EdgeInsets padding;
  @override
  State<MDEditor> createState() => _MDEditorState();
}

class _MDEditorState extends State<MDEditor> {
  EditorState get editorState => widget.controller.editorState;
  @override
  void dispose() {
    widget.onDisposeCallback?.call();
    super.dispose();
  }

  void onSend() {
    widget.onSend?.call(editorState.text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colorScheme ??
        MDEditorColorScheme.light(
          foreground: widget.frontGroundColor,
          background: widget.backgroundColor,
          primary: widget.frontGroundColor,
          selection: widget.frontGroundColor.withValues(alpha: 0.15),
        );
    Widget e = AppFlowyEditor(
      autoScrollEdgeOffset: 40,
      editorState: editorState,
      shrinkWrap: widget.shrinkWrap,
      minCacheExtent: widget.minCacheExtent,
      focusNode: widget.focusNode,
      autoFocus: widget.editable && widget.autoFocus,
      editable: widget.editable,
      disableKeyboardService: !widget.editable,
      disableSelectionService: !widget.editable,
      disableAutoScroll: !widget.editable,
      blockComponentBuilders: {
        ...standardBlockComponentBuilderMap,
        ParagraphBlockKeys.type: MarkdownBlockComponentBuilder(
          configuration: BlockComponentConfiguration(
            placeholderText: (node) =>
                widget.hintText ?? AppFlowyEditorL10n.current.slashPlaceHolder,
          ),
        ),
      },
      editorStyle: EditorStyle.desktop(
        padding: widget.padding,
        cursorColor: colors.primary,
        selectionColor: colors.selection,
        colorScheme: colors,
        textStyleConfiguration: TextStyleConfiguration(
          text: TextStyle(fontSize: 16, color: colors.foreground),
        ),
      ),
      commandShortcutEvents: [
        if (widget.onSend != null) ...[
          sendShortcutEvent(onSend: onSend),
          newlineMarkdownShortcutEvent,
          ...standardCommandShortcutEvents.where(
            (e) => e.key != enterMarkdownShortcutEvent.key,
          ),
        ] else
          ...standardCommandShortcutEvents,
      ],
    );
    e = ColoredBox(color: colors.background, child: e);
    if (widget.multiLine && widget.shrinkWrap) {
      e = IntrinsicHeight(child: e);
    }

    if (widget.decoration != null) {
      e = DecoratedBox(
        decoration: widget.decoration!,
        child: e,
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: widget.minHeight ?? 40,
        maxHeight: widget.maxHeight ?? double.infinity,
      ),
      child: e,
    );
  }
}
