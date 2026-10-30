import 'package:flutter/material.dart';

import '../theme.dart';

/// Height of the header row inside the canvas.
const headerHeight = 64.0;

/// The app's outer shell, as in the Stitch screens: a lavender bezel around
/// one rounded near-white canvas, a header row on top, an optional
/// [background] layer (the edge fluid) under the content, and the screen's
/// [child] beneath the header. On a wide window the whole frame stays a
/// phone-like column centered in the bezel color.
class AppFrame extends StatelessWidget {
  const AppFrame({
    super.key,
    required this.child,
    this.header,
    this.background,
  });

  final Widget child;
  final Widget? header;
  final Widget? background;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    // The bezel already clears some of the safe area; only pad the rest.
    final top = (padding.top - Layout.bezel).clamp(0.0, double.infinity);
    final bottom = (padding.bottom - Layout.bezel).clamp(0.0, double.infinity);

    return Scaffold(
      backgroundColor: Palette.frame,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Layout.maxContentWidth),
          child: Padding(
            padding: const EdgeInsets.all(Layout.bezel),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Shape.canvas),
              child: ColoredBox(
                color: Palette.canvas,
                child: Stack(
                  children: [
                    if (background != null)
                      Positioned.fill(
                        top: top + headerHeight,
                        child: background!,
                      ),
                    Positioned.fill(
                      top: top + (header == null ? 0 : headerHeight),
                      bottom: bottom,
                      child: child,
                    ),
                    if (header != null)
                      Positioned(
                        top: top,
                        left: 0,
                        right: 0,
                        height: headerHeight,
                        child: header!,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Music Copilot" on the left; an optional action (upload) on the right.
class AppHeader extends StatelessWidget {
  const AppHeader({super.key, this.action});

  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.margin),
      child: Row(
        children: [
          Semantics(
            header: true,
            child: Text('Music Copilot', style: TextStyles.labelLg),
          ),
          const Spacer(),
          AnimatedSwitcher(
            duration: Motion.settle,
            child: action ?? const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
