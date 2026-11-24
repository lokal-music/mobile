import 'package:flick/features/search/library_search_matcher.dart';
import 'package:flick/models/song.dart';
import 'package:flutter_test/flutter_test.dart';

const _shape = Song(
  id: '1',
  title: 'Shape of You',
  artist: 'Ed Sheeran',
  album: 'Divide',
  duration: Duration(minutes: 4),
  fileType: 'FLAC',
);
const _perfect = Song(
  id: '2',
  title: 'Perfect',
  artist: 'Ed Sheeran',
  album: 'Divide',
  duration: Duration(minutes: 4),
  fileType: 'FLAC',
);
const _other = Song(
  id: '3',
  title: 'Sheeran Tribute',
  artist: 'Someone Else',
  albumArtist: 'Various',
  album: 'Covers',
  duration: Duration(minutes: 3),
  fileType: 'MP3',
);

void main() {
  test('query words are lowercased, deduplicated and capped like Desktop', () {
    expect(librarySearchWords('  Ed  ed SHEERAN '), ['ed', 'sheeran']);
    expect(librarySearchWords('a b c d e f g h i j').length, 8);
    expect(librarySearchWords('   '), isEmpty);
  });

  test('songs match artist and album names, not just titles', () {
    final words = librarySearchWords('ed sheeran');
    expect(songMatchesLibraryQuery(_shape, words), isTrue);
    expect(songMatchesLibraryQuery(_perfect, words), isTrue);
    expect(songMatchesLibraryQuery(_other, words), isFalse);
    expect(songMatchesLibraryQuery(_perfect, librarySearchWords('divide')),
        isTrue);
    expect(songMatchesLibraryQuery(_other, librarySearchWords('various')),
        isTrue);
  });

  test('words may match across fields in any order', () {
    expect(
      songMatchesLibraryQuery(_shape, librarySearchWords('sheeran shape')),
      isTrue,
    );
    expect(
      songMatchesLibraryQuery(_shape, librarySearchWords('sheeran nope')),
      isFalse,
    );
  });

  test('whole-phrase title matches rank before other field matches', () {
    expect(songLibraryMatchRank(_other, 'sheeran'), 0);
    expect(songLibraryMatchRank(_shape, 'sheeran'), 1);
    expect(songLibraryMatchRank(_shape, 'sheeran shape'), 2);
  });
}
