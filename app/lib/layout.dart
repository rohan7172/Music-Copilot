import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Windows narrower than this get the phone layout, even on a desktop.
const desktopMinWidth = 900.0;

/// Running as a macOS, Windows or Linux app (not in a browser).
bool get isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

/// Whether to show the desktop interface: a sidebar and side-by-side
/// panels instead of one phone-width column. Desktop apps and desktop
/// browsers get it once the window is wide enough; phones and tablets
/// keep the mobile interface.
bool useDesktopLayout(BuildContext context) {
  final wideEnough = MediaQuery.sizeOf(context).width >= desktopMinWidth;
  if (!wideEnough) return false;
  if (isDesktopPlatform) return true;
  // A browser on a computer, not a tablet's.
  return kIsWeb &&
      defaultTargetPlatform != TargetPlatform.iOS &&
      defaultTargetPlatform != TargetPlatform.android;
}

/// Whether the shortcut modifier reads ⌘ (macOS) or Ctrl.
bool get usesCommandKey =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// How a ⌘/Ctrl shortcut on [key] is written on this platform: ⌘O or Ctrl+O.
String commandShortcut(String key) => usesCommandKey ? '⌘$key' : 'Ctrl+$key';
