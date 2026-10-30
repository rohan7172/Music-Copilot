import 'package:flutter/material.dart';

import '../session/scene.dart';
import '../session/session_controller.dart';
import '../theme.dart';
import '../widgets/app_frame.dart';
import '../widgets/fluid_field.dart';
import '../widgets/ui.dart';
import 'views/error_view.dart';
import 'views/idle_view.dart';
import 'views/listening_view.dart';
import 'views/results_view.dart';

/// The one screen the app lives on: the framed canvas with the edge fluid
/// behind it, showing whichever view the session's phase calls for.
class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, this.createController});

  /// Lets a test or preview harness drive the screen with its own session.
  @visibleForTesting
  final SessionController Function(TickerProvider vsync)? createController;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen>
    with SingleTickerProviderStateMixin {
  late final SessionController _controller =
      widget.createController?.call(this) ?? SessionController(vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _controller.noteInteraction(),
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final phase = _controller.phase;
          final busy = phase == Phase.recording || phase == Phase.analyzing;
          final (key, view) = _viewFor(phase);
          return AppFrame(
            header: AppHeader(
              action: busy
                  ? null
                  : PillButton(
                      key: const ValueKey('upload'),
                      label: 'upload',
                      icon: Icons.upload_rounded,
                      textStyle: TextStyles.labelMd,
                      onTap: _controller.pickAndAnalyzeFile,
                    ),
            ),
            background: RepaintBoundary(
              child: CustomPaint(
                painter: FluidFieldPainter(
                  _controller.scene,
                  _controller.clock,
                ),
              ),
            ),
            child: AnimatedSwitcher(
              duration: Motion.settle,
              switchInCurve: Motion.curve,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween(begin: 0.98, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(key: ValueKey(key), child: view),
            ),
          );
        },
      ),
    );
  }

  (String, Widget) _viewFor(Phase phase) {
    if (_controller.error != null) {
      return ('error', ErrorView(controller: _controller));
    }
    return switch (phase) {
      Phase.idle => ('idle', IdleView(controller: _controller)),
      // Recording and analyzing share one view so the hand-off between
      // them animates in place instead of swapping screens.
      Phase.recording ||
      Phase.analyzing => ('listening', ListeningView(controller: _controller)),
      Phase.settled => ('results', ResultsView(controller: _controller)),
    };
  }
}
