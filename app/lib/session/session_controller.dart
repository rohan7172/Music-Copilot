import 'dart:async';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../audio/pick_audio_file.dart';
import '../audio/read_recording.dart';
import '../audio/waveform.dart';
import '../models/harmony.dart';
import '../models/note.dart';
import '../note_range.dart';
import '../services/api_service.dart';
import 'scene.dart';

/// Something went wrong badly enough to stop the session: shown on its own
/// screen with a plain [title], a recovery-oriented [message], and the raw
/// [detail] for debugging.
class SessionError {
  const SessionError(this.title, this.message, [this.detail]);

  final String title;
  final String message;
  final String? detail;
}

/// Owns a recording session end to end — microphone, backend round-trip,
/// playback — so the screens can be plain readers of its state.
///
/// A [ChangeNotifier] fires on discrete changes (phase, results, play/pause,
/// selection). Anything that moves every frame (the playhead, live loudness,
/// animation) is read off [clock], which ticks once per frame.
class SessionController extends ChangeNotifier {
  SessionController({required TickerProvider vsync, ApiService? api})
    : _api = api ?? ApiService() {
    _ticker = vsync.createTicker(_onTick)..start();
    _watchPlayer();
    scene.introStart = 0;
  }

  final ApiService _api;
  final AudioRecorder _recorder = AudioRecorder();
  AudioPlayer _player = AudioPlayer();
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Amplitude>? _amplitudeSub;
  late final Ticker _ticker;
  final Stopwatch _recordingTime = Stopwatch();

  /// Seconds since the controller was created; drives every animation.
  final ValueNotifier<double> clock = ValueNotifier(0);
  final Scene scene = Scene();

  Phase get phase => scene.phase;

  SessionError? error;

  /// Plain-language explanation of the detected key and chords. Null until
  /// an analysis has come back.
  Explanation? explanation;

  /// Whether a finished take is loaded and can be played.
  bool playbackReady = false;

  /// Whether whole-take playback starts over when it reaches the end.
  bool loop = false;

  /// Clock time of the user's last touch anywhere, and of their last tap on
  /// the mascot itself — the mascot dozes off after a while without either,
  /// and gives a quick reaction to a direct tap.
  double lastInteractionAt = 0;
  double? lastTapAt;

  /// Where slice playback stops, in seconds into the take.
  double? _playEnd;

  double _lastLoudAt = 0;
  double _lastLevel = 0;
  bool _autoStopping = false;
  bool _disposed = false;

  /// Set while a looping take is seeking back to the start, so the
  /// per-frame check doesn't fire the restart again before it lands.
  bool _restarting = false;

  static const autoStopMinRecording = 10.0;
  static const _autoStopSilence = 3.0;

  /// Curved live-amplitude thresholds: below [_silenceThreshold] reads as
  /// silence for auto-stop; a rising edge above [_peakThreshold] counts as
  /// a loudness peak (see [Scene.lastPeakAt]).
  static const _silenceThreshold = 0.12;
  static const _peakThreshold = 0.5;

  /// Lets the "listening" moment breathe even when the backend is quick.
  static const _minAnalyzeSeconds = 1.6;

  bool get isPlaying => _player.playing && _playEnd != null;

  /// Notes worth drawing: low-confidence detections are left out, the same
  /// threshold the range-fitting uses (see note_range.dart).
  List<Note> get confidentNotes => [
    for (final n in scene.notes)
      if (n.confidence >= noteConfidenceThreshold) n,
  ];

  /// The chord sounding at the playhead during playback, else the one the
  /// user last tapped.
  int? get activeChord {
    final playhead = scene.playhead;
    if (scene.playingAll && playhead != null) {
      for (var i = 0; i < scene.chords.length; i++) {
        final c = scene.chords[i];
        if (playhead >= c.startTime && playhead < c.endTime) return i;
      }
      return null;
    }
    return scene.selectedChord;
  }

  void _onTick(Duration elapsed) {
    if (phase == Phase.recording) {
      scene.liveDuration = _recordingTime.elapsedMilliseconds / 1000;
      _checkAutoStop();
    }
    _trackPlayback();
    clock.value = elapsed.inMicroseconds / 1e6;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Any touch on the screen: keeps the mascot awake.
  void noteInteraction() {
    final wasAsleep = clock.value - lastInteractionAt > 30;
    lastInteractionAt = clock.value;
    if (wasAsleep) _changed();
  }

  /// A tap on the mascot itself.
  void tapMascot() {
    lastTapAt = clock.value;
    noteInteraction();
    _changed();
  }

  // ---------------------------------------------------------------------
  // Recording

  Future<void> startRecording() async {
    noteInteraction();
    if (!await _recorder.hasPermission()) {
      error = const SessionError(
        'Microphone is off',
        'Allow microphone access for Music Copilot in your device settings, '
            'then try again.',
      );
      _changed();
      return;
    }

    await _resetPlayer();

    // On web the recorder ignores the path and returns a blob URL.
    var path = '';
    if (!kIsWeb) {
      final dir = await getTemporaryDirectory();
      path =
          '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';
    }

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, numChannels: 1),
      path: path,
    );
    _clearResults();
    scene
      ..liveDuration = 0
      ..lastPeakAt = null;
    _lastLoudAt = 0;
    _lastLevel = 0;
    _autoStopping = false;
    _recordingTime
      ..reset()
      ..start();
    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 40))
        .listen(_onAmplitude);

    scene.phase = Phase.recording;
    error = null;
    _changed();
  }

  void _onAmplitude(Amplitude amp) {
    // dBFS -> 0..1, curved so loud playing keeps some shape.
    final level = ((amp.current + 60) / 60).clamp(0.0, 1.0);
    final curved = math.pow(level, 1.6).toDouble();
    scene.live.add(curved);

    if (curved > _silenceThreshold) {
      _lastLoudAt = _recordingTime.elapsedMilliseconds / 1000;
    }
    // A rising edge above a louder threshold, not fired again within a
    // quarter second — an approximate "it's reacting to your rhythm," not a
    // real beat grid (see docs/concepts.md).
    final lastPeak = scene.lastPeakAt;
    if (curved > _peakThreshold &&
        _lastLevel <= _peakThreshold &&
        (lastPeak == null || clock.value - lastPeak > 0.25)) {
      scene.lastPeakAt = clock.value;
    }
    _lastLevel = curved;
  }

  /// "3 s of silence auto-stops after a recording of 10 s or more" — a take
  /// that's gone quiet for a while finishes itself rather than waiting on a
  /// tap, the same as tapping stop would.
  void _checkAutoStop() {
    if (_autoStopping) return;
    if (scene.liveDuration < autoStopMinRecording) return;
    if (scene.liveDuration - _lastLoudAt < _autoStopSilence) return;
    _autoStopping = true;
    unawaited(stopAndAnalyze());
  }

  /// Stops recording and throws the take away.
  Future<void> cancelRecording() async {
    noteInteraction();
    await _recorder.stop();
    _recordingTime.stop();
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _clearResults();
    scene.phase = Phase.idle;
    _changed();
  }

  Future<void> stopAndAnalyze() async {
    noteInteraction();
    final path = await _recorder.stop();
    _recordingTime.stop();
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;

    if (path == null) {
      _fail(
        const SessionError(
          'Nothing was recorded',
          'The microphone didn’t capture any audio. Try recording again.',
        ),
      );
      return;
    }

    _beginAnalyzing();
    try {
      final bytes = await readRecording(path);
      final waveform =
          Waveform.fromWavBytes(bytes) ??
          Waveform(normalizeEnvelope(scene.live), scene.liveDuration);
      scene.waveform = waveform;
      unawaited(_loadPlayback(path));

      final analysis = await _api.analyzeAudio(bytes);
      await _letAnalyzingBreathe();
      if (_disposed) return;
      _settle(analysis);
    } catch (e) {
      if (_disposed) return;
      _fail(_analysisError(e));
    }
  }

  // ---------------------------------------------------------------------
  // File import

  Future<void> pickAndAnalyzeFile() async {
    noteInteraction();
    final PickedAudio picked;
    try {
      final result = await pickAudioFile();
      if (result == null) return;
      picked = result;
    } catch (e) {
      _fail(
        SessionError(
          'Couldn’t open that file',
          'Pick a WAV, MP3 or M4A audio file and try again.',
          '$e',
        ),
      );
      return;
    }

    await _resetPlayer();
    _clearResults();
    scene.liveDuration = 0;
    _beginAnalyzing();

    try {
      // A real envelope if this is WAV; otherwise synthesized from the
      // notes once they come back.
      final waveform = Waveform.fromWavBytes(picked.bytes);
      scene.waveform = waveform;
      unawaited(_loadPlayback(picked.playbackSource));

      final analysis = await _api.analyzeAudio(
        picked.bytes,
        filename: picked.filename,
      );
      await _letAnalyzingBreathe();
      if (_disposed) return;

      if (waveform == null) {
        final notes = analysis.notes;
        final duration = notes.isEmpty
            ? 1.0
            : notes.map((n) => n.endTime).reduce(math.max) + 0.2;
        scene.waveform = Waveform.fromNoteActivity(notes, duration);
      }
      _settle(analysis);
    } catch (e) {
      if (_disposed) return;
      _fail(_analysisError(e));
    }
  }

  // ---------------------------------------------------------------------
  // Phase changes

  void _beginAnalyzing() {
    scene
      ..phase = Phase.analyzing
      ..analyzeStart = clock.value;
    error = null;
    _changed();
  }

  Future<void> _letAnalyzingBreathe() async {
    final start = scene.analyzeStart ?? clock.value;
    final wait = start + _minAnalyzeSeconds - clock.value;
    if (wait > 0) {
      await Future<void>.delayed(Duration(milliseconds: (wait * 1000).round()));
    }
  }

  void _settle(Analysis analysis) {
    scene
      ..notes = analysis.notes
      ..chords = analysis.chords
      ..key = analysis.key
      ..selected = null
      ..selectedChord = null
      ..settleStart = clock.value
      ..phase = Phase.settled;
    explanation = analysis.explanation;
    _changed();
  }

  void _fail(SessionError e) {
    error = e;
    scene.phase = Phase.idle;
    _changed();
  }

  SessionError _analysisError(Object e) {
    final text = '$e';
    final unreachable =
        text.contains('ClientException') ||
        text.contains('SocketException') ||
        text.contains('Connection') ||
        text.contains('Failed to fetch');
    if (unreachable) {
      return SessionError(
        'Can’t reach the analyzer',
        'The analysis server isn’t answering. Start the backend '
            '(./dev.sh) and try again.',
        text,
      );
    }
    return SessionError(
      'Couldn’t analyze that',
      'Something went wrong while finding the notes. Try another take.',
      text,
    );
  }

  /// Back to the start screen, ready for a new take.
  Future<void> newTake() async {
    noteInteraction();
    await _resetPlayer();
    _clearResults();
    error = null;
    scene.phase = Phase.idle;
    _changed();
  }

  void dismissError() {
    noteInteraction();
    error = null;
    _changed();
  }

  void _clearResults() {
    scene
      ..live.clear()
      ..waveform = null
      ..notes = const []
      ..chords = const []
      ..key = null
      ..selected = null
      ..selectedChord = null
      ..settleStart = null
      ..playhead = null
      ..playingAll = false;
    explanation = null;
  }

  // ---------------------------------------------------------------------
  // Playback

  Future<void> _loadPlayback(String path) async {
    try {
      if (!kIsWeb) {
        // The recorder leaves the session in record mode; on iOS that
        // routes playback to the earpiece.
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.music());
      }
      final player = _player;
      await (kIsWeb ? player.setUrl(path) : player.setFilePath(path));
      // Ignore a load that finishes after another take has started.
      if (player == _player) {
        playbackReady = true;
        _changed();
      }
    } catch (e) {
      // Playback is a nice-to-have; the notes still work without it.
      debugPrint('Could not load recording for playback: $e');
    }
  }

  /// Plays the whole take, or pauses it if it's already playing. Resumes
  /// from where it was paused; starts over once it has played to the end.
  Future<void> togglePlay() async {
    noteInteraction();
    if (!playbackReady) return;
    if (scene.playingAll && _player.playing) {
      await _player.pause();
      _changed();
      return;
    }
    final duration = scene.duration;
    final resume =
        scene.playingAll && (scene.playhead ?? duration) < duration - 0.05;
    scene
      ..selected = null
      ..selectedChord = null
      ..playingAll = true;
    if (!resume) await _player.seek(Duration.zero);
    _playEnd = duration;
    unawaited(_player.play());
    _changed();
  }

  /// Seeks to [seconds] and plays onward to the end of the take.
  Future<void> seek(double seconds) async {
    noteInteraction();
    if (!playbackReady) return;
    final t = seconds.clamp(0.0, scene.duration);
    scene
      ..selected = null
      ..selectedChord = null
      ..playingAll = true
      ..playhead = t;
    await _player.seek(Duration(microseconds: (t * 1e6).round()));
    _playEnd = scene.duration;
    unawaited(_player.play());
    _changed();
  }

  /// Plays just note [index]'s slice of the take (index into [Scene.notes]).
  void playNote(int index) {
    final note = scene.notes[index];
    scene
      ..selected = index
      ..selectedChord = null;
    unawaited(_playRange(note.startTime, note.endTime));
  }

  /// Plays chord [index]'s span of the take.
  void playChord(int index) {
    final chord = scene.chords[index];
    scene
      ..selected = null
      ..selectedChord = index;
    unawaited(_playRange(chord.startTime, chord.endTime));
  }

  void toggleLoop() {
    noteInteraction();
    loop = !loop;
    _changed();
  }

  /// Plays from [from] to [to] seconds, with a little air on either side so
  /// short notes don't sound clipped.
  Future<void> _playRange(double from, double to) async {
    noteInteraction();
    if (!playbackReady) {
      _changed();
      return;
    }
    final start = math.max(0.0, from - 0.03);
    final end = math.min(scene.duration, math.max(to + 0.05, start + 0.25));
    scene.playingAll = false;
    await _player.pause();
    await _player.seek(Duration(microseconds: (start * 1e6).round()));
    _playEnd = end;
    scene.playhead = start;
    unawaited(_player.play());
    _changed();
  }

  Future<void> _stopPlayback() async {
    _playEnd = null;
    scene
      ..playhead = null
      ..playingAll = false;
    if (_player.playing) await _player.pause();
    _changed();
  }

  /// Each take gets a fresh player: reusing one kept playing the previous
  /// take after the new one was loaded (seen on web).
  Future<void> _resetPlayer() async {
    await _stopPlayback();
    playbackReady = false;
    final old = _player;
    _player = AudioPlayer();
    _watchPlayer();
    await old.dispose();
  }

  /// Rebuilds when playback starts or stops, so play/pause follows.
  void _watchPlayer() {
    _playingSub?.cancel();
    _playingSub = _player.playingStream.listen((_) => _changed());
  }

  /// Every frame: moves the playhead, loops or stops at the slice's end.
  void _trackPlayback() {
    final end = _playEnd;
    if (end == null) return;
    final position = _player.position.inMicroseconds / 1e6;
    // just_audio keeps `playing` true after reaching the end, so check the
    // processing state rather than `playing`.
    final finished = _player.processingState == ProcessingState.completed;
    if (position >= end - 0.02 || finished) {
      if (loop && scene.playingAll) {
        if (_restarting) return;
        _restarting = true;
        scene.playhead = 0;
        unawaited(
          _player.seek(Duration.zero).then((_) {
            _restarting = false;
            return _player.play();
          }),
        );
        return;
      }
      unawaited(_stopPlayback());
      return;
    }
    if (_player.playing) scene.playhead = position;
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    _amplitudeSub?.cancel();
    _recorder.dispose();
    _playingSub?.cancel();
    _player.dispose();
    clock.dispose();
    super.dispose();
  }
}
