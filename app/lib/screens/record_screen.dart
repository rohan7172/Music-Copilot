import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/api_service.dart';
import 'results_screen.dart';

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final ApiService _apiService = ApiService();

  bool _isRecording = false;
  bool _isAnalyzing = false;
  String? _errorMessage;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      setState(() => _errorMessage = 'Microphone permission is required to record.');
      return;
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder.start(const RecordConfig(encoder: AudioEncoder.wav), path: path);
    setState(() {
      _isRecording = true;
      _errorMessage = null;
    });
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    setState(() => _isRecording = false);

    if (path == null) {
      setState(() => _errorMessage = 'Recording failed, no audio captured.');
      return;
    }

    setState(() => _isAnalyzing = true);
    try {
      final notes = await _apiService.analyzeAudio(File(path));
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => ResultsScreen(notes: notes)),
      );
    } catch (e) {
      setState(() => _errorMessage = 'Could not analyze recording: $e');
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Music Copilot')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            if (_isAnalyzing)
              const CircularProgressIndicator()
            else
              GestureDetector(
                onTap: _isRecording ? _stopRecording : _startRecording,
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: _isRecording ? Colors.red : Colors.blue,
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.mic,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(_isRecording ? 'Recording... tap to stop' : 'Tap to record'),
          ],
        ),
      ),
    );
  }
}
