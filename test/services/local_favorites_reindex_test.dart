import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/models/song.dart';
import 'package:flick/services/favorites_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Library implements SongRepository {
  _Library(this.songs);
  List<Song> songs;

  @override
  Future<List<Song>> getAllSongs() async => songs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Song _local(String id, String path, {int? start, int? end}) => Song(
  id: id,
  title: 'Track $path',
  artist: 'Artist',
  duration: const Duration(minutes: 3),
  fileType: 'FLAC',
  filePath: path,
  startOffsetMs: start,
  endOffsetMs: end,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('local likes survive a rescan that reallocates their database IDs',
      () async {
    final library = _Library([
      for (var i = 0; i < 200; i++)
        _local('${i + 1}', '/music/$i.flac'),
    ]);
    final service = FavoritesService(songRepository: library);
    for (final song in library.songs) {
      await service.addFavorite(song.id, song: song);
    }
    expect((await service.getFavoriteIds()).length, 200);

    // Simulate a cold restart, a partial scan, and recycled Isar IDs.
    library.songs = [
      _local('1', '/music/unrelated.flac'),
      for (var i = 0; i < 24; i++)
        _local('${i + 501}', '/music/$i.flac'),
    ];
    final reopened = FavoritesService(songRepository: library);
    final first = await reopened.getFavorites();
    expect(first, hasLength(200),
        reason: 'unscanned local tracks must not disappear from Liked');
    expect(first.where((song) => song.filePath == '/music/unrelated.flac'),
        isEmpty, reason: 'recycled numeric IDs must not inherit hearts');
    expect(await reopened.getFavoriteIds(), hasLength(200));
    expect(await reopened.isFavorite('501'), isTrue);
    expect(await reopened.isFavorite('1'), isFalse);

    // Once the rest of the library is indexed again, all likes reattach.
    library.songs = [
      for (var i = 0; i < 200; i++)
        _local('${i + 501}', '/music/$i.flac'),
    ];
    final restored = await FavoritesService(songRepository: library)
        .getFavorites();
    expect(restored, hasLength(200));
    expect(restored.every((song) => int.parse(song.id) >= 501), isTrue);
    expect((await reopened.getFavoriteIds()).length, 200);
  });

  test('missing local records keep their metadata and heart across restart',
      () async {
    final library = _Library([_local('3', '/music/only.flac')]);
    await FavoritesService(songRepository: library)
        .addFavorite('3', song: library.songs.single);
    library.songs = [];
    final reopened = FavoritesService(songRepository: library);
    final liked = await reopened.getFavorites();
    expect(liked, hasLength(1));
    expect(liked.single.filePath, '/music/only.flac');
    expect(liked.single.isExternal, isFalse);
    expect(await reopened.getFavoriteIds(), {'3'});
  });

  test('overlapping recycled IDs never merge unrelated local likes',
      () async {
    final library = _Library([
      _local('1', '/music/a.flac'),
      _local('2', '/music/b.flac'),
    ]);
    final initial = FavoritesService(songRepository: library);
    for (final song in library.songs) {
      await initial.addFavorite(song.id, song: song);
    }
    final before = await initial.getFavoriteRanks();

    // First scan page gives A the old ID belonging to B. B is absent.
    library.songs = [_local('2', '/music/a.flac')];
    final partial = FavoritesService(songRepository: library);
    expect((await partial.getFavorites()).map((song) => song.filePath).toSet(),
        {'/music/a.flac', '/music/b.flac'});
    expect(await partial.getFavoriteIds(), {'1', '2'});

    // Later B receives a fresh ID; both hearts can move atomically.
    library.songs = [
      _local('2', '/music/a.flac'),
      _local('3', '/music/b.flac'),
    ];
    final complete = FavoritesService(songRepository: library);
    expect((await complete.getFavorites()).map((song) => song.id).toSet(),
        {'2', '3'});
    expect(await complete.getFavoriteIds(), {'2', '3'});
    final after = await complete.getFavoriteRanks();
    expect(after['2'], before['1']);
    expect(after['3'], before['2']);
  });

  test('CUE segments do not steal one another\'s likes after rescan',
      () async {
    final library = _Library([
      _local('1', '/music/album.flac', start: 0, end: 10000),
      _local('2', '/music/album.flac', start: 10000, end: 20000),
    ]);
    await FavoritesService(songRepository: library)
        .addFavorite('2', song: library.songs.last);
    library.songs = [
      _local('2', '/music/album.flac', start: 0, end: 10000),
      _local('9', '/music/album.flac', start: 10000, end: 20000),
    ];
    final reopened = FavoritesService(songRepository: library);
    expect((await reopened.getFavorites()).single.id, '9');
    expect(await reopened.getFavoriteIds(), {'9'});
  });
}
