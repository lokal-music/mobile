import 'package:flick/features/player/widgets/full_player_seek_bar.dart';
import 'package:flick/models/progress_bar_style.dart';
import 'package:flick/providers/full_player_waveform_provider.dart';
import 'package:flick/features/player/widgets/lokal_player_columns.dart';
import 'package:flick/features/player/widgets/player_video_frame.dart';
import 'package:flick/features/player/widgets/player_lyric_style.dart';
import 'package:flick/core/utils/lokal_layout.dart';

import 'desktop_remote_full_player.dart';

import 'package:flick/providers/lokal_remote_provider.dart';

import 'dart:io';

import 'package:flick/core/theme/lokal_performance_scope.dart';
import 'package:flick/features/music_videos/media3_music_video_surface.dart';
import 'package:flick/features/internet_radio/radio_providers.dart';
import 'package:flick/features/internet_radio/radio_now_playing_page.dart';
import 'package:flick/features/music_videos/video_quality_settings.dart';
import 'package:flick/features/music_videos/music_video_providers.dart';
import 'package:flick/providers/opt_in_source_provider.dart';
import 'package:flick/features/player/widgets/full_player_visuals.dart';
import 'package:flick/features/player/widgets/full_bleed_artwork_frame.dart';
import 'package:flick/features/player/widgets/full_player_identity_layout.dart';

import '../widgets/artist_credit_links.dart';

import 'package:flick/widgets/common/overflow_marquee_title.dart';

import 'package:flick/core/theme/lokal_appearance.dart';

import '../widgets/lyrics_source_button.dart';
import '../widgets/lyrics_file_export.dart';
import '../widgets/lyrics_save_button.dart';
import '../widgets/player_panel_stage.dart';
import '../widgets/motion_art_widget.dart';

import 'package:flick/services/motion_art/moving_cover_settings.dart';
import 'package:flick/services/motion_art/moving_cover_availability.dart';
import 'package:flick/services/motion_art/animated_artwork_service.dart';
import 'package:flick/features/spotify/spotify_storage.dart';

import '../widgets/player_transport_controls.dart';
import '../widgets/player_song_blur_background.dart';
import '../widgets/full_player_header.dart';
import '../widgets/motion_art_frame_source.dart';
import '../widgets/lyric_motion_line.dart';
import '../widgets/flowing_background_vocals.dart';
import '../widgets/lyrics_focus_timing.dart';

import 'package:flick/core/utils/app_log.dart';

import '../widgets/lyrics_subline_timing.dart';
import '../widgets/flowing_lyric_subline.dart';
import '../widgets/immersive_lyrics_stage.dart';
import '../widgets/video_space_layout.dart';
import '../widgets/space_cover_bloom_reveal.dart';
import '../widgets/material_player_thumb.dart';

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flick/features/appearance/lokal_performance_advisor.dart';
import 'package:flick/widgets/lokal/lokal_toast.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/player/widgets/song_stage_carousel.dart';
import 'package:flick/features/player/widgets/player_artwork_image.dart';
import 'package:flick/features/queue/screens/queue_screen.dart';
import 'package:flick/widgets/lokal/lokal_like_burst.dart';
import 'package:flick/core/utils/app_haptics.dart';
import 'package:flick/widgets/lokal/lokal_player_artwork.dart';
import 'package:flick/widgets/lokal/lokal_pull_to_dismiss.dart';
import 'package:flick/widgets/lokal/lokal_quality.dart';
import 'package:flick/services/catalogue_quality.dart';
import 'package:flick/widgets/lokal/lokal_queue_reveal.dart';
import 'package:flick/features/player/widgets/loop_mode_sheet.dart';
import 'package:flick/features/player/widgets/online_lyrics_search_sheet.dart';

import '../widgets/lyrics_subline_buttons.dart';

import 'package:flick/features/player/widgets/shuffle_mode_sheet.dart';
import 'package:flick/features/player/widgets/sleep_timer_bottom_sheet.dart';
import 'package:flick/features/player/widgets/pitch_bottom_sheet.dart';
import 'package:flick/features/player/widgets/full_player_song_menu.dart';
import 'package:flick/features/konnekted/library/lokal_navigation.dart';
import 'package:flick/features/player/widgets/song_metadata_sheet.dart';
import 'package:flick/features/player/widgets/speed_bottom_sheet.dart';
import 'package:flick/features/settings/screens/equalizer_screen.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/models/audio_output_diagnostics.dart';
import 'package:flick/models/shuffle_mode.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/providers.dart';
import 'package:flick/services/favorites_service.dart';
import 'package:flick/services/lyrics_service.dart';
import 'package:flick/services/lyrics_sources.dart';
import 'package:flick/services/lyrics_playback_prefetch.dart';
import 'package:flick/services/player_service.dart';
import 'package:flick/services/external_playback_owner.dart';
import 'package:flick/services/player_volume_control.dart';

import '../widgets/playback_output_picker.dart';

const String _font = 'GoogleSansFlex';

/// Wave player: fluid artwork backdrop, big art, flowing lyrics, and labeled
/// action chips. The same constructor keeps the mini-player and navigation
/// entry points working with this player.
class FullPlayerScreen extends ConsumerStatefulWidget {
  final Object heroTag;

  /// When supplied, this same full player presents a video instead of song
  /// audio. The local audio queue is not replaced by a different recording.
  final Song? videoSong;
  final String? videoId;
  final bool initialLyrics;
  const FullPlayerScreen({
    super.key,
    this.heroTag = 'album_art_hero',
    this.videoSong,
    this.videoId,
    this.initialLyrics = false,
  }) : assert((videoSong == null) == (videoId == null));

  @override
  ConsumerState<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends ConsumerState<FullPlayerScreen>
    with TickerProviderStateMixin {
  final PlayerService _player = PlayerService();
  final LyricsService _lyricsService = LyricsService();

  bool _videoFullscreen = false;
  bool _exitingVideo = false;
  bool _videoRouteReleased = false;
  bool _immersiveLyrics = false;
  // Keep the subtitle layer alive until the exit reveal finishes.
  bool _spaceLayerMounted = false;
  Rect? _spaceCoverRect;
  bool _spaceCanvasMode = false;
  bool _spaceFullCover = false;
  bool _spaceWaitingForQueue = false;
  final GlobalKey _spacePanelKey = GlobalKey(debugLabel: 'space-player-panel');
  bool _spacePanelCompact = false;
  bool _spacePanelTabletCover = false;

  /// Resolve the current artwork bounds without reparenting media surfaces.
  Rect? _spaceArtworkBounds(bool fullCover) {
    final player = _playerBoundsKey.currentContext?.findRenderObject();
    if (player is! RenderBox || !player.attached || !player.hasSize) {
      return null;
    }
    if (fullCover) {
      final bannerHeight =
          (_posterBottom ??
                  player.size.width + MediaQuery.paddingOf(context).top + 56)
              .clamp(1.0, player.size.height)
              .toDouble();
      return Rect.fromLTWH(0, 0, player.size.width, bannerHeight);
    }
    // The panel delegate and the mask use the very same size/offset
    // calculation, avoiding a GlobalKey on individual carousel stages (which
    // can be duplicated when a queue contains the same recording twice).
    final panel = _spacePanelKey.currentContext?.findRenderObject();
    if (panel is RenderBox && panel.attached && panel.hasSize) {
      final local = playerPanelArtworkRect(
        panel.size,
        artGap: _spacePanelTabletCover
            ? 0
            : _spacePanelCompact
            ? 10
            : 17,
        infoReserve: MediaQuery.textScalerOf(context).scale(
          _spacePanelTabletCover
              ? 72 *
                    (_lyricsProgress.value + _queueProgress.value).clamp(
                      0.0,
                      1.0,
                    )
              : 72,
        ),
        queue: _queueProgress.value,
        lyrics: _lyricsProgress.value,
      );
      final origin = player.globalToLocal(panel.localToGlobal(Offset.zero));
      return local.shift(origin);
    }
    return null;
  }

  double _spaceArtworkCornerRadius() {
    if (_spaceFullCover || _spaceCanvasMode) return 0;
    final lyrics = _lyricsProgress.value;
    final compact = (_queueProgress.value * (1 - lyrics) + lyrics).clamp(
      0.0,
      1.0,
    );
    return lerpDouble(20, 12, compact)!;
  }

  void _resumeSpaceAfterQueue(AnimationStatus status) {
    if (status != AnimationStatus.dismissed || !_spaceWaitingForQueue) return;
    _spaceWaitingForQueue = false;
    _queueProgress.removeStatusListener(_resumeSpaceAfterQueue);
    if (mounted) _toggleImmersiveLyrics();
  }

  late final Listenable _spaceCoverMotion = Listenable.merge([
    _lyricsProgress,
    _queueProgress,
  ]);

  late final AnimationController _spaceProgress =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 620),
        reverseDuration: const Duration(milliseconds: 500),
      )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed &&
            !_immersiveLyrics &&
            _spaceLayerMounted &&
            mounted) {
          setState(() => _spaceLayerMounted = false);
        }
      });

  late final Animation<double> _spaceChromeOpacity = ReverseAnimation(
    CurvedAnimation(
      parent: _spaceProgress,
      curve: const Interval(0, .68, curve: Curves.easeOutCubic),
    ),
  );
  final Media3MusicVideoController _videoController =
      Media3MusicVideoController();
  final GlobalKey _videoSurfaceKey = GlobalKey(
    debugLabel: 'persistent-media3-video',
  );

  bool _videoYielded = false;
  ExternalPlaybackLease? _videoOutputLease;
  String? get _activeVideoId =>
      _videoYielded ? null : (_videoOverrideId ?? widget.videoId);
  bool get _videoActive => _activeVideoId != null;
  bool get _usesEmbeddedVideo =>
      _videoActive &&
      (!Platform.isAndroid || !_videoController.nativeNotifier.value);
  Song? get _displayedSong => _videoActive
      ? (_videoOverrideSong ?? widget.videoSong)
      : _player.currentSongNotifier.value;
  bool get _displayedFavorite => _favForSongId == _displayedSong?.id && _isFav;
  String? _videoOverrideId;
  Song? _videoOverrideSong;
  bool _resumeAudioAfterVideo = false;
  bool _enteringVideo = false;
  bool _showLyrics = false;
  bool _lyricsLoading = false;
  bool _savingLyricsFile = false;
  String _lyricsSource = 'auto';
  int _lyricsRequest = 0;
  LyricsData? _lyrics;
  LyricsData? _sublineLyrics;
  LyricsData? _embeddedBackgroundLyrics;
  String? _lyricsForSongId;

  bool _isFav = false;
  String? _favForSongId;

  late final PlayerVolumeControl _volumeControl;
  double _volume = 1.0;
  bool _draggingSeek = false;
  double _seekDrag = 0;
  bool _draggingVolume = false;

  bool _carouselDragging = false;
  final _carouselKey = GlobalKey<SongStageCarouselState>();
  final _playerBoundsKey = GlobalKey();
  final LayerLink _seekbarSubtitleLink = LayerLink();
  final _posterAnchorKey = GlobalKey();
  final _infoAnchorKey = GlobalKey();
  double? _posterBottom;
  bool _posterMeasurePending = false;

  void _measurePoster() {
    if (_posterMeasurePending) return;
    _posterMeasurePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _posterMeasurePending = false;
      if (!mounted || _showLyrics || _queue.engaged) return;
      final slot = _posterAnchorKey.currentContext?.findRenderObject();
      final info = _infoAnchorKey.currentContext?.findRenderObject();
      final frame = _playerBoundsKey.currentContext?.findRenderObject();
      if (slot is! RenderBox ||
          info is! RenderBox ||
          frame is! RenderBox ||
          !slot.hasSize ||
          !info.hasSize) {
        return;
      }
      // End the poster dissolve below the actual artist/quality row.
      final bottom =
          math.max(
            slot.localToGlobal(Offset(0, slot.size.height), ancestor: frame).dy,
            info.localToGlobal(Offset(0, info.size.height), ancestor: frame).dy,
          ) +
          8;
      if (_posterBottom == null || (_posterBottom! - bottom).abs() > .5) {
        setState(() => _posterBottom = bottom);
      }
    });
  }

  /// The queue opens in place: the cover shrinks into a header row and the
  /// list rises under it, all off this one value (0 = player, 1 = queue).
  late final AnimationController _queueProgress = AnimationController(
    vsync: this,
  );
  late final LokalQueueRevealMotion _queue = LokalQueueRevealMotion(
    _queueProgress,
  )..addListener(_onQueueTargetChanged);

  late final AnimationController _lyricsProgress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  bool _canvasHidden = false;
  final _motionFrames = MotionArtFrameSource();
  String? _canvasReadyForSong;
  late final _canvasChrome = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 250),
  );

  bool _motionEnabled(Song song) {
    final prefs = ref.watch(appPreferencesProvider);
    return prefs.animatedAlbumArt &&
        prefs.animationsEnabled &&
        !ref
            .watch(movingCoverSettingsProvider)
            .disabledSongs
            .contains(movingCoverSongKey(song));
  }

  void _restoreCanvasControls() {
    if (_canvasHidden) setState(() => _canvasHidden = false);
    _canvasChrome.forward();
  }

  void _reportCanvas(String songId, bool available) {
    final desired = available ? songId : null;
    if (_canvasReadyForSong == desired) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _player.currentSongNotifier.value?.id != songId ||
          _canvasReadyForSong == desired)
        return;
      setState(() => _canvasReadyForSong = desired);
      if (!available) _restoreCanvasControls();
    });
  }

  void _toggleCanvasControls() {
    setState(() => _canvasHidden = !_canvasHidden);
    _canvasHidden ? _canvasChrome.reverse() : _canvasChrome.forward();
  }

  int _burst = 0;
  bool _burstVisible = false;
  Animation<double>? _initialRouteAnimation;
  bool _initialEntryReady = false;

  @override
  void initState() {
    super.initState();
    _showLyrics = widget.initialLyrics;
    if (widget.initialLyrics) _lyricsProgress.value = 1;
    _videoController.nativeNotifier.addListener(_onVideoBackendChanged);
    if (widget.videoId != null) unawaited(_prepareInitialVideo());
    LokalPerformanceAdvisor.noteNavigation(surface: 'full-player');
    LokalPerformanceAdvisor.enterPlayerSurface('modern-full-player');
    _volumeControl = PlayerVolumeControl(_player);
    _volume = _volumeControl.value;
    _player.currentSongNotifier.addListener(_onSongChanged);
    _player.favoriteNotificationToggleNotifier.addListener(_refreshFavorite);
    // Defer nonessential database, network and lyrics work until the
    // mini-player -> full-player sheet has finished its first animation.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context)?.animation;
    if (identical(_initialRouteAnimation, route) && _initialEntryReady) return;
    _initialRouteAnimation?.removeStatusListener(_onInitialRouteStatus);
    _initialRouteAnimation = route;
    route?.addStatusListener(_onInitialRouteStatus);
    if (route == null || route.status == AnimationStatus.completed) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _finishInitialEntry(),
      );
    }
  }

  void _onInitialRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _finishInitialEntry(),
      );
    }
  }

  void _finishInitialEntry() {
    if (!mounted || _initialEntryReady) return;
    _initialEntryReady = true;
    _initialRouteAnimation?.removeStatusListener(_onInitialRouteStatus);
    if (ref.read(lokalRemoteControllerProvider).controlsDesktop) return;
    unawaited(_refreshFavorite());
    _discoverVideo(_player.currentSongNotifier.value);
    unawaited(_loadLyrics());
  }

  void _discoverVideo(Song? song) {
    if (song == null || !ref.read(musicVideosEnabledProvider)) return;
    // On-demand lookup (remembered by the same index as Library > Videos).
    // Only a positively identified official video earns the footer button.
    unawaited(
      ref
          .read(musicVideoIndexProvider.notifier)
          .find(song)
          .catchError((Object _) => null),
    );
  }

  @override
  void dispose() {
    if (_videoFullscreen) {
      // Restore the device's default rotation policy on every exit path.
      unawaited(
        SystemChrome.setPreferredOrientations(
          LokalLayout.defaultOrientations(),
        ),
      );
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    _initialRouteAnimation?.removeStatusListener(_onInitialRouteStatus);
    LokalPerformanceAdvisor.exitPlayerSurface('modern-full-player');
    _volumeControl.dispose();
    _queue.dispose();
    _queueProgress.removeStatusListener(_resumeSpaceAfterQueue);
    _queueProgress.dispose();
    _lyricsProgress.dispose();
    _spaceProgress.dispose();
    _canvasChrome.dispose();
    _motionFrames.dispose();
    final videoLease = _videoOutputLease;
    if (videoLease != null)
      unawaited(videoLease.release().catchError((Object _) {}));
    _videoController.nativeNotifier.removeListener(_onVideoBackendChanged);
    _videoController.dispose();
    _player.currentSongNotifier.removeListener(_onSongChanged);
    _player.favoriteNotificationToggleNotifier.removeListener(_refreshFavorite);
    super.dispose();
  }

  void _onVideoBackendChanged() {
    void refresh() {
      if (!mounted) return;
      if (_usesEmbeddedVideo && _videoFullscreen) {
        _toggleVideoFullscreen();
      } else {
        setState(() {});
      }
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
    } else {
      refresh();
    }
  }

  void _onSongChanged() {
    _canvasReadyForSong = null;
    _restoreCanvasControls();
    _draggingSeek = false;
    // The entry warm-up always uses the latest song; early queue changes
    // must not initiate duplicate work during the opening sheet animation.
    if (!_initialEntryReady) return;
    unawaited(_refreshFavorite());
    _discoverVideo(_player.currentSongNotifier.value);
    unawaited(_loadLyrics());
  }

  Future<void> _refreshFavorite() async {
    final song = _displayedSong;
    if (song == null) return;
    // Notification toggles write through PlayerService's separate service.
    // Use a fresh reader to avoid a stale per-instance favorites cache.
    final fav = await FavoritesService().isFavorite(song.id);
    if (!mounted || _displayedSong?.id != song.id) return;
    setState(() {
      _isFav = fav;
      _favForSongId = song.id;
    });
  }

  Future<void> _toggleFavorite() async {
    final song = _displayedSong;
    if (song == null) return;
    AppHaptics.selection();
    // Update the shared favorites provider: the Liked library folder watches
    // this provider, while a direct FavoritesService call left it stale.
    final nowFav = await ref
        .read(favoritesProvider.notifier)
        .toggleFavorite(song.id, song: song);
    if (!mounted) return;
    setState(() {
      _isFav = nowFav;
      _favForSongId = song.id;
    });
  }

  Future<void> _loadLyrics({
    bool force = false,
    bool refreshOnline = false,
  }) async {
    final song =
        (_videoActive ? (_videoOverrideSong ?? widget.videoSong) : null) ??
        _player.currentSongNotifier.value;
    if (song == null) return;
    if (!force && _lyricsForSongId == song.id && _lyrics != null) return;
    final request = ++_lyricsRequest;
    setState(() {
      _lyricsLoading = true;
      if (_lyricsForSongId != song.id) {
        _lyrics = null;
        _embeddedBackgroundLyrics = null;
      }
      _lyricsForSongId = song.id;
    });
    _sublineLyrics = null;
    // Always inspect the audio's independent bg lane. A lead-only online,
    // cached or manually selected source must never suppress the backing voice.
    unawaited(_loadEmbeddedBackgroundLyrics(song, request));
    final warm = !force && !refreshOnline && _lyricsSource == 'auto';
    try {
      // Display local sidecar/embedded lyrics as soon as filesystem lookup
      // completes; never gate them on LRCLIB / remote lyric providers.
      final local = warm
          ? await LyricsPlaybackPrefetch.instance.local(song)
          : await _lyricsService.loadLyricsForSong(
              song,
              forceRefresh: force,
              fetchOnline: false,
              source: _lyricsSource,
            );
      if (!mounted ||
          request != _lyricsRequest ||
          ((_videoActive ? (_videoOverrideSong ?? widget.videoSong) : null) ??
                      _player.currentSongNotifier.value)
                  ?.id !=
              song.id)
        return;
      setState(() {
        _lyrics = LyricsService.mergeSupportingVocals(local, [
          _embeddedBackgroundLyrics,
        ]);
        _lyricsLoading = local == null;
      });
      final best = warm
          ? await LyricsPlaybackPrefetch.instance.enhanced(song)
          : await _lyricsService.loadLyricsForSong(
              song,
              forceRefresh: force,
              refreshOnline: refreshOnline,
              source: _lyricsSource,
              stillCurrent: () => mounted && request == _lyricsRequest,
              fetchOnline:
                  refreshOnline ||
                  ref.read(appPreferencesProvider).lyricsAutoFetch,
            );
      if (!mounted ||
          request != _lyricsRequest ||
          ((_videoActive ? (_videoOverrideSong ?? widget.videoSong) : null) ??
                      _player.currentSongNotifier.value)
                  ?.id !=
              song.id)
        return;
      setState(() {
        final selected = lyricQualityRank(best) > lyricQualityRank(_lyrics)
            ? best
            : _lyrics ?? best;
        // An online lead-timing upgrade must not remove independently timed
        // backing vocals that came from the audio file.
        _lyrics = LyricsService.mergeSupportingVocals(selected, [
          _lyrics,
          best,
          _embeddedBackgroundLyrics,
        ]);
        _lyricsLoading = false;
      });
    } catch (_) {
      if (mounted && request == _lyricsRequest) {
        setState(() => _lyricsLoading = false);
      }
    }
  }

  void _moveLyrics(bool open) {
    _restoreCanvasControls();
    setState(() => _showLyrics = open);
    final target = open ? 1.0 : 0.0;
    if (!_animate) {
      _lyricsProgress.value = target;
    } else {
      _lyricsProgress.animateTo(target, curve: Curves.easeInOutCubicEmphasized);
    }
    if (open) unawaited(_loadLyrics());
  }

  Future<void> _loadEmbeddedBackgroundLyrics(Song song, int request) async {
    LyricsData? background;
    try {
      background = await _lyricsService
          .loadEmbeddedSupportingVocals(song)
          .timeout(const Duration(seconds: 8), onTimeout: () => null);
    } catch (error) {
      AppLog.instance.add(
        '[LyricsBG] fullscreenLookupError=${error.runtimeType}',
      );
    }
    if (!mounted || request != _lyricsRequest || _lyricsForSongId != song.id)
      return;
    final selected = LyricsService.mergeSupportingVocals(_lyrics, [background]);
    AppLog.instance.add(
      '[LyricsBG] fullscreenVisible embedded=${LyricsService.supportingVocalCount(background)} '
      'selected=${LyricsService.supportingVocalCount(selected)}',
    );
    setState(() {
      _embeddedBackgroundLyrics = background;
      _lyrics = selected;
    });
  }

  void _toggleImmersiveLyrics() {
    // Wait for the compact queue cover to return to the poster before
    // revealing Space in Fullcover mode.
    if (!_immersiveLyrics &&
        !_spaceWaitingForQueue &&
        _animate &&
        !LokalLayout.isLandscapeTablet(context) &&
        ref.read(lokalAppearanceProvider).fullscreenCover &&
        _queueProgress.value > .005) {
      _spaceWaitingForQueue = true;
      _queueProgress.addStatusListener(_resumeSpaceAfterQueue);
      _queue.setOpen(false, animate: true);
      return;
    }
    if (_immersiveLyrics) {
      // The painter, aperture and subtitles reverse in place. Unmount only
      // when the reverse animation is fully dismissed.
      setState(() => _immersiveLyrics = false);
      if (_animate) {
        _spaceProgress.reverse();
      } else {
        _spaceProgress.value = 0;
        setState(() => _spaceLayerMounted = false);
      }
      _restoreCanvasControls();
      return;
    }

    _restoreCanvasControls();
    if (_showLyrics) _moveLyrics(false);
    // Keep the queue thumbnail -> full-size cover morph. Resetting the
    // queue without animation caused the artwork to pop into Space.
    _queue.setOpen(false, animate: _animate);
    HapticFeedback.selectionClick();
    final active =
        _videoOverrideSong ??
        widget.videoSong ??
        _player.currentSongNotifier.value;
    final fullCover =
        !LokalLayout.isLandscapeTablet(context) &&
        ref.read(lokalAppearanceProvider).fullscreenCover;
    _spaceFullCover = fullCover;
    // Canvas fills the art plane, so the wave leaves its centre clear.
    _spaceCanvasMode =
        _videoFullscreen ||
        (fullCover && active != null && _canvasReadyForSong == active.id);
    _spaceCoverRect = _spaceArtworkBounds(fullCover);
    setState(() {
      _immersiveLyrics = true;
      _spaceLayerMounted = true;
    });
    if (_animate) {
      _spaceProgress.forward();
    } else {
      _spaceProgress.value = 1;
    }
    unawaited(_loadLyrics());
  }

  Future<void> _saveLyricsFile(
    Song song,
    LyricsData lyrics, {
    bool includeDisplayedSubline = false,
  }) async {
    if (!mounted ||
        _savingLyricsFile ||
        _lyricsForSongId != song.id ||
        _displayedSong?.id != song.id) {
      return;
    }
    setState(() => _savingLyricsFile = true);
    try {
      final saved = await saveCurrentLyricsFile(
        song: song,
        lyrics: lyrics,
        includeDisplayedSubline: includeDisplayedSubline,
      );
      if (saved && mounted) {
        LokalToast.fromSnackBar(
          context,
          SnackBar(
            content: Text(l10n.saved),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        LokalToast.fromSnackBar(
          context,
          SnackBar(
            content: Text(lokalText('Could not save lyrics to file.')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingLyricsFile = false);
    }
  }

  VoidCallback? _saveTranslatedLyricsAction(Song song) {
    final selected = _sublineLyrics;
    if (selected == null ||
        !selected.lines.any(
          (line) =>
              line.translation?.trim().isNotEmpty == true &&
              line.translation!.trim() != line.text.trim(),
        )) {
      return null;
    }
    return () => unawaited(
      _saveLyricsFile(song, selected, includeDisplayedSubline: true),
    );
  }

  void _showSpaceOptions() {
    if (!_immersiveLyrics) return;
    final shownSong = _displayedSong;
    final source = _lyrics;
    void saveFromSheet({required bool includeTranslation}) {
      final currentSong = _displayedSong;
      if (shownSong == null ||
          currentSong?.id != shownSong.id ||
          _lyricsForSongId != shownSong.id) {
        return;
      }
      final selected = includeTranslation ? _sublineLyrics : _lyrics;
      if (selected == null || !hasUsableLyrics(selected)) return;
      unawaited(
        _saveLyricsFile(
          shownSong,
          selected,
          includeDisplayedSubline: includeTranslation,
        ),
      );
    }

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, refreshSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.library_music_outlined),
                  title: Text(lokalText('Lyrics source')),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(_chooseImmersiveLyricsSource());
                  },
                ),
                if (source != null && hasUsableLyrics(source))
                  ListTile(
                    leading: const Icon(LucideIcons.download),
                    title: Text(lokalText('Save original lyrics')),
                    enabled: !_savingLyricsFile,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      saveFromSheet(includeTranslation: false);
                    },
                  ),
                if (source != null && hasUsableLyrics(source))
                  ListTile(
                    leading: const Icon(Icons.translate_rounded),
                    title: Text(lokalText('Save with selected translation')),
                    subtitle: Text(
                      lokalText(
                        'Includes the active translation or romanization.',
                      ),
                    ),
                    enabled:
                        !_savingLyricsFile &&
                        _sublineLyrics?.lines.any(
                              (line) =>
                                  line.translation?.trim().isNotEmpty == true &&
                                  line.translation!.trim() != line.text.trim(),
                            ) ==
                            true,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      saveFromSheet(includeTranslation: true);
                    },
                  ),
                if (source != null)
                  LyricsSublineButtons(
                    lyrics: source,
                    onChanged: (updated) {
                      if (mounted && identical(_lyrics, source)) {
                        setState(() => _sublineLyrics = updated);
                        refreshSheet(() {});
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseImmersiveLyricsSource() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
          children: [
            const ListTile(
              title: Text('Lyrics source'),
              subtitle: Text('Choose the best available timing for this song'),
            ),
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('Refresh current source'),
              onTap: () => Navigator.pop(sheetContext, '__refresh'),
            ),
            for (final entry in {
              'auto': 'Automatic',
              'local': 'Local file',
              ...lyricsSources,
            }.entries)
              ListTile(
                title: Text(entry.value),
                trailing: _lyricsSource == entry.key
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(sheetContext, entry.key),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == '__refresh') {
      unawaited(_loadLyrics(force: true, refreshOnline: true));
      return;
    }
    setState(() => _lyricsSource = choice);
    unawaited(_loadLyrics(force: true));
  }

  void _toggleLyrics() {
    HapticFeedback.selectionClick();
    if (_showLyrics) {
      // At the lyric pose the hidden queue can reset without moving artwork.
      // Mid-flight, animate it instead so a rapid reversal stays continuous.
      _queue.setOpen(false, animate: _animate && _lyricsProgress.value < .999);
      _moveLyrics(false);
    } else {
      _queueProgress.stop();
      _moveLyrics(true);
    }
  }

  void _onQueueTargetChanged() {
    if (mounted) setState(() {});
  }

  bool get _animate => !MediaQuery.disableAnimationsOf(context);

  void _setQueueOpen(bool open) {
    if (open == _queue.isOpen && !_showLyrics) return;
    HapticFeedback.selectionClick();
    _queue.setOpen(open, animate: _animate && _lyricsProgress.value < .999);
    if (_showLyrics) _moveLyrics(false);
  }

  void _toggleQueue() => _setQueueOpen(_showLyrics || !_queue.isOpen);

  void _releaseQueue(double upVelocity) {
    final was = _queue.isOpen;
    if (_queue.release(upVelocity, animate: _animate) != was) {
      HapticFeedback.selectionClick();
    }
  }

  Future<void> _close() async {
    if (_immersiveLyrics) {
      _toggleImmersiveLyrics();
    } else if (_videoFullscreen) {
      _toggleVideoFullscreen();
    } else if (_videoOverrideId != null) {
      _exitVideoMode();
    } else {
      if (_videoActive) {
        final released = await _releaseVideoAudio();
        if (!released || !mounted) return;
        setState(() => _videoRouteReleased = true);
      }
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _yieldVideoOutput() async {
    await _videoController.releaseAudio();
    if (!mounted) return;
    final wasFullscreen = _videoFullscreen;
    setState(() {
      _videoYielded = true;
      _videoOverrideId = null;
      _videoOverrideSong = null;
      _resumeAudioAfterVideo = false;
      _videoFullscreen = false;
      _immersiveLyrics = false;
    });
    _videoController.reset();
    _refreshFavorite();
    if (wasFullscreen) {
      unawaited(
        SystemChrome.setPreferredOrientations(
          LokalLayout.defaultOrientations(),
        ),
      );
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    unawaited(_loadLyrics());
  }

  Future<void> _retireVideoForMediaReset() async {
    _resumeAudioAfterVideo = false;
    await _videoController.retireForMediaReset();
  }

  Future<void> _prepareInitialVideo() async {
    try {
      final lease = await _player.acquireExternalPlayback(
        _yieldVideoOutput,
        onMediaReset: _retireVideoForMediaReset,
      );
      _videoOutputLease = lease;
      if (!mounted) {
        await lease.release();
      } else {
        setState(() {});
      }
    } catch (_) {
      if (mounted) setState(() => _videoYielded = true);
    }
  }

  Future<void> _enterVideoMode(Song song, String videoId) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId) ||
        _enteringVideo ||
        _exitingVideo ||
        _videoOverrideId != null)
      return;
    _enteringVideo = true;
    final wasPlaying = _player.isPlayingNotifier.value;
    final originalSong = _player.currentSongNotifier.value;
    try {
      final lease = await _player.acquireExternalPlayback(
        _yieldVideoOutput,
        onMediaReset: _retireVideoForMediaReset,
      );
      _videoOutputLease = lease;
      if (!mounted ||
          lease.isReleased ||
          !identical(_player.currentSongNotifier.value, originalSong)) {
        await lease.release();
        return;
      }
      HapticFeedback.selectionClick();
      setState(() {
        _videoYielded = false;
        _resumeAudioAfterVideo = wasPlaying;
        _videoOverrideSong = song;
        _videoOverrideId = videoId;
      });
      _videoController.reset();
      _refreshFavorite();
      unawaited(_loadLyrics());
    } catch (_) {
      if (mounted) {
        LokalToast.fromSnackBar(
          context,
          const SnackBar(
            content: Text(
              'Playback changed or the previous output could not pause. Try video again.',
            ),
          ),
        );
      }
    } finally {
      _enteringVideo = false;
    }
  }

  Future<bool> _releaseVideoAudio() async {
    try {
      final lease = _videoOutputLease;
      if (lease != null) {
        await lease.release();
      } else {
        await _videoController.releaseAudio();
      }
      return true;
    } catch (_) {
      if (mounted) {
        LokalToast.fromSnackBar(
          context,
          const SnackBar(
            content: Text(
              'Video could not be paused. Try again before returning to audio.',
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _videoCommand(Future<void> Function() command) async {
    try {
      await command();
    } catch (_) {
      if (mounted) {
        LokalToast.fromSnackBar(
          context,
          const SnackBar(
            content: Text(
              'Video controls are not ready. Try again or use the video controls.',
            ),
          ),
        );
      }
    }
  }

  Future<bool> _exitVideoMode({bool resumeAudio = true}) async {
    if (_exitingVideo || _videoOverrideId == null) return false;
    _exitingVideo = true;
    final lease = _videoOutputLease;
    final originalSong = _player.currentSongNotifier.value;
    final resume = resumeAudio && _resumeAudioAfterVideo;
    final intent = _player.playbackIntentRevision;
    try {
      if (!await _releaseVideoAudio() || !mounted) return false;
      if (resume && lease != null) {
        await _player.resumeAfterExternalPlayback(
          lease,
          originalSong,
          intentRevision: intent,
        );
      }
      return true;
    } finally {
      _exitingVideo = false;
    }
  }

  void _toggleVideoFullscreen() {
    if (!_videoFullscreen && _usesEmbeddedVideo) return;
    setState(() => _videoFullscreen = !_videoFullscreen);
    unawaited(
      SystemChrome.setPreferredOrientations(
        _videoFullscreen
            ? [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : LokalLayout.defaultOrientations(),
      ),
    );
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        _videoFullscreen
            ? SystemUiMode.immersiveSticky
            : SystemUiMode.edgeToEdge,
      ),
    );
  }

  /// The native video is the only audio owner while open; the separate
  /// album recording remains paused and never plays in parallel with Media3.
  /// Keep the platform view mounted across fullscreen/fit changes.
  Widget _videoScaffold(Song song, String videoId) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _immersiveLyrics ? _toggleImmersiveLyrics : null,
        onLongPress: _immersiveLyrics ? _showSpaceOptions : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: LayoutBuilder(
                builder: (context, box) {
                  final width = _videoFullscreen
                      ? box.maxWidth
                      : math.min(box.maxWidth, box.maxHeight * 16 / 9);
                  final height = _videoFullscreen
                      ? box.maxHeight
                      : width * 9 / 16;
                  return SizedBox(
                    width: width,
                    height: height,
                    child: Media3MusicVideoSurface(
                      key: _videoSurfaceKey,
                      videoId: videoId,
                      controller: _videoController,
                      maxVideoHeight: ref.watch(videoQualityProvider),
                      showControls: !_immersiveLyrics,
                    ),
                  );
                },
              ),
            ),
            if (!_immersiveLyrics && !_videoFullscreen)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Close video',
                          onPressed: _close,
                          icon: const Icon(
                            LucideIcons.chevronLeft,
                            color: Colors.white,
                          ),
                        ),
                        const Expanded(
                          child: Text(
                            'MUSIC VIDEO',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontFamily: _font,
                              fontSize: 12,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Full-screen video',
                          onPressed: _toggleVideoFullscreen,
                          icon: const Icon(
                            LucideIcons.maximize,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (!_immersiveLyrics)
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    tooltip: 'Exit full-screen video',
                    onPressed: _toggleVideoFullscreen,
                    icon: const Icon(LucideIcons.minimize, color: Colors.white),
                  ),
                ),
              ),
            if (!_videoFullscreen)
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(25, 0, 25, 26),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: _font,
                            fontWeight: FontWeight.w700,
                            fontSize: 24,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: _font,
                            fontSize: 15,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Video playback via YouTube',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_spaceLayerMounted)
              Positioned.fill(
                child: SpaceCoverBloomReveal(
                  coverRect: _spaceCoverRect,
                  coverRectResolver: () => _spaceArtworkBounds(_spaceFullCover),
                  coverMotion: _spaceCoverMotion,
                  coverCornerRadiusResolver: _spaceArtworkCornerRadius,
                  canvasMode: _spaceCanvasMode,
                  coverCornerRadius: _spaceFullCover ? 0 : 20,
                  surfaceColor: const Color(0xFF171820),
                  progress: _spaceProgress,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: math.max(
                          MediaQuery.paddingOf(context).bottom + 52,
                          MediaQuery.sizeOf(context).height * .28,
                        ),
                        child: IgnorePointer(
                          child: ValueListenableBuilder<bool>(
                            valueListenable: _videoController.nativeNotifier,
                            builder: (_, native, __) => native
                                ? _spaceSubtitle(song)
                                : const Text(
                                    'Timed subtitles unavailable in video fallback',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_spaceLayerMounted)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_immersiveLyrics,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleImmersiveLyrics,
                    onLongPress: _showSpaceOptions,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────── gestures ─────────────────────────────

  /// Double-tapping the artwork likes the song (never unlikes it), with a
  /// burst over the cover.
  void _likeFromArtwork() {
    HapticFeedback.mediumImpact();
    setState(() {
      _burst++;
      _burstVisible = true;
    });
    if (!_displayedFavorite) _toggleFavorite();
  }

  Future<void> _openEqualizer() => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const EqualizerScreen()));

  /// Keep track-specific menu actions aligned with the live recording.
  Future<void> _openMore(Song song) =>
      showFullPlayerSongMenu(context, song: song, player: _player);

  // ───────────────────────────── build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    // The Android engine retains its previous phone song while a paired PC
    // owns the transport. Render a remote-aware player instead of that stale
    // phone state; both branches remain in the same fullscreen route.
    if (widget.videoSong == null &&
        ref.watch(
          lokalRemoteControllerProvider.select((s) => s.controlsDesktop),
        )) {
      return DesktopRemoteFullPlayer(
        onClose: _close,
        initialLyrics: widget.initialLyrics,
      );
    }
    // Stations share this exact spring-driven player route with local music
    // and desktop remote playback. The radio transport owns its own session,
    // but chrome, dismissal and artwork morph are not separate architectures.
    if (widget.videoSong == null &&
        ref.watch(radioPlayerProvider.select((s) => s.station != null))) {
      return RadioNowPlayingPage(
        onClose: _close,
        initialLyrics: widget.initialLyrics,
      );
    }
    final palette = ref.watch(albumPaletteSyncProvider);
    final dominant = ref.watch(albumDominantColorSyncProvider);
    final isCasting = ref.watch(isCastingProvider);
    final diagnostics = ref.watch(audioOutputDiagnosticsProvider);
    final colors = palette.length >= 2
        ? palette
        : [
            dominant ?? const Color(0xFF3B3B44),
            HSLColor.fromColor(dominant ?? const Color(0xFF3B3B44))
                .withLightness(0.3)
                .toColor(),
            const Color(0xFF14141A),
          ];

    return PopScope(
      // Back puts the queue or the lyrics away first, then closes the player.
      canPop:
          !_immersiveLyrics &&
          _videoOverrideId == null &&
          (!_videoActive || _videoRouteReleased) &&
          !_videoFullscreen &&
          !_showLyrics &&
          !_queue.isOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_immersiveLyrics) {
          _toggleImmersiveLyrics();
        } else if (_videoFullscreen) {
          _toggleVideoFullscreen();
        } else if (_videoOverrideId != null) {
          _exitVideoMode();
        } else if (_showLyrics) {
          _toggleLyrics();
        } else if (_queue.isOpen) {
          _setQueueOpen(false);
        } else if (_videoActive) {
          unawaited(_close());
        }
      },
      child: LokalPullToDismiss(
        onDismiss: _close,
        // Pulling up drags the queue in, following the finger.
        onPullUpUpdate:
            _immersiveLyrics ||
                _showLyrics ||
                _videoOverrideId != null ||
                widget.videoSong != null
            ? null
            : _queue.dragBy,
        onPullUpEnd:
            _immersiveLyrics ||
                _showLyrics ||
                _videoOverrideId != null ||
                widget.videoSong != null
            ? null
            : _releaseQueue,
        // While the queue is out, its header owns vertical drags.
        isBlocked: () =>
            _immersiveLyrics ||
            _videoOverrideId != null ||
            widget.videoSong != null ||
            _carouselDragging ||
            _queue.engaged,
        child: _scaffold(colors, isCasting, diagnostics),
      ),
    );
  }

  Widget _scaffold(
    List<Color> colors,
    bool isCasting,
    AudioOutputDiagnostics? diagnostics,
  ) {
    final videoSong = _videoOverrideSong ?? widget.videoSong;
    final videoId = _activeVideoId;
    if (_videoActive && _videoOutputLease?.isReleased != false) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_videoFullscreen && videoSong != null && videoId != null) {
      return _videoScaffold(videoSong, videoId);
    }
    final coverPreference = ref.watch(
      lokalAppearanceProvider.select((look) => look.fullscreenCover),
    );
    final tabletCover =
        LokalLayout.isLandscapeTablet(context) && coverPreference;
    final fullCover =
        !LokalLayout.isLandscapeTablet(context) && coverPreference;
    return Scaffold(
      backgroundColor: Colors.black,
      body:
          _immersiveLyrics &&
              _usesEmbeddedVideo &&
              videoSong != null &&
              videoId != null
          ? _embeddedVideoSpace(videoSong, videoId)
          : ValueListenableBuilder<Song?>(
              valueListenable: _player.currentSongNotifier,
              builder: (context, playingSong, _) {
                final song = videoSong ?? playingSong;
                if (song == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final clearViewAvailable =
                    fullCover &&
                    _motionEnabled(song) &&
                    _canvasReadyForSong == song.id &&
                    !_showLyrics &&
                    !_immersiveLyrics &&
                    !_queue.engaged;
                final hidden = clearViewAvailable && _canvasHidden;
                return GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _immersiveLyrics
                      ? _toggleImmersiveLyrics
                      : (clearViewAvailable ? _toggleCanvasControls : null),
                  onLongPress: _immersiveLyrics ? _showSpaceOptions : null,
                  child: Stack(
                    key: _playerBoundsKey,
                    fit: StackFit.expand,
                    children: [
                      PlayerSongBlurBackground(
                        song: song,
                        colors: colors,
                        fullCover: fullCover || tabletCover,
                        motionFrames: _motionFrames,
                      ),
                      if (fullCover)
                        FadeTransition(
                          opacity: _canvasChrome,
                          child: const IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0x33000000),
                                    Color(0x08000000),
                                    Color(0x10000000),
                                    Color(0x40000000),
                                  ],
                                  stops: [0, .28, .66, 1],
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        Container(color: Colors.black.withValues(alpha: 0.10)),
                      if (fullCover) _fullscreenArtwork(song),
                      // Keep the controls, title and quality metadata above the
                      // fullscreen Canvas while its artwork travels out of the
                      // mini-player. The same chrome continues its sheet motion;
                      // the Canvas clear-view toggle still fades this entire tree.
                      LokalPlayerChrome(
                        enabled: fullCover,
                        child: IgnorePointer(
                          ignoring: hidden,
                          child: FadeTransition(
                            opacity: _canvasChrome,
                            child: TickerMode(
                              enabled: !hidden,
                              child: SafeArea(
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    23,
                                    0,
                                    23,
                                    14, // keeps the chip row clear of the system nav bar
                                  ),
                                  child: LayoutBuilder(
                                    builder: (context, c) {
                                      if (LokalLayout.isLandscapeTablet(
                                            context,
                                          ) &&
                                          c.maxWidth >= 720) {
                                        return AnimatedBuilder(
                                          animation: _lyricsProgress,
                                          builder: (context, _) =>
                                              _tabletPlayerChrome(
                                                song,
                                                isCasting,
                                                diagnostics,
                                                fullCover: fullCover,
                                                fillCover: tabletCover,
                                                compact: c.maxHeight < 600,
                                              ),
                                        );
                                      }
                                      final compact = c.maxHeight < 640;
                                      return AnimatedBuilder(
                                        animation: _lyricsProgress,
                                        builder: (context, _) {
                                          final l = _lyricsProgress.value;
                                          return Column(
                                            children: [
                                              ClipRect(
                                                child: Align(
                                                  heightFactor: 1 - l,
                                                  alignment:
                                                      Alignment.topCenter,
                                                  child: IgnorePointer(
                                                    ignoring: _showLyrics,
                                                    child: Opacity(
                                                      opacity: 1 - l,
                                                      child: _spaceHidden(
                                                        _topBar(
                                                          song,
                                                          isCasting,
                                                          diagnostics,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: SizedBox.expand(
                                                  key: _spacePanelKey,
                                                  child: _panelStage(
                                                    song,
                                                    compact,
                                                    fullCover: fullCover,
                                                  ),
                                                ),
                                              ),
                                              // Keep the timeline anchor painted in Space mode.
                                              CompositedTransformTarget(
                                                link: _seekbarSubtitleLink,
                                                child: _spaceHidden(_seekRow()),
                                              ),
                                              // The timeline sits above the transport pads,
                                              // rather than being visually glued to them.
                                              SizedBox(
                                                height: compact ? 12 : 24,
                                              ),
                                              SizedBox(
                                                height: lerpDouble(
                                                  compact ? 6 : 10,
                                                  6,
                                                  l,
                                                ),
                                              ),
                                              _spaceHidden(
                                                _transport(compact, l),
                                              ),
                                              ClipRect(
                                                child: Align(
                                                  heightFactor: 1 - l,
                                                  alignment:
                                                      Alignment.topCenter,
                                                  child: IgnorePointer(
                                                    ignoring: _showLyrics,
                                                    child: Opacity(
                                                      opacity: 1 - l,
                                                      child: Padding(
                                                        padding:
                                                            EdgeInsets.only(
                                                              top: compact
                                                                  ? 13
                                                                  : 17,
                                                            ),
                                                        child: _spaceHidden(
                                                          _optionsStrip(),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                height: compact ? 13 : 17,
                                              ),
                                              _spaceHidden(_chipRow()),
                                            ],
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_spaceLayerMounted)
                        Positioned.fill(
                          child: SpaceCoverBloomReveal(
                            coverRect: _spaceCoverRect,
                            coverRectResolver: () =>
                                _spaceArtworkBounds(_spaceFullCover),
                            coverMotion: _spaceCoverMotion,
                            coverCornerRadiusResolver:
                                _spaceArtworkCornerRadius,
                            canvasMode: _spaceCanvasMode,
                            coverCornerRadius: _spaceFullCover ? 0 : 20,
                            surfaceColor: colors.last,
                            progress: _spaceProgress,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                SeekbarAlignedSpaceSubtitle(
                                  seekbarLink: _seekbarSubtitleLink,
                                  subtitle: _videoActive
                                      ? ValueListenableBuilder<bool>(
                                          valueListenable: _videoController
                                              .timingAvailableNotifier,
                                          builder: (context, native, _) =>
                                              native
                                              ? _spaceSubtitle(song)
                                              : const Text(
                                                  'Waiting for video timing',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                        )
                                      : _spaceSubtitle(song),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_spaceLayerMounted)
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring: !_immersiveLyrics,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _toggleImmersiveLyrics,
                              onLongPress: _showSpaceOptions,
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _embeddedVideoSpace(Song song, String videoId) => VideoSpaceLayout(
    player: Media3MusicVideoSurface(
      key: _videoSurfaceKey,
      videoId: videoId,
      controller: _videoController,
      maxVideoHeight: ref.watch(videoQualityProvider),
      showControls: false,
    ),
    subtitles: ValueListenableBuilder<bool>(
      valueListenable: _videoController.timingAvailableNotifier,
      builder: (_, available, __) => available
          ? _spaceSubtitle(song)
          : Text(
              lokalText('Waiting for video timing'),
              style: const TextStyle(color: FullPlayerVisuals.secondaryText),
            ),
    ),
    onExit: _toggleImmersiveLyrics,
    onOptions: _showSpaceOptions,
  );

  Widget _spaceSubtitle(Song song) => ImmersiveLyricsSubtitle(
    key: ValueKey('space-subtitles:${song.id}'),
    lyrics: _lyricsForSongId == song.id ? (_sublineLyrics ?? _lyrics) : null,
    position: _videoActive
        ? _videoController.positionNotifier
        : _player.positionNotifier,
    playing: _videoActive
        ? _videoController.advancingNotifier
        : _player.isPlayingNotifier,
    playbackSpeed: _videoActive ? null : _player.playbackSpeedNotifier,
    loading: _lyricsLoading || _lyricsForSongId != song.id,
  );

  Widget _spaceHidden(Widget child) => IgnorePointer(
    ignoring: _immersiveLyrics,
    child: FadeTransition(opacity: _spaceChromeOpacity, child: child),
  );

  // ───────────────────────────── top bar ─────────────────────────────

  Widget _topBar(
    Song song,
    bool isCasting,
    AudioOutputDiagnostics? diagnostics,
  ) {
    final castName = ref.watch(activeCastDeviceProvider)?.name.trim();
    final label = isCasting && castName != null && castName.isNotEmpty
        ? castName
        : diagnostics?.outputDeviceLabel.trim().isNotEmpty == true
        ? diagnostics!.outputDeviceLabel.trim()
        : diagnostics?.routeLabel.trim().isNotEmpty == true
        ? diagnostics!.routeLabel.trim()
        : l10n.thisDevice;
    final route = diagnostics?.routeType.toLowerCase() ?? '';
    // Android reports 'bluetooth' for multiple physical device classes.
    // Prefer the output's actual product name instead of a connection icon.
    final deviceName = [
      diagnostics?.outputDeviceLabel ?? '',
      diagnostics?.routeLabel ?? '',
    ].join(' ').toLowerCase();
    final isSpeaker = RegExp(
      r'speaker|soundbar|boombox|homepod|soundlink|flip |charge |boom ',
    ).hasMatch(deviceName);
    final isHeadset = RegExp(
      r'earbud|earphone|airpod|buds|headphone|headset|freebuds|tws|'
      r'wh-|wf-|quietcomfort|momentum|tour pro|fokus',
    ).hasMatch(deviceName);
    final outputIcon = isCasting
        ? LucideIcons.cast
        : route == 'internal' || route == 'speaker'
        ? LucideIcons.speaker
        : route == 'bluetooth'
        ? isSpeaker
              ? LucideIcons.speaker
              : isHeadset
              ? LucideIcons.headphones
              : LucideIcons.bluetooth
        : route == 'usb' || route == 'dock'
        ? LucideIcons.usb
        : LucideIcons.headphones;
    final displayLabel = isCasting
        ? label
        : route == 'internal' || route == 'speaker'
        ? lokalText('Speaker')
        : label == 'Device DAC'
        ? lokalText('Speaker')
        : label;
    // Only full-bleed artwork is directly behind the header. The regular
    // player and tablet columns retain their dark gradient backgrounds.
    final fullCoverBehindHeader = ref.watch(
      lokalAppearanceProvider.select((look) => look.fullscreenCover),
    ) && !LokalLayout.isLandscapeTablet(context);
    final dominantArtwork = ref.watch(albumDominantColorSyncProvider);
    final brightArtwork = fullCoverBehindHeader &&
        dominantArtwork != null &&
        dominantArtwork.computeLuminance() >= .18;
    return FullPlayerHeader(
      deviceLabel: displayLabel,
      brightArtwork: brightArtwork,
      outputIcon: outputIcon,
      song: song,
      onClose: _close,
      onOutput: () => unawaited(PlaybackOutputPicker.show(context)),
      onMore: () => unawaited(_openMore(song)),
    );
  }

  Widget _pill({
    required Widget child,
    VoidCallback? onTap,
    bool selected = false,
    bool compact = false,
  }) {
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: FullPlayerVisuals.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 12,
            vertical: 9,
          ),
          child: child,
        ),
      ),
    );
  }

  // ───────────────────────────── artwork / lyrics ─────────────────────────────

  Widget _fullscreenArtwork(Song song) {
    final motion = _motionEnabled(song);
    return AnimatedBuilder(
      animation: Listenable.merge([_queueProgress, _lyricsProgress]),
      builder: (context, _) {
        final progress =
            (_lyricsProgress.value +
                    _queueProgress.value * (1 - _lyricsProgress.value))
                .clamp(0.0, 1.0);
        return IgnorePointer(
          ignoring: _showLyrics || _queue.engaged,
          child: Opacity(
            opacity: 1 - progress,
            child: TickerMode(
              enabled: progress < 1,
              child: ValueListenableBuilder<List<Song>>(
                valueListenable: _player.upNextNotifier,
                builder: (context, _, __) => ValueListenableBuilder<int>(
                  valueListenable: _player.currentIndexNotifier,
                  builder: (context, _, __) => SongStageCarousel(
                    key: _carouselKey,
                    currentSong: song,
                    nextSong: _player.peekNext,
                    prevSong: _player.peekPrevious,
                    buttonDissolve: true,
                    maskOutgoingOnDissolve: true,
                    animateButtonDissolve:
                        ref.watch(appPreferencesProvider).animationsEnabled &&
                        !LokalPerformanceScope.of(context),
                    enabled:
                        progress == 0 &&
                        !_showLyrics &&
                        !_queue.isOpen &&
                        !_immersiveLyrics &&
                        !_usesEmbeddedVideo,
                    onDragStateChanged: (value) {
                      _carouselDragging = value;
                      if (value) _restoreCanvasControls();
                    },
                    onNext: _player.next,
                    onPrevious: _player.previousBySwipe,
                    stageBuilder: (track) {
                      final current = track.id == song.id;
                      final still = PlayerArtworkImage(
                        song: track,
                        radius: 0,
                        crossfade: false,
                        onArtworkRecovered: current
                            ? (cover) => _player.recoverCurrentOnlineArtwork(
                                songId: track.id,
                                originalArtwork: track.albumArt,
                                recoveredArtwork: cover,
                              )
                            : null,
                      );
                      Widget frame(Widget artwork, bool canvas) {
                        if (current) _reportCanvas(track.id, canvas);
                        return AnimatedBuilder(
                          animation: _canvasChrome,
                          child: artwork,
                          builder: (context, child) => FullBleedArtworkFrame(
                            canvas: canvas,
                            morphEnabled: current,
                            controlsOpacity: canvas ? _canvasChrome.value : 1,
                            bannerBottom: _posterBottom,
                            child: child!,
                          ),
                        );
                      }

                      // Remove the video subtree entirely when disabled; a
                      // retained platform texture must not cover the poster.
                      // Reuse the fullscreen-cover slot for video. Do not
                      // create another page or discard the original artwork
                      // preferences when entering/exiting Video.
                      final content =
                          current &&
                              _videoActive &&
                              track.id ==
                                  (_videoOverrideSong ?? widget.videoSong)?.id
                          ? frame(
                              ColoredBox(
                                color: Colors.black,
                                child: Media3MusicVideoSurface(
                                  key: _videoSurfaceKey,
                                  videoId: _activeVideoId!,
                                  controller: _videoController,
                                  maxVideoHeight: ref.watch(
                                    videoQualityProvider,
                                  ),
                                  showControls: false,
                                  onFullscreen: _immersiveLyrics
                                      ? null
                                      : _toggleVideoFullscreen,
                                ),
                              ),
                              false,
                            )
                          : current && motion
                          ? ValueListenableBuilder<bool>(
                              valueListenable: _player.isPlayingNotifier,
                              builder: (context, playing, _) => MotionArtView(
                                sharedPlaybackKey: 'player:${track.id}',
                                onFrame: (frame) => _motionFrames.update('player:${track.id}', frame),
                                presentationBuilder: (
                                  context,
                                  artwork,
                                  canvas,
                                ) => frame(artwork, canvas),
                                title: track.title,
                                artist: track.artist,
                                album: track.album,
                                duration: track.duration,
                                playbackActive: progress < 1 && playing,
                                borderRadius: BorderRadius.zero,
                                fallback: still,
                              ),
                            )
                          : frame(still, false);
                      final shownBurst = _burst;
                      return GestureDetector(
                        onDoubleTap: current && !_usesEmbeddedVideo
                            ? _likeFromArtwork
                            : null,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            HeroMode(
                              enabled: current,
                              child: Hero(
                                tag: widget.heroTag,
                                createRectTween: (begin, end) =>
                                    LokalArtworkRectTween(
                                      begin: begin,
                                      end: end,
                                    ),
                                flightShuttleBuilder: (
                                  _,
                                  __,
                                  ___,
                                  ____,
                                  _____,
                                ) => content,
                                child: content,
                              ),
                            ),
                            if (current && _burstVisible && !_usesEmbeddedVideo)
                              Center(
                                child: LokalLikeBurst(
                                  key: ValueKey(_burst),
                                  color: context.lokal.accent,
                                  size: MediaQuery.sizeOf(context).width * .28,
                                  onDone: () {
                                    if (mounted && shownBurst == _burst)
                                      setState(() => _burstVisible = false);
                                  },
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _fullPlayerAudioLabel(Song song, LokalQualityTier tier) {
    final preferResolution = ref.watch(
      lokalAppearanceProvider.select(
        (appearance) => appearance.resolutionTagsInFullPlayer,
      ),
    );
    if (preferResolution) {
      final resolution = lokalSongResolutionLabel(song);
      if (resolution != null) return resolution;
    }
    return switch (tier) {
      LokalQualityTier.hiRes => 'HI-RES LOSSLESS',
      LokalQualityTier.lossless => 'LOSSLESS',
      LokalQualityTier.high => 'HIGH',
      LokalQualityTier.low => 'LOW',
      LokalQualityTier.unknown =>
        (song.sourcePackage == 'konnekted.progressive' ||
                song.sourcePackage == 'konnekted.morneye-live')
            ? (catalogueStreamTierLabel(
                    quality: song.resolution,
                    codec: song.fileType,
                    bitDepth: song.bitDepth,
                    sampleRate: song.sampleRate,
                  ) ??
                  'UNKNOWN')
            : 'UNKNOWN',
    };
  }

  /// Landscape tablets give artwork and the transport their own columns.
  /// The existing panel still owns lyrics, queue, carousel and their gestures.
  Widget _tabletPlayerChrome(
    Song song,
    bool isCasting,
    AudioOutputDiagnostics? diagnostics, {
    required bool fullCover,
    bool fillCover = false,
    required bool compact,
  }) {
    return LokalPlayerColumns(
      preferColumns: true,
      key: fillCover ? const ValueKey('tablet-square-cover-player') : null,
      fillCover: fillCover,
      header: _spaceHidden(_topBar(song, isCasting, diagnostics)),
      stage: SizedBox.expand(
        key: _spacePanelKey,
        child: _panelStage(
          song,
          compact,
          fullCover: fullCover,
          tabletCover: fillCover,
          identityInControls: true,
        ),
      ),
      controls: LokalPlayerControls(
        compact: compact,
        heading: _spaceHidden(
          Text(
            lokalText('Now playing').toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 2,
              color: FullPlayerVisuals.secondaryText,
            ),
          ),
        ),
        identity: _panelIdentity(song, compact, 0),
        timeline: CompositedTransformTarget(
          link: _seekbarSubtitleLink,
          child: _spaceHidden(_seekRow()),
        ),
        transport: _spaceHidden(_transport(compact, _lyricsProgress.value)),
        options: _spaceHidden(_optionsStrip()),
        footer: _spaceHidden(_chipRow()),
      ),
    );
  }

  Widget _panelStage(
    Song song,
    bool compact, {
    bool fullCover = false,
    bool tabletCover = false,
    bool identityInControls = false,
  }) {
    final separateIdentity = tabletCover || identityInControls;
    _spacePanelCompact = compact;
    _spacePanelTabletCover = separateIdentity;
    return LayoutBuilder(
      builder: (context, c) {
        _queue.travel = math.max(math.min(c.maxWidth, c.maxHeight) * .8, 200);
        return PlayerPanelStage(
          queueProgress: _queueProgress,
          lyricsProgress: _lyricsProgress,
          queueOpen: _queue.isOpen,
          lyricsOpen: _showLyrics,
          artGap: separateIdentity
              ? 0
              : compact
              ? 10
              : 17,
          infoReserve: separateIdentity
              ? 72 *
                    (_lyricsProgress.value + _queueProgress.value).clamp(
                      0.0,
                      1.0,
                    )
              : 72,
          onQueueHeaderTap: () => _setQueueOpen(false),
          onLyricsCoverReturn: _toggleLyrics,
          onQueueHeaderDrag: _queue.dragBy,
          onQueueHeaderRelease: _releaseQueue,
          artwork: (context, size, p) {
            if (fullCover) {
              // The poster owns the single Hero and carousel in this mode.
              // Only reveal the compact cover while entering lyrics/queue.
              if (p == 0) {
                _measurePoster();
                return SizedBox.expand(key: _posterAnchorKey);
              }
              return IgnorePointer(
                child: HeroMode(
                  enabled: false,
                  child: Opacity(
                    opacity: p,
                    child: _artwork(
                      song,
                      size,
                      current: !_videoActive,
                      progress: p,
                    ),
                  ),
                ),
              );
            }
            final atRest =
                p == 0 && !_queue.isOpen && !_showLyrics && !_immersiveLyrics;
            return ValueListenableBuilder<List<Song>>(
              valueListenable: _player.upNextNotifier,
              builder: (context, _, __) => ValueListenableBuilder<int>(
                valueListenable: _player.currentIndexNotifier,
                builder: (context, _, __) => SongStageCarousel(
                  key: _carouselKey,
                  currentSong: song,
                  nextSong: _player.peekNext,
                  prevSong: _player.peekPrevious,
                  buttonDissolve: true,
                  animateButtonDissolve:
                      ref.watch(appPreferencesProvider).animationsEnabled &&
                      !LokalPerformanceScope.of(context),
                  enabled: atRest,
                  // Match the reference: a slim gutter separates neighbouring
                  // covers while the regular (non-Fullcover) artwork is swiped.
                  // The fullscreen poster carousel keeps its edge-to-edge slide.
                  coverGap: 16,
                  onDragStateChanged: (v) => _carouselDragging = v,
                  onNext: _player.next,
                  onPrevious: _player.previousBySwipe,
                  stageBuilder: (s) => Align(
                    alignment: Alignment.center,
                    child: _artwork(
                      s,
                      size,
                      current: s.id == song.id,
                      progress: p,
                    ),
                  ),
                ),
              ),
            );
          },
          info: (context, p) => separateIdentity && p == 0
              ? const SizedBox.shrink()
              : _panelIdentity(song, compact, p, anchor: !separateIdentity),
          queue: const QueueList(embedded: true),
          lyrics: _lyricsArea(song),
        );
      },
    );
  }

  Widget _panelIdentity(
    Song song,
    bool compact,
    double p, {
    bool anchor = true,
  }) {
    final titleSize = compact ? 25.0 : 29.0;
    return _spaceHidden(
      SizedBox(
        key: anchor ? _infoAnchorKey : null,
        width: double.infinity,
        child: AnimatedSwitcher(
          duration: _animate
              ? const Duration(milliseconds: 420)
              : Duration.zero,
          // Keep both tracks anchored to the same origin. AnimatedSwitcher\'s
          // default ScaleTransition subtly moves title, credits and quality
          // pill as their intrinsic widths differ between providers.
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topLeft,
            children: [...previous, if (current != null) current],
          ),
          child: FullPlayerIdentityLayout(
            key: ValueKey(song.id),
            titleFontSize: lerpDouble(titleSize, 18, p)!,
            titleToArtistGap: lerpDouble(3, 1, p)!,
            title: Semantics(
              button: true,
              label: 'Open album for ${song.title}',
              child: InkWell(
                onTap: () => openLokalAlbumForSong(context, song),
                borderRadius: BorderRadius.circular(8),
                child: OverflowMarqueeTitle(
                  key: ValueKey('full-title:${song.id}'),
                  title: song.title,
                  style: TextStyle(
                    fontFamily: _font,
                    fontSize: lerpDouble(titleSize, 18, p),
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.55,
                    color: FullPlayerVisuals.primaryText,
                  ),
                ),
              ),
            ),
            artist: ArtistCreditLinks(
              credit: song.artist,
              onArtistTap: (name) =>
                  openLokalArtist(context, name: name, song: song),
              style: TextStyle(
                fontFamily: _font,
                fontSize: lerpDouble(13, 12, p),
                fontWeight: FontWeight.w500,
                color: FullPlayerVisuals.secondaryText,
              ),
            ),
            trailing: [
              if (song.year != null && song.year! > 0) ...[
                const _MetadataDot(),
                Text(
                  '${song.year}',
                  style: TextStyle(
                    fontFamily: _font,
                    fontSize: lerpDouble(11, 10, p),
                    color: FullPlayerVisuals.tertiaryText,
                  ),
                ),
              ],
              if (_videoActive) ...[
                const SizedBox(width: 12),
                Text(
                  lokalText('Video').toUpperCase(),
                  style: const TextStyle(
                    fontFamily: _font,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: FullPlayerVisuals.secondaryText,
                    letterSpacing: .6,
                  ),
                ),
              ],
              if (!_videoActive && song.atmosEncoded) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => SongMetadataSheet.show(context, song),
                  child: const LokalAtmosStreamPill(),
                ),
              ],
              if (LokalQualityTier.of(song) case final tier?
                  when !_videoActive && !song.atmosEncoded) ...[
                const SizedBox(width: 12),
                InkWell(
                  onTap: () => SongMetadataSheet.show(context, song),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: FullPlayerVisuals.secondaryText,
                      ),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Tooltip(
                      message: _fullPlayerAudioLabel(song, tier),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: (MediaQuery.sizeOf(context).width * .52)
                              .clamp(110.0, 210.0)
                              .toDouble(),
                        ),
                        child: Text(
                          _fullPlayerAudioLabel(song, tier),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: _font,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .6,
                            color: FullPlayerVisuals.primaryText,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _artwork(
    Song song,
    double side, {
    required bool current,
    double progress = 0,
  }) {
    final prefs = ref.watch(appPreferencesProvider);
    final radius = BorderRadius.circular(lerpDouble(20, 12, progress)!);
    final still = PlayerArtworkImage(
      song: song,
      radius: radius.topLeft.x,
      crossfade: false,
      onArtworkRecovered: current
          ? (cover) => _player.recoverCurrentOnlineArtwork(
              songId: song.id,
              originalArtwork: song.albumArt,
              recoveredArtwork: cover,
            )
          : null,
    );
    final motionEnabled =
        current &&
        prefs.animatedAlbumArt &&
        prefs.animationsEnabled &&
        !ref
            .watch(movingCoverSettingsProvider)
            .disabledSongs
            .contains(movingCoverSongKey(song));
    // Video occupies the exact same cover slot; the full player, queue,
    // Canvas settings and Space all stay on their original surfaces.
    final showVideo =
        current &&
        _videoActive &&
        song.id == (_videoOverrideSong ?? widget.videoSong)?.id;
    Widget art = showVideo
        ? ClipRRect(
            borderRadius: _usesEmbeddedVideo ? BorderRadius.zero : radius,
            child: ColoredBox(
              color: Colors.black,
              child: Media3MusicVideoSurface(
                key: _videoSurfaceKey,
                videoId: _activeVideoId!,
                controller: _videoController,
                maxVideoHeight: ref.watch(videoQualityProvider),
                showControls: false,
                onFullscreen: _immersiveLyrics ? null : _toggleVideoFullscreen,
              ),
            ),
          )
        : ClipRRect(
            borderRadius: radius,
            child: ValueListenableBuilder<bool>(
              valueListenable: _player.isPlayingNotifier,
              builder: (context, playing, _) => MotionArtView(
                sharedPlaybackKey: 'player:${song.id}',
                onFrame: (frame) => _motionFrames.update('player:${song.id}', frame),
                title: song.title,
                artist: song.artist,
                album: song.album,
                duration: song.duration,
                enabled: motionEnabled,
                playbackActive: current && progress < .999 && playing,
                borderRadius: radius,
                fallback: still,
              ),
            ),
          );
    if (showVideo && LokalLayout.isLandscapeTablet(context)) {
      art = PlayerVideoFrame(child: art);
    }
    final shown = _burst;
    return GestureDetector(
      onDoubleTap: current && progress == 0 && !_usesEmbeddedVideo
          ? _likeFromArtwork
          : null,
      child: LokalPlayerArtwork(
        enabled: current && !_usesEmbeddedVideo,
        expandedRadius: lerpDouble(20, 12, progress)!,
        child: SizedBox(
          width: side,
          height: side,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: HeroMode(
                  enabled: current,
                  child: Hero(
                    tag: widget.heroTag,
                    createRectTween: (begin, end) =>
                        LokalArtworkRectTween(begin: begin, end: end),
                    flightShuttleBuilder:
                        (
                          flightContext,
                          animation,
                          direction,
                          fromContext,
                          toContext,
                        ) => AnimatedBuilder(
                          animation: animation,
                          builder: (context, child) => ClipRRect(
                            borderRadius: _usesEmbeddedVideo
                                ? BorderRadius.zero
                                : BorderRadius.circular(
                                    lerpDouble(
                                      21,
                                      20,
                                      Curves.easeInOutCubic.transform(
                                        animation.value,
                                      ),
                                    )!,
                                  ),
                            child: child,
                          ),
                          child: art,
                        ),
                    child: art,
                  ),
                ),
              ),
              if (current && _burstVisible && !_usesEmbeddedVideo)
                LokalLikeBurst(
                  key: ValueKey(_burst),
                  color: context.lokal.accent,
                  size: side * .28,
                  onDone: () {
                    if (mounted && shown == _burst) {
                      setState(() => _burstVisible = false);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lyricsArea(Song song) {
    final data = _lyrics;
    final display = _sublineLyrics ?? data;
    Widget body;
    if (_lyricsLoading && data == null) {
      body = const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.white70,
          ),
        ),
      );
    } else if (data == null || data.lines.isEmpty) {
      body = _noLyrics(song);
    } else if (!data.isSynchronized) {
      body = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 24, 0, 40),
        child: Text(
          display!.lines
              .map(
                (l) =>
                    _sublineLyrics != null && l.translation?.isNotEmpty == true
                    ? '${l.text}\n${l.translation}'
                    : l.text,
              )
              .join('\n'),
          style: const TextStyle(
            fontFamily: _font,
            fontSize: 26,
            height: 1.35,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      );
    } else {
      body = _FlowingLyrics(
        key: ValueKey(song.id),
        player: _player,
        lyrics: display!,
        showTranslation: _sublineLyrics != null,
      );
    }

    return Column(
      key: const ValueKey('lyrics'),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Lyrics',
                style: TextStyle(
                  fontFamily: _font,
                  fontSize: 13,
                  letterSpacing: 0.6,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),
            if (data != null && hasUsableLyrics(data))
              LyricsSaveButton(
                key: const ValueKey('save-current-lyrics-file'),
                saving: _savingLyricsFile,
                iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
                onSaveOriginal: () => unawaited(_saveLyricsFile(song, data)),
                onSaveWithTranslation: _saveTranslatedLyricsAction(song),
              ),
            if (hasImmersiveLyrics(data))
              IconButton(
                tooltip: 'Space — immersive lyrics',
                icon: const Icon(
                  LucideIcons.expand,
                  color: Colors.white70,
                  size: 19,
                ),
                onPressed: _toggleImmersiveLyrics,
              ),
            LyricsSourceButton(
              selected: _lyricsSource,
              lyrics: data,
              song: song,
              lyricsService: _lyricsService,
              busy: _lyricsLoading,
              onSelected: (source) {
                setState(() => _lyricsSource = source);
                unawaited(_loadLyrics(force: true));
              },
              onRefresh: () =>
                  unawaited(_loadLyrics(force: true, refreshOnline: true)),
            ),
            if (data != null)
              LyricsSublineButtons(
                lyrics: data,
                onChanged: (value) => setState(() => _sublineLyrics = value),
              ),
            IconButton(
              tooltip: 'Search online',
              icon: const Icon(
                LucideIcons.search,
                size: 20,
                color: Colors.white70,
              ),
              onPressed: () => _searchOnline(song),
            ),
          ],
        ),
        Expanded(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0.0, 0.07, 0.9, 1.0],
            ).createShader(r),
            child: body,
          ),
        ),
      ],
    );
  }

  Widget _noLyrics(Song song) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No lyrics found',
            style: TextStyle(
              fontFamily: _font,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: () => _searchOnline(song),
            icon: const Icon(LucideIcons.search, size: 18),
            label: const Text('Search online'),
          ),
        ],
      ),
    );
  }

  Future<void> _searchOnline(Song song) async {
    final result = await OnlineLyricsSearchSheet.show(
      context: context,
      song: song,
      lyricsService: _lyricsService,
    );
    if (result == true && mounted) await _loadLyrics(force: true);
  }

  String _clock(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$sec' : '$m:$sec';
  }

  Widget _seekRow() {
    const mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: FullPlayerVisuals.tertiaryText,
    );
    return ValueListenableBuilder<Duration>(
      valueListenable: _videoActive
          ? _videoController.durationNotifier
          : _player.durationNotifier,
      builder: (context, duration, _) {
        final totalMs = math.max(duration.inMilliseconds, 1).toDouble();
        return ValueListenableBuilder<Duration>(
          valueListenable: _videoActive
              ? _videoController.positionNotifier
              : _player.positionNotifier,
          builder: (context, position, _) {
            final live = (position.inMilliseconds / totalMs).clamp(0.0, 1.0);
            final value = _draggingSeek ? _seekDrag : live;
            return Column(
              children: [
                FullPlayerSeekBar(
                  style: ref.watch(progressBarStyleProvider),
                  peaks:
                      !_videoActive &&
                          ref.watch(progressBarStyleProvider) ==
                              ProgressBarStyle.waveform &&
                          _player.currentSongNotifier.value != null
                      ? ref
                            .watch(
                              fullPlayerWaveformProvider(
                                _player.currentSongNotifier.value!,
                              ),
                            )
                            .asData
                            ?.value
                      : null,
                  value: value,
                  onChangeStart:
                      _videoActive &&
                          !_videoController.timingAvailableNotifier.value
                      ? null
                      : (v) => setState(() {
                          _draggingSeek = true;
                          _seekDrag = v;
                        }),
                  onChanged:
                      _videoActive &&
                          !_videoController.timingAvailableNotifier.value
                      ? null
                      : (v) => setState(() => _seekDrag = v),
                  onChangeEnd: (v) async {
                    // One double-pulse on release, not on continuous drag updates.
                    AppHaptics.doublePulse();
                    final id = _player.currentSongNotifier.value?.id;
                    try {
                      final target = Duration(
                        milliseconds: (v * totalMs).round(),
                      );
                      if (_videoActive) {
                        await _videoCommand(
                          () => _videoController.seek(target),
                        );
                      } else {
                        await _player.seek(target);
                      }
                    } finally {
                      if (mounted &&
                          _player.currentSongNotifier.value?.id == id &&
                          _seekDrag == v)
                        setState(() => _draggingSeek = false);
                    }
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _clock(
                          Duration(milliseconds: (value * totalMs).round()),
                        ),
                        style: mono,
                      ),
                      Text(_clock(duration), style: mono),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _transport(
    bool compact,
    double lyricsProgress,
  ) => ValueListenableBuilder<bool>(
    valueListenable: _videoActive
        ? _videoController.playingNotifier
        : _player.isPlayingNotifier,
    builder: (context, playing, _) => PlayerTransportControls(
      compact: compact,
      tallerButtons: true,
      lyricsProgress: lyricsProgress,
      playing: playing,
      accent: FullPlayerVisuals.fromPalette(ref.watch(albumPaletteSyncProvider))
          .play,
      onAccent: Colors.black,
      onPrevious: () async {
        if (_videoActive) {
          if (widget.videoSong != null) {
            _close();
          } else {
            if (await _exitVideoMode(resumeAudio: false))
              await _player.previousBySwipe();
          }
          return;
        }
        if (shouldRestartCurrentTrackOnPrevious(
          _player.positionNotifier.value,
        )) {
          await _player.previous();
        } else {
          _carouselKey.currentState?.animateToPrevious() ?? _player.previous();
        }
      },
      onNext: () async {
        if (_videoActive) {
          if (widget.videoSong != null) {
            _close();
          } else {
            if (await _exitVideoMode(resumeAudio: false)) await _player.next();
          }
          return;
        }
        _carouselKey.currentState?.animateToNext() ?? _player.next();
      },
      onPlayPause: () {
        if (_videoActive) {
          unawaited(_videoCommand(_videoController.togglePlayPause));
        } else {
          _player.togglePlayPause();
        }
      },
    ),
  );

  Widget _optionsStrip() => ListenableBuilder(
    listenable: _volumeControl,
    builder: (context, _) => _buildOptionsStrip(),
  );

  Widget _buildOptionsStrip() {
    if (_videoActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: FullPlayerVisuals.border),
        ),
        child: Row(
          children: [
            const Icon(
              LucideIcons.volume2,
              size: 18,
              color: FullPlayerVisuals.secondaryText,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                lokalText('Use device volume buttons'),
                style: const TextStyle(
                  fontFamily: _font,
                  fontSize: 12,
                  color: FullPlayerVisuals.secondaryText,
                ),
              ),
            ),
            _toggle(
              _displayedFavorite ? Icons.favorite : Icons.favorite_border,
              _displayedFavorite,
              _toggleFavorite,
            ),
          ],
        ),
      );
    }
    final maxVol = _volumeControl.max;
    final sliderValue = (_draggingVolume ? _volume : _volumeControl.value)
        .clamp(0.0, maxVol)
        .toDouble();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: FullPlayerVisuals.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                trackShape: const GappedSliderTrackShape(),
                trackGap: 5,
                thumbShape: const MaterialPlayerThumb(),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: sliderValue,
                min: 0,
                max: maxVol,
                onChangeStart: (_) => setState(() => _draggingVolume = true),
                onChanged: !_volumeControl.available
                    ? null
                    : (v) {
                        setState(() => _volume = v);
                        unawaited(_volumeControl.set(v));
                      },
                onChangeEnd: (_) => setState(() => _draggingVolume = false),
              ),
            ),
          ),
          const SizedBox(width: 13),
          Icon(
            sliderValue <= 0.001 ? LucideIcons.volumeX : LucideIcons.volume2,
            size: 18,
            color: FullPlayerVisuals.secondaryText,
          ),
          const SizedBox(width: 18),
          Container(width: 1, height: 26, color: FullPlayerVisuals.border),
          const SizedBox(width: 10),
          ValueListenableBuilder<ShuffleMode>(
            valueListenable: _player.shuffleModeNotifier,
            builder: (_, mode, __) => _toggle(
              LucideIcons.shuffle,
              mode.isActive,
              () => _player.toggleShuffle(),
              onLong: () => ShuffleModeSheet.show(context, _player),
            ),
          ),
          ValueListenableBuilder<LoopMode>(
            valueListenable: _player.loopModeNotifier,
            builder: (_, mode, __) => _toggle(
              mode == LoopMode.one ? LucideIcons.repeat1 : LucideIcons.repeat,
              mode != LoopMode.off,
              () => _player.toggleLoopMode(),
              onLong: () => LoopModeSheet.show(context, _player),
            ),
          ),
          _toggle(
            _isFav ? Icons.favorite : Icons.favorite_border,
            _isFav,
            _toggleFavorite,
          ),
        ],
      ),
    );
  }

  Widget _toggle(
    IconData icon,
    bool on,
    VoidCallback onTap, {
    VoidCallback? onLong,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: on ? FullPlayerVisuals.selectedSurface : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          onLongPress: onLong,
          child: SizedBox(
            width: 36,
            height: 40,
            child: Icon(
              icon,
              size: 19,
              color: on
                  ? FullPlayerVisuals.primaryText
                  : FullPlayerVisuals.secondaryText,
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────────── chips ─────────────────────────────

  Widget _chipRow() {
    Widget chip(
      IconData icon,
      String label,
      VoidCallback onTap, {
      bool active = false,
      double? width,
      String? semanticLabel,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: 2),
        child: Semantics(
          button: true,
          label: semanticLabel ?? label,
          selected: active,
          onTap: onTap,
          excludeSemantics: true,
          child: SizedBox(
            width: width,
            child: _pill(
              selected: active,
              compact: true,
              onTap: onTap,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 19,
                    color: active
                        ? FullPlayerVisuals.primaryText
                        : FullPlayerVisuals.secondaryText,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: _font,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: FullPlayerVisuals.primaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height:
            44 +
            (MediaQuery.textScalerOf(context).scale(12) - 12).clamp(0, 24) *
                1.4,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            chip(
              LucideIcons.listMusic,
              l10n.queue,
              _toggleQueue,
              active: _queue.isOpen && !_showLyrics,
              width: (constraints.maxWidth - 8) / 4,
            ),
            chip(
              LucideIcons.messageSquareQuote,
              l10n.lyrics,
              _toggleLyrics,
              active: _showLyrics,
              width: (constraints.maxWidth - 8) / 4,
            ),
            if (_lyricsForSongId ==
                    ((_videoActive
                                ? (_videoOverrideSong ?? widget.videoSong)
                                : null) ??
                            _player.currentSongNotifier.value)
                        ?.id &&
                hasImmersiveLyrics(_lyrics))
              chip(
                LucideIcons.expand,
                'Space',
                _toggleImmersiveLyrics,
                active: _immersiveLyrics,
                width: (constraints.maxWidth - 8) / 4,
              ),
            if (_videoOverrideId != null)
              chip(
                LucideIcons.disc3,
                'Audio',
                _exitVideoMode,
                active: true,
                width: (constraints.maxWidth - 8) / 4,
              )
            else if (ref.watch(musicVideosEnabledProvider))
              if (_player.currentSongNotifier.value case final current?)
                if (ref.watch(musicVideoIndexProvider).videoFor(current.id)
                    case final videoId?)
                  chip(
                    LucideIcons.video,
                    'Video',
                    () => unawaited(_enterVideoMode(current, videoId)),
                    width: (constraints.maxWidth - 8) / 4,
                  ),
            ValueListenableBuilder<Duration?>(
              valueListenable: _player.sleepTimerRemainingNotifier,
              builder: (_, remaining, __) => chip(
                LucideIcons.moonStar,
                remaining == null ? lokalText('Sleep') : _clock(remaining),
                () => SleepTimerBottomSheet.show(context, _player),
                active: remaining != null,
                width: (constraints.maxWidth - 8) / 4,
              ),
            ),
            if (!_videoActive)
              if (_player.currentSongNotifier.value case final song?)
                // Probe all configured motion sources, including Spotify Canvas.
                // A saved per-song "off" setting must not hide this control:
                // it still needs to offer a way to turn the clip back on.
                ListenableBuilder(
                  listenable: Listenable.merge([
                    movingCoverRevision,
                    SecureSpotifyTokenStore.sessionRevision,
                    AnimatedArtworkService.instance.revision,
                    EcoDataMode.revision,
                  ]),
                  builder: (context, _) => Consumer(
                    builder: (context, coverRef, _) {
                      final available = coverRef.watch(
                        movingCoverAvailabilityProvider((
                          title: song.title,
                          artist: song.artist,
                          album: song.album,
                          duration: song.duration,
                          sourceRevision: movingCoverRevision.value,
                          spotifySessionRevision:
                              SecureSpotifyTokenStore.sessionRevision.value,
                          artworkRevision:
                              AnimatedArtworkService.instance.revision.value,
                          networkRevision: EcoDataMode.revision.value,
                        )),
                      );
                      if (available.value != true)
                        return const SizedBox.shrink();
                      final disabled = coverRef
                          .watch(movingCoverSettingsProvider)
                          .disabledSongs
                          .contains(movingCoverSongKey(song));
                      return chip(
                        Icons.motion_photos_on_rounded,
                        lokalText('Cover'),
                        () => coverRef
                            .read(movingCoverSettingsProvider.notifier)
                            .setSongEnabled(movingCoverSongKey(song), disabled),
                        active: !disabled,
                        width: (constraints.maxWidth - 8) / 4,
                      );
                    },
                  ),
                ),
            ValueListenableBuilder<double>(
              valueListenable: _player.playbackSpeedNotifier,
              builder: (_, speed, __) => chip(
                LucideIcons.gauge,
                (speed - 1.0).abs() < 0.01
                    ? l10n.speedUp
                    : '${speed.toStringAsFixed(2)}x',
                () => SpeedBottomSheet.show(context, _player),
                active: (speed - 1.0).abs() >= 0.01,
                width: (constraints.maxWidth - 8) / 4,
              ),
            ),
            ValueListenableBuilder<double>(
              valueListenable: _player.pitchSemitonesNotifier,
              builder: (_, pitch, __) => chip(
                Icons.graphic_eq_rounded,
                pitch.abs() < 0.01
                    ? l10n.pitch
                    : '${pitch > 0 ? '+' : ''}${pitch.toStringAsFixed(0)} st',
                () => PitchBottomSheet.show(context, _player),
                active: pitch.abs() >= 0.01,
                semanticLabel:
                    '${l10n.pitch}: ${l10n.pitchSemitones(pitch.round())}',
                width: (constraints.maxWidth - 8) / 4,
              ),
            ),
            chip(
              LucideIcons.slidersHorizontal,
              l10n.equalizer,
              _openEqualizer,
              width: (constraints.maxWidth - 8) / 4,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataDot extends StatelessWidget {
  const _MetadataDot();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 7),
    child: Text(
      '·',
      style: TextStyle(fontSize: 13, color: FullPlayerVisuals.tertiaryText),
    ),
  );
}

// ═════════════════════════════ backdrop ═════════════════════════════

// ═════════════════════════════ flowing lyrics ═════════════════════════════

/// Continuously flowing synced lyrics.
///
/// * One 60 fps ticker drives everything; playback position is extrapolated
///   between the player's position updates so motion never steps.
/// * The scroll offset chases the active line with a critically damped spring
///   (slightly anticipating the next line), so lines glide instead of jumping.
/// * A second smoothed "focus" value drives per-line scale, opacity and blur,
///   so emphasis flows from line to line.
/// * The active line sweeps word by word (real word timing when the lyrics
///   have it, untimed sources keep line-level focus).
/// * Drag to browse (auto-follow resumes after 3 s), tap a line to seek.
class _FlowingLyrics extends StatefulWidget {
  final PlayerService player;
  final LyricsData lyrics;

  /// Each line's translation under it, when it has one.
  final bool showTranslation;
  const _FlowingLyrics({
    super.key,
    required this.player,
    required this.lyrics,
    this.showTranslation = false,
  });

  @override
  State<_FlowingLyrics> createState() => _FlowingLyricsState();
}

class _FlowingLyricsState extends State<_FlowingLyrics>
    with SingleTickerProviderStateMixin {
  static const double _gap = 26;
  static const double _anchor = 0.28;
  static const double _introHeight = 44;
  static const TextStyle _base = playerLyricStyle;
  static const double _subGap = 6;
  static const TextStyle _backingStyle = TextStyle(
    fontFamily: _font,
    fontSize: 18,
    height: 1.25,
    fontWeight: FontWeight.w600,
    color: Color(0xD9FFFFFF),
  );
  static const TextStyle _sub = TextStyle(
    fontFamily: _font,
    fontSize: 18,
    height: 1.25,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  Duration _lastElapsed = Duration.zero;
  Duration _lastPaintElapsed = Duration.zero;
  bool _ultra = false;

  Duration _anchorPos = Duration.zero;
  DateTime _anchorAt = DateTime.now();
  bool _clockPlaying = false;
  double _clockSpeed = 1;

  // The parser keeps start-only enhanced-LRC words for lossless editing.
  // Resolve their end windows once for painting; never do it on each tick.
  late List<LyricsLine> _playbackLines;
  List<LyricsLine> _backgroundVocalLines = const [];
  List<double> _backgroundVocalHeights = const [];
  final FlowingBackgroundVocalReveal _backingReveal =
      FlowingBackgroundVocalReveal();
  // Project translations/romaji exactly once per source change, never during
  // the frame-driven scroll/reveal loop. Null means line-only or plain lyrics.
  List<LyricsLine?> _timedSublines = const [];
  List<LyricsLine> get _lines => _playbackLines;

  void _prepareLyrics() {
    _backingReveal.reset();
    final resolved = LyricsService().playbackLines(widget.lyrics);
    _backgroundVocalLines = flowingBackgroundVocalLines(resolved);
    final leads = resolved.where((line) => line.voice != 'bg').toList();
    _playbackLines = leads.isEmpty ? resolved : leads;
    _ts = [for (final line in _playbackLines) line.timestamp.inMilliseconds];
    AppLog.instance.add(
      '[LyricsBG] fullscreenRenderer supporting=${_backgroundVocalLines.length} '
      'leadLines=${_playbackLines.length}',
    );
    _timedSublines = [
      for (final line in _playbackLines)
        if (line.words?.isNotEmpty == true &&
            line.translation?.trim().isNotEmpty == true)
          projectLyricsSubline(line, line.translation!.trim())
        else
          null,
    ];
  }

  List<int> _ts = const [];

  List<double> _heights = const [];
  List<double> _baseHeights = const [], _subHeights = const [];
  final _subText = <int, String>{};
  double _sublineReveal = 0;
  LyricsData? _layoutLyrics;
  TextScaler? _layoutScaler;
  Locale? _layoutLocale;
  TextDirection? _layoutDirection;
  List<double> _tops = const [];
  double _w = 0;
  double _h = 0;

  double _offset = 0;
  double _focus = -1;
  bool _needsJump = true;
  bool _following = true;
  Timer? _resume;
  int _active = -1;
  int _posMs = 0;

  @override
  void initState() {
    super.initState();
    _prepareLyrics();
    _anchorPos = widget.player.positionNotifier.value;
    _clockPlaying = widget.player.isPlayingNotifier.value;
    _clockSpeed = widget.player.playbackSpeedNotifier.value;
    widget.player.isPlayingNotifier.addListener(_onClockState);
    widget.player.playbackSpeedNotifier.addListener(_onClockState);
    widget.player.positionNotifier.addListener(_onPosition);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(_FlowingLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.lyrics, oldWidget.lyrics)) {
      for (final line in oldWidget.lyrics.lines) {
        if (line.translation?.isNotEmpty == true)
          _subText[line.timestamp.inMilliseconds] = line.translation!;
      }
      _prepareLyrics();
      _ts = [for (final line in _lines) line.timestamp.inMilliseconds];
      _layoutLyrics = null;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _resume?.cancel();
    widget.player.positionNotifier.removeListener(_onPosition);
    widget.player.isPlayingNotifier.removeListener(_onClockState);
    widget.player.playbackSpeedNotifier.removeListener(_onClockState);
    _frame.dispose();
    super.dispose();
  }

  void _onPosition() {
    final v = widget.player.positionNotifier.value;
    // A big jump means the user sought: glide there instead of snapping.
    _anchorPos = v;
    _anchorAt = DateTime.now();
  }

  void _onClockState() {
    _anchorPos = Duration(milliseconds: _posNowMs());
    _anchorAt = DateTime.now();
    _clockPlaying = widget.player.isPlayingNotifier.value;
    _clockSpeed = widget.player.playbackSpeedNotifier.value;
  }

  int _posNowMs() {
    if (!_clockPlaying) return _anchorPos.inMilliseconds;
    final speed = _clockSpeed;
    final elapsed = DateTime.now()
        .difference(_anchorAt)
        .inMilliseconds
        .clamp(0, 600);
    return _anchorPos.inMilliseconds + (elapsed * speed).round();
  }

  int _indexAt(int ms) =>
      focusedLeadUntilVocalsFinish(_lines, Duration(milliseconds: ms));

  double _centerFor(int a) =>
      a < 0 ? -(_introHeight + _gap) : _tops[a.clamp(0, _tops.length - 1)];

  void _ensureLayout(double w, double h) {
    // A panel transition changes the viewport height every frame, not the
    // shaping width. Keep measured paragraphs and only move their anchor.
    _h = h;
    if ((w - _w).abs() < 0.5 &&
        _heights.length == _lines.length &&
        identical(_layoutLyrics, widget.lyrics) &&
        _layoutScaler == MediaQuery.textScalerOf(context) &&
        _layoutLocale == Localizations.maybeLocaleOf(context) &&
        _layoutDirection == Directionality.of(context)) {
      return;
    }
    _w = w;
    _h = h;
    final hs = <double>[], subs = <double>[];
    for (var i = 0; i < _lines.length; i++) {
      final l = _lines[i];
      double lh;
      var sh = 0.0;
      if (l.text.trim().isEmpty) {
        lh = 30;
      } else {
        lh = LyricMotionLine.height(context, l.text, _base, math.max(w, 40));
        if (_translationOf(l) case final sub?) {
          final sp = LyricMotionLine.layout(
            context,
            sub,
            _sub,
            math.max(w, 40),
          );
          // LyricMotionLine reserves an additional 8 px for glyph motion;
          // include it in scrolling geometry to prevent translated lines
          // clipping or colliding with the following line.
          final hasTimedSubline =
              widget.showTranslation &&
              i < _timedSublines.length &&
              _timedSublines[i]?.text == sub;
          sh = _subGap + sp.height + (hasTimedSubline ? 8 : 0);
          sp.dispose();
        }
      }
      hs.add(lh);
      subs.add(sh);
    }
    _baseHeights = hs;
    _subHeights = subs;
    _backgroundVocalHeights = [
      for (final bg in _backgroundVocalLines)
        _subGap +
            LyricMotionLine.height(
              context,
              bg.text,
              _backingStyle,
              math.max(w, 40),
            ) +
            8,
    ];
    _layoutLyrics = widget.lyrics;
    _layoutScaler = MediaQuery.textScalerOf(context);
    _layoutLocale = Localizations.maybeLocaleOf(context);
    _layoutDirection = Directionality.of(context);
    _geometry();
  }

  void _geometry() {
    var y = 0.0;
    final tops = <double>[], heights = <double>[];
    for (var i = 0; i < _baseHeights.length; i++) {
      tops.add(y);
      final backgroundHeight =
          i == _active &&
              _backingReveal.visibleIndex >= 0 &&
              _backingReveal.visibleIndex < _backgroundVocalHeights.length
          ? _backgroundVocalHeights[_backingReveal.visibleIndex] *
                _backingReveal.value
          : 0.0;
      final height =
          _baseHeights[i] + _subHeights[i] * _sublineReveal + backgroundHeight;
      heights.add(height);
      y += height + _gap;
    }
    _heights = heights;
    _tops = tops;
  }

  String? _translationOf(LyricsLine line) {
    if (line.translation?.trim().isNotEmpty == true)
      _subText[line.timestamp.inMilliseconds] = line.translation!.trim();
    if (widget.showTranslation) {
      return line.translation?.trim().isNotEmpty == true
          ? line.translation!.trim()
          : null;
    }
    return _subText[line.timestamp.inMilliseconds];
  }

  void _onTick(Duration elapsed) {
    if (_ultra &&
        elapsed - _lastPaintElapsed < const Duration(microseconds: 33333))
      return;
    _lastPaintElapsed = elapsed;
    final dt = ((elapsed - _lastElapsed).inMicroseconds / 1e6)
        .clamp(0.0, 0.05)
        .toDouble();
    _lastElapsed = elapsed;
    if (_heights.isEmpty || _heights.length != _lines.length) return;

    final previousReveal = _sublineReveal;
    final targetReveal = widget.showTranslation ? 1.0 : 0.0;
    final subMoving = (_sublineReveal - targetReveal).abs() > .002;
    _sublineReveal = MediaQuery.disableAnimationsOf(context)
        ? targetReveal
        : _sublineReveal +
              (targetReveal - _sublineReveal) * (1 - math.exp(-dt * 10));
    if (!subMoving) _sublineReveal = targetReveal;
    final ms = _posNowMs();
    final a = _indexAt(ms);
    final nextBackground = activeFlowingBackgroundVocalIndex(
      _backgroundVocalLines,
      Duration(milliseconds: ms),
    );
    final backgroundMoving = _backingReveal.advance(
      nextBackground,
      dt,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
    );
    if (previousReveal != _sublineReveal || backgroundMoving || a != _active) {
      _active = a;
      _geometry();
    }
    // Never pre-scroll into the next lead while either singer in the
    // current row is still sounding, including overlapping [bg:] voices.
    final aScroll = a;
    final target = _following ? _centerFor(aScroll) : _offset;
    final playing = widget.player.isPlayingNotifier.value;

    if (_needsJump) {
      _offset = _centerFor(aScroll);
      _focus = a.toDouble();
      _needsJump = false;
    } else {
      if (_following) _offset += (target - _offset) * (1 - math.exp(-dt * 7.0));
      _focus += (a - _focus) * (1 - math.exp(-dt * 10.0));
    }

    final settled =
        !playing &&
        !subMoving &&
        !backgroundMoving &&
        (target - _offset).abs() < 0.2 &&
        (a - _focus).abs() < 0.003 &&
        a == _active;
    _posMs = ms;
    _active = a;
    if (!settled) _frame.value++;
  }

  void _pauseFollow() {
    _following = false;
    _resume?.cancel();
    _resume = Timer(
      const Duration(milliseconds: 3200),
      () => _following = true,
    );
  }

  Widget _line(int i) {
    final l = _lines[i];
    if (l.text.trim().isEmpty) return SizedBox(height: _heights[i]);
    final d = (i - _focus).abs();
    final op = d < 1
        ? 1 - 0.66 * d
        : 0.34 - 0.18 * ((d - 1) / 3).clamp(0.0, 1.0);
    final scale = 1 - 0.1 * math.min(d, 1.0);
    final blur = _ultra || d < 1.0 ? 0.0 : math.min((d - 1) * 0.9, 2.8);

    final end = l.words?.lastOrNull?.end;
    final singing =
        i == _active ||
        (end != null && end.inMilliseconds > _posMs && _ts[i] <= _posMs);
    final text = singing
        ? LyricMotionLine(
            line: l,
            position: Duration(milliseconds: _posMs),
            style: _base,
          )
        : Opacity(
            opacity: op,
            child: LyricMotionLine(
              line: l,
              timing: false,
              position: Duration.zero,
              style: _base,
            ),
          );

    final sub = _translationOf(l);
    final backing =
        i == _active &&
            _backingReveal.visibleIndex >= 0 &&
            _backingReveal.visibleIndex < _backgroundVocalLines.length
        ? _backgroundVocalLines[_backingReveal.visibleIndex]
        : null;
    Widget child = Transform.scale(
      alignment: Alignment.centerLeft,
      scale: scale,
      child: backing == null && sub == null
          ? text
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text,
                // This fullscreen renderer is separate from SyncedLyricsView.
                // Keep the independently timed second singer directly beneath
                // whichever lead line is currently focused.
                if (backing != null)
                  ClipRect(
                    child: Align(
                      alignment: Alignment.topLeft,
                      heightFactor: _backingReveal.value,
                      child: Opacity(
                        opacity: _backingReveal.value,
                        child: Transform.translate(
                          offset: Offset(0, (1 - _backingReveal.value) * 8),
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: _subGap,
                              bottom: 8,
                            ),
                            child: LyricMotionLine(
                              line: backing,
                              position: Duration(milliseconds: _posMs),
                              lightweight: _ultra,
                              style: _backingStyle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (sub != null)
                  ClipRect(
                    child: Align(
                      alignment: Alignment.topLeft,
                      heightFactor: _sublineReveal,
                      child: Opacity(
                        opacity: _sublineReveal,
                        child: Padding(
                          padding: const EdgeInsets.only(top: _subGap),
                          child: Transform.translate(
                            offset: Offset(0, (1 - _sublineReveal) * 6),
                            child: FlowingLyricSubline(
                              text: sub,
                              timedLine:
                                  widget.showTranslation &&
                                      i < _timedSublines.length &&
                                      _timedSublines[i]?.text == sub
                                  ? _timedSublines[i]
                                  : null,
                              position: Duration(milliseconds: _posMs),
                              singing: singing,
                              lightweight: _ultra,
                              style: _sub.copyWith(
                                color:
                                    (_sub.color ??
                                            Theme.of(context)
                                                .colorScheme
                                                .onSurface)
                                        .withValues(
                                          alpha: i == _active ? .82 : op * .8,
                                        ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
    if (blur > 0.3) {
      child = ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: blur,
          sigmaY: blur,
          tileMode: TileMode.decal,
        ),
        child: child,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _resume?.cancel();
        _following = true;
        widget.player.seek(Duration(milliseconds: _ts[i]));
      },
      child: child,
    );
  }

  Widget _introDots() {
    final firstMs = _ts.isEmpty ? 0 : _ts.first;
    final p = firstMs <= 0 ? 1.0 : (_posMs / firstMs).clamp(0.0, 1.0);
    final fade = (0 - _focus).clamp(0.0, 1.0).toDouble();
    return Opacity(
      opacity: fade,
      child: SizedBox(
        height: _introHeight,
        child: Row(
          children: [
            for (var k = 0; k < 3; k++)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(
                      alpha: 0.28 + 0.72 * (p * 3 - k).clamp(0.0, 1.0),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _ultra = LokalPerformanceScope.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        _ensureLayout(c.maxWidth, c.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: (_) => _pauseFollow(),
          onVerticalDragUpdate: (d) {
            _pauseFollow();
            _offset = (_offset - d.delta.dy)
                .clamp(
                  -(_introHeight + _gap + _h * 0.3),
                  math.max(_tops.isEmpty ? 0.0 : _tops.last, 0.0),
                )
                .toDouble();
            _frame.value++;
          },
          child: ClipRect(
            child: ValueListenableBuilder<int>(
              valueListenable: _frame,
              builder: (context, _, __) {
                if (_heights.length != _lines.length) {
                  return const SizedBox.expand();
                }
                final anchorY = _h * _anchor;
                final children = <Widget>[];
                final dotsTop = anchorY - (_introHeight + _gap) - _offset;
                if (dotsTop > -80 && dotsTop < _h) {
                  children.add(
                    Positioned(left: 0, top: dotsTop, child: _introDots()),
                  );
                }
                var first = 0, end = _tops.length;
                while (first < end) {
                  final mid = (first + end) ~/ 2;
                  if (anchorY + _tops[mid] - _offset + _heights[mid] < -80) {
                    first = mid + 1;
                  } else {
                    end = mid;
                  }
                }
                for (var i = first; i < _lines.length; i++) {
                  final top = anchorY + _tops[i] - _offset;
                  if (top > _h + 80) break;
                  children.add(
                    Positioned(left: 0, right: 0, top: top, child: _line(i)),
                  );
                }
                return Stack(clipBehavior: Clip.hardEdge, children: children);
              },
            ),
          ),
        );
      },
    );
  }
}
