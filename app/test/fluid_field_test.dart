import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_copilot_app/models/note.dart';
import 'package:music_copilot_app/widgets/fluid_field.dart';
import 'package:music_copilot_app/widgets/score_canvas.dart' show Phase, Scene;

Note _note(int midiPitch, double start, double end) => Note(
  pitch: 'x',
  midiPitch: midiPitch,
  startTime: start,
  endTime: end,
  confidence: 1,
);

void main() {
  const size = Size(400, 800);

  group('edgeAnchor', () {
    test('spans the full rim, corner to corner, down to the true bottom corners', () {
      final start = edgeAnchor(0, size);
      expect(start, const Offset(0, 800)); // true bottom-left corner

      final topMid = edgeAnchor(0.5, size);
      expect(topMid.dy, 0); // somewhere along the top edge

      final end = edgeAnchor(1, size);
      expect(end, const Offset(400, 800)); // true bottom-right corner
    });

    test('clamps t outside 0..1', () {
      expect(edgeAnchor(-1, size), edgeAnchor(0, size));
      expect(edgeAnchor(2, size), edgeAnchor(1, size));
    });
  });

  group('edgeInward', () {
    test('points away from whichever edge a spike anchors to', () {
      expect(edgeInward(0, size), const Offset(1, 0));
      expect(edgeInward(0.5, size), const Offset(0, 1));
      expect(edgeInward(1, size), const Offset(-1, 0));
    });
  });

  group('edgeTaper', () {
    test('is 0 at both bottom corners and 1 through the middle', () {
      expect(edgeTaper(0, size), 0);
      expect(edgeTaper(1, size), 0);
      expect(edgeTaper(0.5, size), 1);
    });

    test('ramps smoothly rather than snapping', () {
      final near0 = edgeTaper(0.001, size);
      final near1 = edgeTaper(0.999, size);
      expect(near0, greaterThan(0));
      expect(near0, lessThan(0.2));
      expect(near1, greaterThan(0));
      expect(near1, lessThan(0.2));
    });
  });

  group('fieldLengthAt', () {
    test('always stays within 0..1 across a spread of inputs', () {
      final scenes = [Scene()..phase = Phase.idle, Scene()..phase = Phase.recording];
      for (final scene in scenes) {
        for (var t = 0.0; t <= 1.0; t += 0.05) {
          for (var now = 0.0; now < 20.0; now += 0.37) {
            expect(fieldLengthAt(t, now, scene), inInclusiveRange(0.0, 1.0));
          }
        }
      }
    });

    test('never drops to exactly zero, so the rim never shows a literal gap', () {
      final idle = Scene()..phase = Phase.idle;
      for (var t = 0.0; t <= 1.0; t += 0.05) {
        for (var now = 0.0; now < 20.0; now += 0.37) {
          expect(fieldLengthAt(t, now, idle), greaterThan(0.0));
        }
      }
    });

    test('recording in silence is completely stagnant: motionless over time', () {
      final silent = Scene()..phase = Phase.recording; // live stays empty

      // The static Gaussian-overlap pattern around the rim can still vary a
      // little from point to point (every spike shares the same amplitude,
      // but centers and gaps don't contribute identically) - what matters
      // for "stagnant" is that nothing *moves*: the same rim position gives
      // the exact same value no matter when it's sampled.
      for (var t = 0.0; t <= 1.0; t += 0.1) {
        final early = fieldLengthAt(t, 3.0, silent);
        final muchLater = fieldLengthAt(t, 30.0, silent);
        expect(muchLater, early);
      }
    });

    test('louder live volume produces a noticeably taller field than silence', () {
      final loud = Scene()
        ..phase = Phase.recording
        ..live.addAll(List.filled(6, 0.85));
      final silent = Scene()..phase = Phase.recording;

      double maxOverRim(Scene scene, double now) {
        var m = 0.0;
        for (var t = 0.0; t <= 1.0; t += 0.01) {
          m = math.max(m, fieldLengthAt(t, now, scene));
        }
        return m;
      }

      expect(maxOverRim(loud, 5.0), greaterThan(maxOverRim(silent, 5.0)));
    });

    test('field magnitude scales up with volume', () {
      final quiet = Scene()
        ..phase = Phase.recording
        ..live.addAll(List.filled(6, 0.2));
      final loud = Scene()
        ..phase = Phase.recording
        ..live.addAll(List.filled(6, 0.9));

      double avgOverRim(Scene scene, double now) {
        var sum = 0.0;
        var n = 0;
        for (var t = 0.0; t <= 1.0; t += 0.02) {
          sum += fieldLengthAt(t, now, scene);
          n++;
        }
        return sum / n;
      }

      expect(avgOverRim(loud, 4.0), greaterThan(avgOverRim(quiet, 4.0)));
    });

    test('a held, sustained volume keeps pulsating rather than decaying like a one-shot blip', () {
      final held = Scene()
        ..phase = Phase.recording
        ..live.addAll(List.filled(6, 0.8));

      double maxOverRim(double now) {
        var m = 0.0;
        for (var t = 0.0; t <= 1.0; t += 0.01) {
          m = math.max(m, fieldLengthAt(t, now, held));
        }
        return m;
      }

      // Sampled far apart in time with the same held volume throughout -
      // neither should have faded toward the resting floor the way a
      // one-shot pulse would have by the second sample.
      final early = maxOverRim(1.0);
      final muchLater = maxOverRim(40.0);
      const restingFloor = 0.08;
      expect(early, greaterThan(restingFloor + 0.1));
      expect(muchLater, greaterThan(restingFloor + 0.1));
    });

    test('settled with nothing playing reads the same as idle', () {
      final settled = Scene()..phase = Phase.settled;
      final idle = Scene()..phase = Phase.idle;
      for (var t = 0.0; t <= 1.0; t += 0.1) {
        expect(fieldLengthAt(t, 2.0, settled), fieldLengthAt(t, 2.0, idle));
      }
    });

    test('a sounding note pulses its own pitch class noticeably above an unrelated one', () {
      final scene = Scene()
        ..phase = Phase.settled
        ..playingAll = true
        ..playhead = 1.0
        ..notes = [_note(60, 0.5, 1.5)]; // midi 60 = C, pitch class 0

      final cSpikeT = 0 / 12; // pitch class 0's own rim position
      final unrelatedT = 6 / 12; // pitch class 6 (F#), not sounding

      expect(
        fieldLengthAt(cSpikeT, 1.0, scene),
        greaterThan(fieldLengthAt(unrelatedT, 1.0, scene)),
      );
    });

    test('nothing pulses above idle when playingAll is false, even with a playhead', () {
      final scene = Scene()
        ..phase = Phase.settled
        ..playingAll = false
        ..playhead = 1.0
        ..notes = [_note(60, 0.5, 1.5)];
      final idle = Scene()..phase = Phase.idle;

      for (var t = 0.0; t <= 1.0; t += 0.1) {
        expect(fieldLengthAt(t, 1.0, scene), fieldLengthAt(t, 1.0, idle));
      }
    });

    test('two simultaneously-sounding notes of different pitch classes both pulse (a chord)', () {
      final scene = Scene()
        ..phase = Phase.settled
        ..playingAll = true
        ..playhead = 1.0
        ..notes = [
          _note(60, 0.5, 1.5), // pitch class 0 (C)
          _note(64, 0.5, 1.5), // pitch class 4 (E)
        ];
      final nothingPlaying = Scene()..phase = Phase.settled;

      final cT = 0 / 12;
      final eT = 4 / 12;
      expect(fieldLengthAt(cT, 1.0, scene), greaterThan(fieldLengthAt(cT, 1.0, nothingPlaying)));
      expect(fieldLengthAt(eT, 1.0, scene), greaterThan(fieldLengthAt(eT, 1.0, nothingPlaying)));
    });

    test('a note does not pulse before its own start time', () {
      final scene = Scene()
        ..phase = Phase.settled
        ..playingAll = true
        ..playhead = 0.1
        ..notes = [_note(60, 0.5, 1.5)];
      // Actively playing, same instant, but nothing at all to sound yet -
      // the "nothing currently active" baseline while playingAll is true
      // (distinct from the idle-ripple fallback, which only kicks in when
      // playingAll is false or there's no playhead at all).
      final baseline = Scene()
        ..phase = Phase.settled
        ..playingAll = true
        ..playhead = 0.1;

      expect(fieldLengthAt(0 / 12, 0.1, scene), fieldLengthAt(0 / 12, 0.1, baseline));
    });

    test('a note keeps pulsing briefly past its own end, then settles back down', () {
      final scene = Scene()
        ..phase = Phase.settled
        ..playingAll = true
        ..notes = [_note(60, 0.0, 1.0)]; // ends at playhead 1.0

      double cField(double playhead) {
        scene.playhead = playhead;
        return fieldLengthAt(0 / 12, playhead, scene);
      }

      final justAfterEnd = cField(1.05);
      final longAfterEnd = cField(1.0 + 2.0); // well past any reasonable release window

      final baseline = Scene()
        ..phase = Phase.settled
        ..playingAll = true
        ..playhead = 5.0;
      final baselineLevel = fieldLengthAt(0 / 12, 5.0, baseline);

      // Still elevated just after the note's literal end...
      expect(justAfterEnd, greaterThan(baselineLevel));
      // ...but back down to the resting level well after.
      expect(longAfterEnd, closeTo(baselineLevel, 0.01));
    });
  });

  group('activeNoteBubbles', () {
    test('is empty outside settled/playing', () {
      final analyzing = Scene()
        ..phase = Phase.analyzing
        ..playingAll = true
        ..playhead = 1.0
        ..notes = [_note(60, 0.5, 1.5)];
      expect(activeNoteBubbles(analyzing), isEmpty);

      final notPlaying = Scene()
        ..phase = Phase.settled
        ..playingAll = false
        ..playhead = 1.0
        ..notes = [_note(60, 0.5, 1.5)];
      expect(activeNoteBubbles(notPlaying), isEmpty);
    });

    test('is empty right as a note starts, before it crosses the label threshold', () {
      final scene = Scene()
        ..phase = Phase.settled
        ..playingAll = true
        ..playhead = 0.5
        ..notes = [_note(60, 0.5, 1.5)];
      expect(activeNoteBubbles(scene), isEmpty);
    });

    test('labels a clearly-sounding note with its own pitch class', () {
      final scene = Scene()
        ..phase = Phase.settled
        ..playingAll = true
        ..playhead = 1.0
        ..notes = [_note(60, 0.5, 1.5)]; // pitch class 0

      final bubbles = activeNoteBubbles(scene);
      expect(bubbles, hasLength(1));
      expect(bubbles.single.pitchClass, 0);
      expect(bubbles.single.envelope, greaterThan(0));
    });

    test('picks the higher-envelope note when two notes share a pitch class', () {
      final justStarted = _note(60, 0.95, 2.0); // low envelope, barely begun
      final wellIntoIt = _note(72, 0.0, 2.0); // same pitch class (0), fully sounding
      final scene = Scene()
        ..phase = Phase.settled
        ..playingAll = true
        ..playhead = 1.0
        ..notes = [justStarted, wellIntoIt];

      final bubbles = activeNoteBubbles(scene);
      final forC = bubbles.where((b) => b.pitchClass == 0);
      expect(forC, hasLength(1));
      expect(forC.single.note, wellIntoIt);
    });
  });

  group('reachScale', () {
    test('is full strength at idle and recording', () {
      expect(reachScale(Scene()..phase = Phase.idle, 5.0), 1.0);
      expect(reachScale(Scene()..phase = Phase.recording, 5.0), 1.0);
    });

    test('is already settled-small immediately if analyzing with no analyzeStart recorded', () {
      // Defensive case: shouldn't really happen in practice (analyzeStart
      // is always set alongside the phase change), but shouldn't read as
      // "full reach" either if it somehow did.
      expect(reachScale(Scene()..phase = Phase.analyzing, 5.0), lessThan(1.0));
    });

    test('eases from full reach down toward the settled scale across analyzing', () {
      final scene = Scene()
        ..phase = Phase.analyzing
        ..analyzeStart = 10.0;
      final justStarted = reachScale(scene, 10.01);
      final midway = reachScale(scene, 10.3);
      final wellAfter = reachScale(scene, 20.0);

      expect(justStarted, closeTo(1.0, 0.05));
      expect(midway, lessThan(justStarted));
      expect(wellAfter, lessThan(midway));
    });

    test('settles at a constant, smaller reach once truly settled', () {
      final settled = reachScale(Scene()..phase = Phase.settled, 5.0);
      expect(settled, lessThan(1.0));
      expect(settled, reachScale(Scene()..phase = Phase.settled, 99.0));
    });
  });

  group('activeDroplet', () {
    test('is null outside the recording phase, even with a recent peak', () {
      final settled = Scene()
        ..phase = Phase.settled
        ..lastPeakAt = 1.0;
      expect(activeDroplet(1.1, settled, size), isNull);
    });

    test('is null while recording until a peak has actually fired', () {
      final recording = Scene()..phase = Phase.recording;
      expect(activeDroplet(5.0, recording, size), isNull);
    });

    test('is non-null and moving for its duration right after a peak', () {
      final recording = Scene()
        ..phase = Phase.recording
        ..lastPeakAt = 2.0;

      final justAfter = activeDroplet(2.05, recording, size);
      expect(justAfter, isNotNull);
      expect(justAfter!.progress, inInclusiveRange(0.0, 1.0));

      final later = activeDroplet(2.3, recording, size);
      expect(later, isNotNull);
      // It should have traveled further inward (farther from its own edge
      // anchor) as progress advances, not sit frozen in one spot.
      expect(later!.progress, greaterThan(justAfter.progress));
    });

    test('is null again once its duration has fully passed', () {
      final recording = Scene()
        ..phase = Phase.recording
        ..lastPeakAt = 2.0;
      expect(activeDroplet(2.0 + 5.0, recording, size), isNull);
    });
  });
}
