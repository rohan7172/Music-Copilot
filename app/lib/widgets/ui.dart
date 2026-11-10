import 'package:flutter/material.dart';

import '../theme.dart';

/// Shrinks a touch while pressed, the Stitch designs' `active:scale-95` —
/// the one press feedback every control in the app shares.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.pressedScale = 0.95,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => _set(true) : null,
          onTapUp: enabled ? (_) => _set(false) : null,
          onTapCancel: enabled ? () => _set(false) : null,
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _down ? widget.pressedScale : 1,
            duration: Motion.quick,
            curve: Motion.curve,
            child: AnimatedOpacity(
              opacity: enabled ? 1 : 0.45,
              duration: Motion.quick,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

enum PillTone {
  /// Deep violet, white text: the one thing to do next.
  primary,

  /// Pale violet: a secondary call to action.
  soft,

  /// Near-canvas: quiet, utility actions.
  quiet,
}

/// A stadium-shaped button with an optional leading or trailing icon.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.tone = PillTone.quiet,
    this.icon,
    this.trailingIcon,
    this.height = 44,
    this.expand = false,
    this.textStyle,
  });

  final String label;
  final VoidCallback? onTap;
  final PillTone tone;
  final IconData? icon;
  final IconData? trailingIcon;
  final double height;
  final bool expand;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      PillTone.primary => (Palette.primary, Palette.onPrimary),
      PillTone.soft => (Palette.primaryFixed, Palette.onPrimaryFixed),
      PillTone.quiet => (Palette.creamAlt, Palette.ink),
    };
    final style = (textStyle ?? TextStyles.labelLg).copyWith(color: fg);
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: style.fontSize! + 6, color: fg),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(label, style: style, overflow: TextOverflow.ellipsis),
        ),
        if (trailingIcon != null) ...[
          const SizedBox(width: 6),
          Icon(trailingIcon, size: style.fontSize! + 4, color: fg),
        ],
      ],
    );
    return Pressable(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        decoration: ShapeDecoration(
          color: bg,
          shape: const StadiumBorder(),
          shadows: tone == PillTone.primary
              ? [
                  BoxShadow(
                    color: Palette.primary.withValues(alpha: 0.2),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: content,
      ),
    );
  }
}

/// A circular icon button, optionally captioned underneath — the idle
/// screen's Live Mic / File Import pair, and the results transport.
class RoundAction extends StatelessWidget {
  const RoundAction({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.caption,
    this.size = 56,
    this.tone = PillTone.quiet,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String semanticLabel;
  final String? caption;
  final double size;
  final PillTone tone;

  /// A quiet toggle that's switched on (e.g. loop).
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      PillTone.primary => (Palette.primary, Palette.onPrimary),
      PillTone.soft => (Palette.primaryFixed, Palette.onPrimaryFixed),
      PillTone.quiet =>
        selected
            ? (Palette.noteSoft.withValues(alpha: 0.45), Palette.primary)
            : (Palette.creamAlt, Palette.ink),
    };
    final circle = AnimatedContainer(
      duration: Motion.quick,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        boxShadow: tone == PillTone.primary
            ? [
                BoxShadow(
                  color: Palette.primary.withValues(alpha: 0.2),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Icon(icon, color: fg, size: size * 0.42),
    );
    return Pressable(
      onTap: onTap,
      pressedScale: 0.9,
      semanticLabel: semanticLabel,
      child: caption == null
          ? circle
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                circle,
                const SizedBox(height: Space.sm),
                ExcludeSemantics(
                  child: Text(caption!, style: TextStyles.labelMd),
                ),
              ],
            ),
    );
  }
}

/// A small stadium label: status ("listening 00:16"), key, counts.
class InfoChip extends StatelessWidget {
  const InfoChip({
    super.key,
    required this.children,
    this.dot,
    this.icon,
    this.onTap,
    this.semanticLabel,
  });

  /// Text spans, so a chip can mix a quiet prefix with an emphasized value.
  final List<InlineSpan> children;

  /// A small leading status dot.
  final Color? dot;
  final IconData? icon;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const ShapeDecoration(
        color: Palette.creamAlt,
        shape: StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
          ],
          if (icon != null) ...[
            Icon(icon, size: 16, color: Palette.ink),
            const SizedBox(width: 6),
          ],
          Text.rich(
            TextSpan(style: TextStyles.labelMd, children: children),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
    if (onTap == null) {
      return Semantics(label: semanticLabel, child: chip);
    }
    return Pressable(onTap: onTap, semanticLabel: semanticLabel, child: chip);
  }
}

/// Small uppercase section heading with an optional right-aligned note.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(text.toUpperCase(), style: TextStyles.labelSm),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Formats seconds as m:ss (or mm:ss past ten minutes).
String clockText(double seconds) {
  final total = seconds.isFinite ? seconds.floor().clamp(0, 5999) : 0;
  final m = total ~/ 60;
  final s = total % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
