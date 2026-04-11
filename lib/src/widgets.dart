import 'package:flutter/material.dart';

import '../appflowy_editor.dart';

class MDEditorController {
  MDEditorController({
    String? initialText,
    this.onInput,
    this.characterCounter,
  }) {
    editorState = EditorState.blank();
    if (initialText != null) {
      editorState.text = initialText;
    }
    // 挂载钩子
    editorState.onInput = (state) => onInput?.call(state.text);
    editorState.characterCounter = characterCounter;
  }

  late final EditorState editorState;

  /// 输入变动的回调
  final void Function(String text)? onInput;

  /// 外部传入的字数统计 Notifier
  final ValueNotifier<int>? characterCounter;

  /// 获取当前纯文本
  String get text => editorState.text;

  /// 设置当前纯文本（会清空历史记录并重置光标）
  set text(String value) => editorState.text = value;

  /// 清空编辑器
  void clear() {
    editorState.text = '';
  }
}

class MDEditor extends StatefulWidget {
  const MDEditor({
    super.key,
    required this.controller,
    this.multiLine = false,
    this.maxHeight,
    this.minHeight,
    this.hintText,
    this.onSend,
    this.onDisposeCallback,
    this.focusNode,
    this.frontGroundColor = Colors.black,
    this.backgroundColor = Colors.white,
    this.decoration,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
  });
  final bool multiLine;
  final MDEditorController controller;
  final double? maxHeight;
  final double? minHeight;
  final String? hintText;
  final FocusNode? focusNode;
  final void Function()? onDisposeCallback;
  final void Function(String)? onSend;
  final Color frontGroundColor;
  final Color backgroundColor;
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
    Widget e = AppFlowyEditor(
      autoScrollEdgeOffset: 40,
      editorState: editorState,
      shrinkWrap: true,
      focusNode: widget.focusNode,
      autoFocus: true,
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
        cursorColor: widget.frontGroundColor,
        selectionColor: widget.frontGroundColor.withValues(alpha: 0.15),
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
    if (widget.multiLine) {
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
