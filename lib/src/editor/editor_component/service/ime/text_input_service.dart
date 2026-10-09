import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract class TextInputService {
  TextInputService({
    required this.onInsert,
    required this.onDelete,
    required this.onReplace,
    required this.onNonTextUpdate,
    required this.onPerformAction,
    this.onFloatingCursor,
    this.contentInsertionConfiguration,
    this.onCompositionStart,
    this.onCompositionEnd,
  });

  Future<bool> Function(TextEditingDeltaInsertion insertion) onInsert;
  Future<bool> Function(TextEditingDeltaDeletion deletion) onDelete;
  Future<bool> Function(TextEditingDeltaReplacement replacement) onReplace;
  Future<bool> Function(TextEditingDeltaNonTextUpdate nonTextUpdate)
      onNonTextUpdate;
  Future<void> Function(TextInputAction action) onPerformAction;
  Future<void> Function(RawFloatingCursorPoint point)? onFloatingCursor;

  final ContentInsertionConfiguration? contentInsertionConfiguration;
  final VoidCallback? onCompositionStart;
  final VoidCallback? onCompositionEnd;
  bool _composingSessionActive = false;

  /// Start before the first preedit; finish after the committed replacement.
  Future<bool> dispatchDelta(TextEditingDelta delta) async {
    final composing = delta.composing.isValid && !delta.composing.isCollapsed;
    if (composing && !_composingSessionActive) {
      _composingSessionActive = true;
      onCompositionStart?.call();
    }
    try {
      if (delta is TextEditingDeltaInsertion) return await onInsert(delta);
      if (delta is TextEditingDeltaDeletion) return await onDelete(delta);
      if (delta is TextEditingDeltaReplacement) return await onReplace(delta);
      if (delta is TextEditingDeltaNonTextUpdate) {
        return await onNonTextUpdate(delta);
      }
      return false;
    } finally {
      if (!composing) finishCompositionSession();
    }
  }

  void finishCompositionSession() {
    if (!_composingSessionActive) return;
    _composingSessionActive = false;
    onCompositionEnd?.call();
  }

  TextRange? get composingTextRange;

  bool get attached;

  void clearComposingTextRange();

  void updateCaretPosition(Size size, Matrix4 transform, Rect rect);

  /// Updates the [TextEditingValue] of the text currently being edited.
  ///
  /// Note that if there are IME-related requirements,
  /// please config `composing` value within [TextEditingValue]
  ///
  /// [BuildContext] is used to get current keyboard appearance(light or dark)
  void attach(
    TextEditingValue textEditingValue,
    TextInputConfiguration configuration,
  );

  /// Applies insertion, deletion and replacement
  ///   to the text currently being edited.
  ///   return false means will not apply
  ///
  /// For more information, please check [TextEditingDelta].
  Future<bool> apply(List<TextEditingDelta> deltas);

  /// Closes the editing state of the text currently being edited.
  void close();
}
