import 'package:flutter/material.dart';

import 'package:appflowy_editor/appflowy_editor.dart';
import '../../block_component/rich_text/markdown_decorator.dart';

/// Compatibility wrapper for the former Markdown-only color scheme.
class MDEditorColorScheme extends EditorColorScheme {
  const MDEditorColorScheme({
    required Color foreground,
    required Color background,
    required Color primary,
    required Color selection,
    required Color mutedForeground,
    required Color border,
    required Color subtleBackground,
    required Color tagBackground,
    required Color tagBorder,
    Color highlightBackground = const Color(0x80FFEB3B),
  }) : super(
          brightness: Brightness.light,
          foreground: foreground,
          background: background,
          surface: background,
          onSurface: foreground,
          subtleSurface: subtleBackground,
          mutedForeground: mutedForeground,
          primary: primary,
          onPrimary: Colors.white,
          selection: selection,
          border: border,
          error: const Color(0xFFE53935),
          highlight: highlightBackground,
          tagBackground: tagBackground,
          tagBorder: tagBorder,
        );

  const MDEditorColorScheme.light({
    Color foreground = const Color(0xFF202124),
    Color background = const Color(0xFFFFFFFF),
    Color primary = const Color(0xFF5B5BD6),
    Color selection = const Color(0x245B5BD6),
    Color mutedForeground = const Color(0xFF7A7D85),
    Color border = const Color(0xFFD7D9E0),
    Color subtleBackground = const Color(0xFFF1F2F5),
    Color tagBackground = const Color(0x145B5BD6),
    Color tagBorder = const Color(0x335B5BD6),
    Color highlightBackground = const Color(0x80FFEB3B),
  }) : super.light(
          foreground: foreground,
          background: background,
          surface: background,
          onSurface: foreground,
          subtleSurface: subtleBackground,
          mutedForeground: mutedForeground,
          primary: primary,
          onPrimary: Colors.white,
          selection: selection,
          border: border,
          highlight: highlightBackground,
          tagBackground: tagBackground,
          tagBorder: tagBorder,
        );

  const MDEditorColorScheme.dark({
    Color foreground = const Color(0xFFE7E7EA),
    Color background = const Color(0xFF1E1F22),
    Color primary = const Color(0xFFA8A7FF),
    Color selection = const Color(0x38A8A7FF),
    Color mutedForeground = const Color(0xFF9A9CA5),
    Color border = const Color(0xFF44464E),
    Color subtleBackground = const Color(0xFF2A2B30),
    Color tagBackground = const Color(0x20A8A7FF),
    Color tagBorder = const Color(0x55A8A7FF),
    Color highlightBackground = const Color(0x99FFD54F),
  }) : super.dark(
          foreground: foreground,
          background: background,
          surface: background,
          onSurface: foreground,
          subtleSurface: subtleBackground,
          mutedForeground: mutedForeground,
          primary: primary,
          onPrimary: Colors.black,
          selection: selection,
          border: border,
          highlight: highlightBackground,
          tagBackground: tagBackground,
          tagBorder: tagBorder,
        );
}

/// The style of the editor.
///
/// You can customize the style of the editor by passing the [EditorStyle] to
///  the [AppFlowyEditor].
///
class EditorStyle {
  EditorStyle({
    required this.padding,
    required this.cursorColor,
    required this.dragHandleColor,
    required this.selectionColor,
    required this.textStyleConfiguration,
    required this.textSpanDecorator,
    required this.colorScheme,
    bool? cursorColorIsExplicit,
    bool? selectionColorIsExplicit,
    bool? dragHandleColorIsExplicit,
    this.textSpanOverlayBuilder,
    this.magnifierSize = const Size(72, 48),
    this.mobileDragHandleBallSize = const Size(8, 8),
    this.mobileDragHandleWidth = 2.0,
    this.cursorWidth = 2.0,
    this.defaultTextDirection,
    this.enableHapticFeedbackOnAndroid = true,
    this.textScaleFactor = 1.0,
    this.maxWidth,
    this.mobileDragHandleTopExtend,
    this.mobileDragHandleWidthExtend,
    this.mobileDragHandleLeftExtend,
    this.mobileDragHandleHeightExtend,
    this.selectionMenuStyle,
    this.autoDismissCollapsedHandleDuration = const Duration(seconds: 3),
    this.maxMarkdownDecorationCharacters = 64 * 1024,
  })  : _cursorColorIsExplicit = cursorColorIsExplicit ?? true,
        _selectionColorIsExplicit = selectionColorIsExplicit ?? true,
        _dragHandleColorIsExplicit = dragHandleColorIsExplicit ?? true;

  // The padding of the editor.
  final EdgeInsets padding;

  // The max width of the editor.
  final double? maxWidth;

  // The cursor color
  final Color cursorColor;

  // The cursor width
  final double cursorWidth;

  // The drag handle color
  // only works on mobile
  // the drag handle color will be ignored on Android.
  final Color dragHandleColor;

  // The selection color
  final Color selectionColor;

  /// Unified colors for Markdown decorations and editor chrome.
  final EditorColorScheme colorScheme;
  final bool _cursorColorIsExplicit;
  final bool _selectionColorIsExplicit;
  final bool _dragHandleColorIsExplicit;

  /// Resolve default editor chrome colors from the effective palette.
  EditorStyle resolvedWith(EditorColorScheme colors) => copyWith(
        colorScheme: colors,
        cursorColor: _cursorColorIsExplicit ? cursorColor : colors.primary,
        selectionColor:
            _selectionColorIsExplicit ? selectionColor : colors.selection,
        dragHandleColor:
            _dragHandleColorIsExplicit ? dragHandleColor : colors.primary,
        cursorColorIsExplicit: _cursorColorIsExplicit,
        selectionColorIsExplicit: _selectionColorIsExplicit,
        dragHandleColorIsExplicit: _dragHandleColorIsExplicit,
      );

  // Customize the text style of the editor.
  //
  // All the text-based components will use this configuration to build their
  //   text style.
  //
  // Notes, this configuration is only for the common config of text style and
  //  it maybe override if the text block has its own [BlockComponentConfiguration].
  final TextStyleConfiguration textStyleConfiguration;

  // Customize the built-in or custom text span.
  //
  // For example, you can add a custom text span for the mention text
  //   or override the built-in text span.
  final TextSpanDecoratorForAttribute? textSpanDecorator;

  /// Customize the text span overlay builder.
  final AppFlowyTextSpanOverlayBuilder? textSpanOverlayBuilder;

  final String? defaultTextDirection;

  // The size of the magnifier.
  // Only works on mobile.
  final Size magnifierSize;

  // mobile drag handler size.
  // Only works on mobile.
  final Size mobileDragHandleBallSize;

  /// The extend of the mobile drag handle.
  ///
  /// By default, the hit test area of drag handle is the ball size.
  /// If you want to extend the hit test area, you can set this value.
  ///
  /// For example, if you set this value to 10, the hit test area of drag handle
  /// will be the ball size + 10 * 2.
  final double? mobileDragHandleTopExtend;
  final double? mobileDragHandleLeftExtend;
  final double? mobileDragHandleWidthExtend;
  final double? mobileDragHandleHeightExtend;

  /// The auto-dismiss time of the collapsed handle.
  ///
  /// The collapsed handle will be dismissed when no user interaction is detected.
  ///
  /// Only works on Android.
  final Duration autoDismissCollapsedHandleDuration;

  final SelectionMenuStyle? selectionMenuStyle;

  final double mobileDragHandleWidth;

  // only works on android
  // enable haptic feedback when updating selection by dragging the drag handler
  final bool enableHapticFeedbackOnAndroid;

  final double textScaleFactor;

  /// Maximum paragraph size that receives live Markdown decoration.
  ///
  /// Larger paragraphs remain editable as plain source so regexp scanning and
  /// inline-widget construction cannot grow without a bound. When enabled,
  /// markup-dense paragraphs also fall back after 512 recognized constructs.
  /// Set to null to disable both safeguards.
  final int? maxMarkdownDecorationCharacters;

  EditorStyle.desktop({
    EdgeInsets? padding,
    Color? cursorColor,
    Color? selectionColor,
    TextStyleConfiguration? textStyleConfiguration,
    TextSpanDecoratorForAttribute? textSpanDecorator,
    this.textSpanOverlayBuilder,
    this.defaultTextDirection,
    this.cursorWidth = 2.0,
    this.textScaleFactor = 1.0,
    this.maxWidth,
    this.selectionMenuStyle,
    EditorColorScheme? colorScheme,
    this.maxMarkdownDecorationCharacters = 64 * 1024,
  })  : _cursorColorIsExplicit = cursorColor != null,
        _selectionColorIsExplicit = selectionColor != null,
        _dragHandleColorIsExplicit = false,
        padding = padding ?? const EdgeInsets.symmetric(horizontal: 100),
        colorScheme = colorScheme ?? const EditorColorScheme.light(),
        cursorColor = cursorColor ??
            colorScheme?.primary ??
            const EditorColorScheme.light().primary,
        selectionColor = selectionColor ??
            colorScheme?.selection ??
            const EditorColorScheme.light().selection,
        textStyleConfiguration = textStyleConfiguration ??
            const TextStyleConfiguration(
              text: TextStyle(fontSize: 16),
            ),
        textSpanDecorator = textSpanDecorator ?? markdownTextSpanDecorator,
        magnifierSize = Size.zero,
        mobileDragHandleBallSize = Size.zero,
        mobileDragHandleWidth = 0.0,
        enableHapticFeedbackOnAndroid = false,
        dragHandleColor = Colors.transparent,
        mobileDragHandleTopExtend = null,
        mobileDragHandleWidthExtend = null,
        mobileDragHandleLeftExtend = null,
        mobileDragHandleHeightExtend = null,
        autoDismissCollapsedHandleDuration = const Duration(seconds: 0);

  EditorStyle.mobile({
    EdgeInsets? padding,
    Color? cursorColor,
    Color? dragHandleColor,
    Color? selectionColor,
    TextStyleConfiguration? textStyleConfiguration,
    TextSpanDecoratorForAttribute? textSpanDecorator,
    this.textSpanOverlayBuilder,
    this.defaultTextDirection,
    this.magnifierSize = const Size(72, 48),
    this.mobileDragHandleBallSize = const Size(8, 8),
    this.mobileDragHandleWidth = 2.0,
    this.cursorWidth = 2.0,
    this.enableHapticFeedbackOnAndroid = true,
    this.textScaleFactor = 1.0,
    this.maxWidth,
    this.mobileDragHandleTopExtend,
    this.mobileDragHandleWidthExtend,
    this.mobileDragHandleLeftExtend,
    this.mobileDragHandleHeightExtend,
    this.autoDismissCollapsedHandleDuration = const Duration(seconds: 3),
    this.selectionMenuStyle,
    EditorColorScheme? colorScheme,
    this.maxMarkdownDecorationCharacters = 64 * 1024,
  })  : _cursorColorIsExplicit = cursorColor != null,
        _selectionColorIsExplicit = selectionColor != null,
        _dragHandleColorIsExplicit = dragHandleColor != null,
        padding = padding ?? const EdgeInsets.symmetric(horizontal: 20),
        colorScheme = colorScheme ?? const EditorColorScheme.light(),
        cursorColor = cursorColor ??
            colorScheme?.primary ??
            const EditorColorScheme.light().primary,
        dragHandleColor = dragHandleColor ??
            colorScheme?.primary ??
            const EditorColorScheme.light().primary,
        selectionColor = selectionColor ??
            colorScheme?.selection ??
            const EditorColorScheme.light().selection,
        textStyleConfiguration = textStyleConfiguration ??
            const TextStyleConfiguration(
              text: TextStyle(fontSize: 16),
            ),
        textSpanDecorator = textSpanDecorator ?? markdownTextSpanDecorator;

  EditorStyle copyWith({
    EdgeInsets? padding,
    Color? cursorColor,
    Color? dragHandleColor,
    Color? selectionColor,
    TextStyleConfiguration? textStyleConfiguration,
    TextSpanDecoratorForAttribute? textSpanDecorator,
    AppFlowyTextSpanOverlayBuilder? textSpanOverlayBuilder,
    String? defaultTextDirection,
    Size? magnifierSize,
    Size? mobileDragHandleBallSize,
    double? mobileDragHandleWidth,
    bool? enableHapticFeedbackOnAndroid,
    double? cursorWidth,
    double? textScaleFactor,
    double? maxWidth,
    double? mobileDragHandleTopExtend,
    double? mobileDragHandleWidthExtend,
    double? mobileDragHandleLeftExtend,
    double? mobileDragHandleHeightExtend,
    Duration? autoDismissCollapsedHandleDuration,
    SelectionMenuStyle? selectionMenuStyle,
    EditorColorScheme? colorScheme,
    int? maxMarkdownDecorationCharacters,
    bool? cursorColorIsExplicit,
    bool? selectionColorIsExplicit,
    bool? dragHandleColorIsExplicit,
  }) {
    return EditorStyle(
      padding: padding ?? this.padding,
      cursorColor: cursorColor ?? this.cursorColor,
      dragHandleColor: dragHandleColor ?? this.dragHandleColor,
      selectionColor: selectionColor ?? this.selectionColor,
      colorScheme: colorScheme ?? this.colorScheme,
      cursorColorIsExplicit: cursorColorIsExplicit ??
          (cursorColor != null || _cursorColorIsExplicit),
      selectionColorIsExplicit: selectionColorIsExplicit ??
          (selectionColor != null || _selectionColorIsExplicit),
      dragHandleColorIsExplicit: dragHandleColorIsExplicit ??
          (dragHandleColor != null || _dragHandleColorIsExplicit),
      textStyleConfiguration:
          textStyleConfiguration ?? this.textStyleConfiguration,
      textSpanDecorator: textSpanDecorator ?? this.textSpanDecorator,
      textSpanOverlayBuilder:
          textSpanOverlayBuilder ?? this.textSpanOverlayBuilder,
      defaultTextDirection: defaultTextDirection,
      magnifierSize: magnifierSize ?? this.magnifierSize,
      mobileDragHandleBallSize:
          mobileDragHandleBallSize ?? this.mobileDragHandleBallSize,
      mobileDragHandleWidth:
          mobileDragHandleWidth ?? this.mobileDragHandleWidth,
      enableHapticFeedbackOnAndroid:
          enableHapticFeedbackOnAndroid ?? this.enableHapticFeedbackOnAndroid,
      cursorWidth: cursorWidth ?? this.cursorWidth,
      textScaleFactor: textScaleFactor ?? this.textScaleFactor,
      maxWidth: maxWidth ?? this.maxWidth,
      mobileDragHandleTopExtend:
          mobileDragHandleTopExtend ?? this.mobileDragHandleTopExtend,
      mobileDragHandleWidthExtend:
          mobileDragHandleWidthExtend ?? this.mobileDragHandleWidthExtend,
      mobileDragHandleLeftExtend:
          mobileDragHandleLeftExtend ?? this.mobileDragHandleLeftExtend,
      mobileDragHandleHeightExtend:
          mobileDragHandleHeightExtend ?? this.mobileDragHandleHeightExtend,
      autoDismissCollapsedHandleDuration: autoDismissCollapsedHandleDuration ??
          this.autoDismissCollapsedHandleDuration,
      selectionMenuStyle: selectionMenuStyle ?? this.selectionMenuStyle,
      maxMarkdownDecorationCharacters: maxMarkdownDecorationCharacters ??
          this.maxMarkdownDecorationCharacters,
    );
  }
}
