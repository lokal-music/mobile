import 'local_device_search.dart';
import '../library_search_matcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flick/core/utils/string_sort_utils.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/models/playlist.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/playlist_provider.dart';
import 'package:flick/providers/songs_provider.dart';
import '../models/global_search_results.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/core/utils/artist_credits.dart';

final globalSearchResultsProvider =
    FutureProvider.autoDispose.family<GlobalSearchResults, String>((ref, rawQuery) async {
  final query = rawQuery.trim();
  if (query.isEmpty) return GlobalSearchResults.empty;

  final lower = query.toLowerCase();

  ref.watch(libraryChangeRevisionProvider);
  ref.watch(playlistsProvider);
  final repo = ref.watch(songRepositoryProvider);
  final loaded = ref.watch(songsProvider).value?.songs;
  final allSongs = phoneLocalSearchSongs(loaded ?? await repo.getAllSongs());

  // Playlists – via service provider.
  List<Playlist> allPlaylists = const [];
  try {
    final service = ref.watch(playlistServiceProvider);
    allPlaylists = await service.getPlaylists();
  } catch (_) {
    // Fallback via playlistsProvider if service fails.
    final asyncPlaylists = ref.watch(playlistsProvider);
    allPlaylists = asyncPlaylists.value?.playlists ?? const [];
  }

  // --- Songs: Desktop parity (`electron/librarySearch.js#searchTracks`).
  // Every query word must appear in title, artist, album or album artist (any
  // order). Whole-phrase title matches rank first, then whole-phrase matches in
  // other fields, then word-only matches; ties sort by title.
  final words = librarySearchWords(query);
  final songRanks = Map<Song, int>.identity();
  final songs = allSongs
      .where((s) => songMatchesLibraryQuery(s, words))
      .toList();
  for (final s in songs) {
    songRanks[s] = songLibraryMatchRank(s, lower);
  }
  songs.sort((a, b) {
    final r = songRanks[a]!.compareTo(songRanks[b]!);
    if (r != 0) return r;
    return compareCaseInsensitive(a.title, b.title);
  });

  // --- Artists: distinct artist names where artist contains ---
  final artistMap = <String, List<Song>>{};
  final artistNames = <String, String>{};
  for (final s in allSongs) {
    for (final artist in songArtistNames(s)) {
      if (!artist.toLowerCase().contains(lower)) continue;
      final key = artistNames.putIfAbsent(artist.toLowerCase(), () => artist);
      artistMap.putIfAbsent(key, () => []).add(s);
    }
  }
  for (final list in artistMap.values) {
    list.sort((a, b) => compareCaseInsensitive(a.title, b.title));
  }
  final artists = artistMap.entries.toList()
    ..sort((a, b) => compareCaseInsensitive(a.key, b.key));

  // --- Album Artists: distinct resolved albumArtist ---
  final albumArtistMap = <String, List<Song>>{};
  for (final s in allSongs) {
    final resolved = SongRepository.albumArtistForSong(s);
    if (!resolved.toLowerCase().contains(lower)) continue;
    albumArtistMap.putIfAbsent(resolved, () => []).add(s);
  }
  for (final list in albumArtistMap.values) {
    list.sort((a, b) => compareCaseInsensitive(a.title, b.title));
  }
  final albumArtists = albumArtistMap.entries.toList()
    ..sort((a, b) => compareCaseInsensitive(a.key, b.key));

  // --- Albums: grouped AlbumGroup where albumName contains ---
  final albumGroupsRaw = <String, List<Song>>{};
  final albumNames = <String, String>{};
  final albumArtistsByKey = <String, Set<String>>{};
  for (final s in allSongs) {
    final albumName = s.album?.trim().isNotEmpty == true
        ? s.album!.trim()
        : l10n.unknownAlbum;
    if (!libraryWordsMatch(words, <String>[
      albumName.toLowerCase(),
      SongRepository.albumArtistForSong(s).toLowerCase(),
      s.artist.toLowerCase(),
    ])) {
      continue;
    }
    final key = '${albumName.toLowerCase()}\u0000${SongRepository.albumArtistForSong(s).toLowerCase()}';
    albumGroupsRaw.putIfAbsent(key, () => []).add(s);
    albumNames[key] = albumName;
    albumArtistsByKey
        .putIfAbsent(key, () => <String>{})
        .add(SongRepository.albumArtistForSong(s));
  }
  final albums = albumGroupsRaw.entries.map((entry) {
    final list = List<Song>.from(entry.value)..sort(_compareAlbumSongs);
    return AlbumGroup(
      key: entry.key,
      albumName: albumNames[entry.key] ?? l10n.unknownAlbum,
      albumArtist: SongRepository.resolveGroupArtist(
        albumArtistsByKey[entry.key] ?? const {},
      ),
      songs: list,
    );
  }).toList()
    ..sort((a, b) {
      final c = compareCaseInsensitive(a.albumArtist, b.albumArtist);
      if (c != 0) return c;
      return compareCaseInsensitive(a.albumName, b.albumName);
    });

  // --- Folders: FolderGroup where folder display name contains ---
  final folderGroups = <String, FolderGroup>{};
  for (final s in allSongs) {
    final rel =
        s.relativeFolderPath ??
        SongsState.extractRelativeSubfolder(s.folderUri, s.filePath);
    final folderUri = s.folderUri ?? '';
    String name;
    String key;
    if (rel.isEmpty) {
      name = SongsState.folderDisplayName(s.folderUri, s.filePath);
      if (name.isEmpty) name = l10n.unknownFolder;
      key = folderUri.isEmpty ? 'unknown::$name' : folderUri;
    } else {
      final parts = rel.split('/');
      name = parts.last;
      if (name.isEmpty) name = rel;
      key = folderUri.isEmpty ? rel : '$folderUri::$rel';
    }
    // Ensure decoded display.
    final decodedName = name;
    final existing = folderGroups[key];
    if (existing == null) {
      folderGroups[key] = FolderGroup(
        name: decodedName,
        key: key,
        folderUri: s.folderUri,
        songs: [s],
      );
    } else {
      existing.songs.add(s);
    }
  }
  // Filter folder groups by name match, then sort.
  final folders = folderGroups.values
      .where((g) => g.name.toLowerCase().contains(lower))
      .toList()
    ..sort((a, b) => compareCaseInsensitive(a.name, b.name));

  // --- Year: songs where year string contains query ---
  final yearMatches = allSongs.where((s) {
    final y = s.year;
    if (y == null) return false;
    return y.toString().contains(lower);
  }).toList()
    ..sort((a, b) {
      final yA = a.year ?? 0;
      final yB = b.year ?? 0;
      final cmp = yB.compareTo(yA);
      if (cmp != 0) return cmp;
      return compareCaseInsensitive(a.title, b.title);
    });

  // --- Playlists: name contains ---
  final playlists = allPlaylists
      .where((p) => p.name.toLowerCase().contains(lower))
      .toList()
    ..sort((a, b) => compareCaseInsensitive(a.name, b.name));

  return GlobalSearchResults(
    query: query,
    songs: songs,
    artists: artists,
    albums: albums,
    albumArtists: albumArtists,
    folders: folders,
    yearMatches: yearMatches,
    playlists: playlists,
  );
});

int _compareAlbumSongs(Song a, Song b) {
  final discA = (a.discNumber != null && a.discNumber! > 0) ? a.discNumber! : 1;
  final discB = (b.discNumber != null && b.discNumber! > 0) ? b.discNumber! : 1;
  final discCmp = discA.compareTo(discB);
  if (discCmp != 0) return discCmp;
  final trackA = (a.trackNumber != null && a.trackNumber! > 0) ? a.trackNumber : null;
  final trackB = (b.trackNumber != null && b.trackNumber! > 0) ? b.trackNumber : null;
  if (trackA != null && trackB != null) {
    final c = trackA.compareTo(trackB);
    if (c != 0) return c;
  } else if (trackA != null || trackB != null) {
    return trackA != null ? -1 : 1;
  }
  final t = compareCaseInsensitive(a.title, b.title);
  if (t != 0) return t;
  return compareCaseInsensitive(a.artist, b.artist);
}
