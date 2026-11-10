import 'dart:async';
import 'dart:io' show File;
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

/// How the chosen harmony line is heard: not at all (the usual take +
/// chords), on its own, with just the sung melody, or with just the music.
enum HarmonyMix { off, alone, withMelody, withMusic }

/// A synthesized track (the chord pad, a harmony line, the melody as a
/// guide) played in step with the take. Each load gets a fresh player,
/// and a load that a newer one overtook is thrown away.
class _AuxTrack {
  _AuxTrack(this.name);

  final String name;
  AudioPlayer player = AudioPlayer();
  bool ready = false;
  int _request = 0;

  /// Fetches and loads new audio; false if it was overtaken or failed.
  Future<bool> load(Future<Uint8List> Function() fetch) async {
    final request = ++_request;
    ready = false;
    try {
      final bytes = await fetch();
      if (request != _request) return false;
      final fresh = AudioPlayer();
      if (kIsWeb) {
        await fresh.setUrl(
          Uri.dataFromBytes(bytes, mimeType: 'audio/wav').toString(),
        );
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/${name}_$request.wav');
        await file.writeAsBytes(bytes);
        await fresh.setFilePath(file.path);
      }
      if (request != _request) {
        await fresh.dispose();
        return false;
      }
      final old = player;
      player = fresh;
      ready = true;
      unawaited(old.dispose());
      return true;
    } catch (e) {
      // The take still plays without this track.
      debugPrint('Could not load $name: $e');
      return false;
    }
  }

  /// Forgets the loaded audio (and any load in flight).
  void clear() {
    _request++;
    ready = false;
    unawaited(player.pause());
  }

  void dispose() => player.dispose();
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

  /// The suggested progressions, beat grid, key and insight for the take.
  /// Null until an analysis has come back.
  Suggestions? suggestions;

  /// The single tune line the suggestions were built from.
  List<Note> melody = const [];

  /// A note when the take wasn't a plain melody (a chord part, a song).
  String? routeNote;

  /// Which progression card is showing (0 = Safe, 1 = Colourful, 2 = Bold).
  int selectedProgression = 0;

  /// Chords per bar the suggestions use: 1, or 2 for a faster harmonic rhythm.
  int perBar = 1;

  /// True while re-suggesting after a grid nudge.
  bool regridding = false;

  /// Whether the chosen progression plays under the take.
  bool withBacking = true;
  bool get backingReady => _backing.ready;
  final _backing = _AuxTrack('backing');

  /// Lines a second singer could sing with the melody, over the chosen
  /// progression (High, Low, Held), and which one is chosen.
  List<HarmonyLine> harmonies = const [];
  int selectedHarmony = 0;
  HarmonyMix harmonyMix = HarmonyMix.off;
  int _harmoniesRequest = 0;
  final _harmonyTrack = _AuxTrack('harmony');

  /// The melody sung by the synth voice: what "with the melody" plays when
  /// no recording of the singing on its own is available.
  final _guide = _AuxTrack('guide');

  /// "melody", "polyphonic" or "full_mix": what the take turned out to be.
  String route = 'melody';

  /// Click while recording, for an exact beat grid. Off by default.
  bool clickOn = false;
  double clickBpm = 90;
  AudioPlayer? _clickPlayer;
  Timer? _clickTimer;
  double? _firstClickAt;

  /// While a song's own chords are being recognised in the background:
  /// its stage ("Separating the instruments") and progress (0..1).
  String? songStage;
  double songProgress = 0;
  Timer? _songPoll;
  String? _songJobId;

  /// For a song: each instrument's part, and which one the screen is
  /// showing ("mix" for everything together).
  List<SongPart> parts = const [];
  String lens = 'mix';
  List<Note> _mixNotes = const [];

  /// What the take player plays when no part is soloed.
  String? _takeSource;

  /// What the take player has loaded right now.
  String? _loadedSource;

  /// Play was pressed while the take player was loading.
  bool _playWhenReady = false;

  /// Clock time a cadence last resolved during playback (V→I or IV→I into
  /// the final chord), for the mascot's happy beat.
  double? lastCadenceAt;
  int? _lastSoundingChord;

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

  Progression? get progression {
    final all = suggestions?.progressions ?? const [];
    if (all.isEmpty) return null;
    return all[selectedProgression.clamp(0, all.length - 1)];
  }

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
    _noticeActiveChord();
    clock.value = elapsed.inMicroseconds / 1e6;
  }

  /// The contour repaints every frame, but the chord cards only rebuild when
  /// told to, so tell them each time playback moves on to another chord.
  void _noticeActiveChord() {
    final now = activeChord;
    if (now == _shownChord) return;
    _shownChord = now;
    _changed();
  }

  int? _shownChord;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Lets a test or preview harness that has set up [scene] directly
  /// refresh the screens.
  @visibleForTesting
  void debugNotify() => _changed();

  /// Lets a test or preview harness show results without audio or a
  /// backend round-trip.
  @visibleForTesting
  void debugSettle(Analysis analysis, {double duration = 30}) {
    scene.waveform = Waveform(const [0.5, 0.5], duration);
    _settle(analysis);
    if (analysis.parts.isNotEmpty) _showSong(analysis);
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
    _firstClickAt = null;
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
    if (clickOn) unawaited(_startClick());

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
    _stopClick();
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
    final clicked = _firstClickAt;
    _stopClick();
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

      final analysis = await _api.analyzeAudio(
        bytes,
        bpm: clicked == null ? null : clickBpm,
        firstBeat: clicked,
      );
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
    _stopSongPoll();
    if (analysis.jobId != null) _pollSong(analysis.jobId!);
    suggestions = analysis.suggestions;
    melody = analysis.melody;
    routeNote = analysis.routeNote;
    route = analysis.route;
    selectedProgression = 0;
    perBar = 1;
    _loadGuide();
    scene
      ..notes = analysis.notes
      ..key = analysis.suggestions.key
      ..selected = null
      ..selectedChord = null
      ..settleStart = clock.value
      ..phase = Phase.settled;
    _showProgression();
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
    suggestions = null;
    melody = const [];
    routeNote = null;
    _stopSongPoll();
    _songJobId = null;
    parts = const [];
    lens = 'mix';
    _mixNotes = const [];
    _playWhenReady = false;
    _backing.clear();
    _harmonyTrack.clear();
    _guide.clear();
    harmonies = const [];
    _harmoniesRequest++;
    harmonyMix = HarmonyMix.off;
    route = 'melody';
    lastCadenceAt = null;
    _lastSoundingChord = null;
  }

  // ---------------------------------------------------------------------
  // Songs

  void _pollSong(String id) {
    _songJobId = id;
    songStage = 'Starting';
    songProgress = 0;
    _songPoll = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      try {
        final job = await _api.job(id);
        if (_disposed || _songPoll == null) return;
        if (job.status == 'running') {
          songStage = job.stage;
          songProgress = job.progress;
        } else {
          _stopSongPoll();
          if (job.status == 'done' && job.result != null) {
            _showSong(job.result!);
          } else {
            routeNote =
                'Couldn’t recognise this song’s own chords (${job.error ?? 'unknown error'}). '
                'The suggestions follow its top line.';
          }
        }
        _changed();
      } catch (e) {
        debugPrint('Polling the song job failed: $e');
      }
    });
  }

  void _stopSongPoll() {
    _songPoll?.cancel();
    _songPoll = null;
    songStage = null;
  }

  /// Swaps the quick melody-based answer for the song's real progression
  /// (the Original card first) and its vocal melody, keeping playback.
  void _showSong(Analysis song) {
    suggestions = song.suggestions;
    melody = song.melody;
    routeNote = null;
    parts = song.parts;
    lens = 'mix';
    _mixNotes = song.notes;
    selectedProgression = 0;
    perBar = 1;
    _loadGuide();
    // The vocal and instrumental stems now exist: "with the melody" and
    // "with the music" can play the real recording's parts.
    unawaited(_switchSource());
    scene
      ..notes = song.notes
      ..key = song.suggestions.key
      ..selected = null
      ..selectedChord = null
      ..settleStart = clock.value;
    _showProgression();
  }

  /// Shows one instrument's part (its notes in the contour, its role) and
  /// plays it alone from its separated stem; "mix" goes back to the whole
  /// recording.
  Future<void> setLens(String id) async {
    noteInteraction();
    if (id == lens) return;
    lens = id;
    final part = parts.where((p) => p.id == id).firstOrNull;
    scene
      ..notes = part?.notes ?? _mixNotes
      ..selected = null;
    _changed();
    await _switchSource();
  }

  /// What the take player should be playing now: a part soloed through its
  /// lens, the vocal or instrumental stem a harmony mix asks for, or the
  /// recording itself.
  String? get _wantedSource {
    final job = _songJobId;
    if (job != null && _stemsReady) {
      if (harmonyMix == HarmonyMix.withMelody) {
        return _api.stemUrl(job, 'vocals');
      }
      if (harmonyMix == HarmonyMix.withMusic) {
        return _api.stemUrl(job, 'instrumental');
      }
    }
    final part = currentPart;
    if (part?.stem != null && job != null) {
      return _api.stemUrl(job, part!.stem!);
    }
    return _takeSource;
  }

  /// Loads [_wantedSource] into the take player if it isn't already there,
  /// carrying on from the same position if it was playing.
  Future<void> _switchSource() async {
    final source = _wantedSource;
    if (source == null || source == _loadedSource) return;
    final wasPlaying = scene.playingAll && _player.playing;
    final position = _player.position;
    await _resetPlayer();
    await _loadPlayback(source, remote: source != _takeSource);
    if (wasPlaying && playbackReady && _wantedSource == source) {
      await seek(position.inMicroseconds / 1e6);
    }
  }

  /// A song whose separated parts (and so the vocal and instrumental
  /// stems) are on the server.
  bool get _stemsReady =>
      _songJobId != null && parts.any((p) => p.stem != null);

  SongPart? get currentPart => parts.where((p) => p.id == lens).firstOrNull;

  // ---------------------------------------------------------------------
  // Suggestions

  /// Shows progression card [index] and loads it as the backing.
  void selectProgression(int index) {
    noteInteraction();
    if (index == selectedProgression) return;
    selectedProgression = index;
    scene.selectedChord = null;
    _showProgression();
    _changed();
  }

  void _showProgression() {
    scene.chords = progression?.chords ?? const [];
    unawaited(_loadBacking());
    unawaited(_loadHarmonies());
  }

  BeatGrid? get grid => suggestions?.grid;

  /// Moves beat 1 by [beats] beats: the usual fix when the guess put the
  /// bar line in the wrong place.
  Future<void> shiftDownbeat(int beats) async {
    final g = grid;
    if (g == null) return;
    await _regrid(g.copyWith(downbeat: g.downbeat + beats * g.beatLength));
  }

  /// Doubles or halves the tempo: the usual fix when the guess counted
  /// twice as many (or half as many) beats as you felt.
  Future<void> scaleTempo(double factor) async {
    final g = grid;
    if (g == null) return;
    await _regrid(g.copyWith(bpm: g.bpm * factor));
  }

  /// Switches between one chord per bar and one per half bar.
  Future<void> togglePerBar() async {
    final g = grid;
    if (g == null) return;
    perBar = perBar == 1 ? 2 : 1;
    await _regrid(g);
  }

  Future<void> _regrid(BeatGrid g) async {
    noteInteraction();
    if (melody.isEmpty || regridding) return;
    regridding = true;
    _changed();
    try {
      final next = await _api.harmonise(
        melody: melody,
        grid: g,
        key: suggestions?.key,
        perBar: perBar,
      );
      if (_disposed) return;
      // A song's recognised progression doesn't depend on the grid: keep it.
      final original =
          suggestions?.progressions
              .where((p) => p.kind == 'original')
              .toList() ??
          const [];
      suggestions = Suggestions(
        grid: next.grid,
        key: next.key,
        progressions: [...original, ...next.progressions],
        insight: suggestions?.insight ?? next.insight,
      );
      scene.selectedChord = null;
      _showProgression();
    } catch (e) {
      debugPrint('Could not re-suggest: $e');
    } finally {
      regridding = false;
      _changed();
    }
  }

  // ---------------------------------------------------------------------
  // Backing

  void toggleBacking() {
    noteInteraction();
    withBacking = !withBacking;
    unawaited(_syncAux(play: scene.playingAll && _player.playing));
    _changed();
  }

  Future<void> _loadBacking() async {
    final chords = scene.chords;
    if (chords.isEmpty) {
      _backing.clear();
      return;
    }
    final duration = scene.duration;
    if (await _backing.load(() => _api.backing(chords, duration))) {
      await _resumeAux();
    }
  }

  // ---------------------------------------------------------------------
  // Harmonies

  HarmonyLine? get harmony => harmonies.isEmpty
      ? null
      : harmonies[selectedHarmony.clamp(0, harmonies.length - 1)];

  /// Whether this take has a tune a second voice could harmonise. A song
  /// nobody sings in has only a stand-in "Top line" (see the song
  /// pipeline), which hops between instruments. Nor does a full song's
  /// quick first answer: its "melody" is the mix's top line until the
  /// vocals have been separated.
  bool get _hasTune =>
      melody.isNotEmpty &&
      !(route == 'full_mix' && parts.isEmpty) &&
      !(parts.isNotEmpty && parts.first.name == 'Top line');

  /// Asks for harmony lines over the progression now showing: the best
  /// second voice depends on the chords under it.
  Future<void> _loadHarmonies() async {
    final request = ++_harmoniesRequest;
    final chords = scene.chords;
    final key = suggestions?.key;
    if (!_hasTune || chords.isEmpty || key == null) {
      harmonies = const [];
      _harmonyTrack.clear();
      _changed();
      return;
    }
    try {
      final lines = await _api.voices(
        melody: melody,
        chords: chords,
        key: key,
        grid: grid,
      );
      if (request != _harmoniesRequest || _disposed) return;
      harmonies = lines;
      _changed();
      await _loadHarmonyTrack();
    } catch (e) {
      debugPrint('Could not suggest harmonies: $e');
    }
  }

  Future<void> _loadHarmonyTrack() async {
    final line = harmony;
    if (line == null) {
      _harmonyTrack.clear();
      return;
    }
    final duration = scene.duration;
    if (await _harmonyTrack.load(() => _api.line(line.notes, duration))) {
      await _resumeAux();
    }
  }

  /// The melody sung by the synth voice, for "with the melody" when the
  /// take isn't just the singing (a song, or chords on one instrument).
  void _loadGuide() {
    if (route == 'melody' || melody.isEmpty) {
      _guide.clear();
      return;
    }
    final notes = melody;
    final duration = scene.duration;
    unawaited(
      _guide.load(() => _api.line(notes, duration)).then((loaded) async {
        if (loaded) await _resumeAux();
      }),
    );
  }

  /// Shows harmony option [index] and loads it to play.
  void selectHarmony(int index) {
    noteInteraction();
    if (index == selectedHarmony && harmonyMix != HarmonyMix.off) return;
    selectedHarmony = index;
    // Picking a harmony means wanting to hear it: with the tune, unless
    // another way of hearing it was already chosen.
    if (harmonyMix == HarmonyMix.off) harmonyMix = HarmonyMix.withMelody;
    unawaited(_loadHarmonyTrack());
    unawaited(_applyMix());
    _changed();
  }

  /// How to hear the harmony: alone, with the melody, with the music, or
  /// not at all.
  void setHarmonyMix(HarmonyMix mix) {
    noteInteraction();
    if (mix == harmonyMix) return;
    harmonyMix = mix;
    unawaited(_applyMix());
    _changed();
  }

  /// Puts the take player on the right source and volume, and starts or
  /// stops each synthesized track, for the current mix.
  Future<void> _applyMix() async {
    await _switchSource();
    await _player.setVolume(_takeVolume);
    await _syncAux(play: scene.playingAll && _player.playing);
  }

  /// The singing on its own is what the take player is playing: a melody
  /// take is just singing, and a song's vocal stem is too.
  bool get _melodyFromTake => route == 'melody' || _stemsReady;

  /// The music without the singing is what the take player is playing:
  /// chords on one instrument have no singing, and a song has its
  /// instrumental stem.
  bool get _musicFromTake => route == 'polyphonic' || _stemsReady;

  /// The take player always runs (its position is the clock everything
  /// follows); muting it is how it's left out of a mix.
  double get _takeVolume => switch (harmonyMix) {
    HarmonyMix.off => 1,
    HarmonyMix.alone => 0,
    HarmonyMix.withMelody => _melodyFromTake ? 1 : 0,
    HarmonyMix.withMusic => _musicFromTake ? 1 : 0,
  };

  bool _audible(_AuxTrack track) {
    if (track == _harmonyTrack) return harmonyMix != HarmonyMix.off;
    if (track == _guide) {
      return harmonyMix == HarmonyMix.withMelody && !_melodyFromTake;
    }
    return switch (harmonyMix) {
      HarmonyMix.off => withBacking,
      HarmonyMix.alone || HarmonyMix.withMelody => false,
      HarmonyMix.withMusic => !_musicFromTake,
    };
  }

  List<_AuxTrack> get _auxTracks => [_backing, _harmonyTrack, _guide];

  /// Puts each synthesized track at the take's position, playing with it
  /// if it belongs in the mix, otherwise paused.
  Future<void> _syncAux({required bool play}) async {
    final position = _player.position;
    await Future.wait([
      for (final track in _auxTracks)
        if (track.ready)
          play && _audible(track)
              ? track.player.seek(position).then((_) {
                  unawaited(track.player.play());
                })
              : track.player.pause(),
    ]);
  }

  /// A track that finished loading mid-playback joins in.
  Future<void> _resumeAux() async {
    if (scene.playingAll && _player.playing) await _syncAux(play: true);
    _changed();
  }

  // ---------------------------------------------------------------------
  // Click

  Future<void> _startClick() async {
    final player = AudioPlayer();
    _clickPlayer = player;
    try {
      await player.setAsset('assets/sounds/click.wav');
    } catch (e) {
      debugPrint('Could not load click: $e');
      return;
    }
    if (_clickPlayer != player || phase != Phase.recording) return;
    final beat = Duration(microseconds: (60e6 / clickBpm).round());
    void tick() {
      _firstClickAt ??= _recordingTime.elapsedMicroseconds / 1e6;
      unawaited(player.seek(Duration.zero).then((_) => player.play()));
    }

    tick();
    _clickTimer = Timer.periodic(beat, (_) => tick());
  }

  void _stopClick() {
    _clickTimer?.cancel();
    _clickTimer = null;
    final player = _clickPlayer;
    _clickPlayer = null;
    unawaited(player?.dispose());
  }

  void toggleClick() {
    noteInteraction();
    clickOn = !clickOn;
    _changed();
  }

  void changeClickTempo(double delta) {
    noteInteraction();
    clickBpm = (clickBpm + delta).clamp(50, 180);
    _changed();
  }

  // ---------------------------------------------------------------------
  // Playback

  Future<void> _loadPlayback(String path, {bool remote = false}) async {
    if (!remote) _takeSource = path;
    _loadedSource = path;
    try {
      if (!kIsWeb) {
        // The recorder leaves the session in record mode; on iOS that
        // routes playback to the earpiece.
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.music());
      }
      final player = _player;
      await (kIsWeb || remote ? player.setUrl(path) : player.setFilePath(path));
      // Ignore a load that finishes after another take has started.
      if (player == _player) {
        await player.setVolume(_takeVolume);
        playbackReady = true;
        if (_playWhenReady) {
          _playWhenReady = false;
          unawaited(togglePlay());
        }
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
    if (!playbackReady) {
      // Mid-switch to another source (a stem a harmony mix asked for): play
      // as soon as it's loaded rather than dropping the tap.
      _playWhenReady = _takeSource != null;
      _changed();
      return;
    }
    if (scene.playingAll && _player.playing) {
      await _player.pause();
      await _syncAux(play: false);
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
    await _player.setVolume(_takeVolume);
    _playEnd = duration;
    _lastSoundingChord = null;
    await _syncAux(play: true);
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
    await _player.setVolume(_takeVolume);
    _playEnd = scene.duration;
    await _syncAux(play: true);
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

  /// Plays chord [index]'s bar of the take, with the chord under it.
  void playChord(int index) {
    final chord = scene.chords[index];
    scene
      ..selected = null
      ..selectedChord = index;
    unawaited(_playRange(chord.startTime, chord.endTime, withChord: true));
  }

  void toggleLoop() {
    noteInteraction();
    loop = !loop;
    _changed();
  }

  /// Plays from [from] to [to] seconds, with a little air on either side so
  /// short notes don't sound clipped.
  Future<void> _playRange(
    double from,
    double to, {
    bool withChord = false,
  }) async {
    noteInteraction();
    if (!playbackReady) {
      _changed();
      return;
    }
    final start = math.max(0.0, from - 0.03);
    final end = math.min(scene.duration, math.max(to + 0.05, start + 0.25));
    scene.playingAll = false;
    await _player.pause();
    await _syncAux(play: false);
    await _player.seek(Duration(microseconds: (start * 1e6).round()));
    // A note is for hearing what was played, whatever the mix: full volume.
    await _player.setVolume(withChord ? _takeVolume : 1);
    _playEnd = end;
    scene.playhead = start;
    if (withChord) await _syncAux(play: true);
    unawaited(_player.play());
    _changed();
  }

  Future<void> _stopPlayback() async {
    _playEnd = null;
    scene
      ..playhead = null
      ..playingAll = false;
    if (_player.playing) await _player.pause();
    await _syncAux(play: false);
    _changed();
  }

  /// Each take gets a fresh player: reusing one kept playing the previous
  /// take after the new one was loaded (seen on web).
  Future<void> _resetPlayer() async {
    await _stopPlayback();
    playbackReady = false;
    _loadedSource = null;
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
        _lastSoundingChord = null;
        unawaited(
          _player.seek(Duration.zero).then((_) async {
            _restarting = false;
            await _syncAux(play: true);
            return _player.play();
          }),
        );
        return;
      }
      unawaited(_stopPlayback());
      return;
    }
    if (_player.playing) {
      scene.playhead = position;
      _noticeCadence();
    }
  }

  /// When playback moves into the last chord and that move is a cadence
  /// (a dominant, or IV, resolving home), the mascot gets its happy beat.
  void _noticeCadence() {
    if (!scene.playingAll) return;
    final now = activeChord;
    if (now == null || now == _lastSoundingChord) return;
    _lastSoundingChord = now;
    final chords = scene.chords;
    if (now != chords.length - 1 || now == 0) return;
    final last = chords[now];
    final before = chords[now - 1];
    if (last.function == 'tonic' &&
        (before.function == 'dominant' ||
            before.roman.toUpperCase().startsWith('IV'))) {
      lastCadenceAt = clock.value;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    _amplitudeSub?.cancel();
    _recorder.dispose();
    _playingSub?.cancel();
    _player.dispose();
    for (final track in _auxTracks) {
      track.dispose();
    }
    _stopClick();
    _stopSongPoll();
    clock.dispose();
    super.dispose();
  }
}
