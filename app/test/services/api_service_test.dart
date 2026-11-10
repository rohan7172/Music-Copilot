import 'package:flutter_test/flutter_test.dart';
import 'package:music_copilot_app/services/api_service.dart';

void main() {
  group('mediaTypeForFilename', () {
    test('recognises .wav', () {
      final type = mediaTypeForFilename('recording.wav');
      expect(type.type, 'audio');
      expect(type.subtype, 'wav');
    });

    test('recognises .mp3', () {
      final type = mediaTypeForFilename('song.mp3');
      expect(type.type, 'audio');
      expect(type.subtype, 'mpeg');
    });

    test('recognises .m4a', () {
      final type = mediaTypeForFilename('song.m4a');
      expect(type.type, 'audio');
      expect(type.subtype, 'mp4');
    });

    test('is case-insensitive', () {
      final type = mediaTypeForFilename('SONG.MP3');
      expect(type.subtype, 'mpeg');
    });

    test('falls back to wav for an unrecognised extension', () {
      final type = mediaTypeForFilename('mystery.xyz');
      expect(type.type, 'audio');
      expect(type.subtype, 'wav');
    });
  });
}
