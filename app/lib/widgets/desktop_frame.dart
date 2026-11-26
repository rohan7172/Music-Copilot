import 'package:flutter/material.dart';

import '../theme.dart';

/// Width of the desktop sidebar.
const desktopSidebarWidth = 280.0;

/// The desktop shell: the same lavender bezel and near-white canvas as on
/// a phone, but filling the window, with a [sidebar] down the left and the
/// session in the main pane, the edge fluid behind it.
class DesktopFrame extends StatelessWidget {
  const DesktopFrame({
    super.key,
    required this.sidebar,
    required this.child,
    this.background,
  });

  final Widget sidebar;
  final Widget child;
  final Widget? background;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.frame,
      body: Padding(
        padding: const EdgeInsets.all(Layout.bezel),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Shape.large),
          child: ColoredBox(
            color: Palette.canvas,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: desktopSidebarWidth, child: sidebar),
                Expanded(
                  child: Stack(
                    children: [
                      if (background != null)
                        Positioned.fill(child: background!),
                      Positioned.fill(
                        child: Padding(
                          // Clear of the edge fluid at rest.
                          padding: const EdgeInsets.fromLTRB(
                            Space.sm,
                            Space.lg,
                            Space.md,
                            Space.sm,
                          ),
                          child: child,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
