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

    test('recording with no peak yet stays calm and uniform, not a generic wave', () {
      final scene = Scene()..phase = Phase.recording; // lastPeakAt still null
      final values = [for (var t = 0.0; t <= 1.0; t += 0.02) fieldLengthAt(t, 3.0, scene)];
      final spread = values.reduce(math.max) - values.reduce(math.min);
      expect(spread, lessThan(0.03));
    });

    test('a peak produces a noticeably taller field than idle ever reaches', () {
      final recording = Scene()
        ..phase = Phase.recording
        ..lastPeakAt = 5.0;
      final idle = Scene()..phase = Phase.idle;

      double maxOverRim(Scene scene, double now) {
        var m = 0.0;
        for (var t = 0.0; t <= 1.0; t += 0.01) {
          m = math.max(m, fieldLengthAt(t, now, scene));
        }
        return m;
      }

      final peakMax = maxOverRim(recording, 5.05);
      final idleMax = maxOverRim(idle, 5.05);
      expect(peakMax, greaterThan(idleMax));
    });

    test('a peak pulse decays back to resting after its duration', () {
      final scene = Scene()
        ..phase = Phase.recording
        ..lastPeakAt = 2.0;

      double maxOverRim(double now) {
        var m = 0.0;
        for (var t = 0.0; t <= 1.0; t += 0.01) {
          m = math.max(m, fieldLengthAt(t, now, scene));
        }
        return m;
      }

      final justAfter = maxOverRim(2.1);
      final longAfter = maxOverRim(4.0);
      expect(justAfter, greaterThan(longAfter));
    });
  });
}
