import 'package:flick/models/song.dart';

/// Matches Desktop's `electron/librarySearch.js` word limit.
const int maxLibrarySearchWords = 8;

/// Splits [query] into deduplicated lowercase words (capped at
/// [maxLibrarySearchWords]), mirroring Desktop's `searchWords`.
List<String> librarySearchWords(String query) {
  final seen = <String>{};
  final words = <String>[];
  for (final raw in query.trim().toLowerCase().split(RegExp(r'\s+'))) {
    if (raw.isEmpty || !seen.add(raw)) continue;
    words.add(raw);
    if (words.length >= maxLibrarySearchWords) break;
  }
  return words;
}

/// Returns true when every word in [words] appears in at least one entry of
/// [lowerFields] (in any order), mirroring Desktop's `wordsMatch`.
bool libraryWordsMatch(List<String> words, Iterable<String> lowerFields) {
  if (words.isEmpty) return false;
  final fields = lowerFields is List<String> ? lowerFields : lowerFields.toList();
  for (final word in words) {
    var matched = false;
    for (final field in fields) {
      if (field.contains(word)) {
        matched = true;
        break;
      }
    }
    if (!matched) return false;
  }
  return true;
}

/// Ranking tier mirroring Desktop's `phraseFirst`:
/// - `0`: the whole lowercase [phraseLower] appears in [primaryLower]
/// - `1`: the whole lowercase [phraseLower] appears in any of [allLowerFields]
/// - `2`: individual words matched across fields
int libraryPhraseRank(
  String phraseLower,
  String primaryLower,
  Iterable<String> allLowerFields,
) {
  if (phraseLower.isEmpty) return 0;
  if (primaryLower.contains(phraseLower)) return 0;
  for (final field in allLowerFields) {
    if (field.contains(phraseLower)) return 1;
  }
  return 2;
}

/// Lowercased searchable track fields matching Desktop's `TRACK_COLUMNS`:
/// `title`, `artist`, `album`, `album_artist`.
List<String> songSearchFieldsLower(Song song) => <String>[
  song.title.toLowerCase(),
  song.artist.toLowerCase(),
  (song.album ?? '').toLowerCase(),
  (song.albumArtist ?? '').toLowerCase(),
];

bool songMatchesLibraryQuery(Song song, List<String> words) =>
    libraryWordsMatch(words, songSearchFieldsLower(song));

int songLibraryMatchRank(Song song, String phraseLower) {
  final fields = songSearchFieldsLower(song);
  return libraryPhraseRank(phraseLower, fields[0], fields);
}
