import 'dart:ui';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/scheduler.dart';

void main() => runApp(const MarkdownLabApp());

class MarkdownLabApp extends StatelessWidget {
  const MarkdownLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Markdown + LaTeX Lab',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
        scaffoldBackgroundColor: const Color(0xFFF5F3FA),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        AppFlowyEditorLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      home: const MarkdownLabPage(),
    );
  }
}

enum LabMode { edit, preview }

class MarkdownLabPage extends StatefulWidget {
  const MarkdownLabPage({super.key});

  @override
  State<MarkdownLabPage> createState() => _MarkdownLabPageState();
}

class _MarkdownLabPageState extends State<MarkdownLabPage> {
  static const _sample = r'''# Markdown + LaTeX 实验室

这是一个接近 Obsidian Live Preview 手感的输入框。

## 行内公式

质能方程是 $E = mc^2$，欧拉恒等式是 $e^{i\pi} + 1 = 0$。

概率密度可以写成 $f(x)=\frac{1}{\sqrt{2\pi}}e^{-x^2/2}$。

## 单行展示公式

$$\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}$$

$$\sum_{n=1}^{\infty}\frac{1}{n^2}=\frac{\pi^2}{6}$$

## Markdown

- [x] 光标在公式中时显示源码
- [x] 离开公式后显示排版结果
- [ ] 尝试修改上面的分数、积分和求和

> 点击已经渲染的公式，可以回到公式源码继续编辑。

普通的 **粗体**、*斜体*、~~删除线~~ 和 `inline code` 也可以一起工作。''';

  late final MDEditorController _controller;
  final FocusNode _focusNode = FocusNode();
  final ValueNotifier<int> _characterCount = ValueNotifier(_sample.length);
  final List<double> _buildTimes = [];
  final List<double> _rasterTimes = [];
  LabMode _mode = LabMode.edit;
  int _paragraphCount = _sample.split('\n').length;

  @override
  void initState() {
    super.initState();
    _controller = MDEditorController(
      initialText: _sample,
      characterCounter: _characterCount,
      onInput: (text) => _paragraphCount = text.split('\n').length,
    );
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _focusNode.dispose();
    _characterCount.dispose();
    super.dispose();
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!mounted) return;
    for (final timing in timings) {
      _buildTimes.add(timing.buildDuration.inMicroseconds / 1000);
      _rasterTimes.add(timing.rasterDuration.inMicroseconds / 1000);
    }
    if (_buildTimes.length > 120) {
      _buildTimes.removeRange(0, _buildTimes.length - 120);
      _rasterTimes.removeRange(0, _rasterTimes.length - 120);
    }
  }

  void _setMode(LabMode mode) {
    if (_mode == mode) return;
    _focusNode.unfocus();
    _controller.editorState.updateSelectionWithReason(null);
    setState(() => _mode = mode);
    if (mode == LabMode.edit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  void _loadStressDocument(int formulaCount) {
    final buffer = StringBuffer('# $formulaCount 条公式压力样本\n\n');
    for (var i = 1; i <= formulaCount; i++) {
      buffer.writeln(
        '第 $i 条：\$x_$i^2 + y_$i^2 = r_$i^2\$，'
        '以及 \$\\frac{$i}{${i + 1}} + \\sqrt{$i}\$。',
      );
    }
    final text = buffer.toString();
    _controller.text = text;
    _characterCount.value = text.length;
    _paragraphCount = formulaCount + 2;
    setState(() {});
  }

  void _restoreSample() {
    _controller.text = _sample;
    _characterCount.value = _sample.length;
    _paragraphCount = _sample.split('\n').length;
    setState(() {});
  }

  double _average(List<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  @override
  Widget build(BuildContext context) {
    final preview = _mode == LabMode.preview;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              _Toolbar(
                mode: _mode,
                onModeChanged: _setMode,
                onRestore: _restoreSample,
                onStress: _loadStressDocument,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE4DFEC)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x10000000),
                              blurRadius: 24,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: MDEditor(
                            key: ValueKey(_mode),
                            controller: _controller,
                            focusNode: _focusNode,
                            editable: !preview,
                            shrinkWrap: false,
                            minCacheExtent: 900,
                            multiLine: true,
                            hintText: '在这里输入 Markdown 和 LaTeX…',
                            padding: const EdgeInsets.symmetric(
                              horizontal: 48,
                              vertical: 4,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 250,
                      child: _MetricsPanel(
                        preview: preview,
                        characterCount: _characterCount,
                        paragraphCount: _paragraphCount,
                        averageBuildMs: _average(_buildTimes),
                        averageRasterMs: _average(_rasterTimes),
                        sampleCount: _buildTimes.length,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.mode,
    required this.onModeChanged,
    required this.onRestore,
    required this.onStress,
  });

  final LabMode mode;
  final ValueChanged<LabMode> onModeChanged;
  final VoidCallback onRestore;
  final ValueChanged<int> onStress;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.functions_rounded, size: 30),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Markdown + LaTeX Lab',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            Text('大输入框 / Live Preview / 压力实验'),
          ],
        ),
        const Spacer(),
        SegmentedButton<LabMode>(
          segments: const [
            ButtonSegment(
              value: LabMode.edit,
              icon: Icon(Icons.edit_outlined),
              label: Text('编辑'),
            ),
            ButtonSegment(
              value: LabMode.preview,
              icon: Icon(Icons.visibility_outlined),
              label: Text('纯预览'),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (value) => onModeChanged(value.first),
        ),
        const SizedBox(width: 12),
        PopupMenuButton<VoidCallback>(
          tooltip: '加载样本',
          onSelected: (callback) => callback(),
          itemBuilder: (_) => [
            PopupMenuItem(value: onRestore, child: const Text('恢复演示内容')),
            PopupMenuItem(
              value: () => onStress(100),
              child: const Text('加载 100 条公式'),
            ),
            PopupMenuItem(
              value: () => onStress(500),
              child: const Text('加载 500 条公式'),
            ),
          ],
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.science_outlined),
                SizedBox(width: 8),
                Text('压力样本'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({
    required this.preview,
    required this.characterCount,
    required this.paragraphCount,
    required this.averageBuildMs,
    required this.averageRasterMs,
    required this.sampleCount,
  });

  final bool preview;
  final ValueNotifier<int> characterCount;
  final int paragraphCount;
  final double averageBuildMs;
  final double averageRasterMs;
  final int sampleCount;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF211F26),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              preview ? 'PURE PREVIEW' : 'LIVE EDITING',
              style: TextStyle(
                color: preview
                    ? const Color(0xFFB6F2C2)
                    : const Color(0xFFD0BCFF),
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 24),
            ValueListenableBuilder<int>(
              valueListenable: characterCount,
              builder: (_, value, __) => _Metric('字符', '$value'),
            ),
            _Metric('段落', '$paragraphCount'),
            _Metric('采样帧', '$sampleCount / 120'),
            const Divider(color: Colors.white24, height: 32),
            _Metric('平均 Build', '${averageBuildMs.toStringAsFixed(2)} ms'),
            _Metric('平均 Raster', '${averageRasterMs.toStringAsFixed(2)} ms'),
            const SizedBox(height: 12),
            Text(
              sampleCount == 0
                  ? '运行 Profile 模式并滚动页面以采集帧数据；切换模式可刷新读数。'
                  : averageBuildMs < 8 && averageRasterMs < 8
                  ? '当前采样余量充足。'
                  : '当前采样需要进一步 Profile。',
              style: const TextStyle(color: Colors.white60, height: 1.5),
            ),
            const Spacer(),
            const Text(
              '建议使用：\nflutter run -d macos --profile',
              style: TextStyle(
                color: Colors.white54,
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white60)),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
