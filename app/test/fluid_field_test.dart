import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_copilot_app/widgets/fluid_field.dart';
import 'package:music_copilot_app/widgets/score_canvas.dart' show Phase, Scene;

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
  });
}
