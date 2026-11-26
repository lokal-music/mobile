import 'library/collection_downloads.dart';

import 'package:flick/services/link/library_song_identity.dart';

import 'dart:async';

import 'package:flick/data/repositories/recently_played_repository.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/features/konnekted/lokal_home_greeting.dart';
import 'package:flick/features/konnekted/lokal_mixes.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/favorites_provider.dart';
import 'package:flick/providers/songs_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Repository boundaries are overridable; rendering the home never requires a
/// platform player in a widget test.
final konnektedHistoryRepositoryProvider = Provider<RecentlyPlayedRepository>(
  (ref) => RecentlyPlayedRepository(),
);

// Home's providers are kept for the session (no autoDispose): the shell
// rebuilds each tab on switch, and Home's shelves should be there at once
// when you come back rather than pop in empty.

// History merge writes arrive in bursts. Keep the first update responsive,
// then coalesce the rest instead of queuing a DB read for every imported play.
Stream<void> _homeHistoryChanges(Ref ref, RecentlyPlayedRepository repository) {
  final changes = StreamController<void>();
  Timer? timer;
  var pending = false;
  void settle() {
    timer = null;
    if (!pending || changes.isClosed) return;
    pending = false;
    changes.add(null);
    timer = Timer(const Duration(milliseconds: 500), settle);
  }

  final subscription = repository.watchHistory().listen((_) {
    if (timer != null) {
      pending = true;
    } else {
      changes.add(null);
      timer = Timer(const Duration(milliseconds: 500), settle);
    }
  }, onError: changes.addError);
  changes.add(null);
  ref.onDispose(() {
    timer?.cancel();
    unawaited(subscription.cancel());
    unawaited(changes.close());
  });
  return changes.stream;
}

final konnektedRecentSongsProvider = StreamProvider<List<Song>>((ref) {
  final repository = ref.watch(konnektedHistoryRepositoryProvider);
  return _homeHistoryChanges(ref, repository).asyncMap((_) async {
    final entries = await repository.getRecentHistory(limit: 40);
    final seen = <String>{};
    return entries
        .map((entry) => entry.song)
        .where((song) => seen.add(song.id))
        .take(12)
        .toList(growable: false);
  });
});

/// Home's personal greeting line, from the latest plays (desktop's rules).
final konnektedGreetingProvider = StreamProvider<LokalHomeMessages>((ref) {
  final repository = ref.watch(konnektedHistoryRepositoryProvider);
  return _homeHistoryChanges(ref, repository).asyncMap(
    (_) async =>
        lokalHomeMessages(await repository.getRecentHistory(limit: 40)),
  );
});

// Riverpod's whenData drops retained data when its input is AsyncLoading.
// A live library refresh must not turn established shelves into placeholders.
AsyncValue<R> _homeData<T, R>(AsyncValue<T> source, R Function(T) map) {
  if (source.hasValue) return AsyncData(map(source.requireValue));
  return source.when(
    data: (value) => AsyncData(map(value)),
    loading: () => const AsyncLoading(),
    error: (error, stack) => AsyncError(error, stack),
  );
}

final collectionOfflineIndexProvider = FutureProvider<OfflineCollectionIndex>((
  ref,
) async {
  final songs = ref.watch(songsProvider).value?.songs ?? const <Song>[];
  return OfflineCollectionIndex.build(songs);
});

final konnektedFavoritesProvider = Provider<AsyncValue<List<Song>>>((ref) {
  final offline = ref.watch(collectionOfflineIndexProvider).value;
  return _homeData(
    ref.watch(favoritesProvider),
    (state) => [
      for (final song in state.favoriteSongs) offline?.resolve(song) ?? song,
    ],
  );
});

/// Keep playlist ID resolution tied to the same deduplication decision as
/// the displayed library: hidden desktop duplicates resolve to phone copies.
final konnektedLibraryIndexProvider =
    Provider<AsyncValue<PreferredLibrarySongIndex>>(
  (ref) => _homeData(
    ref.watch(songsProvider),
    (state) => preferredLibrarySongIndex(state.songs),
  ),
);

final konnektedLibraryProvider = Provider<AsyncValue<List<Song>>>(
  (ref) => _homeData(
    ref.watch(konnektedLibraryIndexProvider),
    (index) => index.visible,
  ),
);

final konnektedRecentlyAddedProvider = Provider<AsyncValue<List<Song>>>(
  (ref) => _homeData(
    ref.watch(konnektedLibraryProvider),
    (songs) => _newestFirst(songs).take(12).toList(growable: false),
  ),
);

({String key, List<LokalMix> mixes})? _mixes;

/// Forgets the cached mixes (tests).
@visibleForTesting
void resetKonnektedMixes() => _mixes = null;

/// Your Mixes, by desktop's rules (`lokal_mixes.dart`). Like desktop, they
/// are built once and kept for the day rather than reshuffled on every play;
/// they are rebuilt when the day turns or the library or favourites change
/// size.
class KonnektedMixRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void refresh() {
    refreshLokalMadeForYou();
    state++;
  }
}

final konnektedMixRefreshProvider = NotifierProvider<KonnektedMixRefresh, int>(
  KonnektedMixRefresh.new,
);

final konnektedMixesProvider = FutureProvider<List<LokalMix>>((ref) async {
  final library = ref.watch(konnektedLibraryProvider.select((s) => s.value));
  final liked =
      ref.watch(konnektedFavoritesProvider.select((s) => s.value)) ??
      const <Song>[];
  // Still loading: stay loading rather than flash an empty Home.
  if (library == null) return Completer<List<LokalMix>>().future;
  if (library.isEmpty) return const [];
  final refresh = ref.watch(konnektedMixRefreshProvider);
  final now = DateTime.now();
  final key =
      '$refresh|${now.year}-${now.month}-${now.day}|${Object.hashAll(library.map((s) => Object.hash(s.id, s.artist, s.genre, s.album)))}|${Object.hashAll(liked.map((s) => s.id))}';
  final cached = _mixes;
  if (cached != null && cached.key == key) return cached.mixes;
  final history = ref.read(konnektedHistoryRepositoryProvider);
  final recent = await history.getRecentHistory(limit: 50);
  final counts = await history.getPlayCounts();
  final mixes = lokalMixes(
    library: library,
    liked: liked,
    history: [for (final entry in recent) entry.song],
    playCounts: counts,
    now: now,
    refreshSeed: refresh,
  );
  _mixes = (key: key, mixes: mixes);
  return mixes;
});

/// Made for you: four songs from each of the first six mixes, picked once
/// per run (desktop's rule).
final konnektedMadeForYouProvider =
    Provider<AsyncValue<List<LokalMadeForYouPick>>>(
      (ref) => _homeData(ref.watch(konnektedMixesProvider), lokalMadeForYou),
    );

/// Keep a recommendation as the visible carousel cover, while opening its
/// local album (in disc/track order) on long-press. The local library is already
/// loaded for Made for You, so no database query runs per cover or gesture.
@visibleForTesting
List<AlbumGroup> konnektedCoversWithLocalAlbums(
  List<LokalMadeForYouPick> picks,
  List<Song> localSongs,
) {
  String key(String? value) => (value ?? '').trim().toLowerCase();
  final albums = <String, List<Song>>{};
  final seenLocalIds = <String>{};
  for (final song in localSongs) {
    // An overlapping library source or transient sync can surface the same
    // recording twice. Each local track belongs on the album back only once.
    if (!seenLocalIds.add(song.id)) continue;
    final albumKey = key(song.album);
    if (albumKey.isEmpty) continue;
    (albums[albumKey] ??= <Song>[]).add(song);
  }

  AlbumGroup coverFor(Song song) {
    final albumName = song.album?.trim() ?? '';
    final candidates = albums[key(albumName)] ?? const <Song>[];
    final albumArtist = key(song.albumArtist);
    final matches = candidates.where((candidate) {
      // Albums with the same title but different known album artists
      // must not be merged. Keep compilation rows lacking that tag.
      final otherArtist = key(candidate.albumArtist);
      return albumArtist.isEmpty ||
          otherArtist.isEmpty ||
          otherArtist == albumArtist;
    }).toList();
    final albumTracks = matches.isEmpty ? <Song>[song] : matches;
    if (!albumTracks.any((candidate) => candidate.id == song.id)) {
      albumTracks.add(song);
    }
    return AlbumGroup(
      key: 'song:${song.id}',
      albumName: albumName.isEmpty ? song.title : albumName,
      albumArtist: song.albumArtist?.trim().isNotEmpty == true
          ? song.albumArtist!.trim()
          : song.artist,
      songs: SongRepository.sortAlbumTracks(albumTracks),
      coverSong: song,
    );
  }

  final seen = <String>{};
  return [
    for (final pick in picks)
      if (seen.add(pick.song.id)) coverFor(pick.song),
  ];
}

/// Home's Cover Flow remains one cover per recommended song. Its back shows
/// all matching *local* album tracks; tapping a face still plays the selected
/// recommendation with the same Made for You shelf as the queue.
/// Build a lightweight local-album shelf while the personalized mix
/// history is loading. This keeps Home's first-open carousel populated as soon
/// as the local library snapshot is available, then swaps to personalized picks.
List<AlbumGroup> _localCoverFlowFallback(List<Song> songs) {
  final groups = <String, List<Song>>{};
  final labels = <String, ({String album, String artist})>{};
  for (final song in songs) {
    final album = song.album?.trim() ?? '';
    if (album.isEmpty) continue;
    final artist = (song.albumArtist?.trim().isNotEmpty == true
        ? song.albumArtist!.trim()
        : song.artist.trim());
    final key = '${album.toLowerCase()}|\u0000${artist.toLowerCase()}';
    (groups[key] ??= <Song>[]).add(song);
    labels[key] = (album: album, artist: artist);
  }
  final result = <AlbumGroup>[];
  for (final entry in groups.entries) {
    final tracks = SongRepository.sortAlbumTracks(entry.value);
    final cover = tracks.firstWhere(
      (song) => song.albumArt?.isNotEmpty == true,
      orElse: () => tracks.first,
    );
    final label = labels[entry.key]!;
    result.add(AlbumGroup(
      key: 'local:${entry.key}',
      albumName: label.album,
      albumArtist: label.artist,
      songs: tracks,
      coverSong: cover,
    ));
    if (result.length == 12) break;
  }
  return result;
}

final konnektedCoverAlbumsProvider = Provider<AsyncValue<List<AlbumGroup>>>(
  (ref) {
    final picks = ref.watch(konnektedMadeForYouProvider);
    final local = ref.watch(konnektedLibraryProvider).value ?? const <Song>[];
    if (!picks.hasValue && local.isNotEmpty) {
      return AsyncData(_localCoverFlowFallback(local));
    }
    return _homeData(picks, (entries) =>
        konnektedCoversWithLocalAlbums(entries, local));
  },
);

List<Song> _newestFirst(Iterable<Song> songs) =>
    List<Song>.of(songs)..sort((a, b) {
      final compared = (b.dateAdded ?? DateTime(1970)).compareTo(
        a.dateAdded ?? DateTime(1970),
      );
      return compared != 0 ? compared : a.title.compareTo(b.title);
    });
