import 'dart:io' show File;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../services/api_service.dart';

/// An audio file the user picked: its bytes, a name for the upload, and a
/// source `just_audio` can play directly.
class PickedAudio {
  PickedAudio({
    required this.bytes,
    required this.filename,
    required this.playbackSource,
  });

  final Uint8List bytes;
  final String filename;

  /// A file path natively; a data URI on web, since `file_picker` only gives
  /// bytes there, with no usable path or blob URL of its own.
  final String playbackSource;
}

/// Opens the system file picker restricted to wav/mp3/m4a. Returns null if
/// the user cancelled.
Future<PickedAudio?> pickAudioFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['wav', 'mp3', 'm4a'],
    withData: kIsWeb,
  );
  if (result == null || result.files.isEmpty) return null;
  final picked = result.files.first;

  if (kIsWeb) {
    final bytes = picked.bytes!;
    final dataUri = Uri.dataFromBytes(
      bytes,
      mimeType: mediaTypeForFilename(picked.name).toString(),
    );
    return PickedAudio(
      bytes: bytes,
      filename: picked.name,
      playbackSource: dataUri.toString(),
    );
  }
  final bytes = await File(picked.path!).readAsBytes();
  return PickedAudio(
    bytes: bytes,
    filename: picked.name,
    playbackSource: picked.path!,
  );
}
