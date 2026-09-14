import 'package:flutter/widgets.dart';

typedef KeyboardHeightCallback = void Function(double height);

/// Shares Flutter's keyboard inset notifications between editor instances.
class KeyboardHeightObserver with WidgetsBindingObserver {
  KeyboardHeightObserver._() {
    WidgetsBinding.instance.addObserver(this);
    _updateHeight();
  }

  static final KeyboardHeightObserver instance = KeyboardHeightObserver._();
  static double currentKeyboardHeight = 0;

  final List<KeyboardHeightCallback> _listeners = [];

  void addListener(KeyboardHeightCallback listener) {
    if (!_listeners.contains(listener)) _listeners.add(listener);
  }

  void removeListener(KeyboardHeightCallback listener) {
    _listeners.remove(listener);
  }

  @override
  void didChangeMetrics() => _updateHeight();

  void _updateHeight() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final view = views.first;
    final height = view.viewInsets.bottom / view.devicePixelRatio;
    if (height == currentKeyboardHeight) return;
    currentKeyboardHeight = height;
    for (final listener in List.of(_listeners)) {
      listener(height);
    }
  }
}
