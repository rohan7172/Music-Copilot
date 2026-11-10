/// A song found by name in Apple's catalogue, with a 30-second preview the
/// backend can analyse.
class SongHit {
  const SongHit({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.artwork,
    this.duration,
  });

  factory SongHit.fromJson(Map<String, dynamic> json) => SongHit(
    id: (json['id'] as num).toInt(),
    title: json['title'] as String,
    artist: json['artist'] as String,
    album: json['album'] as String?,
    artwork: json['artwork'] as String?,
    duration: (json['duration'] as num?)?.toDouble(),
  );

  final int id;
  final String title;
  final String artist;
  final String? album;

  /// Cover art URL (200×200), if Apple has one.
  final String? artwork;

  /// The full track's length in seconds; only a 30 s preview is analysed.
  final double? duration;
}
