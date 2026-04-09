import 'package:flutter/material.dart';

import '../appflowy_editor.dart';

class MDEditorController {
  MDEditorController(){
    editorState = EditorState.blank();
  }
  late EditorState editorState;
  String get text {
    return editorState.fullText;
  }
  
  

  void clear() {
    editorState.clear();
  }

  void setText(String text){
    clear();
    editorState.insertText(0, text);
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
  @override
  State<MDEditor> createState() => _MDEditorState();
}

class _MDEditorState extends State<MDEditor> {
  EditorState get editorState => widget.controller.editorState;
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    widget.onDisposeCallback?.call();
    super.dispose();
  }

  void onSend() {
    var text = editorState.document.root.children.map((e)=>e.delta?.toPlainText()).join();
    widget.onSend?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    Widget e =  AppFlowyEditor(
      editorState: editorState,
      shrinkWrap: true,
      focusNode: widget.focusNode,
      autoFocus: true,
      blockComponentBuilders: {
        ...standardBlockComponentBuilderMap,
        ParagraphBlockKeys.type: MarkdownBlockComponentBuilder(
          configuration: BlockComponentConfiguration(
            placeholderText: (node) => widget.hintText ?? "",
          ),
        ),
      },
      editorStyle: EditorStyle.desktop(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        cursorColor: widget.frontGroundColor,
        selectionColor: widget.frontGroundColor.withAlpha(40),
      ),
      commandShortcutEvents: [
        if (widget.onSend != null) ...[
          sendShortcutEvent(onSend: onSend),
          newlineMarkdownShortcutEvent,
          ...standardCommandShortcutEvents,
        ]else ...standardCommandShortcutEvents,
      ],
    );
    if(widget.multiLine){
      e = IntrinsicHeight(
          child:e
      );
    }
    return ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: widget.minHeight??40,
          maxHeight: widget.maxHeight??double.infinity,
        ),
        child: e
    );
  }
}
