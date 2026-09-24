import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/note.dart';

/// Talks to the Music Copilot backend.
///
/// Defaults to 127.0.0.1, which the iOS Simulator can reach directly since
/// it shares the host machine's network. A physical device needs the host's
/// LAN IP instead.
class ApiService {
  ApiService({this.baseUrl = 'http://127.0.0.1:8000'});

  final String baseUrl;

  Future<List<Note>> analyzeAudio(File audioFile) async {
    final uri = Uri.parse('$baseUrl/analyze');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        await http.MultipartFile.fromPath(
          'file',
          audioFile.path,
          contentType: MediaType('audio', 'wav'),
        ),
      );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception('Server returned ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final notesJson = data['notes'] as List<dynamic>;
    return notesJson.map((n) => Note.fromJson(n as Map<String, dynamic>)).toList();
  }
}
