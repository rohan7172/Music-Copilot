import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// Reads the bytes of a finished recording. On web, `record` hands back a
/// blob URL rather than a file path.
Future<Uint8List> readRecording(String path) async {
  if (kIsWeb) {
    final response = await http.get(Uri.parse(path));
    return response.bodyBytes;
  }
  return File(path).readAsBytes();
}
