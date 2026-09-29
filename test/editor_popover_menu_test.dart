import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('popover stays within the overlay near its bottom right edge',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => GestureDetector(
            onTap: () => EditorPopoverMenu.show(
              context: context,
              anchor: const Rect.fromLTWH(770, 570, 20, 20),
              entries: [
                EditorMenuEntry(label: 'Action', onSelected: () {}),
              ],
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    final menu = tester.getRect(
      find.byKey(const ValueKey('editor-popover-menu')),
    );
    expect(menu.left, greaterThanOrEqualTo(8));
    expect(menu.top, greaterThanOrEqualTo(8));
    expect(menu.right, lessThanOrEqualTo(792));
    expect(menu.bottom, lessThanOrEqualTo(592));
    expect(menu.bottom, lessThan(570));
  });
}
