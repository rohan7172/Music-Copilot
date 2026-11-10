import 'package:flutter_test/flutter_test.dart';
import 'package:music_copilot_app/models/song.dart';

void main() {
  test('parses a search result', () {
    final hit = SongHit.fromJson({
      'id': 726138298,
      'title': 'My Funny Valentine',
      'artist': 'Chet Baker',
      'album': null,
      'artwork': 'https://example.com/200x200bb.jpg',
      'duration': 140.0,
    });
    expect(hit.id, 726138298);
    expect(hit.title, 'My Funny Valentine');
    expect(hit.album, isNull);
    expect(hit.duration, 140.0);
  });

  test('tolerates missing optional fields', () {
    final hit = SongHit.fromJson({'id': 1, 'title': 'T', 'artist': 'A'});
    expect(hit.artwork, isNull);
    expect(hit.duration, isNull);
  });
}
