import 'dart:math' as math;

import '../audio/waveform.dart';
import '../models/harmony.dart';
import '../models/note.dart';

/// Where a session is: waiting, capturing audio, waiting on the backend, or
/// showing what was found.
enum Phase { idle, recording, analyzing, settled }

/// Roughly how long the home screen's one-time wake-up intro takes (the
/// fluid growing in from the edges) after the splash hands off.
const introDuration = 1.6;

/// Everything about the current session that painters animate from. Owned
/// and mutated by `SessionController`; painters only read it. All animation
/// is derived from timestamps on the controller's shared clock (seconds),
/// so any moment can be replayed by resetting a time.
class Scene {
  Phase phase = Phase.idle;

  /// Set once, when the session screen first appears, for the fluid's
  /// grow-in from the edges. Null means "already settled, no intro".
  double? introStart;

  /// Live loudness (0..1) sampled every 40 ms while recording, evenly
  /// spaced over [liveDuration].
  final List<double> live = [];
  double liveDuration = 0;

  /// When the live input last crossed a loudness peak while recording —
  /// an approximate "it's reacting to your rhythm" cue (not a real beat
  /// grid; see docs/concepts.md).
  double? lastPeakAt;

  /// Envelope decoded from the finished recording (or synthesized from the
  /// notes for formats that can't be decoded here).
  Waveform? waveform;

  double? analyzeStart;
  double? settleStart;

  List<Note> notes = const [];
  List<Chord> chords = const [];
  MusicKey? key;

  /// The note or chord most recently tapped, if any.
  int? selected;
  int? selectedChord;

  /// Current playback position (seconds) while audio is playing or paused.
  double? playhead;

  /// True while the whole recording is playing, as opposed to one slice.
  bool playingAll = false;

  /// Length of the analyzed audio in seconds.
  double get duration => waveform?.duration ?? 1;
}

/// How loud *right now* — a short trailing average of recently sampled live
/// loudness (see [Scene.live]), not a per-moment history. Shared by the
/// edge fluid field and the acoustic stream, so both read "how loud is it
/// right now" the same way.
double liveVolume(List<double> live) {
  if (live.isEmpty) return 0;
  final window = math.min(6, live.length);
  var sum = 0.0;
  for (var i = live.length - window; i < live.length; i++) {
    sum += live[i];
  }
  return sum / window;
}
