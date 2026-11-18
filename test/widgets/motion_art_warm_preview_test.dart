import 'package:shared_preferences/shared_preferences.dart';
import 'package:flick/features/player/widgets/motion_art_widget.dart';
import 'package:flick/features/spotify/spotify_storage.dart';
import 'package:flick/services/motion_art/animated_artwork_service.dart';
import 'package:flick/services/motion_art/moving_cover_settings.dart';
import 'package:flick/services/motion_art/shared_motion_playback.dart';
import 'package:flick/services/motion_art/motion_art_memory_pressure.dart';
import 'package:flick/features/player/widgets/motion_art_frame_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
// The platform interface is supplied by the production video_player dependency.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _VideoPlatform extends VideoPlayerPlatform {
  @override
  Future<void> init() async {}
  @override
  Widget buildView(int playerId) =>
      const ColoredBox(key: ValueKey('decoded-frame'), color: Colors.red);
}

class _WarmController extends VideoPlayerController {
  _WarmController()
    : super.networkUrl(Uri.parse('https://video.test/clip.mp4'));
  @override
  int get playerId => 7;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(MotionArtMemoryPressure.instance.resetForTesting);
  testWidgets('ticker-disabled pull preview shows the warm Canvas immediately', (
    tester,
  ) async {
    final previousPlatform = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = _VideoPlatform();
    addTearDown(() => VideoPlayerPlatform.instance = previousPlatform);
    final controller = _WarmController();
    controller.value = const VideoPlayerValue(
      duration: Duration(seconds: 8),
      size: Size(200, 200),
      isInitialized: true,
      position: Duration(seconds: 3),
    );
    var created = 0;
    var disposed = 0;
    final activations = <bool>[];
    final pool = SharedMotionPlayback<VideoPlayerController>(
      create: (_) async {
        created++;
        return controller;
      },
      activate: (_, active) async => activations.add(active),
      dispose: (resource) async {
        disposed++;
        await resource.dispose();
      },
    );
    final key =
        'player:42|${movingCoverRevision.value}|${SecureSpotifyTokenStore.sessionRevision.value}|${AnimatedArtworkService.instance.revision.value}';
    final mini = await pool.acquire(key, 'https://video.test/clip.mp4');
    await mini.setActive(true);
    final suppression = ValueNotifier(false);
    final frames = <MotionArtFrame>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.square(
          dimension: 200,
          child: TickerMode(
            enabled: false,
            child: MotionArtView(
              title: 'Song',
              artist: 'Artist',
              sharedPlaybackKey: 'player:42',
              onFrame: frames.add,
              sharedPlaybackOverride: pool,
              offlineOverride: () async => false,
              suppressionOverride: suppression,
              fallback: const Text('static cover'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('decoded-frame')), findsOneWidget);
    expect(created, 1);
    expect(frames.last.controller, same(controller));
    expect(controller.value.position, const Duration(seconds: 3));
    expect(tester.takeException(), isNull);

    // A backgrounded app releases its motion-art view lease instead of
    // retaining an invisible Android video surface. On resume, a still-live
    // mini-player lease can supply its already decoded frame.
    // Drive the view observer while the test binding keeps producing frames;
    // an actually paused binding cannot render the teardown frame we inspect.
    (tester.state(find.byType(MotionArtView)) as WidgetsBindingObserver)
        .didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump();
    expect(find.byType(VideoPlayer), findsNothing);
    expect(find.text('static cover'), findsOneWidget);
    (tester.state(find.byType(MotionArtView)) as WidgetsBindingObserver)
        .didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('decoded-frame')), findsOneWidget);
    expect(created, 1);

    // Memory pressure prioritizes the audio player and releases optional
    // video immediately; a new decoder must not be started on this frame.
    tester.binding.handleMemoryPressure();
    await tester.pump();
    expect(find.byType(VideoPlayer), findsNothing);
    expect(find.text('static cover'), findsOneWidget);
    // The mini-player no longer requests playback. Recovery must reactivate
    // the view's existing warm resource rather than start another decoder.
    await mini.setActive(false);
    expect(activations.last, isFalse);
    suppression.value = true;
    await tester.pump();
    expect(frames.last.controller, isNull);
    expect(find.byType(VideoPlayer), findsNothing);
    expect(find.text('static cover'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    // The pressure guard belongs to the process, not only the original
    // widget: navigating back to a fresh player must not decode video early.
    suppression.value = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.square(
          dimension: 200,
          child: MotionArtView(
            title: 'Song',
            artist: 'Artist',
            sharedPlaybackKey: 'player:42',
            onFrame: frames.add,
            sharedPlaybackOverride: pool,
              offlineOverride: () async => false,
            suppressionOverride: suppression,
            fallback: const Text('static cover'),
          ),
        ),
      ),
    );
    expect(find.byType(VideoPlayer), findsNothing);
    expect(find.text('static cover'), findsOneWidget);
    // Keep the fresh view mounted with its ticker active throughout cooldown.
    // A retained mini-player lease may supply the already decoded resource.
    await tester.pump(const Duration(minutes: 2));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('decoded-frame')), findsOneWidget);
    expect(created, 1);
    expect(activations.last, isTrue);

    // With the only other lease gone, memory pressure must dispose the
    // final decoder immediately rather than wait for a 500 ms handoff.
    await mini.release(immediate: true);
    tester.binding.handleMemoryPressure();
    await tester.pump();
    await tester.pump();
    expect(find.byType(VideoPlayer), findsNothing);
    expect(disposed, 1);
    expect(frames.last.controller, isNull);
    await tester.pumpWidget(const SizedBox());
    suppression.dispose();
    // Process-lifetime recovery is intentionally armed by the pressure event;
    // cancel it before Flutter's pending-timer invariant runs.
    MotionArtMemoryPressure.instance.resetForTesting();
  });

  testWidgets('memory pressure without any mounted view still gates new video', (
    tester,
  ) async {
    final previousPlatform = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = _VideoPlatform();
    addTearDown(() => VideoPlayerPlatform.instance = previousPlatform);

    MotionArtMemoryPressure.instance.start();
    final controller = _WarmController();
    controller.value = const VideoPlayerValue(
      duration: Duration(seconds: 8),
      size: Size(200, 200),
      isInitialized: true,
    );
    var created = 0;
    final activations = <bool>[];
    final pool = SharedMotionPlayback<VideoPlayerController>(
      create: (_) async {
        created++;
        return controller;
      },
      activate: (_, active) async => activations.add(active),
      dispose: (resource) async => resource.dispose(),
    );
    final key =
        'player:unmounted|${movingCoverRevision.value}|${SecureSpotifyTokenStore.sessionRevision.value}|${AnimatedArtworkService.instance.revision.value}';
    final warm = await pool.acquire(key, 'https://video.test/clip.mp4');
    final suppression = ValueNotifier(false);

    // The process observer must record this even before a MotionArtView exists.
    tester.binding.handleMemoryPressure();
    expect(MotionArtMemoryPressure.instance.isSuspended, isTrue);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.square(
          dimension: 200,
          child: MotionArtView(
            title: 'Song',
            artist: 'Artist',
            sharedPlaybackKey: 'player:unmounted',
            sharedPlaybackOverride: pool,
              offlineOverride: () async => false,
            suppressionOverride: suppression,
            fallback: const Text('static cover'),
          ),
        ),
      ),
    );
    expect(find.byType(VideoPlayer), findsNothing);
    expect(find.text('static cover'), findsOneWidget);
    expect(created, 1);

    await tester.pump(const Duration(minutes: 1, seconds: 59));
    expect(find.byType(VideoPlayer), findsNothing);
    expect(activations, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(MotionArtMemoryPressure.instance.isSuspended, isFalse);
    await tester.pump();
    expect(find.byKey(const ValueKey('decoded-frame')), findsOneWidget);
    expect(created, 1);
    expect(activations.last, isTrue);

    await tester.pumpWidget(const SizedBox());
    await warm.release(immediate: true);
    suppression.dispose();
  });
}
