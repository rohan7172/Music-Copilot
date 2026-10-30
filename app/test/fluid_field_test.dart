import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_copilot_app/widgets/fluid_field.dart';
import 'package:music_copilot_app/widgets/score_canvas.dart' show Phase;

void main() {
  const size = Size(400, 800);

  group('edgeAnchor', () {
    test('never reaches into the reserved bottom strip', () {
      final fluidBottom = size.height * (1 - fluidBottomReserve);
      for (var i = 0; i <= 100; i++) {
        final t = i / 100;
        final anchor = edgeAnchor(t, size, fluidBottomReserve);
        expect(anchor.dy, lessThanOrEqualTo(fluidBottom + 0.001));
      }
    });

    test('covers the left edge, top edge, and right edge in order', () {
      final start = edgeAnchor(0, size, fluidBottomReserve);
      expect(start.dx, 0); // left edge, starting at the reserved line
      expect(start.dy, closeTo(size.height * (1 - fluidBottomReserve), 0.001));

      final topMid = edgeAnchor(0.5, size, fluidBottomReserve);
      expect(topMid.dy, 0); // somewhere along the top edge

      final end = edgeAnchor(1, size, fluidBottomReserve);
      expect(end.dx, size.width); // right edge
      expect(end.dy, closeTo(size.height * (1 - fluidBottomReserve), 0.001));
    });

    test('clamps t outside 0..1', () {
      expect(edgeAnchor(-1, size, fluidBottomReserve), edgeAnchor(0, size, fluidBottomReserve));
      expect(edgeAnchor(2, size, fluidBottomReserve), edgeAnchor(1, size, fluidBottomReserve));
    });
  });

  group('edgeInward', () {
    test('points away from whichever edge a spike anchors to', () {
      expect(edgeInward(0, size, fluidBottomReserve), const Offset(1, 0));
      expect(edgeInward(0.5, size, fluidBottomReserve), const Offset(0, 1));
      expect(edgeInward(1, size, fluidBottomReserve), const Offset(-1, 0));
    });
  });

  group('fieldLengthAt', () {
    test('always stays within 0..1 across a spread of inputs', () {
      for (var t = 0.0; t <= 1.0; t += 0.05) {
        for (var now = 0.0; now < 20.0; now += 0.37) {
          expect(fieldLengthAt(t, now, Phase.recording), inInclusiveRange(0.0, 1.0));
          expect(fieldLengthAt(t, now, Phase.idle), inInclusiveRange(0.0, 1.0));
        }
      }
    });

    test('never drops to exactly zero, so the rim never shows a literal gap', () {
      for (var t = 0.0; t <= 1.0; t += 0.05) {
        for (var now = 0.0; now < 20.0; now += 0.37) {
          expect(fieldLengthAt(t, now, Phase.idle), greaterThan(0.0));
        }
      }
    });

    test('recording reaches noticeably farther than idle, on average', () {
      var recordingSum = 0.0, idleSum = 0.0;
      var samples = 0;
      for (var t = 0.0; t <= 1.0; t += 0.02) {
        for (var now = 0.0; now < 10.0; now += 0.31) {
          recordingSum += fieldLengthAt(t, now, Phase.recording);
          idleSum += fieldLengthAt(t, now, Phase.idle);
          samples++;
        }
      }
      expect(recordingSum / samples, greaterThan(idleSum / samples * 1.5));
    });
  });
}
