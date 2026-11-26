import 'package:flick/core/utils/lokal_layout.dart';
import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/features/konnekted/lokal_mixes.dart';
import 'package:flick/models/song.dart';
import 'package:flick/widgets/lokal/lokal_cover_flow.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Song _track(
  String id,
  String album, {
  int addedDay = 1,
  int? trackNumber,
  int? discNumber,
  String artist = 'Artist',
  String albumArtist = 'Artist',
}) => Song(
  id: id,
  title: 'Track $id',
  artist: artist,
  album: album,
  albumArtist: albumArtist,
  trackNumber: trackNumber,
  discNumber: discNumber,
  duration: const Duration(minutes: 3),
  fileType: 'FLAC',
  filePath: '/music/$album/$id.flac',
  dateAdded: DateTime(2026, 1, addedDay),
);

AlbumGroup _album(String name, List<Song> songs) =>
    AlbumGroup(key: name, albumName: name, albumArtist: 'Artist', songs: songs);

Widget _app(Widget child) => MaterialApp(
  theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
  home: LokalContentScope(
    tablet: false,
    child: Scaffold(body: Center(child: child)),
  ),
);

/// The transparent Cover Flow stage is the direct AnimatedBuilder child of
/// its SizedBox, rather than a painted panel inside the Home gradient.
Finder _flowStage() => find.descendant(
  of: find.byType(LokalCoverFlow),
  matching: find.byWidgetPredicate(
    (widget) => widget is SizedBox && widget.child is AnimatedBuilder,
  ),
);

void main() {
  final albums = [
    _album('First', [_track('1a', 'First'), _track('1b', 'First')]),
    _album('Second', [_track('2a', 'Second')]),
    _album('Third', [_track('3a', 'Third')]),
  ];

  testWidgets(
    'Cover Flow leaves the continuous Home gradient visible on every theme',
    (tester) async {
      final flow = LokalCoverFlow(
        albums: albums,
        initialIndex: 1,
        cover: (_) => const ColoredBox(color: Colors.blueGrey),
        onPlay: (_, _) {},
      );
      Element? originalElement;
      for (final themeId in LokalThemeId.values) {
        final tokens = LokalTokens.resolve(themeId);
        // Reproduce the actual shell gradient rather than just its scaffold
        // color: a flat tokens.bg stage covered up this gradient on Home.
        final tint = Color.lerp(tokens.bg, tokens.accent, .13)!;
        await tester.pumpWidget(
          MaterialApp(
            theme: LokalTheme.build(tokens),
            home: Scaffold(
              body: DecoratedBox(
                key: const ValueKey('test-home-gradient'),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [tint, tokens.bg],
                    stops: const [0, .55],
                  ),
                ),
                child: Center(child: flow),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final flowElement = tester.element(find.byType(LokalCoverFlow));
        originalElement ??= flowElement;
        expect(
          identical(flowElement, originalElement),
          isTrue,
          reason: 'Theme changes must not remount Cover Flow',
        );

        // A paint layer here, even one using tokens.bg, creates a visible
        // horizontal stripe when the shell gradient is artwork tinted.
        expect(
          _flowStage(),
          findsOneWidget,
          reason: '${themeId.name} must have no opaque Cover Flow stage',
        );
        final stage = tester.widget<SizedBox>(_flowStage());
        expect(stage.child, isA<AnimatedBuilder>());
        final backdrop = tester.widget<DecoratedBox>(
          find.byKey(const ValueKey('test-home-gradient')),
        );
        final gradient =
            (backdrop.decoration as BoxDecoration).gradient! as LinearGradient;
        expect(gradient.colors, [tint, tokens.bg]);
        expect(Theme.of(flowElement).scaffoldBackgroundColor, tokens.bg);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'iTunes reference triangles match four projected corners on both sides',
    (tester) async {
      final five = [
        ...albums,
        _album('Fourth', [_track('4a', 'Fourth')]),
        _album('Fifth', [_track('5a', 'Fifth')]),
      ];
      await tester.pumpWidget(
        _app(
          LokalCoverFlow(
            albums: five,
            initialIndex: 2,
            cover: (_) => const ColoredBox(color: Colors.blueGrey),
            onPlay: (_, _) {},
          ),
        ),
      );
      Transform panel(String key) => tester.widget<Transform>(
        find
            .descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(Transform),
            )
            .first,
      );
      final left = panel('Second');
      final right = panel('Fourth');
      final selected = panel('Third');
      final size = tester.getSize(find.byWidget(selected.child!)).width;

      // The first Transform in each Positioned cover applies the real
      // Matrix4 perspective. Project the actual local cover corners, including
      // its transform origin and homogeneous perspective division.
      Offset project(Transform panel, double x, double y) {
        final origin = panel.origin!;
        return MatrixUtils.transformPoint(
              panel.transform,
              Offset(x - origin.dx, y - origin.dy),
            ) +
            origin -
            Offset(size / 2, size / 2);
      }

      for (final panel in [left, right, selected]) {
        expect(
          panel.origin!.dx,
          closeTo(size / 2, .0001),
          reason: '3D pivot must be at artwork center',
        );
        expect(panel.origin!.dy, closeTo(size / 2, .0001));
      }
      // Normalized coordinates measured on the iTunes reference. The outer
      // edges are ~92% of artwork height; the inner edges only ~65% and
      // drop toward the lower vanishing point. BOTH triangle slopes matter.
      final loTop = project(left, 0, 0);
      final loBottom = project(left, 0, size);
      final liTop = project(left, size, 0);
      final liBottom = project(left, size, size);
      final riTop = project(right, 0, 0);
      final riBottom = project(right, 0, size);
      final roTop = project(right, size, 0);
      final roBottom = project(right, size, size);
      void near(String label, double actual, double normalized) =>
          expect(actual / size, closeTo(normalized, .007), reason: label);

      near('left outside upper x', loTop.dx, -1.067);
      near('left outside upper y', loTop.dy, -.447);
      near('left outside lower y', loBottom.dy, .473);
      near('left inside upper x', liTop.dx, -.429);
      near('left inside upper y', liTop.dy, -.269);
      near('left inside lower y', liBottom.dy, .381);
      near('right inside upper x', riTop.dx, .429);
      near('right outside upper x', roTop.dx, 1.067);
      near('right outside upper y', roTop.dy, -.447);
      near('right outside lower y', roBottom.dy, .473);
      near('right inside upper y', riTop.dy, -.269);
      near('right inside lower y', riBottom.dy, .381);

      expect(
        liTop.dx,
        greaterThan(-size * .5),
        reason: 'center cover masks left inner edge',
      );
      expect(
        riTop.dx,
        lessThan(size * .5),
        reason: 'center cover masks right inner edge',
      );
      expect(
        loTop.dy,
        lessThan(liTop.dy),
        reason: 'top triangular gap slopes down to center',
      );
      expect(
        loBottom.dy,
        greaterThan(liBottom.dy),
        reason: 'lower triangle slopes up to center',
      );
      expect(roTop.dy, lessThan(riTop.dy));
      expect(roBottom.dy, greaterThan(riBottom.dy));
      expect(
        left.transform.entry(2, 0),
        lessThan(0),
        reason: 'left outer edge projects toward the viewer',
      );
      expect(
        right.transform.entry(2, 0),
        greaterThan(0),
        reason: 'right outer edge projects toward the viewer',
      );
      expect(
        left.transform.entry(3, 2),
        lessThan(0),
        reason: 'rearward depth must SHRINK the covers',
      );
      expect(right.transform.entry(3, 2), lessThan(0));

      final coverStack = tester
          .widgetList<Stack>(
            find.descendant(
              of: find.byType(LokalCoverFlow),
              matching: find.byType(Stack),
            ),
          )
          .firstWhere(
            (stack) => stack.children.whereType<Positioned>().length == 5,
          );
      expect(
        coverStack.children.last.key,
        const ValueKey('Third'),
        reason: 'center album paints above all four adjacent angled covers',
      );
      expect(
        find.byType(ShaderMask),
        findsNothing,
        reason: 'mobile reflection shader must be completely removed',
      );
      expect(
        find.byType(OverflowBox),
        findsNothing,
        reason: 'no mirrored second artwork subtree',
      );
    },
  );

  test('production center/depth translation is C1-smooth across near/far covers', () {
    // Exercise production code; copied formulas could pass after a regression.
    final pos = LokalCoverFlow.centerDistance;
    final depth = LokalCoverFlow.depthDistance;
    const e = .00001;
    expect(pos(0), 0);
    expect(pos(1), closeTo(.91, 1e-9));
    expect(pos(2) - pos(1), closeTo(.18, 1e-9));
    expect((pos(1) - pos(1 - e)) / e, closeTo((pos(1 + e) - pos(1)) / e, .001));
    expect(
      (LokalCoverFlow.projectedCenterDistance(e) -
              LokalCoverFlow.projectedCenterDistance(0)) /
          e,
      closeTo(.70, .001),
      reason: 'the projected rail starts with controlled horizontal velocity',
    );
    expect(depth(0), 0);
    expect(depth(1), closeTo(.60, 1e-9));
    expect(
      (depth(1) - depth(1 - e)) / e,
      closeTo((depth(1 + e) - depth(1)) / e, .001),
    );
  });

  test('screen-space centers form a flat horizontal rail with smooth near/far transitions', () {
    final projected = LokalCoverFlow.projectedCenterDistance;
    final world = LokalCoverFlow.centerDistance;
    final depth = LokalCoverFlow.depthDistance;
    const epsilon = .00001;
    final first = .91 / (1 + .60 / 1.92);
    final step = .18 / (1 + .60 / 1.92);
    expect(projected(0), 0);
    expect(projected(1), closeTo(first, 1e-9));
    expect(projected(2) - projected(1), closeTo(step, 1e-9));
    expect(
      world(1),
      closeTo(.91, 1e-9),
      reason: 'do not disturb the iTunes reference triangles',
    );
    expect(world(2) - world(1), closeTo(.18, 1e-9));
    expect(depth(1), closeTo(.60, 1e-9));

    // Perspective cancellation: the apparent X position must equal the
    // intended horizontal rail, even during the depth/rotation transition.
    for (final d in <double>[.1, .2, .35, .5, .65, .8, .9, 1, 1.5, 2, 4]) {
      expect(world(d) / (1 + depth(d) / 1.92), closeTo(projected(d), 1e-9));
      expect(
        projected(d),
        greaterThan(projected(d - .001)),
        reason: 'a cover never reverses horizontal direction',
      );
    }
    final near = (projected(1) - projected(1 - epsilon)) / epsilon;
    final far = (projected(1 + epsilon) - projected(1)) / epsilon;
    expect(
      near,
      closeTo(far, .001),
      reason: 'no abrupt speed change when entering the angled side stack',
    );
    expect(
      projected(.5),
      lessThan(.44),
      reason: 'reduce the old arc-like horizontal lurch near center',
    );
  });

  testWidgets('fast fling never teleports or reverses a visible side cover', (
    tester,
  ) async {
    final ten = [
      ...albums,
      for (var i = 3; i < 10; i++)
        _album('Glide $i', [_track('g$i', 'Glide $i')]),
    ];
    await tester.pumpWidget(
      _app(
        LokalCoverFlow(
          albums: ten,
          initialIndex: 2,
          cover: (_) => const ColoredBox(color: Colors.blueGrey),
          onPlay: (_, _) {},
        ),
      ),
    );
    final flow = find.byType(LokalCoverFlow);
    final size = math.min(250.0, tester.getSize(flow).width * .60);
    // A hard flick previously passed its unbounded velocity straight into
    // SpringSimulation, allowing a cover to jump several slots per frame.
    await tester.fling(flow, Offset(-size * 3, 0), 14000);
    final target = find.byKey(const ValueKey('Glide 4'));
    double? previous;
    for (var frame = 0; frame < 35; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final panel = tester.widget<Transform>(
        find.descendant(of: target, matching: find.byType(Transform)).first,
      );
      final m = panel.transform;
      final x = m.entry(0, 3) / m.entry(3, 3);
      if (previous != null) {
        expect(
          x,
          lessThanOrEqualTo(previous! + 1.0),
          reason:
              'a right-side cover must only glide left during a leftward fling',
        );
        expect(
          (x - previous!).abs(),
          lessThan(size * .45),
          reason: 'one rendered frame must not skip a visible cover',
        );
      }
      previous = x;
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'second neighbor receives visible strip taps beyond first neighbor quad',
    (tester) async {
      final five = [
        ...albums,
        _album('Fourth', [_track('4a', 'Fourth')]),
        _album('Fifth', [_track('5a', 'Fifth')]),
      ];
      final selected = <int>[];
      await tester.pumpWidget(
        _app(
          LokalCoverFlow(
            albums: five,
            initialIndex: 2,
            cover: (_) => const ColoredBox(color: Colors.blueGrey),
            onPlay: (_, _) {},
            onSelect: selected.add,
          ),
        ),
      );
      final flow = find.byType(LokalCoverFlow);
      final size = math.min(250.0, tester.getSize(flow).width * .60);
      final stage = _flowStage();
      expect(stage, findsOneWidget);
      final topLeft = tester.getTopLeft(stage);
      final stageWidth = tester.getSize(stage).width;

      // At x=1.13 cover widths, the first neighbor's actual painted edge
      // ends around x=1.067, but Flutter's affine hit rectangle extends to
      // x≈1.16. The second neighbor is visibly painted here and must win.
      await tester.tapAt(
        topLeft + Offset(stageWidth / 2 + size * 1.13, size * .56),
      );
      await tester.pump();
      expect(
        selected,
        [4],
        reason: 'tap in visible second-neighbor strip must not be stolen by hidden first-neighbor bounds',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home Cover Flow starts centered for odd and even shelves', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final four = [
      ...albums,
      _album('Fourth', [_track('4a', 'Fourth')]),
    ];

    Widget shelf(List<AlbumGroup> entries) => _app(
      LokalCoverFlow(
        key: ValueKey(entries.length),
        albums: entries,
        initialIndex: entries.length ~/ 2,
        cover: (_) => const ColoredBox(color: Colors.blueGrey),
        onPlay: (_, _) {},
      ),
    );

    await tester.pumpWidget(shelf(albums));
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^Cover Flow'))).value,
      '2 of 3',
    );
    expect(find.text('Second'), findsOneWidget);

    // Async recommendations can increase the shelf length while Home is open.
    await tester.pumpWidget(shelf(four));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^Cover Flow'))).value,
      '3 of 4',
    );
    expect(find.text('Third'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
    'removing cover flow during a drag does not query a dead context',
    (tester) async {
      await tester.pumpWidget(
        _app(
          LokalCoverFlow(
            albums: albums,
            cover: (_) => const ColoredBox(color: Colors.blueGrey),
            onPlay: (_, _) {},
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(LokalCoverFlow)),
      );
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await gesture.cancel();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a swipe spins to the next album and settles on it', (
    tester,
  ) async {
    final seen = <int>[];
    await tester.pumpWidget(
      _app(
        LokalCoverFlow(
          albums: albums,
          cover: (album) => ColoredBox(
            color: Colors.blueGrey,
            child: Text('cover ${album.albumName}'),
          ),
          onPlay: (_, _) {},
          onIndexChanged: seen.add,
        ),
      ),
    );
    expect(find.text('First'), findsOneWidget);
    await tester.drag(find.byType(LokalCoverFlow), const Offset(-90, 0));
    await tester.pumpAndSettle();
    expect(seen.last, 1);
    expect(find.text('Second'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the facing cover flips to its tracks and plays the album', (
    tester,
  ) async {
    Song? played;
    List<Song>? queue;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        LokalCoverFlow(
          albums: albums,
          cover: (_) => const ColoredBox(color: Colors.blueGrey),
          onPlay: (song, album) {
            played = song;
            queue = album;
          },
        ),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^Cover Flow'))).value,
      '1 of 3',
    );
    await tester.tapAt(
      tester.getCenter(find.byType(LokalCoverFlow)) - const Offset(0, 40),
    );
    await tester.pumpAndSettle();
    expect(find.text('Track 1b'), findsOneWidget);
    await tester.tap(find.text('PLAY'));
    expect(played?.id, '1a');
    expect(queue?.map((s) => s.id), ['1a', '1b']);
    semantics.dispose();
  });

  testWidgets('with onSelect, one tap on any cover centres and selects it', (
    tester,
  ) async {
    final selected = <int>[];
    final seen = <int>[];
    await tester.pumpWidget(
      _app(
        LokalCoverFlow(
          albums: albums,
          cover: (_) => const ColoredBox(color: Colors.blueGrey),
          onPlay: (_, _) => fail('the track list should stay closed'),
          onSelect: selected.add,
          onIndexChanged: seen.add,
        ),
      ),
    );
    final centre =
        tester.getCenter(find.byType(LokalCoverFlow)) - const Offset(0, 40);
    // The facing cover: selected at once, no flip.
    await tester.tapAt(centre);
    await tester.pumpAndSettle();
    expect(selected, [0]);
    expect(find.text('PLAY'), findsNothing);
    // A side cover: comes forward and is selected in the same tap.
    await tester.tapAt(centre + const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(selected, [0, 1]);
    expect(seen.last, 1);
    expect(find.text('Second'), findsOneWidget);
    // Long-press on the facing cover still shows its tracks.
    await tester.longPressAt(centre);
    await tester.pumpAndSettle();
    expect(find.text('PLAY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Cover Flow keeps one recommended song per cover, no repeats', () {
    final songs = [_track('a', 'A'), _track('b', 'B'), _track('a', 'A')];
    const mix = LokalMix(
      id: 'm',
      name: 'Daily Mix',
      type: LokalMixType.daily,
      tracks: [],
    );
    final container = ProviderContainer(
      overrides: [
        konnektedLibraryProvider.overrideWithValue(AsyncData(songs)),
        konnektedMadeForYouProvider.overrideWithValue(
          AsyncData([
            for (final song in songs) LokalMadeForYouPick(song: song, mix: mix),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    final covers = container.read(konnektedCoverAlbumsProvider).value!;
    expect(covers.map((a) => a.coverSong!.id), ['a', 'b']);
    expect(covers.map((a) => a.albumName), ['A', 'B']);
    expect(covers.first.songs.map((s) => s.id), ['a']);
  });

  test('Cover Flow shows local album fallback while mixes are loading', () {
    final songs = [
      _track('a1', 'Album A', trackNumber: 1),
      _track('a2', 'Album A', trackNumber: 2),
      _track('b1', 'Album B', trackNumber: 1),
    ];
    final container = ProviderContainer(
      overrides: [
        konnektedLibraryProvider.overrideWithValue(AsyncData(songs)),
        konnektedMadeForYouProvider.overrideWithValue(
          const AsyncLoading(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final covers = container.read(konnektedCoverAlbumsProvider);
    expect(covers.hasValue, isTrue);
    expect(covers.value!.map((album) => album.albumName), [
      'Album A',
      'Album B',
    ]);
    expect(covers.value!.first.songs.map((song) => song.id), ['a1', 'a2']);
  });

  test(
    'Cover Flow back finds complete local album, in disc and track order',
    () {
      final selected = _track('picked', ' Evening Album ', trackNumber: 3);
      final local = [
        selected,
        _track('track-2', 'Evening Album', trackNumber: 2),
        _track('track-1', 'evening album', trackNumber: 1),
        _track('track-4', 'Evening Album', trackNumber: 1, discNumber: 2),
        _track('wrong', 'Another Album', trackNumber: 1),
        _track(
          'other-artist',
          'Evening Album',
          albumArtist: 'Different Artist',
        ),
      ];
      const mix = LokalMix(
        id: 'm',
        name: 'Daily Mix',
        type: LokalMixType.daily,
        tracks: [],
      );
      final covers = konnektedCoversWithLocalAlbums([
        LokalMadeForYouPick(song: selected, mix: mix),
        LokalMadeForYouPick(song: selected, mix: mix),
      ], local);
      expect(covers, hasLength(1), reason: 'one cover per recommended song');
      final card = covers.single;
      expect(card.key, 'song:picked');
      expect(card.coverSong, same(selected));
      expect(card.albumName, 'Evening Album');
      expect(card.songs.map((s) => s.id), [
        'track-1',
        'track-2',
        'picked',
        'track-4',
      ]);
    },
  );

  test('unknown album never expands into unrelated untagged tracks', () {
    const mix = LokalMix(
      id: 'm',
      name: 'Daily Mix',
      type: LokalMixType.daily,
      tracks: [],
    );
    final unknown = Song(
      id: 'untagged',
      title: 'No Album',
      artist: 'Artist',
      duration: const Duration(minutes: 1),
      fileType: 'FLAC',
    );
    final card = konnektedCoversWithLocalAlbums(
      [LokalMadeForYouPick(song: unknown, mix: mix)],
      [
        unknown,
        const Song(
          id: 'other',
          title: 'Other',
          artist: 'Artist',
          duration: Duration(minutes: 1),
          fileType: 'FLAC',
        ),
      ],
    ).single;
    expect(card.albumName, 'No Album');
    expect(card.songs.map((s) => s.id), ['untagged']);
  });
}
