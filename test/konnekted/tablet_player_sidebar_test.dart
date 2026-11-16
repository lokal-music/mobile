import 'package:flick/models/audio_engine_type.dart';
import 'package:flick/features/konnekted/konnekted_shell.dart';
import 'package:flick/widgets/lokal/lokal_glass.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/features/player/widgets/lyrics_source_button.dart';
import 'package:flick/features/player/widgets/online_lyrics_search_sheet.dart';

import 'dart:io';
import 'dart:convert';

import 'package:flick/features/player/widgets/synced_lyrics_view.dart';
import 'package:flick/services/lyrics_playback_prefetch.dart';

import 'package:flick/services/motion_art/moving_cover_settings.dart';

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/data/repositories/recently_played_repository.dart';
import 'package:flick/features/internet_radio/radio_catalog.dart';
import 'package:flick/features/internet_radio/station_metadata.dart';
import 'package:flick/features/internet_radio/radio_providers.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/features/konnekted/konnekted_dock.dart';
import 'package:flick/features/konnekted/konnekted_tablet_footer.dart';
import 'package:flick/features/konnekted/konnekted_tablet_player_sidebar.dart';
import 'package:flick/features/konnekted/konnekted_tablet_workspace.dart';
import 'package:flick/features/konnekted/tablet_playback.dart';
import 'package:flick/models/audio_output_diagnostics.dart';
import 'package:flick/models/lokal_remote_state.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/app_preferences_provider.dart';
import 'package:flick/providers/favorites_provider.dart';
import 'package:flick/providers/lokal_remote_provider.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flick/services/app_preferences_service.dart';
import 'package:flick/services/player_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const song = Song(
  id: 'one',
  title: 'Northern Lights',
  artist: 'The Quiet Hours',
  album: 'After the Rain',
  albumArtist: 'The Quiet Hours',
  year: 2025,
  genre: 'Ambient',
  trackNumber: 3,
  fileType: 'FLAC',
  bitDepth: 24,
  sampleRate: 96000,
  duration: Duration(minutes: 4),
);
const nextSong = Song(
  id: 'two',
  title: 'Open Water',
  artist: 'North Shore',
  album: 'Blue Hour',
  fileType: 'FLAC',
  duration: Duration(minutes: 3),
);
const station = RadioStation(
  id: 'station',
  title: 'Live station',
  url: 'https://example.com/radio',
  codec: 'AAC',
  bitrate: 256,
);

class _Player extends PlayerNotifier {
  _Player([this.initialSong = song]);
  final Song initialSong;
  final actions = <String>[];
  @override
  PlayerState build() => PlayerState(
    currentSong: initialSong,
    duration: Duration(minutes: 4),
    position: Duration(seconds: 60),
    playlist: [song, nextSong],
    upNext: [nextSong],
    currentIndex: 0,
  );
  @override
  Future<void> togglePlayPause() async {
    actions.add('play');
    state = state.copyWith(isPlaying: !state.isPlaying);
  }

  @override
  Future<void> toggleShuffle() async {
    actions.add('shuffle');
    state = state.copyWith(isShuffle: !state.isShuffle);
  }

  @override
  void toggleLoopMode() {
    actions.add('repeat');
    state = state.copyWith(loopMode: LoopMode.one);
  }

  @override
  Future<void> next() async {
    actions.add('next');
    state = state.copyWith(currentSong: nextSong);
  }

  @override
  Future<void> previous({bool allowRestart = true}) async =>
      actions.add('previous');
  @override
  Future<void> seek(Duration position) async {
    actions.add('seek:${position.inSeconds}');
    state = state.copyWith(position: position);
  }

  @override
  Future<void> playFromUpNextIndex(int index) async {
    actions.add('queue-play:$index');
    state = state.copyWith(currentSong: nextSong);
  }

  @override
  Future<void> setVolume(double volume) async => actions.add('volume');
}

class _Remote extends LokalRemoteController {
  _Remote([this.enabled = false]);
  final bool enabled;
  void enable() => state = state.copyWith(controlsDesktop: true);
  @override
  LokalRemoteControllerState build() => LokalRemoteControllerState(
    controlsDesktop: enabled,
    desktopName: 'Studio',
    snapshot: const LokalRemoteSnapshot(
      currentTrack: null,
      connected: true,
      isPlaying: false,
      progress: 60,
      duration: 240,
      volume: .5,
      repeat: 'none',
      shuffle: false,
      updatedAt: 1,
      currentIndex: 0,
      queue: [],
    ),
  );
}

class _Radio extends RadioPlayerNotifier {
  _Radio([this.enabled = false]);
  final bool enabled;
  final actions = <String>[];
  @override
  RadioPlayback build() => RadioPlayback(station: enabled ? station : null);
  @override
  List<RadioStation> get stationQueue => const [station];
  @override
  Future<void> toggle() async => actions.add('radio-play');
  @override
  Future<void> nextStation() async => actions.add('radio-next');
  @override
  Future<void> previousStation() async => actions.add('radio-previous');
  @override
  Future<void> setVolume(double value) async => volume.value = value;
  @override
  Future<void> play(RadioStation station, {List<RadioStation>? queue}) async =>
      actions.add('radio-queue');
}

class _Preferences extends AppPreferencesNotifier {
  @override
  AppPreferences build() => const AppPreferences(
    animatedAlbumArt: false,
    animationsEnabled: false,
    lyricsAutoFetch: false,
  );
}

class _Favorites extends FavoritesNotifier {
  @override
  Future<FavoritesState> build() async =>
      const FavoritesState(isLoading: false);
  @override
  Future<bool> toggleFavorite(String id, {Song? song}) async {
    final liked = !(state.value?.isFavorite(id) ?? false);
    state = AsyncData(
      FavoritesState(favoriteIds: liked ? {id} : {}, isLoading: false),
    );
    return liked;
  }
}

class _History extends Fake implements RecentlyPlayedRepository {
  @override
  Future<Map<String, int>> getPlayCounts() async => const {'one': 7};
}

class _Service extends Fake implements PlayerService {
  @override
  final extendedVolumeEnabledNotifier = ValueNotifier(false);
  @override
  AudioEngineType get currentEngineType => AudioEngineType.normalAndroid;
  @override
  final isPlayingNotifier = ValueNotifier(false);
  @override
  final audioOutputDiagnosticsNotifier = ValueNotifier<AudioOutputDiagnostics?>(
    null,
  );
  @override
  final playbackContextNotifier = ValueNotifier(
    const PlaybackContext(
      source: PlaybackSource.album,
      sourceName: 'After the Rain',
    ),
  );
  @override
  final positionNotifier = ValueNotifier(const Duration(seconds: 2));
  @override
  bool get isCasting => false;
  @override
  bool get isVolumeAvailable => true;
  @override
  double get maxVolume => 1;
  @override
  double currentVolume = .5;
  @override
  Future<void> setVolume(double value) async => currentVolume = value;
}

class _LyricsProbe extends StatefulWidget {
  const _LyricsProbe({super.key});
  @override
  State<_LyricsProbe> createState() => _LyricsProbeState();
}

class _LyricsProbeState extends State<_LyricsProbe> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => setState(() => count++),
      child: Text('Lyric selection $count'),
    ),
  );
}

Widget _app(
  Widget child, {
  double scale = 1,
  bool light = false,
  _Player? player,
  bool radio = false,
  bool remote = false,
  bool animate = false,
  TargetPlatform? platform,
}) => ProviderScope(
  overrides: [
    playerProvider.overrideWith(() => player ?? _Player()),
    playerServiceProvider.overrideWithValue(_Service()),
    appPreferencesProvider.overrideWith(_Preferences.new),
    lokalRemoteControllerProvider.overrideWith(() => _Remote(remote)),
    radioPlayerProvider.overrideWith(() => _Radio(radio)),
    favoritesProvider.overrideWith(_Favorites.new),
    konnektedHistoryRepositoryProvider.overrideWithValue(_History()),
  ],
  child: MaterialApp(
    theme: LokalTheme.build(
      LokalTokens.resolve(light ? LokalThemeId.light : LokalThemeId.dark),
    ).copyWith(platform: platform),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: !animate,
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(body: child),
      ),
    ),
  ),
);

void main() {
  testWidgets('sidebar Lyrics opens the full-player lyrics entry point', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(340, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var playerOpens = 0, lyricsOpens = 0;
    await tester.pumpWidget(
      _app(
        KonnektedTabletPlayerSidebar(
          active: true,
          tab: TabletPlayerTab.details,
          onTabChanged: (_) {},
          onClose: () {},
          onOpenPlayer: () => playerOpens++,
          onOpenLyrics: () => lyricsOpens++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Lyrics, full screen'));
    await tester.tap(find.byTooltip('Lyrics, full screen'));
    expect(lyricsOpens, 1);
    expect(playerOpens, 0);
    expect(find.byType(Scaffold), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sidebar-artwork')));
    await tester.pump(const Duration(milliseconds: 350));
    expect(playerOpens, 1);
    expect(lyricsOpens, 1);
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          (_) async => null,
        );
    for (final (family, asset) in [
      (LokalTheme.sans, 'assets/fonts/DMSans-Regular.ttf'),
      (LokalTheme.mono, 'assets/fonts/DMMono-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/lucide_icons_flutter/Lucide',
        'packages/lucide_icons_flutter/assets/lucide.ttf',
      ),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
    }
  });

  test(
    'radio lyrics are keyed to the recording and wait for real metadata',
    () {
      final unknown = TabletPlayback(
        song: song,
        remote: false,
        radio: const RadioPlayback(station: station),
      );
      expect(unknown.lyricsSong, isNull);
      final first = TabletPlayback(
        song: song,
        remote: false,
        radio: const RadioPlayback(
          station: station,
          trackMetadata: StationLiveMetadata(title: 'First', artist: 'Artist'),
        ),
      );
      final next = TabletPlayback(
        song: song,
        remote: false,
        radio: const RadioPlayback(
          station: station,
          trackMetadata: StationLiveMetadata(title: 'Second', artist: 'Artist'),
        ),
      );
      expect(first.lyricsSong!.id, isNot(next.lyricsSong!.id));
      expect(first.song!.id, next.song!.id);
      expect(TabletPlayback(song: song, remote: true).lyricsSong, same(song));
    },
  );

  testWidgets(
    'sidebar card and full-height lyrics share state through tab changes',
    (tester) async {
      tester.view
        ..physicalSize = const Size(340, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var tab = TabletPlayerTab.details;
      var opened = 0;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) => KonnektedTabletPlayerSidebar(
              active: true,
              tab: tab,
              onTabChanged: (next) => setState(() => tab = next),
              onClose: () {},
              onOpenPlayer: () => opened++,
              lyricsBuilder: (_, _, _) => const _LyricsProbe(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sidebar-metadata')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('below-cover-lyrics')),
      );
      await tester.tap(find.byKey(const ValueKey('below-cover-lyrics')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sidebar-metadata')), findsNothing);
      await tester.ensureVisible(find.text('Lyric selection 0'));
      await tester.tap(find.text('Lyric selection 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('player-sidebar-tab-lyrics')));
      await tester.pumpAndSettle();
      expect(find.text('Lyric selection 1'), findsOneWidget);
      expect(tester.getSize(find.byType(_LyricsProbe)).width, greaterThan(280));
      await tester.tap(find.byKey(const ValueKey('player-sidebar-tab-queue')));
      await tester.pumpAndSettle();
      expect(find.text('Open Water'), findsOneWidget);
      expect(tester.getRect(find.text('Open Water')).width, greaterThan(40));
      expect(find.text('Open Water').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Open Water'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(KonnektedTabletPlayerSidebar)),
      );
      expect(
        (container.read(playerProvider.notifier) as _Player).actions,
        contains('queue-play:0'),
      );
      expect(opened, 0);
      expect(find.text('Lyric selection 1'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('player-sidebar-tab-details')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Lyric selection 1'));
      expect(find.text('Lyric selection 1'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('combine-sidebar-cards')),
      );
      await tester.tap(find.byKey(const ValueKey('combine-sidebar-cards')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sidebar-metadata')), findsOneWidget);
      expect(find.text('Lyric selection 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'artwork like and motion toggles remain functional below the cover',
    (tester) async {
      tester.view
        ..physicalSize = const Size(340, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          KonnektedTabletPlayerSidebar(
            active: true,
            tab: TabletPlayerTab.details,
            onTabChanged: (_) {},
            onClose: () {},
            onOpenPlayer: () {},
            lyricsBuilder: (_, _, _) => const _LyricsProbe(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(KonnektedTabletPlayerSidebar)),
        listen: false,
      );
      final artwork = find.byKey(const ValueKey('sidebar-artwork'));
      await tester.tapAt(tester.getCenter(artwork));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(tester.getCenter(artwork));
      await tester.pumpAndSettle();
      expect(
        container.read(favoritesProvider).value!.isFavorite(song.id),
        isTrue,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('sidebar-like')));
      await tester.tap(find.byKey(const ValueKey('sidebar-like')));
      await tester.pumpAndSettle();
      expect(
        container.read(favoritesProvider).value!.isFavorite(song.id),
        isFalse,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('sidebar-motion-toggle')),
      );
      await tester.tap(find.byKey(const ValueKey('sidebar-motion-toggle')));
      await tester.pumpAndSettle();
      expect(
        container
            .read(movingCoverSettingsProvider)
            .disabledSongs
            .contains(movingCoverSongKey(song)),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real compact lyrics retain source controls at 200 percent text',
    (tester) async {
      SharedPreferences.setMockInitialValues({'lyrics_auto_fetch': false});
      tester.view
        ..physicalSize = const Size(300, 700)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('tablet-lyrics-'),
      );
      addTearDown(() async {
        await directory!.delete(recursive: true);
      });
      final audio = File('${directory!.path}/track.flac');
      await tester.runAsync(() async {
        await audio.writeAsBytes([]);
        await File('${directory.path}/track.lrc').writeAsString(
          '[00:01.00]First light\n[00:02.00]Over open water\n[00:04.00]After the rain',
        );
      });
      SharedPreferences.setMockInitialValues({
        'lyrics_auto_fetch': false,
        'lyrics_manual_overrides_v1': jsonEncode({
          audio.path: '${directory.path}/track.lrc',
        }),
      });
      final lyricSong = song.copyWith(id: directory.path, filePath: audio.path);
      final prefetched = await tester.runAsync(
        () => LyricsPlaybackPrefetch.instance.local(lyricSong),
      );
      expect(prefetched?.isSynchronized, isTrue);
      addTearDown(() => LyricsPlaybackPrefetch.instance.invalidate(lyricSong));
      var tab = TabletPlayerTab.lyrics;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) => KonnektedTabletPlayerSidebar(
              active: true,
              tab: tab,
              onTabChanged: (value) => setState(() => tab = value),
              onClose: () {},
              onOpenPlayer: () {},
            ),
          ),
          player: _Player(lyricSong),
          scale: 2,
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(SyncedLyricsView), findsOneWidget);
      expect(
        tester
            .widget<SyncedLyricsView>(find.byType(SyncedLyricsView))
            .fullPlayerTypography,
        isTrue,
      );
      expect(
        tester.getSize(find.byType(SyncedLyricsView)).height,
        greaterThan(350),
      );
      final toolbar = find.byKey(const ValueKey('compact-lyrics-toolbar'));
      expect(tester.getSize(toolbar).height, lessThanOrEqualTo(48));
      expect(find.text(l10n.useExistingFile), findsNothing);
      expect(find.text(l10n.searchOnline), findsNothing);
      expect(find.byTooltip(l10n.useExistingFile), findsOneWidget);
      expect(find.byTooltip(l10n.searchOnline), findsOneWidget);
      final source = tester.widget<LyricsSourceButton>(
        find.byType(LyricsSourceButton),
      );
      expect(source.iconOnly, isTrue);
      expect(source.onResetManual, isNotNull);
      await tester.tap(find.byTooltip(l10n.searchOnline));
      await tester.pumpAndSettle();
      expect(find.byType(OnlineLyricsSearchSheet), findsOneWidget);
      expect(find.widgetWithText(TextField, lyricSong.title), findsOneWidget);
      Navigator.of(tester.element(find.byType(OnlineLyricsSearchSheet))).pop();
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('player-sidebar-tab-details')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('below-cover-lyrics')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('below-cover-lyrics')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('below-cover-lyrics')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(SyncedLyricsView));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(SyncedLyricsView)).width,
        greaterThan(250),
      );
      expect(tester.getSize(toolbar).height, lessThanOrEqualTo(48));
      expect(
        tester.getSize(find.byType(SyncedLyricsView)).height,
        greaterThan(350),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      // Flush the existing embedded-reader timeout after disposing the card.
      await tester.pump(const Duration(seconds: 9));
    },
  );

  testWidgets('footer and sidebar fit dark/light themes and 200 percent text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final light in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        for (final size in [
          const Size(600, 960),
          const Size(768, 1024),
          const Size(1024, 768),
          const Size(1366, 1024),
        ]) {
          for (final collapsed in [false, true]) {
            tester.view.physicalSize = size;
            await tester.pumpWidget(
              _app(
                KonnektedTabletWorkspace(
                  selected: KonnektedTab.listen,
                  route: null,
                  onSelect: (_) {},
                  onNavigate: (_) {},
                  leftOpen: true,
                  rightOpen: size.width >= 1000,
                  hasPlayer: true,
                  playerCollapsed: collapsed,
                  onToggleLeft: () {},
                  onToggleRight: () {},
                  mobileDock: const SizedBox.shrink(),
                  player: KonnektedTabletFooter(
                    collapsed: collapsed,
                    onExpand: () {},
                    onOpenPlayer: () {},
                    onOpenPanel: (_) {},
                  ),
                  playerSidebar: KonnektedTabletPlayerSidebar(
                    active: size.width >= 1000,
                    tab: TabletPlayerTab.details,
                    onTabChanged: (_) {},
                    onClose: () {},
                    onOpenPlayer: () {},
                    lyricsBuilder: (_, _, _) => const _LyricsProbe(),
                  ),
                  child: const Center(child: Text('Library content')),
                ),
                scale: scale,
                light: light,
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('tablet-player-bar')),
              findsOneWidget,
            );
            expect(find.byType(KonnektedTabletFooter), findsOneWidget);
            final timeline = find.byType(TabletSeekBar);
            if (timeline.evaluate().isNotEmpty) {
              final timelineRect = tester.getRect(timeline);
              final footerRect = tester.getRect(
                find.byKey(const ValueKey('tablet-footer-glass')),
              );
              expect(timelineRect.width, lessThanOrEqualTo(448));
              expect(
                timelineRect.center.dx,
                closeTo(footerRect.center.dx, .01),
              );
            }
            final footer = tester.getRect(
              find.byKey(const ValueKey('tablet-footer-glass')),
            );
            if (footer.width >= 440) {
              expect(
                tester.getCenter(find.byTooltip('Play')).dx,
                closeTo(footer.center.dx, .01),
                reason: 'Transport must stay centred when the sidebar narrows the footer.',
              );
            }
            expect(
              tester.takeException(),
              isNull,
              reason: '$size text=$scale light=$light collapsed=$collapsed',
            );
          }
        }
      }
    }
  });

  testWidgets(
    'reveals share live pane/footer geometry at 120 Hz without rebuilding panel content',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(
        left: 24,
        right: 18,
        bottom: 34,
      );
      tester.view.viewPadding = const FakeViewPadding(
        left: 24,
        right: 18,
        bottom: 34,
      );
      addTearDown(tester.view.reset);
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        for (final width in [600.0, 768.0, 1024.0, 1366.0]) {
          await tester.pumpWidget(const SizedBox.shrink());
          tester.view.physicalSize = Size(width, 900);
          var left = false, right = false, panelBuilds = 0;
          late StateSetter change;
          final page = const _LyricsProbe(key: ValueKey('reveal-page-state'));
          final panel = Builder(
            builder: (_) {
              panelBuilds++;
              return const _LyricsProbe(key: ValueKey('reveal-panel-state'));
            },
          );
          await tester.pumpWidget(
            _app(
              StatefulBuilder(
                builder: (context, setState) {
                  change = setState;
                  return KonnektedTabletWorkspace(
                    selected: KonnektedTab.listen,
                    route: null,
                    onSelect: (_) {},
                    onNavigate: (_) {},
                    leftOpen: left,
                    rightOpen: right,
                    hasPlayer: true,
                    onToggleLeft: () => setState(() => left = !left),
                    onToggleRight: () => setState(() => right = !right),
                    mobileDock: const SizedBox.shrink(),
                    playerSidebar: panel,
                    player: KonnektedTabletFooter(
                      onOpenPlayer: () {},
                      onOpenPanel: (_) {},
                    ),
                    child: page,
                  );
                },
              ),
              animate: true,
              platform: platform,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('reveal-page-state')));
          await tester.pumpAndSettle();
          final pageState = tester.state(
            find.byKey(const ValueKey('reveal-page-state')),
          );
          final footerBefore = tester.getRect(
            find.byKey(const ValueKey('tablet-footer-glass')),
          );
          final searchBefore = tester.getRect(
            find.byKey(const ValueKey('tablet-header-search')),
          );
          change(() {
            left = true;
            right = true;
          });
          await tester.pump();
          final leftSlot = find.byKey(
            const ValueKey('tablet-navigation-reveal'),
          );
          final rightSlot = find.byKey(const ValueKey('tablet-player-reveal'));
          expect(tester.getSize(leftSlot).width, 104);
          expect(tester.getSize(rightSlot).width, 0);
          expect(
            tester.getRect(find.byKey(const ValueKey('tablet-footer-glass'))),
            footerBefore,
          );
          expect(
            tester.getRect(find.byKey(const ValueKey('tablet-header-search'))),
            searchBefore,
          );
          final buildsAtReveal = panelBuilds;
          var lastLeft = 104.0, lastRight = 0.0;
          for (var frame = 0; frame < 44; frame++) {
            await tester.pump(const Duration(microseconds: 8333));
            final leftRect = tester.getRect(leftSlot);
            final rightRect = tester.getRect(rightSlot);
            final footer = tester.getRect(
              find.byKey(const ValueKey('tablet-footer-glass')),
            );
            expect(leftRect.width, greaterThanOrEqualTo(lastLeft));
            expect(rightRect.width, greaterThanOrEqualTo(lastRight));
            if (footer.width >= 440) {
              expect(
                tester.getCenter(find.byTooltip('Play')).dx,
                closeTo(footer.center.dx, .01),
              );
            }
            expect(footer.left, greaterThanOrEqualTo(leftRect.right - .01));
            expect(footer.right, lessThanOrEqualTo(rightRect.left + .01));
            expect(
              tester
                  .getSize(find.byKey(const ValueKey('tablet-player-sidebar')))
                  .width,
              340,
            );
            expect(
              tester
                  .getSize(find.byKey(const ValueKey('reveal-page-state')))
                  .width,
              closeTo(
                width - leftRect.width - (width >= 1000 ? rightRect.width : 0),
                .01,
              ),
            );
            expect(panelBuilds, buildsAtReveal);
            expect(
              tester.takeException(),
              isNull,
              reason: '$platform width=$width frame=$frame',
            );
            lastLeft = leftRect.width;
            lastRight = rightRect.width;
          }
          expect(lastRight, 340);
          expect(
            identical(
              tester.state(find.byKey(const ValueKey('reveal-page-state'))),
              pageState,
            ),
            isTrue,
          );
          expect((pageState as _LyricsProbeState).count, 1);
          change(() {
            left = false;
            right = false;
          });
          await tester.pump();
          expect(leftSlot, findsOneWidget);
          expect(tester.getSize(leftSlot).width, 104);
          expect(rightSlot, findsNothing);
          expect(
            tester
                .getSize(find.byKey(const ValueKey('reveal-page-state')))
                .width,
            width - 104,
          );
          expect(
            tester
                .getRect(find.byKey(const ValueKey('tablet-player-bar')))
                .left,
            104,
          );
          expect(
            tester
                .getRect(find.byKey(const ValueKey('tablet-player-bar')))
                .right,
            width,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets(
    'a reveal can be interrupted, hidden instantly and disabled by reduced motion',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1366, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var right = false, reduced = false;
      late StateSetter change;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              change = setState;
              return MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(disableAnimations: reduced),
                child: KonnektedTabletWorkspace(
                  selected: KonnektedTab.listen,
                  route: null,
                  onSelect: (_) {},
                  onNavigate: (_) {},
                  leftOpen: false,
                  rightOpen: right,
                  hasPlayer: true,
                  onToggleLeft: () {},
                  onToggleRight: () => setState(() => right = !right),
                  mobileDock: const SizedBox.shrink(),
                  playerSidebar: const _LyricsProbe(),
                  player: KonnektedTabletFooter(
                    onOpenPlayer: () {},
                    onOpenPanel: (_) {},
                  ),
                  child: const SizedBox.expand(),
                ),
              );
            },
          ),
          animate: true,
        ),
      );
      await tester.pumpAndSettle();
      change(() => right = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final slot = find.byKey(const ValueKey('tablet-player-reveal'));
      expect(tester.getSize(slot).width, inExclusiveRange(0, 340));
      change(() => right = false);
      await tester.pump();
      expect(slot, findsNothing);
      change(() => right = true);
      await tester.pump();
      expect(tester.getSize(slot).width, 0);
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getSize(slot).width, inExclusiveRange(0, 340));
      change(() => reduced = true);
      await tester.pump();
      expect(tester.getSize(slot).width, 340);
      await tester.pumpAndSettle();
      change(() => right = false);
      await tester.pump();
      change(() => right = true);
      await tester.pump();
      expect(tester.getSize(slot).width, 340);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'footer stays strictly between visible sidebars at every tablet size',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final width in [600.0, 768.0, 1024.0, 1366.0]) {
        tester.view.physicalSize = Size(width, 900);
        for (final left in [false, true]) {
          for (final right in [false, true]) {
            for (final collapsed in [false, true]) {
              await tester.pumpWidget(
                _app(
                  KonnektedTabletWorkspace(
                    selected: KonnektedTab.listen,
                    route: null,
                    onSelect: (_) {},
                    onNavigate: (_) {},
                    leftOpen: left,
                    rightOpen: right,
                    hasPlayer: true,
                    playerCollapsed: collapsed,
                    onToggleLeft: () {},
                    onToggleRight: () {},
                    mobileDock: const SizedBox.shrink(),
                    playerSidebar: const SizedBox.expand(),
                    player: KonnektedTabletFooter(
                      collapsed: collapsed,
                      onExpand: () {},
                      onOpenPlayer: () {},
                      onOpenPanel: (_) {},
                    ),
                    child: const SizedBox.expand(),
                  ),
                  scale: 2,
                ),
              );
              await tester.pumpAndSettle();
              final footer = tester.getRect(
                find.byKey(const ValueKey('tablet-footer-glass')),
              );
              if (left) {
                expect(
                  footer.left,
                  greaterThanOrEqualTo(
                    tester
                        .getRect(
                          find.byKey(const ValueKey('tablet-navigation-list')),
                        )
                        .right,
                  ),
                );
              }
              if (right) {
                expect(
                  footer.right,
                  lessThanOrEqualTo(
                    tester
                        .getRect(
                          find.byKey(const ValueKey('tablet-player-sidebar')),
                        )
                        .left,
                  ),
                );
              }
              expect(footer.width, greaterThan(0));
              expect(find.byTooltip('Play').hitTestable(), findsOneWidget);
              expect(
                tester.takeException(),
                isNull,
                reason: '$width left=$left right=$right folded=$collapsed',
              );
            }
          }
        }
      }
    },
  );

  testWidgets('footer follows sidebar resizing and safe-area boundaries', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1366, 900)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(left: 24, right: 18, bottom: 34)
      ..viewPadding = const FakeViewPadding(left: 24, right: 18, bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        KonnektedTabletWorkspace(
          selected: KonnektedTab.listen,
          route: null,
          onSelect: (_) {},
          onNavigate: (_) {},
          leftOpen: true,
          rightOpen: true,
          hasPlayer: true,
          onToggleLeft: () {},
          onToggleRight: () {},
          mobileDock: const SizedBox.shrink(),
          playerSidebar: const SizedBox.expand(),
          player: KonnektedTabletFooter(
            onOpenPlayer: () {},
            onOpenPanel: (_) {},
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final footer = find.byKey(const ValueKey('tablet-footer-glass'));
    final before = tester.getRect(footer);
    await tester.drag(
      find.byKey(const ValueKey('resize-player-sidebar')),
      const Offset(-80, 0),
    );
    await tester.pumpAndSettle();
    final after = tester.getRect(footer);
    final right = tester.getRect(
      find.byKey(const ValueKey('tablet-player-sidebar')),
    );
    final left = tester.getRect(
      find.byKey(const ValueKey('tablet-navigation-list')),
    );
    expect(right.width, 420);
    expect(after, isNot(before));
    expect(after.left, greaterThanOrEqualTo(left.right));
    expect(after.right, lessThanOrEqualTo(right.left));
    expect(after.bottom, 866);
    tester.view.physicalSize = const Size(600, 900);
    await tester.pumpAndSettle();
    final small = tester.getRect(footer);
    expect(
      small.right,
      lessThanOrEqualTo(
        tester
            .getRect(find.byKey(const ValueKey('tablet-player-sidebar')))
            .left,
      ),
    );
    expect(
      small.left,
      greaterThanOrEqualTo(
        tester
            .getRect(find.byKey(const ValueKey('tablet-navigation-list')))
            .right,
      ),
    );
    expect(small.size, const Size(60, 56));
    await tester.tap(find.byTooltip('Play'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pause').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'either sidebar retracts and reopens independently without losing its state',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1366, 1024)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var left = true, right = true;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) => KonnektedTabletWorkspace(
              selected: KonnektedTab.listen,
              route: null,
              onSelect: (_) {},
              onNavigate: (_) {},
              leftOpen: left,
              rightOpen: right,
              hasPlayer: true,
              onToggleLeft: () => setState(() => left = !left),
              onToggleRight: () => setState(() => right = !right),
              player: const SizedBox(
                height: 100,
                child: Text('Desktop footer'),
              ),
              playerSidebar: const _LyricsProbe(),
              mobileDock: const SizedBox.shrink(),
              child: const SizedBox.expand(key: ValueKey('page')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final originalWidth = tester
          .getSize(find.byKey(const ValueKey('page')))
          .width;
      await tester.tap(find.text('Lyric selection 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('toggle-left-sidebar')));
      await tester.pumpAndSettle();
      expect(left, isFalse);
      expect(right, isTrue);
      expect(
        tester.getSize(find.byKey(const ValueKey('page'))).width,
        greaterThan(originalWidth),
      );
      await tester.tap(find.byKey(const ValueKey('toggle-right-sidebar')));
      await tester.pumpAndSettle();
      expect(right, isFalse);
      expect(find.text('Lyric selection 1'), findsNothing);
      expect(find.text('Desktop footer'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toggle-right-sidebar')));
      await tester.pumpAndSettle();
      expect(find.text('Lyric selection 1'), findsOneWidget);
      expect(left, isFalse);
      tester.view.physicalSize = const Size(768, 1024);
      await tester.pumpAndSettle();
      expect(find.text('Lyric selection 1'), findsOneWidget);
      await tester.tapAt(
        const Offset(30, 200),
      ); // Narrow-pane scrim dismisses only the player.
      await tester.pumpAndSettle();
      expect(right, isFalse);
      expect(left, isFalse);
      expect(find.text('Desktop footer'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toggle-left-sidebar')));
      await tester.pumpAndSettle();
      expect(left, isTrue);
      expect(right, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'floating glass footer folds on scroll and stays clear of system/navigation',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1366, 1024)
        ..devicePixelRatio = 1
        ..padding = const FakeViewPadding(bottom: 34)
        ..viewPadding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.reset);
      final scroll = DockScrollHysteresis();
      var collapsed = false;
      late StateSetter update;
      EdgeInsets? clearance;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return KonnektedTabletWorkspace(
                selected: KonnektedTab.listen,
                route: null,
                onSelect: (_) {},
                onNavigate: (_) {},
                leftOpen: true,
                rightOpen: false,
                hasPlayer: true,
                playerCollapsed: collapsed,
                onToggleLeft: () {},
                onToggleRight: () {},
                mobileDock: const SizedBox.shrink(),
                playerSidebar: const SizedBox.shrink(),
                player: KonnektedTabletFooter(
                  collapsed: collapsed,
                  onExpand: () => setState(() => collapsed = false),
                  onOpenPlayer: () {},
                  onOpenPanel: (_) {},
                ),
                child: Builder(
                  builder: (context) {
                    clearance = MediaQuery.paddingOf(context);
                    return NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollEndNotification) {
                          scroll.reset();
                        }
                        if (notification is ScrollUpdateNotification &&
                            notification.dragDetails != null) {
                          final next = scroll.push(
                            notification.scrollDelta ?? 0,
                            collapsed: collapsed,
                          );
                          if (next != null) setState(() => collapsed = next);
                        }
                        return false;
                      },
                      child: ListView.builder(
                        key: const ValueKey('browsing-page'),
                        itemExtent: 80,
                        itemCount: 100,
                        itemBuilder: (_, index) => Text('Album $index'),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          animate: true,
        ),
      );
      await tester.pumpAndSettle();
      final glass = find.byKey(const ValueKey('tablet-footer-glass'));
      expect(tester.getSize(glass), const Size(1118, 80));
      expect(tester.getRect(glass).bottom, 990);
      expect(
        tester.getRect(find.byKey(const ValueKey('browsing-page'))).bottom,
        1024,
      );
      expect(clearance!.bottom, 122);
      final optics = tester.widget<LokalGlass>(glass);
      expect(optics.singlePassLens, isTrue);
      expect(optics.backdropBlurSigma, 2);
      expect(optics.pronouncedRim, isTrue);
      final settings = find.text('Settings');
      expect(
        tester.getRect(settings).bottom,
        lessThan(tester.getRect(glass).top),
      );
      await tester.drag(
        find.byKey(const ValueKey('browsing-page')),
        const Offset(0, -160),
      );
      await tester.pumpAndSettle();
      expect(collapsed, isTrue);
      expect(tester.getSize(glass), const Size(760, 56));
      expect(clearance!.bottom, 98);
      expect(find.byTooltip('Expand player'), findsNothing);
      await tester.drag(glass, const Offset(0, 80));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final middle = tester.getSize(glass);
      expect(middle.height, inExclusiveRange(56, 80));
      update(
        () => collapsed = true,
      ); // Reverse while the pill is still expanding.
      await tester.pumpAndSettle();
      expect(tester.getSize(glass), const Size(760, 56));
      expect(find.byTooltip('Expand player'), findsNothing);
      await tester.drag(glass, const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(tester.getSize(glass), const Size(1118, 80));
      await tester.tap(find.byTooltip('Volume'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tablet-volume')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'collapsed tablet transport keeps previous playable on Android and iOS',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        for (final radio in [false, true]) {
          for (final width in [220.0, 360.0, 600.0, 768.0, 1366.0]) {
            await tester.pumpWidget(const SizedBox.shrink());
            tester.view.physicalSize = Size(width, 900);
            final player = _Player();
            await tester.pumpWidget(
              _app(
                Align(
                  alignment: Alignment.bottomCenter,
                  child: KonnektedTabletFooter(
                    collapsed: true,
                    onExpand: () {},
                    onOpenPlayer: () {},
                    onOpenPanel: (_) {},
                  ),
                ),
                player: player,
                radio: radio,
                platform: platform,
              ),
            );
            await tester.pumpAndSettle();
            for (final tooltip in ['Previous', 'Play', 'Next', 'Full screen']) {
              expect(
                find.byTooltip(tooltip).hitTestable(),
                findsOneWidget,
                reason: '$platform width=$width radio=$radio',
              );
            }
            expect(find.byTooltip('Playback options'), findsNothing);
            expect(find.byTooltip('Expand player'), findsNothing);
            if (width >= 440) {
              expect(
                find.byTooltip('Shuffle off').hitTestable(),
                findsOneWidget,
              );
              expect(
                find.byTooltip('Repeat all').hitTestable(),
                findsOneWidget,
              );
            }
            await tester.tap(find.byTooltip('Previous'));
            await tester.pumpAndSettle();
            if (radio) {
              final container = ProviderScope.containerOf(
                tester.element(find.byType(KonnektedTabletFooter)),
              );
              final notifier =
                  container.read(radioPlayerProvider.notifier) as _Radio;
              expect(notifier.actions, ['radio-previous']);
            } else {
              expect(player.actions, ['previous']);
            }
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );

  testWidgets(
    'footer controls dispatch to music and panel views; seek commits once',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1366, 1024)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final player = _Player();
      final panels = <TabletPlayerTab>[];
      var opened = 0;
      await tester.pumpWidget(
        _app(
          Align(
            alignment: Alignment.bottomCenter,
            child: KonnektedTabletFooter(
              onOpenPlayer: () => opened++,
              onOpenPanel: panels.add,
            ),
          ),
          player: player,
        ),
      );
      await tester.pumpAndSettle();
      for (final tooltip in [
        'Play',
        'Next',
        'Previous',
        'Shuffle off',
        'Repeat all',
      ]) {
        await tester.tap(find.byTooltip(tooltip));
        await tester.pumpAndSettle();
      }
      expect(player.actions.take(5), [
        'play',
        'next',
        'previous',
        'shuffle',
        'repeat',
      ]);
      await tester.tap(find.byTooltip('Lyrics'));
      await tester.tap(find.byTooltip('Queue'));
      await tester.tap(find.byTooltip('Now playing'));
      expect(panels, [
        TabletPlayerTab.lyrics,
        TabletPlayerTab.queue,
        TabletPlayerTab.details,
      ]);
      expect(find.byTooltip('Playback options'), findsNothing);
      await tester.tap(find.byTooltip('Full screen'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      final slider = find.byKey(const ValueKey('tablet-seek'));
      final rect = tester.getRect(slider);
      final gesture = await tester.startGesture(
        Offset(rect.left + rect.width * .3, rect.center.dy),
      );
      await gesture.moveTo(Offset(rect.left + rect.width * .7, rect.center.dy));
      await tester.pump();
      expect(player.actions.where((a) => a.startsWith('seek:')), isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(player.actions.where((a) => a.startsWith('seek:')).length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'radio has station queue and no seek; desktop overrides stale radio state',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1366, 1024)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final footer = Align(
        alignment: Alignment.bottomCenter,
        child: KonnektedTabletFooter(onOpenPlayer: () {}, onOpenPanel: (_) {}),
      );
      await tester.pumpWidget(_app(footer, radio: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tablet-seek')), findsNothing);
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('Live station'), findsWidgets);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(KonnektedTabletFooter)),
        listen: false,
      );
      (container.read(lokalRemoteControllerProvider.notifier) as _Remote)
          .enable();
      await tester.pumpAndSettle();
      expect(find.text('LIVE'), findsNothing);
      expect(find.text('Northern Lights'), findsOneWidget);
      expect(find.byKey(const ValueKey('tablet-seek')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
