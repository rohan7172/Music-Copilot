import 'package:flutter_test/flutter_test.dart';
import 'package:music_copilot_app/widgets/mascot.dart';
import 'package:music_copilot_app/widgets/score_canvas.dart';

void main() {
  group('expressionForPhase', () {
    test('maps each phase to its own expression', () {
      expect(expressionForPhase(Phase.idle), MascotExpression.idle);
      expect(expressionForPhase(Phase.recording), MascotExpression.listening);
      expect(expressionForPhase(Phase.analyzing), MascotExpression.analyzing);
      expect(expressionForPhase(Phase.settled), MascotExpression.revealing);
    });

    test('every phase maps to a distinct expression', () {
      final expressions = Phase.values.map(expressionForPhase).toSet();
      expect(expressions.length, Phase.values.length);
    });
  });
}
