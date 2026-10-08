import 'dart:async';

import 'package:flutter/material.dart';

import '../appflowy_editor.dart';
import 'editor/util/platform_extension.dart';

final _markdownDocumentRules = <DocumentRule>[
  codeFencePromotionRule,
  dividerPromotionRule,
];

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
    editorState.nodeBehaviors = {
      ParagraphBlockKeys.type: codeFenceDraftParagraphBehavior,
      CodeBlockKeys.type: codeNodeBehavior,
    };
    editorState.documentRules = _markdownDocumentRules;
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
    characterCounter?.value = state.textLength;
    if (onInput == null) return;
    _inputTimer?.cancel();
    if (inputDebounce == Duration.zero) {
      _emitInput(state);
    } else {
      _inputTimer = Timer(inputDebounce, () => _emitInput(state));
    }
  }

  void _emitInput(EditorState state) {
    if (_isDisposed) return;
    onInput?.call(state.text);
  }

  /// 获取当前纯文本
  String get text => editorState.text;

  /// 设置当前纯文本（会清空历史记录并重置光标）
  set text(String value) => editorState.text = value;

  /// 重新设置文档内容并将光标移至末尾，**会清空**撤销/重做历史。
  Future<void> setText(String value) => editorState.setText(value);

  /// 在现有内容后追加文本并将光标移至末尾，保留撤销/重做历史。
  Future<void> append(String value) => editorState.append(value);

  /// 清空编辑器
  void clear() {
    editorState.setText('');
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
    this.useIndexedScrollbar = true,
    this.maxHeight,
    this.minHeight,
    this.hintText,
    this.onSend,
    this.focusNode,
    this.frontGroundColor,
    this.backgroundColor,
    this.colorScheme,
    this.contextMenuBuilder = defaultContextMenuBuilder,
    this.decoration,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    this.onPaste,
    this.showMagnifier = true,
    this.maxMarkdownDecorationCharacters = 64 * 1024,
  });
  final bool multiLine;
  final bool editable;
  final bool autoFocus;
  final bool shrinkWrap;
  final double? minCacheExtent;
  final bool useIndexedScrollbar;
  final MDEditorController controller;
  final double? maxHeight;
  final double? minHeight;
  final String? hintText;
  final FocusNode? focusNode;
  final void Function(String)? onSend;
  final FutureOr<bool> Function()? onPaste;
  final Color? frontGroundColor;
  final Color? backgroundColor;
  final EditorColorScheme? colorScheme;
  final ContextMenuWidgetBuilder? contextMenuBuilder;
  final Decoration? decoration;
  final EdgeInsets padding;
  final bool showMagnifier;
  final int? maxMarkdownDecorationCharacters;
  @override
  State<MDEditor> createState() => _MDEditorState();
}

class _MDEditorState extends State<MDEditor> {
  EditorState get editorState => widget.controller.editorState;

  void onSend() {
    widget.onSend?.call(editorState.text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colorScheme ??
        const EditorColorScheme.light().copyWith(
          foreground: widget.frontGroundColor,
          background: widget.backgroundColor,
          surface: widget.backgroundColor,
          onSurface: widget.frontGroundColor,
          // Preserve the old foreground-as-cursor behavior for this API.
          primary: widget.frontGroundColor,
          selection: widget.frontGroundColor?.withValues(alpha: 0.15),
        );
    final selectionMenuStyle = SelectionMenuStyle.fromScheme(colors);
    final textStyleConfiguration = TextStyleConfiguration(
      text: TextStyle(fontSize: 16, color: colors.foreground),
    );
    final editorStyle = PlatformExtension.isMobile
        ? EditorStyle.mobile(
            padding: widget.padding,
            cursorColor: colors.primary,
            dragHandleColor: colors.primary,
            selectionColor: colors.selection,
            selectionMenuStyle: selectionMenuStyle,
            colorScheme: colors,
            textStyleConfiguration: textStyleConfiguration,
            maxMarkdownDecorationCharacters:
                widget.maxMarkdownDecorationCharacters,
          )
        : EditorStyle.desktop(
            padding: widget.padding,
            cursorColor: colors.primary,
            selectionColor: colors.selection,
            selectionMenuStyle: selectionMenuStyle,
            colorScheme: colors,
            textStyleConfiguration: textStyleConfiguration,
            maxMarkdownDecorationCharacters:
                widget.maxMarkdownDecorationCharacters,
          );
    Widget e = AppFlowyEditor(
      autoScrollEdgeOffset: 40,
      editorState: editorState,
      shrinkWrap: widget.shrinkWrap,
      minCacheExtent: widget.minCacheExtent,
      useIndexedScrollbar: widget.useIndexedScrollbar && !widget.shrinkWrap,
      focusNode: widget.focusNode,
      autoFocus: widget.editable && widget.autoFocus,
      editable: widget.editable,
      disableKeyboardService: !widget.editable,
      disableSelectionService: !widget.editable,
      disableAutoScroll: !widget.editable,
      showMagnifier: widget.showMagnifier,
      onPaste: widget.onPaste,
      blockComponentBuilders: {
        ...standardBlockComponentBuilderMap,
        CodeBlockKeys.type: CodeBlockComponentBuilder(),
        ParagraphBlockKeys.type: MarkdownBlockComponentBuilder(
          configuration: BlockComponentConfiguration(
            placeholderText: (node) =>
                widget.hintText ?? AppFlowyEditorL10n.current.slashPlaceHolder,
          ),
        ),
      },
      editorStyle: editorStyle,
      contextMenuBuilder: widget.contextMenuBuilder,
      nodeBehaviors: {
        ParagraphBlockKeys.type: codeFenceDraftParagraphBehavior,
        CodeBlockKeys.type: codeNodeBehavior,
      },
      documentRules: _markdownDocumentRules,
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
