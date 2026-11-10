import 'package:flutter_test/flutter_test.dart';
import 'package:music_copilot_app/session/scene.dart';
import 'package:music_copilot_app/widgets/mascot/mascot_mood.dart';

MascotMood mood({
  Phase phase = Phase.idle,
  double now = 100,
  bool hasError = false,
  double lastInteractionAt = 100,
  double? lastTapAt,
  double? settleStart,
  bool playing = false,
  int noteCount = 5,
  double? keyConfidence = 0.9,
  bool boldSelected = false,
  double? cadenceAt,
}) => moodFor(
  phase: phase,
  now: now,
  hasError: hasError,
  lastInteractionAt: lastInteractionAt,
  lastTapAt: lastTapAt,
  settleStart: settleStart,
  playing: playing,
  noteCount: noteCount,
  keyConfidence: keyConfidence,
  boldSelected: boldSelected,
  cadenceAt: cadenceAt,
);

void main() {
  test('an error always reads as surprised', () {
    for (final phase in Phase.values) {
      expect(mood(phase: phase, hasError: true), MascotMood.surprised);
    }
  });

  test('recording listens, analyzing concentrates', () {
    expect(mood(phase: Phase.recording), MascotMood.listening);
    expect(mood(phase: Phase.analyzing), MascotMood.concentrating);
  });

  test('idle dozes off only after a long while untouched', () {
    expect(mood(lastInteractionAt: 90), MascotMood.idle);
    expect(mood(lastInteractionAt: 100 - sleepAfter - 1), MascotMood.sleepy);
  });

  test('a fresh tap gets a reaction that wears off', () {
    expect(mood(lastTapAt: 99.8), MascotMood.tapped);
    expect(mood(lastTapAt: 99), MascotMood.idle);
  });

  test('results land happy, or excited when the key is clear', () {
    expect(
      mood(phase: Phase.settled, settleStart: 99.5, keyConfidence: 0.9),
      MascotMood.excited,
    );
    expect(
      mood(phase: Phase.settled, settleStart: 99.5, keyConfidence: 0.6),
      MascotMood.happy,
    );
    expect(mood(phase: Phase.settled, settleStart: 90), MascotMood.idle);
  });

  test('settled with nothing found, or an unsure key, is curious', () {
    expect(mood(phase: Phase.settled, noteCount: 0), MascotMood.curious);
    expect(
      mood(phase: Phase.settled, settleStart: 90, keyConfidence: 0.2),
      MascotMood.curious,
    );
    expect(
      mood(phase: Phase.settled, settleStart: 90, keyConfidence: null),
      MascotMood.curious,
    );
  });

  test('playback sings along, over the reveal reaction', () {
    expect(
      mood(phase: Phase.settled, settleStart: 99.5, playing: true),
      MascotMood.singing,
    );
  });

  test(
    'the Bold card gets a curious tilt; a cadence in playback a happy beat',
    () {
      expect(
        mood(phase: Phase.settled, settleStart: 90, boldSelected: true),
        MascotMood.curious,
      );
      expect(
        mood(
          phase: Phase.settled,
          settleStart: 90,
          playing: true,
          cadenceAt: 99.5,
        ),
        MascotMood.happy,
      );
      expect(
        mood(
          phase: Phase.settled,
          settleStart: 90,
          playing: true,
          cadenceAt: 90,
        ),
        MascotMood.singing,
      );
    },
  );
}
