import 'dart:async';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../audio/read_recording.dart';
import '../audio/waveform.dart';
import '../models/note.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/score_canvas.dart';

/// One continuous canvas: an empty slate that becomes a waveform while you
/// play, which then gives up its notes into a pitch lane above it.
class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  AudioPlayer _player = AudioPlayer();
  StreamSubscription<bool>? _playingSub;
  final ApiService _apiService = ApiService();
  final Scene _scene = Scene();
  final ValueNotifier<double> _clock = ValueNotifier(0);
  final Stopwatch _recordingTime = Stopwatch();

  late final Ticker _ticker;
  StreamSubscription<Amplitude>? _amplitudeSub;
  String? _errorMessage;

  /// Whether the finished recording is loaded into [_player].
  bool _playbackReady = false;

  /// Where playback stops, in seconds into the recording.
  double? _playEnd;

  /// Whether the whole recording is playing (or paused mid-way), as opposed
  /// to a single note's slice.
  bool _playingAll = false;

  Phase get _phase => _scene.phase;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      if (_phase == Phase.recording) {
        _scene.liveDuration = _recordingTime.elapsedMilliseconds / 1000;
      }
      _trackPlayback();
      _clock.value = elapsed.inMicroseconds / 1e6;
    })..start();
    _watchPlayer();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _amplitudeSub?.cancel();
    _recorder.dispose();
    _playingSub?.cancel();
    _player.dispose();
    _clock.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      setState(() => _errorMessage = 'Microphone permission is required to record.');
      return;
    }

    await _resetPlayer();

    // On web the recorder ignores the path and returns a blob URL.
    var path = '';
    if (!kIsWeb) {
      final dir = await getTemporaryDirectory();
      path = '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';
    }

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, numChannels: 1),
      path: path,
    );
    _scene
      ..live.clear()
      ..liveDuration = 0
      ..waveform = null
      ..notes = const []
      ..chords = const []
      ..key = null
      ..hints = const []
      ..selected = null
      ..selectedChord = null;
    _recordingTime
      ..reset()
      ..start();
    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 40))
        .listen((amp) {
      // dBFS -> 0..1, curved so loud playing keeps some shape.
      final level = ((amp.current + 60) / 60).clamp(0.0, 1.0);
      _scene.live.add(math.pow(level, 1.6).toDouble());
    });

    setState(() {
      _scene.phase = Phase.recording;
      _errorMessage = null;
    });
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    _recordingTime.stop();
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;

    if (path == null) {
      setState(() {
        _scene.phase = Phase.idle;
        _errorMessage = 'Recording failed, no audio captured.';
      });
      return;
    }

    final analyzeStart = _clock.value;
    setState(() {
      _scene
        ..phase = Phase.analyzing
        ..analyzeStart = analyzeStart;
    });

    try {
      final bytes = await readRecording(path);
      final waveform = Waveform.fromWavBytes(bytes) ??
          Waveform(normalizeEnvelope(_scene.live), _scene.liveDuration);
      _scene
        ..waveform = waveform
        ..morphStart = _clock.value
        ..hints = waveform.peakTimes();
      unawaited(_loadPlayback(path));

      final analysis = await _apiService.analyzeAudio(bytes);
      // Let the listening moment breathe even when the backend is quick.
      final minListen = analyzeStart + 1.6 - _clock.value;
      if (minListen > 0) {
        await Future<void>.delayed(Duration(milliseconds: (minListen * 1000).round()));
      }
      if (!mounted) return;
      _scene
        ..chords = analysis.chords
        ..key = analysis.key;
      _settle(analysis.notes);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scene.phase = _scene.waveform == null ? Phase.idle : Phase.settled;
        _errorMessage = 'Could not analyze recording: $e';
      });
    }
  }

  void _settle(List<Note> notes) {
    setState(() {
      _scene
        ..notes = notes
        ..selected = null
        ..selectedChord = null
        ..settleStart = _clock.value
        ..phase = Phase.settled;
    });
  }

  void _replay() {
    if (_scene.waveform == null) return;
    _stopPlayback();
    setState(() {
      _scene
        ..phase = Phase.analyzing
        ..analyzeStart = _clock.value
        ..morphStart = _clock.value - 10
        ..selected = null
        ..selectedChord = null;
    });
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (mounted && _phase == Phase.analyzing) _settle(_scene.notes);
    });
  }

  Future<void> _loadPlayback(String path) async {
    try {
      if (!kIsWeb) {
        // The recorder leaves the session in record mode; on iOS that routes
        // playback to the earpiece.
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.music());
      }
      final player = _player;
      await (kIsWeb ? player.setUrl(path) : player.setFilePath(path));
      // Ignore a load that finishes after another recording has started.
      if (player == _player) _playbackReady = true;
    } catch (e) {
      // Playback is a nice-to-have; the notes still work without it.
      debugPrint('Could not load recording for playback: $e');
    }
  }

  /// Plays the stretch of the recording from [from] to [to] seconds, with a
  /// little air on either side so short notes don't sound clipped.
  Future<void> _playRange(double from, double to) async {
    if (!_playbackReady) return;
    final duration = _scene.waveform?.duration ?? to;
    final start = math.max(0.0, from - 0.03);
    final end = math.min(duration, math.max(to + 0.05, start + 0.25));
    _setPlayingAll(false);
    await _player.pause();
    await _player.seek(Duration(microseconds: (start * 1e6).round()));
    _playEnd = end;
    unawaited(_player.play());
  }

  /// Plays the whole recording, or pauses it if it's already playing. Resumes
  /// from where it was paused; starts over once it has played to the end.
  Future<void> _togglePlayAll() async {
    if (!_playbackReady) return;
    if (_playingAll && _player.playing) {
      await _player.pause();
      return;
    }
    final duration = _scene.waveform?.duration ?? 0;
    final resume = _playingAll && (_scene.playhead ?? duration) < duration - 0.05;
    setState(() {
      _scene
        ..selected = null
        ..selectedChord = null;
    });
    _setPlayingAll(true);
    if (!resume) await _player.seek(Duration.zero);
    _playEnd = duration;
    unawaited(_player.play());
  }

  void _setPlayingAll(bool value) {
    if (_playingAll == value) return;
    if (mounted) {
      setState(() => _playingAll = _scene.playingAll = value);
    } else {
      _playingAll = _scene.playingAll = value;
    }
  }

  Future<void> _stopPlayback() async {
    _playEnd = null;
    _scene.playhead = null;
    _setPlayingAll(false);
    if (_player.playing) await _player.pause();
  }

  /// Swaps in a fresh player for a new recording. Reusing one player kept
  /// playing the previous recording after the new one was loaded (seen on
  /// web), so each recording gets its own.
  Future<void> _resetPlayer() async {
    await _stopPlayback();
    _playbackReady = false;
    final old = _player;
    _player = AudioPlayer();
    _watchPlayer();
    await old.dispose();
  }

  /// Rebuilds when playback starts or stops, so the play/pause label follows.
  void _watchPlayer() {
    _playingSub?.cancel();
    _playingSub = _player.playingStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  /// Called every frame: moves the playhead and stops at the slice's end.
  void _trackPlayback() {
    final end = _playEnd;
    if (end == null) return;
    final position = _player.position.inMicroseconds / 1e6;
    // just_audio keeps `playing` true after reaching the end, so check the
    // processing state rather than `playing`.
    final finished = _player.processingState == ProcessingState.completed;
    if (position >= end - 0.02 || finished) {
      _stopPlayback();
      return;
    }
    if (_player.playing) _scene.playhead = position;
  }

  void _onTap(TapUpDetails details, Size size) {
    if (_phase != Phase.settled || _scene.notes.isEmpty) return;
    final layout = SceneLayout(size, _scene);
    final tap = details.localPosition;

    // A chord band...
    for (var j = 0; j < _scene.chords.length; j++) {
      final chord = _scene.chords[j];
      if (layout.chordRect(chord).inflate(6).contains(tap)) {
        setState(() {
          _scene
            ..selected = null
            ..selectedChord = j;
        });
        _playRange(chord.startTime, chord.endTime);
        return;
      }
    }

    int? hit;

    // ...a note head in the lane...
    var best = 24.0;
    for (var i = 0; i < _scene.notes.length; i++) {
      final d = (layout.target(_scene.notes[i]) - tap).distance;
      if (d < best) {
        best = d;
        hit = i;
      }
    }

    // ...or the stretch of waveform a note was heard in.
    if (hit == null && (tap.dy - layout.waveY).abs() < layout.waveAmp + 12) {
      final t = (tap.dx - layout.left) / layout.width * layout.duration;
      for (var i = 0; i < _scene.notes.length; i++) {
        final n = _scene.notes[i];
        if (t >= n.startTime && t <= n.endTime) {
          hit = i;
          break;
        }
      }
    }

    setState(() {
      _scene
        ..selected = hit
        ..selectedChord = null;
    });
    if (hit == null) {
      _stopPlayback();
    } else {
      final note = _scene.notes[hit];
      _playRange(note.startTime, note.endTime);
    }
  }

  String get _status {
    switch (_phase) {
      case Phase.idle:
        return 'Play something';
      case Phase.recording:
        return 'listening…';
      case Phase.analyzing:
        return 'finding the notes…';
      case Phase.settled:
        final playhead = _scene.playhead;
        if (_playingAll && playhead != null) {
          final sounding = [
            for (final c in _scene.chords)
              if (playhead >= c.startTime && playhead <= c.endTime) c.name,
            for (final n in _scene.notes)
              if (playhead >= n.startTime && playhead <= n.endTime) n.pitch,
          ];
          return sounding.isEmpty ? '·' : sounding.join('  ·  ');
        }
        final chordIndex = _scene.selectedChord;
        if (chordIndex != null) {
          final c = _scene.chords[chordIndex];
          final key = _scene.key;
          return '${c.name}  ·  ${c.roman}${key == null ? '' : ' in ${key.name}'}'
              '  ·  ${c.notes.join(' ')}';
        }
        final selected = _scene.selected;
        if (selected != null) {
          final n = _scene.notes[selected];
          return '${n.pitch}  ·  ${n.startTime.toStringAsFixed(2)}–'
              '${n.endTime.toStringAsFixed(2)} s  ·  '
              '${(n.confidence * 100).round()}%';
        }
        final count = _scene.notes.length;
        if (count == 0) return 'No notes found. Try a clearer, sustained tone.';
        final chords = _scene.chords.length;
        return '$count note${count == 1 ? '' : 's'}'
            '${chords == 0 ? '' : '  ·  $chords chord${chords == 1 ? '' : 's'}'}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final idle = _phase == Phase.idle;
    return Scaffold(
      backgroundColor: Palette.paper,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _onTap(d, size),
                  child: CustomPaint(painter: ScorePainter(_scene, _clock)),
                ),
              ),
              // Status line: sits above the slate when idle, below the
              // waveform once there's something to look at.
              AnimatedPositioned(
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeInOutCubic,
                left: 24,
                right: 24,
                top: idle ? size.height * 0.70 - 96 : size.height * 0.82,
                // Rebuilt every frame so it can name the notes sounding
                // during full playback.
                child: ValueListenableBuilder<double>(
                  valueListenable: _clock,
                  builder: (context, _, _) {
                    final status = _status;
                    return AnimatedSwitcher(
                      duration: Duration(milliseconds: _playingAll ? 120 : 400),
                      child: Text(
                        status,
                        key: ValueKey(status),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: idle ? 20 : 13,
                          fontWeight: FontWeight.w300,
                          letterSpacing: idle ? 0.4 : 0.8,
                          color: Palette.ink.withValues(alpha: idle ? 0.55 : 0.5),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_errorMessage != null)
                Positioned(
                  left: 24,
                  right: 24,
                  top: size.height * 0.08,
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Palette.error),
                  ),
                ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeInOutCubic,
                left: 0,
                right: 0,
                top: idle ? size.height * 0.70 - 32 : size.height * 0.90 - 32,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _RecordButton(
                      phase: _phase,
                      onTap: switch (_phase) {
                        Phase.recording => _stopRecording,
                        Phase.analyzing => null,
                        _ => _startRecording,
                      },
                    ),
                    if (_phase == Phase.settled && _scene.waveform != null)
                      Positioned(
                        right: size.width / 2 + 52,
                        child: _QuietButton(
                          label: _playingAll && _player.playing ? 'pause' : 'play',
                          onTap: _togglePlayAll,
                        ),
                      ),
                    if (_phase == Phase.settled && _scene.notes.isNotEmpty)
                      Positioned(
                        left: size.width / 2 + 52,
                        child: _QuietButton(label: 'redraw', onTap: _replay),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A soft ring with an ink dot that breathes while waiting, becomes a stop
/// square while recording, and dims while analyzing.
class _RecordButton extends StatefulWidget {
  const _RecordButton({required this.phase, required this.onTap});

  final Phase phase;
  final VoidCallback? onTap;

  @override
  State<_RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<_RecordButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recording = widget.phase == Phase.recording;
    final busy = widget.phase == Phase.analyzing;
    return Semantics(
      button: true,
      label: recording ? 'Stop recording' : 'Start recording',
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _breath,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_breath.value);
            final ring = recording ? 1.0 + 0.08 * t : 1.0 + 0.04 * t;
            return AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: busy ? 0.3 : 1,
              child: SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.scale(
                      scale: ring,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Palette.paper,
                          border: Border.all(
                            color: Palette.ink.withValues(alpha: 0.14 + 0.06 * t),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Palette.accent.withValues(alpha: 0.06 + 0.06 * t),
                              blurRadius: 18 + 10 * t,
                            ),
                          ],
                        ),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      width: recording ? 18 : 14 + 2 * t,
                      height: recording ? 18 : 14 + 2 * t,
                      decoration: BoxDecoration(
                        color: Palette.accent.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(recording ? 4 : 10),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _QuietButton extends StatelessWidget {
  const _QuietButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: Palette.ink.withValues(alpha: 0.55),
        textStyle: const TextStyle(fontSize: 13, letterSpacing: 0.8),
        minimumSize: Size(math.max(48, label.length * 9.0), 40),
      ),
      child: Text(label),
    );
  }
}
