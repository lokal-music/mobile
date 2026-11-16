import 'package:flick/features/search/download_activity.dart';
import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/features/konnekted/library/collection_download_dialog.dart';
import 'package:flick/features/konnekted/library/collection_downloads.dart';
import 'package:flick/features/konnekted/library/lokal_library_pages.dart';
import 'package:flick/features/konnekted/library/lokal_library_kit.dart';
import 'package:flick/features/konnekted/library/lokal_playlists.dart';
import 'package:flick/features/konnekted/library/playlist_hero_header.dart';
import 'package:flick/models/playlist.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flick/providers/playlist_provider.dart';
import 'package:flick/services/link/library_song_identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Player extends PlayerNotifier {
  @override
  PlayerState build() => const PlayerState();
}

const songs = [
  Song(
    id: 'one',
    title: 'One',
    artist: 'Artist',
    duration: Duration(minutes: 3),
    fileType: 'ONLINE',
  ),
  Song(
    id: 'two',
    title: 'Two',
    artist: 'Artist',
    duration: Duration(minutes: 3),
    fileType: 'ONLINE',
  ),
];

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DownloadActivity.instance.load();
    resetPreparedPlaylistBanners();
  });
  for (final liked in [false, true]) {
    testWidgets(
      'download whole ${liked ? 'Liked' : 'playlist'} despite search filter',
      (tester) async {
        tester.view
          ..physicalSize = const Size(400, 900)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final downloaded = <String>[];
        final downloader = CollectionDownloader(
          library: () async => [],
          download:
              (
                song, {
                required cancel,
                required cancelled,
                required onStatus,
              }) async {
                downloaded.add(song.id);
                return song.copyWith(filePath: '/music/${song.id}.flac');
              },
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playerProvider.overrideWith(_Player.new),
              collectionDownloaderProvider.overrideWithValue(downloader),
              konnektedFavoritesProvider.overrideWithValue(
                const AsyncData(songs),
              ),
              konnektedLibraryIndexProvider.overrideWithValue(
                const AsyncData(
                  PreferredLibrarySongIndex(visible: [], byId: {}),
                ),
              ),
              playlistProvider.overrideWith(
                (ref, id) => Playlist(
                  id: id,
                  name: 'Collection',
                  songIds: ['one', 'two'],
                  createdAt: DateTime(2026),
                ),
              ),
              lokalResolvedPlaylistSongsProvider.overrideWith(
                (ref, id) => songs,
              ),
            ],
            child: MaterialApp(
              theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
              home: liked
                  ? lokalLibraryPage('favorites')
                  : const LokalPlaylistPage(playlistId: 'collection'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'One');
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
        if (liked) {
          final downloadAction = find.widgetWithText(
            LokalPill,
            'Download missing songs',
          );
          expect(downloadAction, findsOneWidget);
          expect(find.byTooltip('Download missing songs'), findsNothing);
          await tester.tap(downloadAction);
        } else {
          await tester.tap(find.byTooltip('More').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Download missing songs'));
        }
        await tester.pumpAndSettle();
        expect(downloaded, isEmpty);
        await tester.tap(find.widgetWithText(FilledButton, 'Download'));
        for (var i = 0; i < 200 && downloaded.length < songs.length; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
        await tester.pumpAndSettle();
        expect(downloaded, ['one', 'two']);
        expect(find.textContaining('Downloaded 2'), findsOneWidget);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
