import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/editor_component/service/ime/delta_input_on_floating_cursor_update.dart';
import 'package:appflowy_editor/src/editor/util/platform_extension.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'ime/delta_input_impl.dart';

// handle software keyboard and hardware keyboard
class KeyboardServiceWidget extends StatefulWidget {
  const KeyboardServiceWidget({
    super.key,
    this.commandShortcutEvents = const [],
    this.characterShortcutEvents = const [],
    this.focusNode,
    this.contentInsertionConfiguration,
    required this.child,
  });

  final ContentInsertionConfiguration? contentInsertionConfiguration;
  final FocusNode? focusNode;
  final List<CommandShortcutEvent> commandShortcutEvents;
  final List<CharacterShortcutEvent> characterShortcutEvents;
  final Widget child;

  @override
  State<KeyboardServiceWidget> createState() => KeyboardServiceWidgetState();
}

@visibleForTesting
class KeyboardServiceWidgetState extends State<KeyboardServiceWidget>
    implements AppFlowyKeyboardService {
  late final SelectionGestureInterceptor interceptor;
  late final EditorState editorState = context.read<EditorState>();
  late final TextInputService textInputService;
  late final FocusNode focusNode;
  final FloatingCursorHandler _floatingCursorHandler = FloatingCursorHandler();

  final List<AppFlowyKeyboardServiceInterceptor> interceptors = [];

  // previous selection
  Selection? previousSelection;

  // use for IME only
  bool enableIMEShortcuts = true;

  // use for hardware keyboard only
  bool enableKeyboardShortcuts = true;

  @override
  void initState() {
    super.initState();

    editorState.selectionNotifier.addListener(_onSelectionChanged);

    interceptor = SelectionGestureInterceptor(
      key: 'keyboard',
      canTap: (details) {
        enableIMEShortcuts = true;
        focusNode.requestFocus();
        textInputService.close();

        return true;
      },
    );
    editorState.service.selectionService
        .registerGestureInterceptor(interceptor);

    textInputService = buildTextInputService();

    focusNode = widget.focusNode ?? FocusNode(debugLabel: 'keyboard service');
    focusNode.addListener(_onFocusChanged);
    editorState.focusNotifier.value = focusNode.hasFocus;

    editorState.keepEditorFocusNotifier.addListener(_onKeepEditorFocusChanged);
  }

  @override
  void dispose() {
    editorState.focusNotifier.value = false;
    textInputService.close();
    editorState.selectionNotifier.removeListener(_onSelectionChanged);
    editorState.service.selectionService.unregisterGestureInterceptor(
      'keyboard',
    );
    focusNode.removeListener(_onFocusChanged);
    if (widget.focusNode == null) {
      focusNode.dispose();
    }
    editorState.keepEditorFocusNotifier
        .removeListener(_onKeepEditorFocusChanged);
    super.dispose();
  }

  @override
  void disable({
    bool showCursor = false,
    UnfocusDisposition disposition = UnfocusDisposition.previouslyFocusedChild,
  }) {
    focusNode.unfocus(disposition: disposition);
  }

  @override
  void enable() {
    focusNode.requestFocus();
  }

  @override
  void enableShortcuts() {
    enableKeyboardShortcuts = true;
  }

  @override
  void disableShortcuts() {
    enableKeyboardShortcuts = false;
  }

  // Used in mobile only
  @override
  void closeKeyboard() {
    textInputService.close();
  }

  // Used in mobile only
  @override
  void enableKeyBoard(Selection selection) {
    _attachTextInputService(selection);
  }

  @override
  Widget build(BuildContext context) {
    Widget child = widget.child;
    // if there is no command shortcut event, we don't need to handle hardware keyboard.
    // like in read-only mode.
    if (widget.commandShortcutEvents.isNotEmpty) {
      // the Focus widget is used to handle hardware keyboard.
      child = Focus(
        focusNode: focusNode,
        onKeyEvent: _onKeyEvent,
        child: child,
      );
    }

    // ignore the default behavior of the space key on web
    if (kIsWeb) {
      child = Shortcuts(
        shortcuts: {
          LogicalKeySet(LogicalKeyboardKey.space):
              const DoNothingAndStopPropagationIntent(),
        },
        child: child,
      );
    }

    return child;
  }

  @override
  void registerInterceptor(AppFlowyKeyboardServiceInterceptor interceptor) {
    interceptors.add(interceptor);
  }

  @override
  void unregisterInterceptor(AppFlowyKeyboardServiceInterceptor interceptor) {
    interceptors.remove(interceptor);
  }

  /// handle hardware keyboard
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!enableKeyboardShortcuts) {
      return KeyEventResult.ignored;
    }

    if ((event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        !enableIMEShortcuts) {
      if (textInputService.composingTextRange != TextRange.empty) {
        return KeyEventResult.skipRemainingHandlers;
      }

      return KeyEventResult.ignored;
    }

    for (final shortcutEvent in widget.commandShortcutEvents) {
      // check if the shortcut event can respond to the raw key event
      if (shortcutEvent.canRespondToRawKeyEvent(event)) {
        final result = shortcutEvent.handler(editorState);
        if (result == KeyEventResult.handled) {
          AppFlowyEditorLog.keyboard.debug(
            'keyboard service - handled by command shortcut event: $shortcutEvent',
          );

          return KeyEventResult.handled;
        } else if (result == KeyEventResult.skipRemainingHandlers) {
          AppFlowyEditorLog.keyboard.debug(
            'keyboard service - skip by command shortcut event: $shortcutEvent',
          );

          return KeyEventResult.skipRemainingHandlers;
        }
        continue;
      }
    }

    return KeyEventResult.ignored;
  }

  void _onSelectionChanged() {
    final doNotAttach = editorState
        .selectionExtraInfo?[selectionExtraInfoDoNotAttachTextService];
    if (doNotAttach == true) {
      return;
    }

    // attach the delta text input service if needed
    final selection = editorState.selection;

    enableIMEShortcuts = true;

    if (selection == null) {
      textInputService.close();
    } else {
      // For the deletion, we should attach the text input service immediately.
      _attachTextInputService(selection);
      _updateCaretPosition(selection);

      // Delay an extra caret update until the next frame.
      // This is crucial for node splitting (like Enter): at the moment the
      // selection changes, the new node's renderBox might not be mounted yet.
      // The IME needs the post-layout position.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _updateCaretPosition(editorState.selection);
        }
      });

      if (editorState.selectionUpdateReason == SelectionUpdateReason.uiEvent) {
        focusNode.requestFocus();
        AppFlowyEditorLog.editor.debug('keyboard service - request focus');
      } else {
        AppFlowyEditorLog.editor.debug(
          'keyboard service - selection changed: $selection',
        );
      }
    }

    previousSelection = selection;
  }

  void _attachTextInputService(Selection selection) {
    final textEditingValue = _getCurrentTextEditingValue(selection);
    AppFlowyEditorLog.editor.debugLazy(
      () => 'keyboard service - attach text input service: $textEditingValue',
    );
    if (textEditingValue != null) {
      textInputService.attach(
        textEditingValue,
        TextInputConfiguration(
          viewId: View.of(context).viewId,
          enableDeltaModel: false,
          inputType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          inputAction: TextInputAction.newline,
          keyboardAppearance: Theme.of(context).brightness,
          allowedMimeTypes:
              widget.contentInsertionConfiguration?.allowedMimeTypes ?? [],
        ),
      );
      // disable shortcuts when the IME active
      enableIMEShortcuts = textEditingValue.composing == TextRange.empty;
    } else {
      enableIMEShortcuts = true;
    }
  }

  // This function is used to get the current text editing value of the editor
  // based on the given selection.
  TextEditingValue? _getCurrentTextEditingValue(Selection selection) {
    // Moving the caret or a selection handle finishes an active mobile IME
    // composition. Keeping the old composing range after the selection moves
    // can make the next Chinese/Japanese IME update replace text at the stale
    // location. Drag updates opt out of reattaching the input service and this
    // is applied once when the gesture ends.
    final shouldClearComposingRange =
        editorState.selectionType == SelectionType.inline &&
            editorState.selectionUpdateReason == SelectionUpdateReason.uiEvent;

    if (PlatformExtension.isMobile && shouldClearComposingRange) {
      textInputService.clearComposingTextRange();
    }

    // Get the composing text range.
    final composingTextRange =
        textInputService.composingTextRange ?? TextRange.empty;
    // Build selected text once, since this range can span an entire document.
    final text = StringBuffer();
    var hasEditableNode = false;
    for (final node in editorState.getNodesInSelection(selection)) {
      final delta = node.delta;
      if (delta == null) {
        continue;
      }
      if (hasEditableNode) {
        text.write('\n');
      }
      text.write(delta.toPlainText());
      hasEditableNode = true;
    }
    if (hasEditableNode) {
      return TextEditingValue(
        text: text.toString(),
        selection: TextSelection(
          baseOffset: selection.startIndex,
          extentOffset: selection.endIndex,
        ),
        composing: composingTextRange,
      );
    }

    return null;
  }

  void _onFocusChanged() {
    editorState.focusNotifier.value = focusNode.hasFocus;
    AppFlowyEditorLog.editor.debug(
      'keyboard service - focus changed: ${focusNode.hasFocus}}',
    );

    /// On web, we don't need to close the keyboard when the focus is lost.
    if (kIsWeb) {
      return;
    }

    // clear the selection when the focus is lost.
    if (!focusNode.hasFocus) {
      if (editorState.keepEditorFocusNotifier.shouldKeepFocus) {
        return;
      }

      final children =
          WidgetsBinding.instance.focusManager.primaryFocus?.children;
      if (children != null && !children.contains(focusNode)) {
        editorState.selection = null;
      }
      textInputService.close();
    }
  }

  void _onKeepEditorFocusChanged() {
    AppFlowyEditorLog.editor.debug(
      'keyboard service - on keep editor focus changed: ${editorState.keepEditorFocusNotifier.value}}',
    );

    if (!editorState.keepEditorFocusNotifier.shouldKeepFocus) {
      focusNode.requestFocus();
    }
  }

  // only verify on macOS.
  void _updateCaretPosition(Selection? selection) {
    if (selection == null || !selection.isCollapsed) {
      return;
    }
    final node = editorState.getNodeAtPath(selection.start.path);
    if (node == null) {
      return;
    }
    final renderBox = node.renderBox;
    final selectable = node.selectable;
    if (renderBox != null && selectable != null) {
      final size = renderBox.size;
      final transform = renderBox.getTransformTo(null);
      final rect = selectable.getCursorRectInPosition(
        selection.end,
        shiftWithBaseOffset: true,
      );
      if (rect != null) {
        textInputService.updateCaretPosition(size, transform, rect);
      }
    }
  }

  NonDeltaTextInputService buildTextInputService() {
    return NonDeltaTextInputService(
      keepEditorFocusNotifier: editorState.keepEditorFocusNotifier,
      onInsert: (insertion) async {
        for (final interceptor in interceptors) {
          final result = await interceptor.interceptInsert(
            insertion,
            editorState,
            widget.characterShortcutEvents,
          );
          if (result) {
            AppFlowyEditorLog.input.info(
              'keyboard service onInsert - intercepted by interceptor: $interceptor',
            );

            return false;
          }
        }

        await onInsert(
          insertion,
          editorState,
          widget.characterShortcutEvents,
        );

        return true;
      },
      onDelete: (deletion) async {
        for (final interceptor in interceptors) {
          final result = await interceptor.interceptDelete(
            deletion,
            editorState,
          );
          if (result) {
            AppFlowyEditorLog.input.info(
              'keyboard service onDelete - intercepted by interceptor: $interceptor',
            );

            return false;
          }
        }

        await onDelete(
          deletion,
          editorState,
        );

        return true;
      },
      onReplace: (replacement) async {
        for (final interceptor in interceptors) {
          final result = await interceptor.interceptReplace(
            replacement,
            editorState,
            widget.characterShortcutEvents,
          );
          if (result) {
            AppFlowyEditorLog.input.info(
              'keyboard service onReplace - intercepted by interceptor: $interceptor',
            );

            return false;
          }
        }

        await onReplace(
          replacement,
          editorState,
          widget.characterShortcutEvents,
        );

        return true;
      },
      onNonTextUpdate: (nonTextUpdate) async {
        for (final interceptor in interceptors) {
          final result = await interceptor.interceptNonTextUpdate(
            nonTextUpdate,
            editorState,
            widget.characterShortcutEvents,
          );
          if (result) {
            AppFlowyEditorLog.input.info(
              'keyboard service onNonTextUpdate - intercepted by interceptor: $interceptor',
            );

            return false;
          }
        }

        await onNonTextUpdate(
          nonTextUpdate,
          editorState,
          widget.characterShortcutEvents,
        );

        return true;
      },
      onPerformAction: (action) async {
        for (final interceptor in interceptors) {
          final result = await interceptor.interceptPerformAction(
            action,
            editorState,
          );
          if (result) {
            AppFlowyEditorLog.input.info(
              'keyboard service onPerformAction - intercepted by interceptor: $interceptor',
            );

            return;
          }
        }

        await onPerformAction(
          action,
          editorState,
        );
      },
      onFloatingCursor: (point) async {
        for (final interceptor in interceptors) {
          final result = await interceptor.interceptFloatingCursor(
            point,
            editorState,
          );
          if (result) {
            AppFlowyEditorLog.input.info(
              'keyboard service onFloatingCursor - intercepted by interceptor: $interceptor',
            );

            return;
          }
        }

        await _floatingCursorHandler.update(
          point,
          editorState,
        );
      },
      contentInsertionConfiguration: widget.contentInsertionConfiguration,
    );
  }
}
