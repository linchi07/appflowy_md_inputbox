import 'package:chat_demo/main.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('switches between editing and pure preview', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MarkdownLabApp());
    await tester.pumpAndSettle();

    expect(find.text('LIVE EDITING'), findsOneWidget);
    expect(
      tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor)).editable,
      isTrue,
    );

    await tester.tap(find.text('纯预览'));
    await tester.pumpAndSettle();

    expect(find.text('PURE PREVIEW'), findsOneWidget);
    final preview = tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor));
    expect(preview.editable, isFalse);
    expect(preview.disableKeyboardService, isTrue);
    expect(preview.disableSelectionService, isTrue);
  });
}
