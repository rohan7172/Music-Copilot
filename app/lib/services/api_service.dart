import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/harmony.dart';
import '../models/note.dart';

final _mediaTypesByExtension = {
  'wav': MediaType('audio', 'wav'),
  'mp3': MediaType('audio', 'mpeg'),
  'm4a': MediaType('audio', 'mp4'),
};

/// The content type to upload a file as, inferred from its extension.
/// Falls back to WAV for anything unrecognised.
MediaType mediaTypeForFilename(String filename) {
  final extension = filename.split('.').last.toLowerCase();
  return _mediaTypesByExtension[extension] ?? _mediaTypesByExtension['wav']!;
}

/// Talks to the Music Copilot backend.
///
/// Defaults to 127.0.0.1, which the iOS Simulator and a local web build can
/// reach directly. A physical device needs the host's LAN IP instead, e.g.
/// `flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000`.
class ApiService {
  ApiService({
    this.baseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8000',
    ),
  });

  final String baseUrl;

  /// Transcribes a take and suggests progressions for its melody. Pass
  /// [bpm] and [firstBeat] (seconds into the take) when a click was played,
  /// so the beat grid is exact instead of estimated.
  Future<Analysis> analyzeAudio(
    Uint8List bytes, {
    String filename = 'recording.wav',
    double? bpm,
    double? firstBeat,
    int meter = 4,
  }) async {
    final uri = Uri.parse('$baseUrl/analyze');
    final request = http.MultipartRequest('POST', uri)
      ..fields.addAll({
        if (bpm != null) 'bpm': '$bpm',
        if (firstBeat != null) 'first_beat': '$firstBeat',
        'meter': '$meter',
      })
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: mediaTypeForFilename(filename),
        ),
      );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception(
        'Server returned ${response.statusCode}: ${response.body}',
      );
    }

    return Analysis.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Re-suggests for an already-analyzed melody after a grid nudge or key
  /// override. No audio is sent.
  Future<Suggestions> harmonise({
    required List<Note> melody,
    required BeatGrid grid,
    MusicKey? key,
    int perBar = 1,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/harmonise'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'melody': [for (final n in melody) n.toJson()],
        'grid': grid.toJson(),
        if (key != null) 'key': key.toJson(),
        'per_bar': perBar,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Server returned ${response.statusCode}: ${response.body}',
      );
    }
    return Suggestions.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// A background song analysis's progress, and its result once done.
  Future<SongJob> job(String id) async {
    final response = await http.get(Uri.parse('$baseUrl/jobs/$id'));
    if (response.statusCode != 200) {
      throw Exception(
        'Server returned ${response.statusCode}: ${response.body}',
      );
    }
    return SongJob.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// A WAV of [chords] played as a soft pad, [duration] seconds long.
  Future<Uint8List> backing(
    List<ProgressionChord> chords,
    double duration,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/backing'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'chords': [for (final c in chords) c.toBackingJson()],
        'duration': duration,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Server returned ${response.statusCode}: ${response.body}',
      );
    }
    return response.bodyBytes;
  }
}
