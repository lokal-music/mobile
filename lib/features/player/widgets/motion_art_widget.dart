import 'package:flick/core/theme/lokal_performance_scope.dart';

import 'dart:async';
import 'dart:io';

import 'package:flick/core/utils/app_log.dart';
import 'package:flick/core/utils/dev_log.dart';
import 'package:flick/services/motion_art/animated_artwork_service.dart';
import 'package:flick/services/motion_art/moving_cover_service.dart';
import 'package:flick/services/motion_art/motion_art_offline_cache.dart';
import 'package:flick/services/motion_art/moving_cover_settings.dart';
import 'package:flick/features/spotify/spotify_storage.dart';
import 'package:flick/services/player_service.dart';
import 'package:flick/services/ios_now_playing_session.dart';
import 'package:flick/services/playback_source_priority.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flick/services/motion_art/shared_motion_playback.dart';
import 'package:flick/services/motion_art/motion_art_memory_pressure.dart';

import 'motion_art_frame_source.dart';

/// Renders Apple Music Motion Art for an album while falling back to [fallback]
/// (typically the Ken Burns [AnimatedAlbumArt] or a static artwork widget).
///
/// Controllers are always created with [VideoPlayerOptions.mixWithOthers] so
/// ExoPlayer never requests audio focus and playback of the actual music via
/// just_audio is not interrupted.
///
/// Suppressed while [PlayerService.motionArtSuppressedNotifier] is set
/// (direct/exclusive bit-perfect output): a second output stream can preempt
/// the native stream on some DAPs. [fallback] renders instead.
class MotionArtView extends StatefulWidget {
  const MotionArtView({
    super.key,
    required this.title,
    required this.artist,
    required this.fallback,
    this.album,
    this.duration,
    this.offlineArtistAlias,
    this.enabled = true,
    this.playbackActive = true,
    this.albumMode = false,
    this.representativeSongTitle,
    this.preferVertical = false,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.suppressionOverride,
    this.offlineOverride,
    this.serviceOverride,
    this.loadingFallback,
    this.sharedPlaybackKey,
    this.sharedPlaybackOverride,
    this.presentationBuilder,
    this.onFrame,
  });

  /// Song title, or the album name when [albumMode] is true.
  final String title;
  final String artist;
  final String? album;
  final Duration? duration;

  /// Alternate metadata identity for the same song (track vs album artist).
  /// Only used for offline indexing; online provider matching is unchanged.
  final String? offlineArtistAlias;

  /// Always rendered when no video is available or [enabled] is false.
  final Widget fallback;

  /// Rendered while the first lookup is still in flight, so a static cover can
  /// wait for the motion art without visibly swapping widgets. Settles to
  /// [fallback] once the lookup concludes there is no motion art.
  final Widget? loadingFallback;

  final bool enabled;

  /// Pause the decoder while preserving its last frame in a compact header.
  final bool playbackActive;

  /// Resolve by album (edition-aware) rather than by song.
  final bool albumMode;
  final String? representativeSongTitle;

  /// Prefer the portrait motion-art variant (full-bleed backgrounds).
  final bool preferVertical;

  /// Optional source-aware frame for full-bleed player artwork. The decoded
  /// controller retains source identity across mini/full-player handoffs.
  final Widget Function(BuildContext, Widget, bool isSpotifyCanvas)?
  presentationBuilder;

  final BoxFit fit;

  /// Borrow the displayed frame for effects such as the player backdrop.
  /// The view keeps sole ownership of playback, suppression and disposal.
  final ValueChanged<MotionArtFrame>? onFrame;
  final BorderRadius? borderRadius;

  /// Test hook: replaces [PlayerService.motionArtSuppressedNotifier].
  @visibleForTesting
  final ValueListenable<bool>? suppressionOverride;

  /// Test hook: model an explicitly online/offline native device when
  /// the Flutter test runner has no platform connectivity channel.
  @visibleForTesting
  final Future<bool> Function()? offlineOverride;

  /// Test hook: replaces the shared [AnimatedArtworkService] instance.
  @visibleForTesting
  final AnimatedArtworkService? serviceOverride;
  final String? sharedPlaybackKey;
  final SharedMotionPlayback<VideoPlayerController>? sharedPlaybackOverride;

  @override
  State<MotionArtView> createState() => _MotionArtViewState();
}

class _MotionArtViewState extends State<MotionArtView>
    with WidgetsBindingObserver {
  static const Duration _debounce = Duration(milliseconds: 120);
  static const Duration _retryDelay = Duration(seconds: 35);
  static const int _maxAttempts = 4;

  static final Set<VideoPlayerController> _liveControllers = {};
  static final _spotifyCanvas = Expando<bool>();
  static final _cachedSource = Expando<String>();

  static final _shared = SharedMotionPlayback<VideoPlayerController>(
    create: (url) async {
      final uri = Uri.parse(url);
      final options = VideoPlayerOptions(mixWithOthers: true);
      final controller = uri.scheme == 'file'
          ? VideoPlayerController.file(
              File.fromUri(uri),
              videoPlayerOptions: options,
            )
          : VideoPlayerController.networkUrl(
              uri,
              formatHint: uri.path.toLowerCase().endsWith('.m3u8')
                  ? VideoFormat.hls
                  : null,
              videoPlayerOptions: options,
            );
      try {
        await controller.initialize().timeout(const Duration(seconds: 15));
        await controller.setLooping(true);
        await controller.setVolume(0);
        return controller;
      } catch (_) {
        try {
          await controller.dispose().timeout(const Duration(seconds: 4));
        } catch (_) {}
        rethrow;
      } finally {
        await restoreIosNowPlayingAfterSilentVideo();
      }
    },
    activate: (controller, active) =>
        active ? controller.play() : controller.pause(),
    dispose: (controller) =>
        controller.dispose().timeout(const Duration(seconds: 4)),
  );
  SharedMotionPlayback<VideoPlayerController> get _playbackPool =>
      widget.sharedPlaybackOverride ?? _shared;
  MotionPlaybackLease<VideoPlayerController>? _sharedLease;
  VideoPlayerController? _controller;
  final _frameOwner = Object();
  VideoPlayerController? _reportedController;
  ValueChanged<MotionArtFrame>? _reportedCallback;

  void _reportFrame(VideoPlayerController? controller) {
    if (_performance ||
        _suppressed ||
        _suspendedForMemoryPressure ||
        !widget.enabled) {
      controller = null;
    }
    final callback = widget.onFrame;
    if (_reportedCallback != callback) {
      _reportedCallback?.call(
        MotionArtFrame(owner: _frameOwner, controller: null),
      );
      _reportedCallback = callback;
      _reportedController = null;
    } else if (identical(_reportedController, controller)) {
      return;
    }
    _reportedController = controller;
    callback?.call(MotionArtFrame(owner: _frameOwner, controller: controller));
  }

  bool _hasVideo = false;
  bool _dependenciesReady = false;
  bool _reduceMotion = false;
  bool _performance = false;
  bool _reusedClip = false;
  bool _settledWithoutMotion = false;
  bool _suppressed = false;
  bool _routeIsCurrent = true;
  bool _tickerEnabled = true;
  bool _loading = false;
  bool _ecoReady = false;
  bool _ecoActive = false;
  bool _offlineActive = false;
  int _ecoCheckVersion = 0;
  bool get _suspendedForMemoryPressure =>
      MotionArtMemoryPressure.instance.isSuspended;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  bool get _canPlay =>
      _ecoReady &&
      widget.enabled &&
      widget.playbackActive &&
      !_suppressed &&
      !_suspendedForMemoryPressure &&
      _routeIsCurrent &&
      _tickerEnabled &&
      _lifecycle == AppLifecycleState.resumed;
  bool _listeningToSuppression = false;
  Timer? _timer;
  Timer? _retryTimer;
  int _generation = 0;
  int _attempt = 0;

  static String _rssLabel() {
    try {
      final mb = ProcessInfo.currentRss ~/ (1024 * 1024);
      return 'rss=${mb}MB';
    } catch (_) {
      return 'rss=?';
    }
  }

  static void _logLifecycle(String message) {
    AppLog.instance.add('[MotionArt] $message', source: LogSource.dart);
  }

  ValueListenable<bool> get _suppression =>
      widget.suppressionOverride ?? PlayerService().motionArtSuppressedNotifier;

  @override
  void initState() {
    super.initState();
    // The process observer is already registered at bootstrap; starting here
    // also keeps isolated widget tests consistent.
    MotionArtMemoryPressure.instance.start();
    WidgetsBinding.instance.addObserver(this);
    MotionArtMemoryPressure.instance.suspended.addListener(
      _onMemoryPressureChanged,
    );
    EcoDataMode.observeConnectionChanges();
    EcoDataMode.revision.addListener(_onEcoRevisionChanged);
    unawaited(_checkEco());
    movingCoverRevision.addListener(_onRevisionChanged);
    SecureSpotifyTokenStore.sessionRevision.addListener(_onRevisionChanged);
    if (widget.enabled) {
      _listenToSuppression();
    }
    AnimatedArtworkService.instance.revision.addListener(_onRevisionChanged);
    _restart();
  }

  /// Recheck both when Eco is toggled and when Wi-Fi/cellular changes.
  /// Tear down the existing video before any asynchronous connectivity check
  /// so a previously streamed clip cannot keep using cellular bandwidth.
  void _onEcoRevisionChanged() {
    if (!mounted) return;
    _ecoReady = false;
    _teardown(immediate: true);
    setState(() {});
    unawaited(_checkEco());
  }

  Future<void> _checkEco() async {
    final version = ++_ecoCheckVersion;
    // Query transport concurrently with Eco preferences so a warm decoder
    // can be leased without waiting an extra frame for a second platform call.
    final offlineRequest =
        (widget.offlineOverride ?? EcoDataMode.isOffline)();
    bool active;
    try {
      active = await EcoDataMode.activeOnCellular();
    } catch (error) {
      devLog('[MotionArt] Eco policy unavailable: $error');
      active = false;
    }
    // A disconnected device must not borrow an online decoder or try a
    // provider URL from an earlier successful lookup.
    bool offline;
    try {
      offline = await offlineRequest;
    } catch (error) {
      devLog('[MotionArt] connectivity policy unavailable: $error');
      offline = false;
    }
    if (!mounted || version != _ecoCheckVersion) return;
    _ecoActive = active;
    _offlineActive = offline;
    _ecoReady = true;
    _restart();
    setState(() {});
  }

  void _onRevisionChanged() {
    if (!mounted) return;
    _restart();
    setState(() {});
  }

  void _listenToSuppression() {
    if (_listeningToSuppression) return;
    _listeningToSuppression = true;
    _suppressed = _suppression.value;
    _suppression.addListener(_onSuppressionChanged);
  }

  void _stopListeningToSuppression() {
    if (!_listeningToSuppression) return;
    _listeningToSuppression = false;
    _suppression.removeListener(_onSuppressionChanged);
    _suppressed = false;
  }

  void _onSuppressionChanged() {
    final suppressed = _suppression.value;
    if (suppressed == _suppressed) return;
    _suppressed = suppressed;
    _restart();
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    // Pausing a video is not enough when Android backgrounds Lokal: ExoPlayer
    // still owns its decoder and buffers while the music service keeps
    // playing. Release that memory and recreate the visual on resume.
    // "inactive" is transient (notification shade, permission dialogs), so
    // only tear down once the app is actually hidden or backgrounded.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_controller != null ||
          _loading ||
          _timer != null ||
          _retryTimer != null) {
        _teardown();
        if (mounted) setState(() {});
      }
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _onEcoRevisionChanged();
    } else {
      _syncPlayback();
    }
  }

  void _onMemoryPressureChanged() {
    if (!mounted) return;
    if (_suspendedForMemoryPressure) {
      // Optional video decoding must release its buffers before music.
      // Drop the shared lease immediately: the 500 ms handoff is only for
      // normal mini/full-player transitions, not memory pressure.
      _teardown(immediate: true);
    } else {
      _beginLoad();
    }
    setState(() {});
  }

  void _syncPlayback() {
    final controller = _controller;
    if (controller != null) {
      final action =
          _sharedLease?.setActive(_canPlay) ??
          (_canPlay ? controller.play() : controller.pause());
      unawaited(
        action.catchError(
          (Object error) => _logFailureOnce('video state', error),
        ),
      );
    } else if (!_settledWithoutMotion) {
      _beginLoad();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dependenciesReady = true;
    final performance = LokalPerformanceScope.of(context);
    final budgetChanged = _performance != performance;
    _performance = performance;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _tickerEnabled = TickerMode.of(context) && !_reduceMotion && !_performance;
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (isCurrent != _routeIsCurrent || budgetChanged) {
      _routeIsCurrent = isCurrent;
      _restart();
    } else {
      _syncPlayback();
    }
  }

  @override
  void didUpdateWidget(covariant MotionArtView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      if (widget.enabled) {
        _listenToSuppression();
      } else {
        _stopListeningToSuppression();
      }
    }
    final changed =
        oldWidget.title != widget.title ||
        oldWidget.artist != widget.artist ||
        oldWidget.album != widget.album ||
        oldWidget.offlineArtistAlias != widget.offlineArtistAlias ||
        oldWidget.albumMode != widget.albumMode ||
        oldWidget.representativeSongTitle != widget.representativeSongTitle ||
        oldWidget.preferVertical != widget.preferVertical ||
        oldWidget.sharedPlaybackKey != widget.sharedPlaybackKey ||
        oldWidget.enabled != widget.enabled;
    if (changed)
      _restart();
    else if (oldWidget.playbackActive != widget.playbackActive)
      _syncPlayback();
    if (oldWidget.onFrame != widget.onFrame) {
      _reportFrame(_hasVideo ? _controller : null);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MotionArtMemoryPressure.instance.suspended.removeListener(
      _onMemoryPressureChanged,
    );
    EcoDataMode.revision.removeListener(_onEcoRevisionChanged);
    movingCoverRevision.removeListener(_onRevisionChanged);
    SecureSpotifyTokenStore.sessionRevision.removeListener(_onRevisionChanged);
    AnimatedArtworkService.instance.revision.removeListener(_onRevisionChanged);
    _stopListeningToSuppression();
    _teardown();
    super.dispose();
  }

  void _teardown({bool immediate = false}) {
    _reportFrame(null);
    _generation++;
    _loading = false;
    _timer?.cancel();
    _timer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _hasVideo = false;
    _reusedClip = false;
    _settledWithoutMotion = false;
    final controller = _controller;
    final lease = _sharedLease;
    _controller = null;
    _sharedLease = null;
    unawaited(_disposeVideo(controller, lease: lease, immediate: immediate));
  }

  Future<void> _disposeVideo(
    VideoPlayerController? controller, {
    MotionPlaybackLease<VideoPlayerController>? lease,
    bool immediate = false,
  }) async {
    if (controller == null) return;
    final cachedSource = _cachedSource[controller];
    if (lease != null) {
      try {
        await lease.release(
          immediate:
              immediate ||
              _suspendedForMemoryPressure ||
              _suppressed ||
              _performance ||
              !widget.enabled ||
              _lifecycle != AppLifecycleState.resumed,
        );
      } finally {
        if (cachedSource != null) {
          MotionArtOfflineCache.instance.release(cachedSource);
        }
      }
      return;
    }
    if (_liveControllers.remove(controller)) {
      _logLifecycle('stopped active=${_liveControllers.length}');
    }
    try {
      await controller.dispose().timeout(const Duration(seconds: 4));
    } catch (_) {
      /* The platform may already have released the decoder. */
    } finally {
      if (cachedSource != null) {
        MotionArtOfflineCache.instance.release(cachedSource);
      }
    }
  }

  void _restart() {
    _teardown();
    _attempt = 0;
    _beginLoad();
  }

  String? get _sharedKey => widget.sharedPlaybackKey == null
      ? null
      : '${widget.sharedPlaybackKey}|${movingCoverRevision.value}|${SecureSpotifyTokenStore.sessionRevision.value}|${AnimatedArtworkService.instance.revision.value}';

  void _beginLoad() {
    if (!_dependenciesReady || !_ecoReady) return;
    final key = _sharedKey;
    if (key != null &&
        _controller == null &&
        !_loading &&
        widget.enabled &&
        !_suppressed &&
        !_suspendedForMemoryPressure &&
        !_reduceMotion &&
        _routeIsCurrent &&
        _lifecycle == AppLifecycleState.resumed) {
      // A previous *network* decoder must never be reused when Eco becomes
      // active. Reuse an already-decoded local file where possible.
      final lease = _playbackPool.acquireExisting(
        key,
        allow: (controller) =>
            (!_ecoActive && !_offlineActive) ||
            _cachedSource[controller] != null,
      );
      if (lease != null) {
        _timer?.cancel();
        _timer = null;
        _sharedLease = lease;
        _controller = lease.resource;
        final cachedSource = _cachedSource[lease.resource];
        if (cachedSource != null) {
          MotionArtOfflineCache.instance.retain(cachedSource);
        }
        _hasVideo = true;
        _reusedClip = true;
        _reportFrame(_controller);
        unawaited(
          lease
              .setActive(_canPlay)
              .catchError(
                (Object error) => _logFailureOnce('video handoff', error),
              ),
        );
        if (mounted) setState(() {});
        return;
      }
    }
    if (!_canPlay ||
        _loading ||
        _timer?.isActive == true ||
        _retryTimer?.isActive == true)
      return;
    final generation = _generation;
    _timer = Timer(_debounce, () {
      _timer = null;
      _loadOnce(generation);
    });
  }

  void _scheduleRetry() {
    if (!widget.enabled || _suppressed || !_routeIsCurrent) return;
    if (_attempt >= _maxAttempts) {
      _logLifecycle('gave up after $_attempt attempt(s)');
      _settle();
      return;
    }
    _attempt++;
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, () {
      if (!mounted) return;
      _beginLoad();
    });
  }

  /// Marks the lookup as concluded with no motion art, so the regular
  /// [MotionArtView.fallback] replaces [MotionArtView.loadingFallback].
  void _settle() {
    if (_settledWithoutMotion) return;
    _settledWithoutMotion = true;
    if (mounted) setState(() {});
  }

  void _logFailureOnce(String stage, Object error) {
    if (_attempt == 0) {
      _logLifecycle('$stage failed: $error');
    }
  }

  Future<void> _loadOnce(int generation) async {
    if (!_canPlay || _loading || generation != _generation) return;
    _loading = true;
    try {
      await _loadClip(generation);
    } finally {
      if (generation == _generation) _loading = false;
    }
  }

  Future<void> _loadClip(int generation) async {
    MotionArtLookup? lookup;
    try {
      final service = widget.serviceOverride ?? AnimatedArtworkService.instance;
      if (widget.serviceOverride == null) {
        lookup = await MovingCoverService.instance.lookup(
          title: widget.albumMode
              ? widget.representativeSongTitle ?? widget.title
              : widget.title,
          artist: widget.artist,
          album: widget.albumMode ? widget.album ?? widget.title : widget.album,
          duration: widget.duration,
          alternateArtist: widget.offlineArtistAlias,
        );
      } else if (widget.albumMode) {
        lookup = await service.lookupAnimatedArtworkForAlbum(
          albumName: widget.album ?? widget.title,
          artist: widget.artist,
          representativeSongTitle: widget.representativeSongTitle,
        );
      } else {
        lookup = await service.lookupAnimatedArtwork(
          songTitle: widget.title,
          artist: widget.artist,
          albumName: widget.album,
          duration: widget.duration,
        );
      }
    } catch (error) {
      _logFailureOnce('lookup', error);
      devLog('[MotionArt] lookup failed: $error');
    }

    if (!mounted || generation != _generation || !_canPlay) return;
    final artwork = lookup?.artwork;
    final playable = artwork == null
        ? null
        : await MotionArtOfflineCache.instance.playable(
            artwork,
            preferVertical: widget.preferVertical,
          );
    if (!mounted || generation != _generation || !_canPlay) return;
    final url = playable?.url;
    if ((_ecoActive || _offlineActive) && playable?.cachedSource == null) {
      // Never hand a stale streaming URL to AVPlayer/ExoPlayer in airplane
      // mode or cellular Eco; only complete local media is allowed.
      _settle();
      return;
    }
    if (url == null) {
      if (lookup?.transient ?? true) {
        // Network hiccup, 429/503, timeout: a later attempt may still find
        // motion art, so keep showing the loading fallback and retry.
        _scheduleRetry();
      } else {
        // Definitive "no motion art": settle immediately instead of keeping a
        // static cover in the loading state through pointless retries.
        _settle();
      }
      return;
    }

    // Download independently of native video initialization. Previously the
    // cache only began *after* the decoder started, leaving no saved clip if
    // initialization failed or the player route was replaced early.
    // Lookups used by the footer do not warm media: only the active video
    // surface may cause a bounded background download.
    if (playable?.cachedSource == null &&
        widget.serviceOverride == null &&
        artwork != null &&
        !_ecoActive &&
        !_offlineActive) {
      unawaited(
        MovingCoverService.instance.cachePlayedClip(
          title: widget.albumMode
              ? widget.representativeSongTitle ?? widget.title
              : widget.title,
          artist: widget.artist,
          album: widget.albumMode ? widget.album ?? widget.title : widget.album,
          artwork: artwork,
          preferVertical: widget.preferVertical,
          alternateArtist: widget.offlineArtistAlias,
        ),
      );
    }

    VideoPlayerController? controller;
    MotionPlaybackLease<VideoPlayerController>? lease;
    try {
      final sharedKey = _sharedKey;
      if (sharedKey != null) {
        lease = await _playbackPool.acquire(sharedKey, url);
        controller = lease.resource;
      } else {
        final uri = Uri.parse(url);
        final options = VideoPlayerOptions(mixWithOthers: true);
        controller = uri.scheme == 'file'
            ? VideoPlayerController.file(
                File.fromUri(uri),
                videoPlayerOptions: options,
              )
            : VideoPlayerController.networkUrl(
                uri,
                // Explicit format hint for remote Apple HLS manifests.
                formatHint: uri.path.toLowerCase().endsWith('.m3u8')
                    ? VideoFormat.hls
                    : null,
                videoPlayerOptions: options,
              );
        await controller.initialize().timeout(const Duration(seconds: 15));
        await controller.setLooping(true);
        await controller.setVolume(0);
      }
      if (!mounted || generation != _generation) {
        await _disposeVideo(controller, lease: lease);
        return;
      }
      if (lease != null) {
        await lease.setActive(_canPlay);
      } else if (_canPlay) {
        await controller.play();
      }
    } catch (error) {
      _logFailureOnce('video init', error);
      devLog('[MotionArt] video init failed: $error');
      await _disposeVideo(controller, lease: lease);
      if (playable?.cachedSource case final String source) {
        // Corrupted or unsupported local HLS should never trap the player in
        // repeated attempts against the same file. Retry the original URL.
        if (_ecoActive || _offlineActive) {
          // Keep the completed clip: a transient native decoder failure
          // during airplane mode must not erase the only offline copy.
          _settle();
        } else {
          await MotionArtOfflineCache.instance.discard(source);
          _retryTimer?.cancel();
          _retryTimer = Timer(const Duration(milliseconds: 400), () {
            if (mounted) _beginLoad();
          });
        }
      } else {
        _scheduleRetry();
      }
      return;
    } finally {
      await restoreIosNowPlayingAfterSilentVideo();
    }

    if (!mounted || generation != _generation) {
      await _disposeVideo(controller, lease: lease);
      return;
    }

    if (playable?.cachedSource case final String source) {
      _cachedSource[controller] = source;
      MotionArtOfflineCache.instance.retain(source);
    }
    _spotifyCanvas[controller] = artwork!.albumId.startsWith('spotify:');
    final previous = _controller;
    final previousLease = _sharedLease;
    if (lease == null) _liveControllers.add(controller);
    _logLifecycle(
      'started ${lease == null ? 'active=${_liveControllers.length}' : 'shared player clip'} ${_rssLabel()} '
      '${widget.albumMode ? 'album="${widget.album ?? widget.title}"' : 'song="${widget.title}"'}',
    );
    setState(() {
      _controller = controller;
      _sharedLease = lease;
      _hasVideo = true;
    });
    _reportFrame(controller);
    _attempt = 0;
    await _disposeVideo(previous, lease: previousLease);
  }

  @override
  Widget build(BuildContext context) {
    Widget present(Widget child, {bool canvas = false}) =>
        widget.presentationBuilder?.call(context, child, canvas) ?? child;
    if (_suppressed ||
        _suspendedForMemoryPressure ||
        _performance ||
        !widget.enabled)
      return present(widget.fallback);
    final controller = _controller;
    if (!_hasVideo || controller == null || !controller.value.isInitialized) {
      if (_ecoActive) return present(widget.fallback);
      final loading = widget.loadingFallback;
      if (_settledWithoutMotion || loading == null)
        return present(widget.fallback);
      return present(loading);
    }

    final size = controller.value.size;
    if (size.width <= 0 || size.height <= 0) return present(widget.fallback);

    Widget video = SizedBox.expand(
      child: FittedBox(
        fit: widget.fit,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
    final radius = widget.borderRadius;
    if (radius != null) {
      video = ClipRRect(borderRadius: radius, child: video);
    }
    return present(
      Stack(
        fit: StackFit.expand,
        children: [
          widget.fallback,
          if (_reusedClip)
            video
          else
            TweenAnimationBuilder<double>(
              key: ValueKey(controller),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 240),
              child: video,
              builder: (context, value, child) =>
                  Opacity(opacity: value, child: child),
            ),
        ],
      ),
      canvas: _spotifyCanvas[controller] ?? false,
    );
  }
}
