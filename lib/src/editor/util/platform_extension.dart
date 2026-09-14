import 'package:flutter/foundation.dart';

abstract final class PlatformExtension {
  static bool get isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static bool get isLinux =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get isWebOnMacOS =>
      kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static bool get isWebOnWindows =>
      kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static bool get isWebOnLinux =>
      kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  static bool get isDesktopOrWeb => kIsWeb || isDesktop;

  static bool get isDesktop =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  static bool get isMobile =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  static bool get isNotMobile => !isMobile;
}
