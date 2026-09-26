import 'dart:collection';

import 'package:flutter/foundation.dart';

/// A value holder that notifies listeners even when the value is unchanged.

class PropertyValueNotifier<T> extends ChangeNotifier
    implements ValueListenable<T> {
  /// Creates a [ChangeNotifier] that wraps this value.
  PropertyValueNotifier(this._value);

  /// The current value stored in this notifier.
  ///
  /// When the value is replaced with something that is not equal to the old
  /// value as evaluated by the equality operator ==, this class notifies its
  /// listeners.
  @override
  T get value => _value;
  T _value;

  set value(T newValue) {
    _value = newValue;
    notifyListeners();
  }
}

/// Keeps listener removal fast when many editor blocks unmount in one frame.
/// [ChangeNotifier.removeListener] scans and shifts its array for every removal.
mixin IndexedListenerRegistry on ChangeNotifier {
  final LinkedList<_IndexedListener> _listeners =
      LinkedList<_IndexedListener>();
  final Map<VoidCallback, Queue<_IndexedListener>> _registrations = {};
  bool _disposed = false;
  int _notificationDepth = 0;

  @override
  bool get hasListeners => _listeners.isNotEmpty;

  @override
  void addListener(VoidCallback listener) {
    assert(ChangeNotifier.debugAssertNotDisposed(this));
    if (kFlutterMemoryAllocationsEnabled) {
      ChangeNotifier.maybeDispatchObjectCreation(this);
    }
    final entry = _IndexedListener(listener);
    _listeners.add(entry);
    _registrations
        .putIfAbsent(listener, Queue<_IndexedListener>.new)
        .add(entry);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_disposed) return;
    final entries = _registrations[listener];
    if (entries == null) return;
    final entry = entries.removeFirst();
    entry.active = false;
    entry.unlink();
    if (entries.isEmpty) _registrations.remove(listener);
  }

  @override
  void notifyListeners() {
    assert(ChangeNotifier.debugAssertNotDisposed(this));
    if (_listeners.isEmpty) return;
    _notificationDepth++;
    try {
      // A snapshot excludes listeners added during this notification. Entries
      // removed meanwhile are marked inactive before their turn arrives.
      for (final entry in _listeners.toList(growable: false)) {
        if (!entry.active || _disposed) continue;
        try {
          entry.callback();
        } catch (exception, stack) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: exception,
              stack: stack,
              library: 'foundation library',
              context: ErrorDescription(
                'while dispatching notifications for $runtimeType',
              ),
            ),
          );
        }
      }
    } finally {
      _notificationDepth--;
    }
  }

  @override
  void dispose() {
    assert(_notificationDepth == 0);
    _disposed = true;
    _listeners.clear();
    _registrations.clear();
    super.dispose();
  }
}

/// A property notifier with indexed listener removal.
class IndexedPropertyValueNotifier<T> extends PropertyValueNotifier<T>
    with IndexedListenerRegistry {
  IndexedPropertyValueNotifier(super.value);
}

/// A [ValueNotifier] with indexed listener removal.
class IndexedValueNotifier<T> extends ValueNotifier<T>
    with IndexedListenerRegistry {
  IndexedValueNotifier(super.value);
}

final class _IndexedListener extends LinkedListEntry<_IndexedListener> {
  _IndexedListener(this.callback);

  final VoidCallback callback;
  bool active = true;
}
