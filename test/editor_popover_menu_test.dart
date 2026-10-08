import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('search uses editor colors and keyboard skips disabled actions',
      (tester) async {
    String? selected;
    final openerFocus = FocusNode();
    const colors = EditorColorScheme.dark(primary: Colors.orange);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        ),
        home: EditorTheme(
          colors: colors,
          child: Builder(
            builder: (context) => TextButton(
              focusNode: openerFocus,
              onPressed: () => EditorPopoverMenu.show(
                context: context,
                anchor: const Rect.fromLTWH(20, 20, 80, 20),
                searchHint: 'Search actions',
                entries: [
                  EditorMenuEntry(
                    label: 'Rust',
                    onSelected: () => selected = 'Rust',
                  ),
                  EditorMenuEntry(
                    label: 'Ruby',
                    enabled: false,
                    onSelected: () => selected = 'Ruby',
                  ),
                  EditorMenuEntry(
                    label: 'Racket',
                    onSelected: () => selected = 'Racket',
                  ),
                ],
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    openerFocus.requestFocus();
    await tester.pump();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.style?.color, colors.onSurface);
    expect(field.cursorColor, colors.primary);
    expect(
      (field.decoration!.focusedBorder! as OutlineInputBorder).borderSide.color,
      colors.primary,
    );
    final surface = tester.element(find.byType(EditorMenuSurface));
    expect(EditorMenuSurface.decoration(surface).color, colors.surface);

    await tester.enterText(find.byType(TextField), 'r');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 'Racket');
    expect(find.byType(EditorMenuSurface), findsNothing);
    expect(openerFocus.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    openerFocus.dispose();
  });

  testWidgets('empty search can be dismissed with Escape', (tester) async {
    var dismissals = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => EditorPopoverMenu.show(
              context: context,
              anchor: const Rect.fromLTWH(20, 20, 80, 20),
              searchHint: 'Search',
              entries: [EditorMenuEntry(label: 'Action', onSelected: () {})],
              onDismiss: () => dismissals++,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump();
    expect(find.text('No results'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(dismissals, 1);
    expect(find.byType(EditorMenuSurface), findsNothing);
  });

  testWidgets('keyboard navigation scrolls long menus to the active action',
      (tester) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => EditorPopoverMenu.show(
              context: context,
              anchor: const Rect.fromLTWH(20, 20, 80, 20),
              maxHeight: 160,
              entries: [
                for (var i = 0; i < 40; i++)
                  EditorMenuEntry(
                    label: 'Action $i',
                    onSelected: () => selected = i,
                  ),
              ],
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    final item = tester.getRect(find.text('Action 39'));
    final menu = tester.getRect(find.byType(EditorMenuSurface));
    expect(item.bottom, lessThanOrEqualTo(menu.bottom));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 39);
  });

  testWidgets('footer input keeps its own Enter action', (tester) async {
    var selected = false;
    String? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => EditorPopoverMenu.show(
              context: context,
              anchor: const Rect.fromLTWH(20, 20, 80, 20),
              entries: [
                EditorMenuEntry(
                  label: 'Preset',
                  onSelected: () => selected = true,
                ),
              ],
              footerHeight: 44,
              footerBuilder: (context, dismiss) => EditorMenuTextField(
                onSubmitted: (value) {
                  submitted = value;
                  dismiss();
                },
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '#aabbcc');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, isFalse);
    expect(find.byType(EditorMenuSurface), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(submitted, '#aabbcc');
    expect(find.byType(EditorMenuSurface), findsNothing);
  });
}
