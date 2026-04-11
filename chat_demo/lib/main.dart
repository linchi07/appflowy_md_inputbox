import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  runApp(const AppFlowyChatDemo());
}

class AppFlowyChatDemo extends StatelessWidget {
  const AppFlowyChatDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AppFlowy MD Input Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        fontFamily: 'Inter',
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        AppFlowyEditorLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', '')],
      home: const ChatScreen(),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isMe;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isMe,
    required this.timestamp,
  });
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [
    ChatMessage(
      text: '你好！欢迎使用 AppFlowy Markdown 输入框。',
      isMe: false,
      timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
    ChatMessage(
      text: '这是一个基于 AppFlowy Editor 改造的轻量级输入组件，支持 **Markdown** 实时预览。',
      isMe: false,
      timestamp: DateTime.now().subtract(const Duration(minutes: 4)),
    ),
  ];

  late final MDEditorController _controller;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<int> _charCount = ValueNotifier(0);
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _testInputController = TextEditingController(text: 'Hello AppFlowy!');

  @override
  void initState() {
    super.initState();
    _controller = MDEditorController(
      onInput: (text) {
        _charCount.value = text.length;
      },
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _charCount.dispose();
    _focusNode.dispose();
    _testInputController.dispose();
    super.dispose();
  }

  void _handleSend(String text) {
    if (text.trim().isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isMe: true,
        timestamp: DateTime.now(),
      ));
    });
    _controller.clear();
    _charCount.value = 0;

    // Scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AppFlowy MD Input', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Obsidian-style Handfeel', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(() => _messages.clear()),
            tooltip: '清空聊天记录',
          ),
        ],
      ),
      body: Row(
        children: [
          // Left: Chat Main Area
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(20),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _MessageBubble(message: _messages[index]);
                    },
                  ),
                ),
                _buildInputArea(),
              ],
            ),
          ),
          // Right: Test & Info Panel
          const VerticalDivider(width: 1),
          Container(
            width: 300,
            color: Colors.white,
            padding: const EdgeInsets.all(20),
            child: _buildSidePanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -2),
            blurRadius: 10,
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                const Text('Markdown 已启用', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const Spacer(),
                ValueListenableBuilder<int>(
                  valueListenable: _charCount,
                  builder: (context, count, _) {
                    return Text('$count 字符', style: const TextStyle(fontSize: 12, color: Colors.grey));
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: MDEditor(
                    controller: _controller,
                    focusNode: _focusNode,
                    multiLine: true,
                    minHeight: 45,
                    maxHeight: 200,
                    hintText: '输入内容，Enter 发送，Shift + Enter 换行...',
                    onSend: _handleSend,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F2F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.transparent),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.indigo,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: () => _handleSend(_controller.text),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('功能测试', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _TestButton(
          label: '强制聚焦',
          icon: Icons.center_focus_strong,
          onTap: () => _focusNode.requestFocus(),
        ),
        _TestButton(
          label: '插入 Markdown 模板',
          icon: Icons.description_outlined,
          onTap: () {
            _controller.text = '# 标题\n- [ ] 任务 1\n- [x] 任务 2\n\n> 引用块';
            _charCount.value = _controller.text.length;
          },
        ),
        _TestButton(
          label: '插入带缩进列表',
          icon: Icons.format_list_bulleted,
          onTap: () {
            _controller.text = '1. 第一项\n2. 第二项\n   - 子项 A\n   - 子项 B';
            _charCount.value = _controller.text.length;
          },
        ),
        _TestButton(
          label: '清空输入框',
          icon: Icons.clear_all,
          color: Colors.redAccent,
          onTap: () {
            _controller.clear();
            _charCount.value = 0;
          },
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        const Text('API 压力/功能测试', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: _testInputController,
          decoration: InputDecoration(
            hintText: '输入要设置的内容',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 12),
        _TestButton(
          label: 'Set (保留 Undo)',
          icon: Icons.edit_note,
          onTap: () {
            _controller.text = _testInputController.text;
            _charCount.value = _controller.text.length;
          },
        ),
        _TestButton(
          label: 'Set (清空 Undo)',
          icon: Icons.history_toggle_off,
          onTap: () {
            _controller.setText(_testInputController.text);
            _charCount.value = _controller.text.length;
          },
        ),
        _TestButton(
          label: 'Append (追加)',
          icon: Icons.playlist_add,
          onTap: () {
            _controller.append(_testInputController.text);
            _charCount.value = _controller.text.length;
          },
        ),
        const Spacer(),
        const Divider(),
        const Text('实时预览 (Raw)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: SingleChildScrollView(
              child: ValueListenableBuilder<int>(
                valueListenable: _charCount,
                builder: (context, _, __) {
                  return Text(
                    _controller.text,
                    style: const TextStyle(fontFamily: 'Courier', fontSize: 13),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.5),
        decoration: BoxDecoration(
          color: message.isMe ? Colors.indigo : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(message.isMe ? 16 : 0),
            bottomRight: Radius.circular(message.isMe ? 0 : 16),
          ),
          boxShadow: [
            if (!message.isMe)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.isMe ? Colors.white : Colors.black87,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

class _TestButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  const _TestButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: color ?? Colors.indigo),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 13, color: color ?? Colors.black87),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
