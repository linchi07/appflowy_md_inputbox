import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';



void main() {
  runApp(const MinimalTestApp());
}

class MinimalTestApp extends StatelessWidget {
  const MinimalTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        AppFlowyEditorLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', ''), Locale('zh', '')],
      home: const MinimalEditorPage(),
    );
  }
}

class MinimalEditorPage extends StatefulWidget {
  const MinimalEditorPage({super.key});

  @override
  State<MinimalEditorPage> createState() => _MinimalEditorPageState();
}

class _MinimalEditorPageState extends State<MinimalEditorPage> {
  late EditorState editorState;

  @override
  void initState() {
    super.initState();
    editorState = EditorState.blank();
  }

  void _handleSend() {
    debugPrint('发送消息: ${editorState.toPlainText()}');
    editorState.clear();
  }

  @override
  Widget build(BuildContext context) {
    var s = MediaQuery.of(context).size;
    return Scaffold(
      appBar: AppBar(title: const Text('AppFlowy Editor Minimal Test')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Container(
              width: 531,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blueAccent),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: s.height * 0.5),
                child: IntrinsicHeight(
                  child: AppFlowyEditor(
                    editorState: editorState,
                    shrinkWrap: true,
                    autoFocus: true,
                    blockComponentBuilders: {
                      ...standardBlockComponentBuilderMap,
                      ParagraphBlockKeys.type: MarkdownBlockComponentBuilder(
                        configuration: BlockComponentConfiguration(
                          placeholderText: (node) => '请输入内容...',
                        ),
                      ),
                    },
                    editorStyle: EditorStyle.desktop(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 3,
                      ),
                      cursorColor: Colors.blue,
                      selectionColor: Colors.blue.withValues(alpha: 0.2),
                    ),
                    commandShortcutEvents: [
                      sendShortcutEvent(onSend: _handleSend),
                      newlineMarkdownShortcutEvent,
                      ...standardCommandShortcutEvents.where(
                        (e) => e.key != newlineMarkdownShortcutEvent.key,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.only(left: 20),
            child: Text('请在此反复输入文字并按 ↑ 键测试卡死情况'),
          ),
        ],
      ),
    );
  }
}
