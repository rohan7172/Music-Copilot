import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/harmony.dart';

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

  Future<Analysis> analyzeAudio(Uint8List wavBytes) async {
    final uri = Uri.parse('$baseUrl/analyze');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          wavBytes,
          filename: 'recording.wav',
          contentType: MediaType('audio', 'wav'),
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
