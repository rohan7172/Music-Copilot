import 'dart:async';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
import '../theme.dart';
import '../widgets/mascot.dart';
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

  /// Plain-language explanation of the detected key and chords, shown in the
  /// status line. Null until an analysis has come back.
  Explanation? _explanation;

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
      setState(
        () => _errorMessage = 'Microphone permission is required to record.',
      );
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
    _scene
      ..live.clear()
      ..liveDuration = 0
      ..waveform = null
      ..notes = const []
      ..chords = const []
      ..key = null
      ..hints = const []
      ..selected = null
      ..selectedChord = null
      ..showFaintNotes = false
      ..faintToggleStart = null;
    _explanation = null;
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
      final waveform =
          Waveform.fromWavBytes(bytes) ??
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
        await Future<void>.delayed(
          Duration(milliseconds: (minListen * 1000).round()),
        );
      }
      if (!mounted) return;
      _scene
        ..chords = analysis.chords
        ..key = analysis.key;
      _explanation = analysis.explanation;
      _settle(analysis.notes);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scene.phase = _scene.waveform == null ? Phase.idle : Phase.settled;
        _errorMessage = 'Could not analyze recording: $e';
      });
    }
  }

  Future<void> _pickAndAnalyzeFile() async {
    final PickedAudio picked;
    try {
      final result = await pickAudioFile();
      if (result == null) return;
      picked = result;
    } catch (e) {
      setState(() => _errorMessage = 'Could not open that file: $e');
      return;
    }

    await _resetPlayer();
    _scene
      ..live.clear()
      ..liveDuration = 0
      ..waveform = null
      ..notes = const []
      ..chords = const []
      ..key = null
      ..hints = const []
      ..selected = null
      ..selectedChord = null
      ..showFaintNotes = false
      ..faintToggleStart = null;
    _explanation = null;

    final analyzeStart = _clock.value;
    setState(() {
      _scene
        ..phase = Phase.analyzing
        ..analyzeStart = analyzeStart;
      _errorMessage = null;
    });

    try {
      // A real envelope if this is WAV; otherwise left null until the notes
      // come back, so the live-amplitude fallback below (only meaningful for
      // recordings) isn't used.
      final waveform = Waveform.fromWavBytes(picked.bytes);
      if (waveform != null) {
        _scene
          ..waveform = waveform
          ..morphStart = _clock.value
          ..hints = waveform.peakTimes();
      }
      unawaited(_loadPlayback(picked.playbackSource));

      final analysis = await _apiService.analyzeAudio(
        picked.bytes,
        filename: picked.filename,
      );
      final minListen = analyzeStart + 1.6 - _clock.value;
      if (minListen > 0) {
        await Future<void>.delayed(
          Duration(milliseconds: (minListen * 1000).round()),
        );
      }
      if (!mounted) return;

      if (waveform == null) {
        final notes = analysis.notes;
        final duration = notes.isEmpty
            ? 1.0
            : notes.map((n) => n.endTime).reduce(math.max) + 0.2;
        _scene
          ..waveform = Waveform.fromNoteActivity(notes, duration)
          ..morphStart = _clock.value
          ..hints = const [];
      }

      _scene
        ..chords = analysis.chords
        ..key = analysis.key;
      _explanation = analysis.explanation;
      _settle(analysis.notes);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scene.phase = _scene.waveform == null ? Phase.idle : Phase.settled;
        _errorMessage = 'Could not analyze file: $e';
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
    final resume =
        _playingAll && (_scene.playhead ?? duration) < duration - 0.05;
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

  /// Seeks to [from] and plays onward to the end of the recording, lighting
  /// up notes/chords as it crosses them the same way _togglePlayAll does -
  /// a separate method so a plain note/chord tap can keep previewing just
  /// its own slice (_playRange) unchanged.
  Future<void> _playFromHere(double from) async {
    if (!_playbackReady) return;
    final duration = _scene.waveform?.duration ?? from;
    setState(() {
      _scene
        ..selected = null
        ..selectedChord = null;
    });
    _setPlayingAll(true);
    await _player.seek(Duration(microseconds: (from * 1e6).round()));
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

  /// Selects chord [index], playing its slice of the recording. Shared by a
  /// canvas tap on the chord band and a tap on its mention in the overview
  /// sentence, so both entry points do exactly the same thing.
  void _selectChord(int index) {
    setState(() {
      _scene
        ..selected = null
        ..selectedChord = index
        ..chordTapStart = _clock.value;
    });
    final chord = _scene.chords[index];
    _playRange(chord.startTime, chord.endTime);
  }

  void _onTap(TapUpDetails details, Size size) {
    if (_phase != Phase.settled || _scene.notes.isEmpty) return;
    final layout = SceneLayout(size, _scene);
    final tap = details.localPosition;

    // A chord tab...
    for (var j = 0; j < _scene.chords.length; j++) {
      if (layout.chordRect(_scene.chords[j]).inflate(6).contains(tap)) {
        _selectChord(j);
        return;
      }
    }

    // ...a note head in the lane...
    int? hit;
    var best = 24.0;
    for (var i = 0; i < _scene.notes.length; i++) {
      final d = (layout.target(_scene.notes[i]) - tap).distance;
      if (d < best) {
        best = d;
        hit = i;
      }
    }
    if (hit != null) {
      setState(() {
        _scene
          ..selected = hit
          ..selectedChord = null;
      });
      final note = _scene.notes[hit];
      _playRange(note.startTime, note.endTime);
      return;
    }

    // ...or the waveform itself, which always just seeks and plays onward
    // from that point, with no note/chord preview involved.
    if ((tap.dy - layout.waveY).abs() < layout.waveAmp + 12) {
      final t = (tap.dx - layout.left) / layout.width * layout.duration;
      _playFromHere(t);
      return;
    }

    setState(() {
      _scene
        ..selected = null
        ..selectedChord = null;
    });
    _stopPlayback();
  }

  /// The idle/recording/analyzing message; null once settled, where the
  /// overview (built from the explanation) takes over instead.
  String? get _phaseMessage => switch (_phase) {
    Phase.idle => 'Play something',
    Phase.recording => 'listening…',
    Phase.analyzing => 'finding the notes…',
    Phase.settled => null,
  };

  /// What's currently selected or playing, shown above the overview. Null
  /// when nothing is: the overview is all there is to say.
  String? get _detailText {
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
      final explained = _explanation?.chords;
      if (explained != null && chordIndex < explained.length) {
        return explained[chordIndex].text;
      }
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
    return null;
  }

  TextStyle _statusStyle(bool idle) => TextStyle(
    fontSize: idle ? 20 : 13,
    fontWeight: FontWeight.w300,
    letterSpacing: idle ? 0.4 : 0.8,
    color: Palette.ink.withValues(alpha: idle ? 0.55 : 0.5),
  );

  /// The overview: the idle/recording/analyzing message, or, once settled,
  /// the explanation summary with each chord mention tappable (same action
  /// as tapping that chord's band on the canvas). Always showing something
  /// once settled, unlike the detail line above it.
  Widget _buildOverview(bool idle) {
    final style = _statusStyle(idle);
    final phaseMessage = _phaseMessage;
    if (phaseMessage != null) {
      return Text(
        phaseMessage,
        key: ValueKey(phaseMessage),
        textAlign: TextAlign.center,
        style: style,
      );
    }
    final count = _scene.notes.length;
    if (count == 0) {
      const message = 'No notes found. Try a clearer, sustained tone.';
      return Text(
        message,
        key: const ValueKey(message),
        textAlign: TextAlign.center,
        style: style,
      );
    }
    final segments = _explanation?.summary;
    if (segments == null) {
      final message = '$count note${count == 1 ? '' : 's'}';
      return Text(
        message,
        key: ValueKey(message),
        textAlign: TextAlign.center,
        style: style,
      );
    }
    final linkStyle = style.copyWith(
      decoration: TextDecoration.underline,
      color: Palette.ink.withValues(alpha: 0.8),
    );
    return RichText(
      key: ValueKey(segments),
      textAlign: TextAlign.center,
      text: TextSpan(
        style: style,
        children: [
          for (final segment in segments)
            segment.chordIndex == null
                ? TextSpan(text: segment.text)
                : TextSpan(
                    text: segment.text,
                    style: linkStyle,
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _selectChord(segment.chordIndex!),
                  ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final idle = _phase == Phase.idle;
    return Scaffold(
      backgroundColor: Palette.paper,
      // Primarily mobile, but centered at a phone-like width on a wide
      // (desktop) window rather than stretching the waveform/mascot thin.
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Layout.maxContentWidth),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              final statusTop = switch (_phase) {
                Phase.idle => size.height * 0.70 - 96,
                Phase.settled => size.height * 0.79,
                _ => size.height * 0.82,
              };
              // The mascot is a large, calm presence at rest, centered where
              // the waveform will grow from. The moment there's a task
              // underway it recedes to a small icon paired tightly against
              // the "KEY" label's own left margin and vertical center (see
              // ScorePainter._paintKey) — a deliberate small gap, rather
              // than floating independently and reading as two unrelated
              // elements that happen to share the top of the screen.
              const nonIdleMascotSize = 32.0;
              const mascotKeyGap = 8.0;
              final mascotSize = idle ? 132.0 : nonIdleMascotSize;
              final mascotLeft = idle
                  ? (size.width - mascotSize) / 2
                  : canvasMargin - nonIdleMascotSize - mascotKeyGap;
              final mascotTop = idle
                  ? statusTop - mascotSize - 16
                  : size.height * 0.06 - (nonIdleMascotSize - 17) / 2;
              return Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) => _onTap(d, size),
                      child: CustomPaint(painter: ScorePainter(_scene, _clock)),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeInOutCubic,
                    left: mascotLeft,
                    top: mascotTop,
                    width: mascotSize,
                    child: Center(
                      child: Mascot(
                        scene: _scene,
                        clock: _clock,
                        size: mascotSize,
                      ),
                    ),
                  ),
                  // Status area: sits above the slate when idle, below the
                  // waveform once there's something to look at. Once settled,
                  // it's two lines: a detail line above (what's selected or
                  // playing, if anything) over the overview, which never goes
                  // away once there's an analysis to show.
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeInOutCubic,
                    left: 24,
                    right: 24,
                    top: statusTop,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_phase == Phase.settled)
                          SizedBox(
                            height: 22,
                            // Rebuilt every frame so it can name the notes
                            // sounding during full playback.
                            child: ValueListenableBuilder<double>(
                              valueListenable: _clock,
                              builder: (context, _, _) {
                                final detail = _detailText;
                                return AnimatedSwitcher(
                                  duration: Duration(
                                    milliseconds: _playingAll ? 120 : 400,
                                  ),
                                  child: detail == null
                                      ? const SizedBox.shrink(
                                          key: ValueKey('no-detail'),
                                        )
                                      : Text(
                                          detail,
                                          key: ValueKey(detail),
                                          textAlign: TextAlign.center,
                                          style: _statusStyle(false),
                                        ),
                                );
                              },
                            ),
                          ),
                        if (_phase == Phase.settled) const SizedBox(height: 8),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          child: _buildOverview(idle),
                        ),
                      ],
                    ),
                  ),
                  // Always reachable except mid-recording/analyzing, so starting
                  // a new recording never blocks picking a file instead (and
                  // vice versa) — it doesn't depend on which phase you're in.
                  if (_phase == Phase.idle || _phase == Phase.settled)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: _QuietButton(
                        label: 'upload',
                        onTap: _pickAndAnalyzeFile,
                      ),
                    ),
                  if (_phase == Phase.settled &&
                      _scene.notes.any(
                        (n) => n.confidence < noteConfidenceThreshold,
                      ))
                    Positioned(
                      top: 16,
                      left: 16,
                      child: _QuietButton(
                        label: _scene.showFaintNotes
                            ? 'hide faint'
                            : 'show faint',
                        onTap: () => setState(() {
                          _scene
                            ..showFaintNotes = !_scene.showFaintNotes
                            ..faintToggleStart = _clock.value;
                        }),
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
                        style: const TextStyle(
                          fontSize: 13,
                          color: Palette.error,
                        ),
                      ),
                    ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeInOutCubic,
                    left: 0,
                    right: 0,
                    top: idle
                        ? size.height * 0.70 - 32
                        : size.height * 0.90 - 32,
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
                              label: _playingAll && _player.playing
                                  ? 'pause'
                                  : 'play',
                              onTap: _togglePlayAll,
                            ),
                          ),
                        if (_phase == Phase.settled && _scene.notes.isNotEmpty)
                          Positioned(
                            left: size.width / 2 + 52,
                            child: _QuietButton(
                              label: 'redraw',
                              onTap: _replay,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
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
                            color: Palette.ink.withValues(
                              alpha: 0.14 + 0.06 * t,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Palette.accent.withValues(
                                alpha: 0.06 + 0.06 * t,
                              ),
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

/// A small pill chip — the app's one button shape, everywhere a quiet,
/// secondary action is offered (upload, play, redraw, show/hide faint).
class _QuietButton extends StatelessWidget {
  const _QuietButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Palette.paper,
      shape: const StadiumBorder(),
      elevation: 0,
      shadowColor: Palette.ink.withValues(alpha: 0.08),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(
            minWidth: math.max(48, label.length * 9.0),
          ),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(Shape.pill),
            boxShadow: [
              BoxShadow(
                color: Palette.ink.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              letterSpacing: 0.8,
              color: Palette.ink.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}
