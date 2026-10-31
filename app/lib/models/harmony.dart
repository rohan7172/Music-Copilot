import 'note.dart';

double _d(Object? v) => (v as num).toDouble();

/// The melody's key, e.g. "C major", with the runner-up (often its
/// relative minor or major).
class MusicKey {
  MusicKey({
    required this.name,
    required this.tonic,
    required this.mode,
    required this.confidence,
    this.runnerUp,
  });

  factory MusicKey.fromJson(Map<String, dynamic> json) {
    final runner = json['runner_up'];
    return MusicKey(
      name: json['name'] as String,
      tonic: json['tonic'] as String,
      mode: json['mode'] as String,
      confidence: _d(json['confidence']),
      runnerUp: runner == null
          ? null
          : MusicKey.fromJson(runner as Map<String, dynamic>),
    );
  }

  final String name;

  /// The home note, e.g. "G" or "F#".
  final String tonic;
  final String mode;
  final double confidence;
  final MusicKey? runnerUp;

  Map<String, dynamic> toJson() => {'tonic': tonic, 'mode': mode};
}

/// The bars and beats a melody is harmonised against: exact when the app
/// played a click, otherwise estimated and marked [guessed].
class BeatGrid {
  BeatGrid({
    required this.bpm,
    required this.downbeat,
    required this.meter,
    required this.guessed,
    required this.beats,
  });

  factory BeatGrid.fromJson(Map<String, dynamic> json) => BeatGrid(
    bpm: _d(json['bpm']),
    downbeat: _d(json['downbeat']),
    meter: json['meter'] as int,
    guessed: json['guessed'] as bool,
    beats: [
      for (final b in (json['beats'] as List<dynamic>? ?? const []))
        Beat(
          time: _d((b as Map<String, dynamic>)['time']),
          downbeat: b['downbeat'] as bool,
        ),
    ],
  );

  final double bpm;

  /// Time (seconds) of a bar's first beat.
  final double downbeat;
  final int meter;
  final bool guessed;
  final List<Beat> beats;

  double get beatLength => 60 / bpm;

  /// The same grid with a different downbeat, tempo or meter, for the
  /// user's nudges. Beats are recomputed by the backend.
  BeatGrid copyWith({double? bpm, double? downbeat, int? meter}) => BeatGrid(
    bpm: bpm ?? this.bpm,
    downbeat: downbeat ?? this.downbeat,
    meter: meter ?? this.meter,
    guessed: guessed,
    beats: const [],
  );

  Map<String, dynamic> toJson() => {
    'bpm': bpm,
    'downbeat': downbeat,
    'meter': meter,
    'guessed': guessed,
  };
}

class Beat {
  const Beat({required this.time, required this.downbeat});
  final double time;
  final bool downbeat;
}

/// How a suggested chord sits with the melody in its bar.
enum ChordFit { fits, colour, clash }

/// One chord of a suggested progression, spanning one bar (or half).
class ProgressionChord {
  ProgressionChord({
    required this.bar,
    required this.startTime,
    required this.endTime,
    required this.symbol,
    required this.roman,
    required this.function,
    required this.kind,
    required this.fit,
    required this.pitchClasses,
    required this.reasons,
    this.confidence,
  });

  factory ProgressionChord.fromJson(Map<String, dynamic> json) =>
      ProgressionChord(
        bar: json['bar'] as int,
        startTime: _d(json['start_time']),
        endTime: _d(json['end_time']),
        symbol: json['symbol'] as String,
        roman: json['roman'] as String,
        function: json['function'] as String,
        kind: json['kind'] as String,
        fit: ChordFit.values.byName(json['fit'] as String),
        pitchClasses: (json['pitch_classes'] as List<dynamic>).cast<int>(),
        reasons: (json['reasons'] as List<dynamic>).cast<String>(),
        confidence: (json['confidence'] as num?)?.toDouble(),
      );

  final int bar;
  final double startTime;
  final double endTime;

  /// Display name, e.g. "Am7".
  final String symbol;

  /// Function in the key, e.g. "vi7" or "V7/vi".
  final String roman;

  /// "tonic", "predominant" or "dominant".
  final String function;

  /// "diatonic", "seventh", "sus", "secondary", "borrowed" or "chromatic".
  final String kind;
  final ChordFit fit;

  /// Chord tones as pitch classes, root first. Sent back for /backing.
  final List<int> pitchClasses;

  /// Why it works, most telling first.
  final List<String> reasons;

  /// For a chord recognised in a song: how sure the recognition was
  /// (0..1). Null for suggested chords.
  final double? confidence;

  /// A recognised chord the model wasn't sure of, shown as a "maybe".
  bool get uncertain => confidence != null && confidence! < 0.35;

  bool get isColour => kind != 'diatonic';

  Map<String, dynamic> toBackingJson() => {
    'start_time': startTime,
    'end_time': endTime,
    'pitch_classes': pitchClasses,
  };
}

/// One suggested progression: Safe, Colourful or Bold.
class Progression {
  Progression({
    required this.kind,
    required this.source,
    required this.character,
    required this.chords,
  });

  factory Progression.fromJson(Map<String, dynamic> json) => Progression(
    kind: json['kind'] as String,
    source: json['source'] as String,
    character: json['character'] as String,
    chords: [
      for (final c in json['chords'] as List<dynamic>)
        ProgressionChord.fromJson(c as Map<String, dynamic>),
    ],
  );

  /// "original" (recognised in a song), "safe", "colourful" or "bold".
  final String kind;

  /// "recognised", "theory", or "llm" when an LLM proposed it and the
  /// engine validated it.
  final String source;

  /// The one-line mood, e.g. "warm and settled".
  final String character;
  final List<ProgressionChord> chords;

  String get title => switch (kind) {
    'original' => 'Original',
    'safe' => 'Safe',
    'colourful' => 'Colourful',
    _ => 'Bold',
  };
}

/// What /analyze and /harmonise return: the progressions plus everything
/// needed to re-ask after a nudge.
class Suggestions {
  Suggestions({
    required this.grid,
    required this.key,
    required this.progressions,
    required this.insight,
  });

  factory Suggestions.fromJson(Map<String, dynamic> json) {
    final grid = json['grid'];
    final key = json['key'];
    return Suggestions(
      grid: grid == null
          ? null
          : BeatGrid.fromJson(grid as Map<String, dynamic>),
      key: key == null ? null : MusicKey.fromJson(key as Map<String, dynamic>),
      progressions: [
        for (final p in (json['progressions'] as List<dynamic>? ?? const []))
          Progression.fromJson(p as Map<String, dynamic>),
      ],
      insight: json['insight'] as String?,
    );
  }

  final BeatGrid? grid;
  final MusicKey? key;
  final List<Progression> progressions;
  final String? insight;
}

/// Everything /analyze returns for a take.
class Analysis {
  Analysis({
    required this.notes,
    required this.melody,
    required this.route,
    required this.routeNote,
    required this.suggestions,
    this.jobId,
  });

  factory Analysis.fromJson(Map<String, dynamic> json) => Analysis(
    notes: [
      for (final n in json['notes'] as List<dynamic>)
        Note.fromJson(n as Map<String, dynamic>),
    ],
    melody: [
      for (final n in (json['melody'] as List<dynamic>? ?? const []))
        Note.fromJson(n as Map<String, dynamic>),
    ],
    route: json['route'] as String? ?? 'melody',
    routeNote: json['route_note'] as String?,
    suggestions: Suggestions.fromJson(json),
    jobId: (json['job'] as Map<String, dynamic>?)?['id'] as String?,
  );

  /// Every note Basic Pitch heard.
  final List<Note> notes;

  /// The single tune line the harmoniser worked from.
  final List<Note> melody;

  /// "melody", "polyphonic" or "full_mix".
  final String route;

  /// A one-line note when the take isn't a plain melody, else null.
  final String? routeNote;
  final Suggestions suggestions;

  /// Set when the backend is still recognising a song's own chords in the
  /// background; poll it with ApiService.job.
  final String? jobId;
}

/// A background song analysis: where it's got to, and the full result
/// once it's done.
class SongJob {
  SongJob({
    required this.status,
    required this.stage,
    required this.progress,
    this.result,
    this.error,
  });

  factory SongJob.fromJson(Map<String, dynamic> json) {
    final result = json['result'];
    return SongJob(
      status: json['status'] as String,
      stage: json['stage'] as String? ?? '',
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      result: result == null
          ? null
          : Analysis.fromJson(result as Map<String, dynamic>),
      error: json['error'] as String?,
    );
  }

  /// "running", "done" or "failed".
  final String status;
  final String stage;
  final double progress;
  final Analysis? result;
  final String? error;
}
