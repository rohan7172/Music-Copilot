import 'package:flutter/material.dart';

import '../theme.dart';

/// Height of the header row inside the canvas.
const headerHeight = 64.0;

/// The app's outer shell, as in the Stitch screens: a lavender bezel around
/// one rounded near-white canvas, a header row on top, an optional
/// [background] layer (the edge fluid, which also forms the header bar)
/// under everything, and the screen's [child] beneath the header. On a
/// wide window the whole frame stays a phone-like column centered in the
/// bezel color.
class AppFrame extends StatelessWidget {
  const AppFrame({
    super.key,
    required this.child,
    this.header,
    this.background,
  });

  final Widget child;
  final Widget? header;

  /// Built with the header's bottom edge (from the top of the canvas), so
  /// the fluid can fill the header bar exactly.
  final Widget Function(double headerBottom)? background;

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
                        child: background!(
                          header == null ? 0 : top + headerHeight,
                        ),
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

/// "Music Copilot" on the left and an optional action (upload) on the
/// right, sitting on the lavender header bar the edge fluid forms.
/// [reveal] (0..1) fades it in as the liquid arrives beneath it.
class AppHeader extends StatelessWidget {
  const AppHeader({super.key, this.action, this.reveal = 1});

  final Widget? action;
  final double reveal;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.margin),
      child: Row(
        children: [
          Semantics(
            header: true,
            // White on lavender: large and bold enough (18px w700) to
            // clear the 3:1 large-text contrast floor.
            child: Text(
              'Music Copilot',
              style: TextStyles.labelLg.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
                color: Palette.canvas,
              ),
            ),
          ),
          const Spacer(),
          AnimatedSwitcher(
            duration: Motion.settle,
            child: action ?? const SizedBox.shrink(),
          ),
        ],
      ),
    );
    if (reveal >= 1) return content;
    return Opacity(
      opacity: Curves.easeOut.transform(reveal),
      child: Transform.translate(
        offset: Offset(0, -6 * (1 - reveal)),
        child: content,
      ),
    );
  }
}
