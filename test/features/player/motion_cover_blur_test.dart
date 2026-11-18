import 'dart:ui' as ui;

import 'package:flick/features/player/widgets/motion_art_frame_source.dart';
import 'package:flick/features/player/widgets/motion_cover_blur.dart';
import 'package:flick/features/player/widgets/motion_art_widget.dart';
import 'package:flick/services/motion_art/shared_motion_playback.dart';
import 'package:flick/services/motion_art/moving_cover_settings.dart';
import 'package:flick/services/motion_art/animated_artwork_service.dart';
import 'package:flick/features/spotify/spotify_storage.dart';
import 'package:flick/features/player/widgets/player_song_blur_background.dart';
import 'package:flick/models/song.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _FramePlatform extends VideoPlayerPlatform {
  final color = ValueNotifier<Color>(Colors.red);
  @override
  Future<void> init() async {}
  @override
  Widget buildView(int playerId) => ValueListenableBuilder<Color>(
    valueListenable: color,
    builder: (_, color, __) => ColoredBox(color: color),
  );
}

class _WarmController extends VideoPlayerController {
  _WarmController()
    : super.networkUrl(Uri.parse('https://video.test/cover.mp4')) {
    value = const VideoPlayerValue(
      duration: Duration(seconds: 8),
      size: Size(200, 200),
      isInitialized: true,
      position: Duration(seconds: 3),
    );
  }
  @override
  int get playerId => 7;
}

const song = Song(
  id: 'track',
  title: 'Track',
  artist: 'Fixture',
  duration: Duration(minutes: 3),
  fileType: 'FLAC',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'foreground publishes its warm frame during build and suppression releases the blur',
    (tester) async {
      final previous = VideoPlayerPlatform.instance;
      final platform = _FramePlatform();
      VideoPlayerPlatform.instance = platform;
      addTearDown(() {
        VideoPlayerPlatform.instance = previous;
        platform.color.dispose();
      });
      final controller = _WarmController(), source = MotionArtFrameSource();
      var created = 0, disposed = 0;
      final pool = SharedMotionPlayback<VideoPlayerController>(
        create: (_) async {
          created++;
          return controller;
        },
        activate: (_, __) async {},
        dispose: (_) async => disposed++,
      );
      final key =
          'player:track|${movingCoverRevision.value}|${SecureSpotifyTokenStore.sessionRevision.value}|${AnimatedArtworkService.instance.revision.value}';
      final mini = await pool.acquire(key, 'https://video.test/cover.mp4');
      final suppression = ValueNotifier(false);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox.square(
                dimension: 200,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PlayerSongBlurBackground(
                      song: song,
                      colors: const [Colors.green, Colors.black],
                      fullCover: true,
                      motionFrames: source,
                    ),
                    Center(
                      child: SizedBox.square(
                        dimension: 80,
                        child: MotionArtView(
                          title: song.title,
                          artist: song.artist,
                          sharedPlaybackKey: 'player:track',
                          sharedPlaybackOverride: pool,
              offlineOverride: () async => false,
                          suppressionOverride: suppression,
                          onFrame: (frame) =>
                              source.update('player:track', frame),
                          fallback: const ColoredBox(color: Colors.green),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(source.forKey('player:track'), same(controller));
      expect(find.byType(VideoPlayer), findsNWidgets(2));
      expect(created, 1);
      expect(
        tester.takeException(),
        isNull,
        reason: 'reporting a warm frame during build must be safe',
      );
      suppression.value = true;
      await tester.pump();
      await tester.pump();
      expect(source.forKey('player:track'), isNull);
      expect(find.byType(VideoPlayer), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await mini.release(immediate: true);
      expect(
        disposed,
        1,
        reason: 'the backdrop must not hold another decoder lease',
      );
      source.dispose();
      suppression.dispose();
    },
  );
  test(
    'outgoing frame owners cannot clear a replacement or another song',
    () async {
      final frames = MotionArtFrameSource();
      final first = _WarmController(), second = _WarmController();
      final oldOwner = Object(), nextOwner = Object();
      frames.update(
        'player:track',
        MotionArtFrame(owner: oldOwner, controller: first),
      );
      frames.update(
        'player:track',
        MotionArtFrame(owner: nextOwner, controller: second),
      );
      frames.update(
        'player:track',
        MotionArtFrame(owner: oldOwner, controller: null),
      );
      expect(frames.forKey('player:track'), same(second));
      expect(frames.forKey('player:another-track'), isNull);
      frames.update(
        'player:track',
        MotionArtFrame(owner: nextOwner, controller: null),
      );
      expect(frames.forKey('player:track'), isNull);
      frames.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final fullCover in [false, true]) {
      testWidgets(
        '$platform ${fullCover ? "full cover" : "card"} blur follows the live cover frame',
        (tester) async {
          final previous = VideoPlayerPlatform.instance;
          final videoPlatform = _FramePlatform();
          VideoPlayerPlatform.instance = videoPlatform;
          addTearDown(() {
            VideoPlayerPlatform.instance = previous;
            videoPlatform.color.dispose();
          });
          final controller = _WarmController();
          final source = MotionArtFrameSource();
          final owner = Object(), boundary = GlobalKey();
          source.update(
            'player:track',
            MotionArtFrame(owner: owner, controller: controller),
          );
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: ThemeData(platform: platform),
                home: Scaffold(
                  body: Center(
                    child: RepaintBoundary(
                      key: boundary,
                      child: SizedBox.square(
                        dimension: 200,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            PlayerSongBlurBackground(
                              song: song,
                              colors: const [Colors.green, Colors.black],
                              fullCover: fullCover,
                              motionFrames: source,
                            ),
                            Center(
                              child: SizedBox.square(
                                dimension: 40,
                                child: VideoPlayer(controller),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          expect(find.byType(MotionCoverBlur), findsOneWidget);
          final views = tester.widgetList<VideoPlayer>(
            find.byType(VideoPlayer),
          );
          expect(views, hasLength(2));
          expect(
            views.every((view) => identical(view.controller, controller)),
            true,
            reason: 'cover and blur must use one decoder/clock',
          );
          Future<List<int>> pixel([int y = 30]) async =>
              (await tester.runAsync(() async {
                final image =
                    await (boundary.currentContext!.findRenderObject()
                            as RenderRepaintBoundary)
                        .toImage();
                final bytes = (await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!;
                final offset = (y * image.width + 30) * 4;
                final result = List.generate(
                  3,
                  (channel) => bytes.getUint8(offset + channel),
                );
                image.dispose();
                return result;
              }))!;
          final red = await pixel();
          expect(red[0], greaterThan(red[2] + 80));
          videoPlatform.color.value = Colors.blue;
          await tester.pump();
          final blue = await pixel();
          expect(
            blue[2],
            greaterThan(blue[0] + 80),
            reason: 'changing video frames must recolor the actual blurred backdrop',
          );
          expect(
            controller.value.position,
            const Duration(seconds: 3),
            reason: 'painting a backdrop must not seek or restart the cover',
          );
          videoPlatform.color.value = Colors.white;
          await tester.pump();
          expect(
            (await pixel()).every((channel) => channel < 125),
            true,
            reason: 'bright clips must retain header contrast',
          );
          expect(
            (await pixel(170)).every((channel) => channel < 125),
            true,
            reason: 'bright clips must retain transport/lyrics contrast',
          );
          source.update(
            'player:track',
            MotionArtFrame(owner: owner, controller: null),
          );
          await tester.pump();
          await tester.pump();
          expect(find.byType(MotionCoverBlur), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          source.dispose();
        },
      );
    }
  }
}
