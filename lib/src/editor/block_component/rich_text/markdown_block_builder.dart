import 'package:flutter/material.dart';
import '../../../../appflowy_editor.dart';

class MarkdownBlockComponentBuilder extends BlockComponentBuilder {
  MarkdownBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return MarkdownBlockComponentWidget(
      node: node,
      key: node.key,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
      actionTrailingBuilder: (context, state) =>
          actionTrailingBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate =>
      (node) => node.delta != null;
}

class MarkdownBlockComponentWidget extends BlockComponentStatefulWidget {
  const MarkdownBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<MarkdownBlockComponentWidget> createState() =>
      _MarkdownBlockComponentWidgetState();
}

class _MarkdownBlockComponentWidgetState
    extends State<MarkdownBlockComponentWidget>
    with
        SelectableMixin,
        DefaultSelectableMixin,
        BlockComponentConfigurable,
        BlockComponentBackgroundColorMixin,
        NestedBlockComponentStatefulWidgetMixin,
        BlockComponentTextDirectionMixin,
        BlockComponentAlignMixin {
  @override
  final forwardKey = GlobalKey(debugLabel: 'flowy_rich_text');

  @override
  GlobalKey<State<StatefulWidget>> get containerKey => widget.node.key;

  @override
  GlobalKey<State<StatefulWidget>> blockComponentKey = GlobalKey(
    debugLabel: 'markdown_block',
  );

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  bool _showPlaceholder = false;

  @override
  void initState() {
    super.initState();
    editorState.selectionNotifier.addListener(_onSelectionChange);
    _onSelectionChange();
  }

  @override
  void dispose() {
    editorState.selectionNotifier.removeListener(_onSelectionChange);
    super.dispose();
  }

  void _onSelectionChange() {
    final selection = editorState.selection;
    final showPlaceholder =
        selection != null &&
        (selection.isSingle && selection.start.path.equals(node.path));
    if (showPlaceholder != _showPlaceholder) {
      if (mounted) setState(() => _showPlaceholder = showPlaceholder);
    }
  }

  @override
  Widget buildComponent(
    BuildContext context, {
    bool withBackgroundColor = true,
  }) {
    final text = node.delta?.toPlainText() ?? '';
    bool isQuote = text.startsWith('> ');
    bool isTodo = text.startsWith('- [ ]') || text.startsWith('- [x]');
    bool isList =
        !isTodo &&
        (text.startsWith('- ') ||
            text.startsWith('* ') ||
            RegExp(r'^\d+\. ').hasMatch(text));

    final textDirection = calculateTextDirection(
      layoutDirection: Directionality.maybeOf(context),
    );

    Widget richText = AppFlowyRichText(
      key: forwardKey,
      delegate: this,
      node: widget.node,
      editorState: editorState,
      textAlign: alignment?.toTextAlign ?? textAlign,
      placeholderText: _showPlaceholder ? placeholderText : ' ',
      textDirection: textDirection,
      textSpanDecorator: (textSpan) =>
          textSpan.updateTextStyle(textStyleWithTextSpan(textSpan: textSpan)),
      placeholderTextSpanDecorator: (textSpan) => textSpan.updateTextStyle(
        placeholderTextStyleWithTextSpan(textSpan: textSpan),
      ),
      cursorColor: editorState.editorStyle.cursorColor,
      selectionColor: editorState.editorStyle.selectionColor,
      cursorWidth: editorState.editorStyle.cursorWidth,
    );

    Widget child = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      textDirection: textDirection,
      children: [richText],
    );

    if (isQuote) {
      child = Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Colors.blue.withValues(alpha: 0.5),
              width: 4,
            ),
          ),
        ),
        padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: child,
      );
    } else if (isList || isTodo) {
      child = Padding(padding: const EdgeInsets.only(left: 8), child: child);
    }

    child = Container(
      key: blockComponentKey,
      alignment: Alignment.centerLeft,
      decoration: withBackgroundColor ? decoration : null,
      padding: padding,
      child: child,
    );

    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [BlockSelectionType.block],
      child: child,
    );

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    return child;
  }
}
