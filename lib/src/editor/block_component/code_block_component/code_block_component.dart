import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:node_code_editor/node_code_editor.dart';
import 'package:provider/provider.dart';

class CodeBlockKeys {
  const CodeBlockKeys._();
  static const type = 'code_block';
  static const language = 'language';
  static const openingFence = 'openingFence';
  static const closed = 'closed';
}

/// The delta contains editable code only; fences remain structural metadata.
Node codeBlockNode({
  required String code,
  String language = '',
  String? openingFence,
  bool closed = true,
}) =>
    Node(
      type: CodeBlockKeys.type,
      attributes: {
        blockComponentDelta: (Delta()..insert(code)).toJson(),
        CodeBlockKeys.language: language,
        CodeBlockKeys.openingFence: openingFence ?? '```$language',
        CodeBlockKeys.closed: closed,
      },
    );

String codeBlockToMarkdown(Node node) {
  final opening = node.attributes[CodeBlockKeys.openingFence] as String? ??
      '```${node.attributes[CodeBlockKeys.language] ?? ''}';
  final code = node.delta?.toPlainText() ?? '';
  final closed = node.attributes[CodeBlockKeys.closed] == true;
  return '$opening\n$code${closed ? '\n```' : ''}';
}

class CodeBlockComponentBuilder extends BlockComponentBuilder {
  CodeBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext context) =>
      CodeBlockComponentWidget(
        key: context.node.key,
        node: context.node,
        configuration: configuration,
        showActions: showActions(context.node),
        actionBuilder: (buildContext, state) => actionBuilder(context, state),
        actionTrailingBuilder: (buildContext, state) =>
            actionTrailingBuilder(context, state),
      );

  @override
  BlockComponentValidate get validate => (node) => node.delta != null;
}

class CodeBlockComponentWidget extends BlockComponentStatefulWidget {
  const CodeBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<CodeBlockComponentWidget> createState() =>
      _CodeBlockComponentWidgetState();
}

class _CodeBlockComponentWidgetState extends State<CodeBlockComponentWidget>
    with SelectableMixin, DefaultSelectableMixin, BlockComponentConfigurable {
  final _highlighter = CodeHighlighter();
  @override
  final forwardKey = GlobalKey(debugLabel: 'code_rich_text');
  @override
  GlobalKey<State<StatefulWidget>> get containerKey => widget.node.key;
  @override
  final blockComponentKey = GlobalKey(debugLabel: 'code_block');
  @override
  BlockComponentConfiguration get configuration => widget.configuration;
  @override
  Node get node => widget.node;
  late final EditorState editorState = context.read<EditorState>();

  Future<void> _chooseLanguage() async {
    final language = await showSearch<String>(
      context: context,
      delegate: _CodeLanguageSearch(),
    );
    if (!mounted ||
        language == null ||
        editorState.getNodeAtPath(node.path) != node) {
      return;
    }
    final opening = node.attributes[CodeBlockKeys.openingFence] as String? ??
        '```${node.attributes[CodeBlockKeys.language] ?? ''}';
    final indent = RegExp(r'^[ \t]*').stringMatch(opening) ?? '';
    editorState.apply(
      editorState.transaction
        ..updateNode(node, {
          CodeBlockKeys.language: language,
          CodeBlockKeys.openingFence: '$indent```$language',
        }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = editorState.editorStyle.colorScheme;
    final language = node.attributes[CodeBlockKeys.language] as String? ?? '';
    final source = node.delta?.toPlainText() ?? '';
    final dark = Theme.of(context).brightness == Brightness.dark;
    final codeStyle = TextStyle(
      fontFamily: 'monospace',
      height: 1.45,
    );
    Widget child = Container(
      key: markdownCodeBlockKey,
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.subtleBackground,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const ValueKey('code-language-picker'),
                      onPressed: editorState.editable ? _chooseLanguage : null,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(28, 24),
                        alignment: Alignment.centerLeft,
                      ),
                      child: Text(
                        language.isEmpty ? 'Plain text' : language,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.foreground.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('copy-code-block'),
                  tooltip: 'Copy code',
                  icon: const Icon(Icons.copy, size: 15),
                  iconSize: 15,
                  constraints:
                      const BoxConstraints.tightFor(width: 28, height: 28),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: source)),
                ),
              ],
            ),
          ),
          AppFlowyRichText(
            key: forwardKey,
            delegate: this,
            node: node,
            editorState: editorState,
            placeholderText: ' ',
            textDirection: TextDirection.ltr,
            textSpanDecorator: (span) => span.updateTextStyle(codeStyle),
            textSpanDecoratorForCustomAttributes:
                (context, node, offset, insert, before, after) {
              // Completion inserts are display-only and extend past the
              // document text. Keep their ghost/transparent styling intact.
              if (insert.attributes?.autoComplete == true ||
                  insert.attributes?.transparent == true ||
                  offset + insert.text.length > source.length) {
                return before;
              }
              return _highlighter.spanForSegment(
                source: source,
                language: language,
                start: offset,
                segment: insert.text,
                style: (before.style ?? const TextStyle())
                    .merge(codeStyle)
                    .copyWith(color: colors.foreground),
                dark: dark,
              );
            },
            cursorColor: editorState.editorStyle.cursorColor,
            selectionColor: editorState.editorStyle.selectionColor,
            cursorWidth: editorState.editorStyle.cursorWidth,
          ),
        ],
      ),
    );
    child = Container(key: blockComponentKey, child: child);
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

class _CodeLanguageSearch extends SearchDelegate<String> {
  @override
  String get searchFieldLabel => 'Code language';

  @override
  List<Widget> buildActions(BuildContext context) => [
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      );

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    final filtered = CodeHighlighter.supportedLanguages
        .where((name) => name.contains(query.toLowerCase().trim()))
        .toList();
    return ListView.builder(
      itemCount: filtered.length + (query.isEmpty ? 1 : 0),
      itemBuilder: (context, index) {
        if (query.isEmpty && index == 0) {
          return ListTile(
            title: const Text('Plain text'),
            onTap: () => close(context, ''),
          );
        }
        final name = filtered[index - (query.isEmpty ? 1 : 0)];
        return ListTile(
          title: Text(name),
          onTap: () => close(context, name),
        );
      },
    );
  }
}
