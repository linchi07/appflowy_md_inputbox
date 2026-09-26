import 'package:appflowy_editor/src/editor/util/property_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

class _ListenerOwner {
  int calls = 0;
  void onChange() => calls++;
}

void main() {
  test('indexed notifier preserves duplicate listener registrations', () {
    final notifier = IndexedPropertyValueNotifier<int>(0);
    var calls = 0;
    void listener() => calls++;

    notifier
      ..addListener(listener)
      ..addListener(listener);
    notifier.value = 0;
    expect(calls, 2);

    notifier.removeListener(listener);
    notifier.value = 1;
    expect(calls, 3);

    notifier
      ..removeListener(listener)
      ..removeListener(listener);
    notifier.value = 2;
    expect(calls, 3);
    notifier.dispose();
    notifier.removeListener(listener);
  });

  test('listeners added or removed during notification wait for next turn', () {
    final notifier = IndexedPropertyValueNotifier<int>(0);
    final calls = <String>[];
    void removed() => calls.add('removed');
    void added() => calls.add('added');
    void first() {
      calls.add('first');
      notifier.removeListener(removed);
      notifier.addListener(added);
    }

    notifier
      ..addListener(first)
      ..addListener(removed);
    notifier.value = 1;
    expect(calls, ['first']);

    notifier.value = 2;
    expect(calls, ['first', 'first', 'added']);
    notifier.dispose();
  });

  test('bulk teardown clears all registered block listeners', () {
    final notifier = IndexedPropertyValueNotifier<int>(0);
    var calls = 0;
    final listeners = List.generate(10000, (_) => () => calls++);
    for (final listener in listeners) {
      notifier.addListener(listener);
    }
    for (final listener in listeners) {
      notifier.removeListener(listener);
    }

    notifier.value = 1;
    expect(calls, 0);
    notifier.dispose();
  });

  test('indexed value notifier only notifies when the value changes', () {
    final notifier = IndexedValueNotifier<bool>(false);
    var calls = 0;
    notifier.addListener(() => calls++);
    notifier.value = false;
    notifier.value = true;
    notifier.value = true;
    expect(calls, 1);
    notifier.dispose();
  });

  test('a new bound method tear-off removes the registered listener', () {
    final notifier = IndexedPropertyValueNotifier<int>(0);
    final owner = _ListenerOwner();
    notifier.addListener(owner.onChange);
    notifier.removeListener(owner.onChange);
    notifier.value = 1;
    expect(owner.calls, 0);
    notifier.dispose();
  });
}
