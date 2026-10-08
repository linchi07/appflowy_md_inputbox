import 'package:appflowy_editor/src/editor/editor_component/style/editor_color_scheme.dart';
import 'package:flutter/material.dart';

class SelectionMenuStyle {
  const SelectionMenuStyle({
    required this.selectionMenuBackgroundColor,
    required this.selectionMenuItemTextColor,
    required this.selectionMenuItemIconColor,
    required this.selectionMenuItemSelectedTextColor,
    required this.selectionMenuItemSelectedIconColor,
    required this.selectionMenuItemSelectedColor,
    required this.selectionMenuUnselectedLabelColor,
    required this.selectionMenuDividerColor,
    required this.selectionMenuLinkBorderColor,
    required this.selectionMenuInvalidLinkColor,
    required this.selectionMenuButtonColor,
    required this.selectionMenuButtonTextColor,
    required this.selectionMenuButtonIconColor,
    required this.selectionMenuButtonBorderColor,
    required this.selectionMenuTabIndicatorColor,
  });

  static const light = SelectionMenuStyle(
    selectionMenuBackgroundColor: Color(0xFFFFFFFF),
    selectionMenuItemTextColor: Color(0xFF333333),
    selectionMenuItemIconColor: Color(0xFF333333),
    selectionMenuItemSelectedTextColor: Color.fromARGB(255, 56, 91, 247),
    selectionMenuItemSelectedIconColor: Color.fromARGB(255, 56, 91, 247),
    selectionMenuItemSelectedColor: Color(0xFFE0F8FF),
    selectionMenuUnselectedLabelColor: Color(0xFF333333),
    selectionMenuDividerColor: Color(0xFF00BCF0),
    selectionMenuLinkBorderColor: Color(0xFF00BCF0),
    selectionMenuInvalidLinkColor: Color(0xFFE53935),
    selectionMenuButtonColor: Color(0xFF00BCF0),
    selectionMenuButtonTextColor: Color(0xFF333333),
    selectionMenuButtonIconColor: Color(0xFF333333),
    selectionMenuButtonBorderColor: Color(0xFF00BCF0),
    selectionMenuTabIndicatorColor: Color(0xFF00BCF0),
  );

  static const dark = SelectionMenuStyle(
    selectionMenuBackgroundColor: Color(0xFF282E3A),
    selectionMenuItemTextColor: Color(0xFFBBC3CD),
    selectionMenuItemIconColor: Color(0xFFBBC3CD),
    selectionMenuItemSelectedTextColor: Color(0xFF131720),
    selectionMenuItemSelectedIconColor: Color(0xFF131720),
    selectionMenuItemSelectedColor: Color(0xFF00BCF0),
    selectionMenuUnselectedLabelColor: Color(0xFFBBC3CD),
    selectionMenuDividerColor: Color(0xFF3A3F44),
    selectionMenuLinkBorderColor: Color(0xFF3A3F44),
    selectionMenuInvalidLinkColor: Color(0xFFE53935),
    selectionMenuButtonColor: Color(0xFF00BCF0),
    selectionMenuButtonTextColor: Color(0xFFFFFFFF),
    selectionMenuButtonIconColor: Color(0xFFFFFFFF),
    selectionMenuButtonBorderColor: Color(0xFF00BCF0),
    selectionMenuTabIndicatorColor: Color(0xFF00BCF0),
  );

  final Color selectionMenuBackgroundColor;
  final Color selectionMenuItemTextColor;
  final Color selectionMenuItemIconColor;
  final Color selectionMenuItemSelectedTextColor;
  final Color selectionMenuItemSelectedIconColor;
  final Color selectionMenuItemSelectedColor;
  final Color selectionMenuUnselectedLabelColor;
  final Color selectionMenuDividerColor;
  final Color selectionMenuLinkBorderColor;
  final Color selectionMenuInvalidLinkColor;
  final Color selectionMenuButtonColor;
  final Color selectionMenuButtonTextColor;
  final Color selectionMenuButtonIconColor;
  final Color selectionMenuButtonBorderColor;
  final Color selectionMenuTabIndicatorColor;

  static SelectionMenuStyle fromScheme(EditorColorScheme colors) =>
      SelectionMenuStyle(
        selectionMenuBackgroundColor: colors.surface,
        selectionMenuItemTextColor: colors.onSurface,
        selectionMenuItemIconColor: colors.onSurface,
        selectionMenuItemSelectedTextColor: colors.primary,
        selectionMenuItemSelectedIconColor: colors.primary,
        selectionMenuItemSelectedColor:
            Color.alphaBlend(colors.selection, colors.surface),
        selectionMenuUnselectedLabelColor: colors.mutedForeground,
        selectionMenuDividerColor: colors.border,
        selectionMenuLinkBorderColor: colors.primary,
        selectionMenuInvalidLinkColor: colors.error,
        selectionMenuButtonColor: colors.primary,
        selectionMenuButtonTextColor: colors.onPrimary,
        selectionMenuButtonIconColor: colors.onPrimary,
        selectionMenuButtonBorderColor: colors.primary,
        selectionMenuTabIndicatorColor: colors.primary,
      );

  static SelectionMenuStyle fromColors({
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    final unselectedTextColor =
        backgroundColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;

    final selectedBackgroundColor = foregroundColor.withValues(alpha: 0.15);
    final selectedTextColor =
        (Color.alphaBlend(selectedBackgroundColor, backgroundColor))
                    .computeLuminance() >
                0.5
            ? Colors.black
            : Colors.white;

    final buttonTextColor =
        foregroundColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;

    return SelectionMenuStyle(
      selectionMenuBackgroundColor: backgroundColor,
      selectionMenuItemTextColor: unselectedTextColor,
      selectionMenuItemIconColor: unselectedTextColor,
      selectionMenuItemSelectedTextColor: selectedTextColor,
      selectionMenuItemSelectedIconColor: selectedTextColor,
      selectionMenuItemSelectedColor: selectedBackgroundColor,
      selectionMenuUnselectedLabelColor:
          unselectedTextColor.withValues(alpha: 0.7),
      selectionMenuDividerColor: foregroundColor.withValues(alpha: 0.1),
      selectionMenuLinkBorderColor: foregroundColor,
      selectionMenuInvalidLinkColor: const Color(0xFFE53935),
      selectionMenuButtonColor: foregroundColor,
      selectionMenuButtonTextColor: buttonTextColor,
      selectionMenuButtonIconColor: buttonTextColor,
      selectionMenuButtonBorderColor: foregroundColor,
      selectionMenuTabIndicatorColor: foregroundColor,
    );
  }
}
