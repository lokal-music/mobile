import 'package:flick/features/konnekted/library/online_album_store.dart';
import 'package:flick/features/konnekted/library/lokal_online_catalogue.dart';
import 'package:flick/features/konnekted/library/artist_follow_store.dart';
import 'package:flick/features/konnekted/library/lokal_albums_artists.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('save online albums without any tracks and restore after restart', () async {
    SharedPreferences.setMockInitialValues({});
    final store = OnlineAlbumStore();
    await store.load();
    const release = LokalCatalogueAlbum(
      title: 'Online Album', artist: 'Only Online',
      artwork: 'https://example.com/cover.jpg', id: 'catalogue-42',
      trackCount: 12, releaseKind: LokalReleaseKind.album,
    );
    await store.setSaved(release, true);
    expect(store.isSaved(' online ALBUM ', 'ONLY online'), isTrue);
    expect(store.albums.single.artwork, 'https://example.com/cover.jpg');

    final restored = OnlineAlbumStore();
    await restored.load();
    expect(restored.albums.single.release.id, 'catalogue-42');
    expect(restored.albums.single.release.trackCount, 12);
    expect(restored.albums.single.release.releaseKind, LokalReleaseKind.album);
    await restored.setSaved(release, false);
    expect(restored.albums, isEmpty);

    final reopened = OnlineAlbumStore();
    await reopened.load();
    expect(reopened.albums, isEmpty);
  });

  test('duplicate saves update metadata without creating another album', () async {
    SharedPreferences.setMockInitialValues({});
    final store = OnlineAlbumStore();
    await store.load();
    await store.setSaved(const LokalCatalogueAlbum(
      title: 'Example', artist: 'Artist',
      artwork: 'https://example.com/a.png', id: '100',
    ), true);
    await store.setSaved(const LokalCatalogueAlbum(
      title: ' example ', artist: 'ARTIST',
    ), true);
    expect(store.albums, hasLength(1));
    expect(store.albums.single.artwork, 'https://example.com/a.png');
    expect(store.albums.single.id, '100');
  });

  test('unfollowing online-only artists removes them from the Artists list', () async {
    SharedPreferences.setMockInitialValues({});
    final follows = ArtistFollowStore();
    await follows.setFollowed('An Online Artist', true);
    expect(selectArtistFavorites(
      const [], follows, ArtistFavoritesFilter.all,
    ).map((a) => a.name), contains('An Online Artist'));
    await follows.setFollowed('An Online Artist', false);
    expect(selectArtistFavorites(
      const [], follows, ArtistFavoritesFilter.all,
    ), isEmpty);
  });
}
