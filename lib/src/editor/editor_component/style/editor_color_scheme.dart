import 'package:flutter/material.dart';

@immutable
class EditorSyntaxColors {
  const EditorSyntaxColors({
    required this.keyword,
    required this.string,
    required this.number,
    required this.comment,
    required this.key,
  });

  const EditorSyntaxColors.light()
      : keyword = const Color(0xFF6F42C1),
        string = const Color(0xFF22863A),
        number = const Color(0xFFB05A00),
        comment = const Color(0xFF6A737D),
        key = const Color(0xFF006D77);

  const EditorSyntaxColors.dark()
      : keyword = const Color(0xFFBFA7FF),
        string = const Color(0xFFA5D6A7),
        number = const Color(0xFFFFC078),
        comment = const Color(0xFF9199A4),
        key = const Color(0xFF80CBC4);

  final Color keyword;
  final Color string;
  final Color number;
  final Color comment;
  final Color key;

  @override
  bool operator ==(Object other) =>
      other is EditorSyntaxColors &&
      keyword == other.keyword &&
      string == other.string &&
      number == other.number &&
      comment == other.comment &&
      key == other.key;

  @override
  int get hashCode => Object.hash(keyword, string, number, comment, key);
}

/// Semantic colors shared by the editor, its nodes, and its controls.
@immutable
class EditorColorScheme {
  const EditorColorScheme({
    required this.brightness,
    required this.background,
    required this.foreground,
    required this.surface,
    required this.onSurface,
    required this.subtleSurface,
    required this.mutedForeground,
    required this.primary,
    required this.border,
    required this.error,
    required this.highlight,
    Color? onPrimary,
    Color? selection,
    Color? tagBackground,
    Color? tagBorder,
    this.syntax,
  })  : _onPrimary = onPrimary,
        _selection = selection,
        _tagBackground = tagBackground,
        _tagBorder = tagBorder;

  const EditorColorScheme.light({
    this.background = const Color(0xFFFFFFFF),
    this.foreground = const Color(0xFF202124),
    this.surface = const Color(0xFFFFFFFF),
    this.onSurface = const Color(0xFF202124),
    this.subtleSurface = const Color(0xFFF1F2F5),
    this.mutedForeground = const Color(0xFF7A7D85),
    this.primary = const Color(0xFF5B5BD6),
    this.border = const Color(0xFFD7D9E0),
    this.error = const Color(0xFFE53935),
    this.highlight = const Color(0x80FFEB3B),
    Color? onPrimary,
    Color? selection,
    Color? tagBackground,
    Color? tagBorder,
    this.syntax,
  })  : brightness = Brightness.light,
        _onPrimary = onPrimary,
        _selection = selection,
        _tagBackground = tagBackground,
        _tagBorder = tagBorder;

  const EditorColorScheme.dark({
    this.background = const Color(0xFF1E1F22),
    this.foreground = const Color(0xFFE7E7EA),
    this.surface = const Color(0xFF282E3A),
    this.onSurface = const Color(0xFFE7E7EA),
    this.subtleSurface = const Color(0xFF2A2B30),
    this.mutedForeground = const Color(0xFF9A9CA5),
    this.primary = const Color(0xFFA8A7FF),
    this.border = const Color(0xFF44464E),
    this.error = const Color(0xFFFF8A80),
    this.highlight = const Color(0x99FFD54F),
    Color? onPrimary,
    Color? selection,
    Color? tagBackground,
    Color? tagBorder,
    this.syntax,
  })  : brightness = Brightness.dark,
        _onPrimary = onPrimary,
        _selection = selection,
        _tagBackground = tagBackground,
        _tagBorder = tagBorder;

  final Brightness brightness;
  final Color background;
  final Color foreground;
  final Color surface;
  final Color onSurface;
  final Color subtleSurface;
  final Color mutedForeground;
  final Color primary;
  final Color border;
  final Color error;
  final Color highlight;
  final EditorSyntaxColors? syntax;
  EditorSyntaxColors get syntaxColors =>
      syntax ??
      (brightness == Brightness.dark
          ? const EditorSyntaxColors.dark()
          : const EditorSyntaxColors.light());
  final Color? _onPrimary;
  final Color? _selection;
  final Color? _tagBackground;
  final Color? _tagBorder;

  Color get onPrimary =>
      _onPrimary ??
      (primary.computeLuminance() > 0.179 ? Colors.black : Colors.white);
  Color get selection =>
      _selection ??
      primary.withValues(alpha: brightness == Brightness.dark ? 0.22 : 0.14);

  /// Compatibility names for existing Markdown clients.
  Color get subtleBackground => subtleSurface;
  Color get highlightBackground => highlight;
  Color get tagBackground =>
      _tagBackground ??
      primary.withValues(alpha: brightness == Brightness.dark ? 0.13 : 0.08);
  Color get tagBorder =>
      _tagBorder ??
      primary.withValues(alpha: brightness == Brightness.dark ? 0.33 : 0.20);

  Color get hover => Color.alphaBlend(
        primary.withValues(alpha: 0.08),
        surface,
      );
  Color get tableStripeBackground => Color.alphaBlend(
        subtleSurface.withValues(alpha: 0.5),
        background,
      );

  EditorColorScheme copyWith({
    Brightness? brightness,
    Color? background,
    Color? foreground,
    Color? surface,
    Color? onSurface,
    Color? subtleSurface,
    Color? mutedForeground,
    Color? primary,
    Color? onPrimary,
    Color? border,
    Color? selection,
    Color? error,
    Color? highlight,
    Color? tagBackground,
    Color? tagBorder,
    EditorSyntaxColors? syntax,
  }) {
    return EditorColorScheme(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      foreground: foreground ?? this.foreground,
      surface: surface ?? this.surface,
      onSurface: onSurface ?? this.onSurface,
      subtleSurface: subtleSurface ?? this.subtleSurface,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? (primary == null ? _onPrimary : null),
      border: border ?? this.border,
      selection: selection ?? (primary == null ? _selection : null),
      error: error ?? this.error,
      highlight: highlight ?? this.highlight,
      tagBackground: tagBackground ?? (primary == null ? _tagBackground : null),
      tagBorder: tagBorder ?? (primary == null ? _tagBorder : null),
      syntax: syntax ?? this.syntax,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EditorColorScheme &&
      brightness == other.brightness &&
      background == other.background &&
      foreground == other.foreground &&
      surface == other.surface &&
      onSurface == other.onSurface &&
      subtleSurface == other.subtleSurface &&
      mutedForeground == other.mutedForeground &&
      primary == other.primary &&
      onPrimary == other.onPrimary &&
      border == other.border &&
      selection == other.selection &&
      error == other.error &&
      highlight == other.highlight &&
      tagBackground == other.tagBackground &&
      tagBorder == other.tagBorder &&
      syntax == other.syntax;

  @override
  int get hashCode => Object.hashAll([
        brightness,
        background,
        foreground,
        surface,
        onSurface,
        subtleSurface,
        mutedForeground,
        primary,
        onPrimary,
        border,
        selection,
        error,
        highlight,
        tagBackground,
        tagBorder,
        syntax,
      ]);
}

/// Exposes one resolved palette to every node inside an editor instance.
class EditorTheme extends InheritedTheme {
  const EditorTheme({
    super.key,
    required this.colors,
    required super.child,
  });

  final EditorColorScheme colors;

  static EditorColorScheme of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<EditorTheme>();
    assert(theme != null, 'EditorTheme is missing above this editor component');
    return theme!.colors;
  }

  static EditorColorScheme? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EditorTheme>()?.colors;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      EditorTheme(colors: colors, child: child);

  @override
  bool updateShouldNotify(EditorTheme oldWidget) => colors != oldWidget.colors;
}
