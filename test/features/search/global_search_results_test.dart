import 'dart:async';

import 'package:flick/features/search/providers/global_search_provider.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/providers/songs_provider.dart';
import 'package:flick/providers/playlist_provider.dart';
import 'package:flick/services/playlist_service.dart';
import 'package:flick/models/song.dart';
import 'package:flick/models/playlist.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Library extends SongsNotifier {
  _Library(this.rows);
  List<Song> rows;
  @override
  Future<SongsState> build() async => SongsState(songs: rows);
  void replace(List<Song> next) {
    rows = next;
    state = AsyncData(SongsState(songs: next));
  }
}

class _Repo implements SongRepository {
  int reads = 0;
  @override
  Future<List<Song>> getAllSongs() async {
    reads++;
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Playlists implements PlaylistService {
  List<Playlist> rows = [];
  @override
  Future<List<Playlist>> getPlaylists() async => rows;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const a = Song(
  id: '1',
  title: 'First',
  artist: 'Alpha, Beta',
  albumArtist: 'Alpha',
  album: 'Shared title',
  duration: Duration(minutes: 3),
  fileType: 'FLAC',
  year: 2024,
  folderUri: '/Music',
  relativeFolderPath: 'Jazz',
);
const b = Song(
  id: '2',
  title: 'Second',
  artist: 'Gamma',
  album: 'Shared title',
  duration: Duration(minutes: 3),
  fileType: 'FLAC',
);
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('artists, albums, folders, year and playlists use the right entities and refresh live', () async {
    final library = _Library([a, b]);
    final repo = _Repo();
    final lists = _Playlists();
    final c = ProviderContainer(
      overrides: [
        songsProvider.overrideWith(() => library),
        songRepositoryProvider.overrideWithValue(repo),
        songLibraryWatchProvider.overrideWithValue(const Stream.empty()),
        playlistServiceProvider.overrideWithValue(lists),
      ],
    );
    addTearDown(c.dispose);
    await c.read(songsProvider.future);
    await c.read(playlistsProvider.future);
    expect(
      (await c.read(globalSearchResultsProvider('Beta').future)).artists
          .map((e) => e.key),
      ['Beta'],
    );
    expect(
      (await c.read(globalSearchResultsProvider('Shared').future))
          .albums
          .length,
      2,
    );
    expect(
      (await c.read(globalSearchResultsProvider('Jazz').future))
          .folders
          .single
          .songs,
      [a],
    );
    expect(
      (await c.read(globalSearchResultsProvider('2024').future)).yearMatches,
      [a],
    );
    // Issue #618: Songs matches artist/album like Desktop, any word order.
    expect(
      (await c.read(globalSearchResultsProvider('gamma').future)).songs,
      [b],
    );
    expect(
      (await c.read(globalSearchResultsProvider('first shared').future)).songs,
      [a],
    );
    expect(
      (await c.read(globalSearchResultsProvider('Second').future)).songs,
      [b],
    );
    final provider = globalSearchResultsProvider('Mix');
    final sub = c.listen(provider, (_, _) {});
    addTearDown(sub.close);
    expect((await c.read(provider.future)).playlists, isEmpty);
    lists.rows = [
      Playlist(id: 'p', name: 'New Mix', createdAt: DateTime(2026)),
    ];
    c.invalidate(playlistsProvider);
    await c.read(playlistsProvider.future);
    expect((await c.read(provider.future)).playlists.single.name, 'New Mix');
    final artists = globalSearchResultsProvider('Delta');
    final artistSub = c.listen(artists, (_, _) {});
    addTearDown(artistSub.close);
    expect((await c.read(artists.future)).artists, isEmpty);
    library.replace([a.copyWith(artist: 'Delta'), b]);
    expect((await c.read(artists.future)).artists.single.key, 'Delta');
    expect(
      repo.reads,
      0,
    ); // Reuse loaded library; category changes need no full database read.
  });
}
