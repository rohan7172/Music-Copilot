import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/harmony.dart';

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

  Future<Analysis> analyzeAudio(Uint8List bytes, {String filename = 'recording.wav'}) async {
    final uri = Uri.parse('$baseUrl/analyze');
    final request = http.MultipartRequest('POST', uri)
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
      throw Exception('Server returned ${response.statusCode}: ${response.body}');
    }

    return Analysis.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
