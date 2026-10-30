import '../../session/scene.dart';

/// The mascot's expressions, named after the reference sheet
/// (`Inpiration/Mascot States and Emotions Sheet.png`). Only the states
/// that a real event can trigger are here — "looking around" and the
/// per-note colors from the sheet are deliberately left out.
enum MascotMood {
  idle,
  sleepy,
  tapped,
  listening,
  concentrating,
  happy,
  excited,
  singing,
  curious,
  surprised,
}

/// How long without any touch before the idle mascot dozes off.
const sleepAfter = 30.0;

/// How long the reaction to a direct tap lasts.
const tapReaction = 0.6;

/// How long the happy/excited reaction holds after results land.
const revealReaction = 2.4;

/// How long the happy beat lasts when a cadence resolves during playback.
const cadenceReaction = 1.2;

/// Key confidence at or above which results land as "excited" rather than
/// just "happy"; below [unsureKey] the mascot stays curious afterwards.
const confidentKey = 0.75;
const unsureKey = 0.45;

/// Which expression the mascot shows right now. Pure — every input is a
/// real session event or a timestamp — so it's unit-testable without a
/// widget and the mascot can never show a state nothing caused.
MascotMood moodFor({
  required Phase phase,
  required double now,
  required bool hasError,
  required double lastInteractionAt,
  double? lastTapAt,
  double? settleStart,
  bool playing = false,
  int noteCount = 0,
  double? keyConfidence,
  bool boldSelected = false,
  double? cadenceAt,
}) {
  if (hasError) return MascotMood.surprised;
  switch (phase) {
    case Phase.recording:
      return MascotMood.listening;
    case Phase.analyzing:
      return MascotMood.concentrating;
    case Phase.settled:
      if (noteCount == 0) return MascotMood.curious;
      // A cadence resolving under the take earns a happy beat mid-song.
      if (_recently(cadenceAt, now, cadenceReaction)) return MascotMood.happy;
      if (playing) return MascotMood.singing;
      if (_recently(lastTapAt, now, tapReaction)) return MascotMood.tapped;
      if (settleStart != null && now - settleStart < revealReaction) {
        return (keyConfidence ?? 0) >= confidentKey
            ? MascotMood.excited
            : MascotMood.happy;
      }
      // The Bold card is the adventurous one: the mascot tilts its head at it.
      if (boldSelected) return MascotMood.curious;
      if (keyConfidence == null || keyConfidence < unsureKey) {
        return MascotMood.curious;
      }
      return MascotMood.idle;
    case Phase.idle:
      if (_recently(lastTapAt, now, tapReaction)) return MascotMood.tapped;
      if (now - lastInteractionAt > sleepAfter) return MascotMood.sleepy;
      return MascotMood.idle;
  }
}

bool _recently(double? at, double now, double window) =>
    at != null && now - at >= 0 && now - at < window;
