import '../services/link/library_sync_notification.dart';
import '../services/link/file_copy_notification.dart';
import '../data/database.dart';
import '../services/link/link_download_outbox.dart';
import '../services/favorites_service.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io' show WebSocketException;
import 'dart:typed_data';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import '../services/player_service.dart';
import '../services/notification_service.dart';
import '../services/link/lokal_link_service.dart';
import '../services/link/link_protocol.dart';
import '../services/link/link_journal.dart';
import '../services/link/link_sync_coordinator.dart';
import '../services/link/link_profile_service.dart';
import '../services/link/link_file_copy.dart';
import '../services/link/desktop_track_copy_command.dart';
import '../services/link/desktop_catalogue_import.dart';
import '../services/link/lokal_desktop_source.dart';
import '../core/navigation/root_navigator.dart';
import '../widgets/lokal/lokal_toast.dart';
import 'favorites_provider.dart';
import 'playlist_provider.dart';
import '../core/theme/lokal_appearance.dart';

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState, WidgetsBinding;

import '../models/lokal_remote_state.dart';
import '../services/lokal_remote_credentials_store.dart';
import '../services/lokal_remote_service.dart';

final lokalRemoteCredentialsStoreProvider =
    Provider<LokalRemoteCredentialsStore>(
      (ref) => SecureLokalRemoteCredentialsStore(),
    );

final lokalRemoteServiceProvider = Provider<LokalRemoteService>((ref) {
  final service = LokalRemoteService();
  ref.onDispose(service.close);
  return service;
});

final lokalLinkServiceProvider = Provider<LokalLinkService>((ref) {
  final service = LokalLinkService();
  ref.onDispose(() => unawaited(service.close()));
  return service;
});

final linkedDesktopProfileProvider = FutureProvider<LinkedProfile?>((
  ref,
) async {
  final credentials = await ref
      .watch(lokalRemoteCredentialsStoreProvider)
      .read();
  if (credentials?.desktopId == null) return null;
  return LinkProfileService.load(credentials!);
});

final lokalRemoteControllerProvider =
    NotifierProvider<LokalRemoteController, LokalRemoteControllerState>(
      LokalRemoteController.new,
    );

/// The desktop can publish a new track before its playback engine updates
/// the top-level duration. Prefer the recording's own metadata when present,
/// then correct Android again as fresh snapshots arrive.
Duration desktopNotificationDuration(LokalRemoteSnapshot snapshot) {
  final trackSeconds = snapshot.currentTrack?.duration ?? 0;
  final seconds = trackSeconds.isFinite && trackSeconds > 0
      ? trackSeconds
      : snapshot.duration;
  return Duration(milliseconds: (seconds * 1000).round());
}

/// Owns one authenticated desktop connection, including polling and bounded
/// reconnects. Paired desktop state is kept separate from the local engine.
class LokalRemoteController extends Notifier<LokalRemoteControllerState>
    implements RemoteFavoritesDelegate {
  static const _pollInterval = Duration(milliseconds: 1200);
  static const _maximumBackoff = Duration(seconds: 20);

  Timer? _pollTimer;
  Timer? _linkTimer;
  Timer? _statsDebounce;
  String? _notificationArtworkKey;
  String? _notificationArtwork;
  String? _loadingArtworkKey;
  int _artworkAttempts = 0;
  DateTime _artworkRetryAfter = DateTime.fromMillisecondsSinceEpoch(0);
  LinkSyncCoordinator? _linkSync;
  final _downloadOutbox = LinkDownloadOutbox();
  final _syncNotification = LibrarySyncNotification();
  final _copyNotification = FileCopyNotification();
  LinkFileCopy? _copyPlanner;
  bool _socketWanted = false, _openingSocket = false, _receivingTheme = false;
  DateTime _lastStatsSyncAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _statsSyncInFlight = false;
  Map<String, dynamic>? _desktopState;
  DateTime? _desktopStateAt;
  DateTime _lastPhoneStateAt = DateTime.now();
  String _lastPhoneSignature = '';
  List<Song>? _lastPhoneQueue;
  double _lastPhoneProgress = 0;
  String? _notificationTrack;
  bool? _notificationPlaying;
  bool? _notificationFavorite;
  late final MediaNotificationOwner _notificationOwner = MediaNotificationOwner(
    onTogglePlayPause: () => unawaited(sendRawCommand('togglePlay')),
    onPlay: () => unawaited(sendRawCommand('play')),
    onPause: () => unawaited(sendRawCommand('pause')),
    onStop: () => unawaited(sendRawCommand('pause')),
    onNext: () => unawaited(sendRawCommand('next')),
    onToggleFavorite: () {
      final id = state.snapshot?.currentTrack?.id;
      if (id != null) unawaited(toggleFavorite('desktop:$id'));
    },
    onToggleShuffle: () => unawaited(
      sendRawCommand('setShuffle', !(state.snapshot?.shuffle ?? false)),
    ),
    onSetVolume: (volume) => unawaited(sendRawCommand('volume', volume)),
    onPrevious: () => unawaited(sendRawCommand('prev')),
    onSeek: (position) =>
        unawaited(sendRawCommand('seek', position.inMilliseconds / 1000)),
  );
  LokalRemoteCredentials? _credentials;
  Future<void>? _restoreTask;
  Future<void> _commandTail = Future<void>.value();
  Future<void> _incomingCommandTail = Future<void>.value();
  var _polling = false;
  bool _syncInFlight = false;
  var _shouldPoll = false;
  var _failures = 0;
  var _generation = 0;
  var _configurationRevision = 0;
  var _disposed = false;

  @override
  LokalRemoteControllerState build() {
    _disposed = false;
    FavoritesService.remoteDelegate = this;
    final link = ref.read(lokalLinkServiceProvider);
    final messages = link.messages.listen(_onLinkMessage);
    final connections = link.connections.listen(_socketConnectionChanged);
    var wasBackgrounded = false;
    final lifecycle = AppLifecycleListener(
      onPause: () => wasBackgrounded = true,
      onResume: () {
        if (!wasBackgrounded) return;
        wasBackgrounded = false;
        unawaited(resumeConnection());
      },
    );
    // Only play events may initiate background synchronization. Library,
    // metadata, likes and playlists still require explicit Sync now.
    final historyChanges = LinkJournal.instance.historyChanges.stream.listen(
      (_) => _scheduleStatsSync(const Duration(seconds: 15)),
    );
    ref.listen(lokalAppearanceProvider, (_, appearance) {
      if (!_receivingTheme && link.connected) unawaited(_sendTheme(appearance));
    });
    ref.onDispose(() {
      _copyPlanner?.cancel();
      _syncNotification.dispose();
      _copyNotification.dispose();
      _disposed = true;
      lifecycle.dispose();
      if (identical(FavoritesService.remoteDelegate, this))
        FavoritesService.remoteDelegate = null;
      _pollTimer?.cancel();
      _linkTimer?.cancel();
      _statsDebounce?.cancel();
      unawaited(historyChanges.cancel());
      unawaited(messages.cancel());
      unawaited(connections.cancel());
      NotificationService().release(_notificationOwner);
    });
    _restoreTask = _restore();
    unawaited(_restoreTask!);
    return const LokalRemoteControllerState();
  }

  Future<void> _restore() async {
    final revision = _configurationRevision;
    try {
      final credentials = await ref
          .read(lokalRemoteCredentialsStoreProvider)
          .read();
      if (_disposed ||
          revision != _configurationRevision ||
          credentials == null)
        return;
      _credentials = credentials;
      state = state.copyWith(
        config: LokalRemoteConfig.fromCredentials(credentials),
        status: LokalRemoteConnectionStatus.disconnected,
        clearError: true,
      );
      if (credentials.desktopId != null && credentials.remoteToken.isNotEmpty) {
        scheduleMicrotask(() {
          if (!_disposed) unawaited(connect());
        });
      }
    } catch (_) {
      if (!_disposed && revision == _configurationRevision) {
        state = state.copyWith(
          status: LokalRemoteConnectionStatus.unconfigured,
          error: 'Saved Lokal remote settings could not be read.',
        );
      }
    }
  }

  Future<void> _ensureRestored() async {
    final task = _restoreTask;
    if (task != null) await task;
  }

  Future<void> saveConfiguration({
    required String origin,
    required String remoteToken,
    required String apiKey,
  }) async {
    final revision = ++_configurationRevision;
    await _ensureRestored();
    if (_disposed || revision != _configurationRevision) return;
    disconnect();
    final normalized = LokalRemoteService.normalizeOrigin(origin);
    final credentials = LokalRemoteCredentials(
      origin: normalized,
      remoteToken: remoteToken.trim(),
      apiKey: apiKey.trim(),
    );
    await ref.read(lokalRemoteCredentialsStoreProvider).write(credentials);
    if (_disposed || revision != _configurationRevision) return;
    _generation++;
    _shouldPoll = false;
    _pollTimer?.cancel();
    final saved = await ref.read(lokalRemoteCredentialsStoreProvider).read();
    if (_disposed || revision != _configurationRevision) return;
    _credentials = saved;
    state = LokalRemoteControllerState(
      config: LokalRemoteConfig.fromCredentials(credentials),
      status: LokalRemoteConnectionStatus.disconnected,
    );
  }

  Future<void> forgetConfiguration({
    required LokalRemoteCredentials? expected,
  }) async {
    final revision = ++_configurationRevision;
    await _ensureRestored();
    if (_disposed || revision != _configurationRevision) {
      throw StateError('Desktop pairing changed. Refresh and retry.');
    }
    // Read/compare/clear is serialized with writes by the same credential
    // store. A stale confirmation cannot erase a newly-paired desktop.
    await ref
        .read(lokalRemoteCredentialsStoreProvider)
        .clearIfMatching(expected);
    if (_disposed || revision != _configurationRevision) return;
    disconnect();
    _generation++;
    _shouldPoll = false;
    _pollTimer?.cancel();
    _credentials = null;
    ref.invalidate(linkedDesktopProfileProvider);
    state = const LokalRemoteControllerState();
  }

  void disconnect() {
    _syncNotification.pause();
    _socketWanted = false;
    _notificationArtworkKey = null;
    _notificationArtwork = null;
    _linkTimer?.cancel();
    _statsDebounce?.cancel();
    _linkSync = null;
    unawaited(ref.read(lokalLinkServiceProvider).disconnect());
    NotificationService().release(_notificationOwner);
    _generation++;
    _shouldPoll = false;
    _pollTimer?.cancel();
    if (_disposed) return;
    state = state.copyWith(
      status: state.config == null
          ? LokalRemoteConnectionStatus.unconfigured
          : LokalRemoteConnectionStatus.disconnected,
      clearSnapshot: true,
      clearError: true,
      commandInFlight: false,
      socketConnected: false,
      controlsDesktop: false,
      clearRemoteArtwork: true,
      clearArtworkServer: true,
    );
  }

  /// The OS may suspend the socket while backgrounded. Reopen it on return,
  /// retaining the same saved pair and respecting an explicit Disconnect.
  Future<void> resumeConnection() async {
    await _ensureRestored();
    if (_disposed ||
        !_shouldPoll ||
        _credentials?.desktopId == null ||
        _openingSocket)
      return;
    if (ref.read(lokalLinkServiceProvider).connected &&
        (_syncInFlight || _statsSyncInFlight || state.fileCopyProgress.busy))
      return;
    await connect();
  }

  Future<void> connect() async {
    await _ensureRestored();
    if (_disposed) return;
    if (_credentials == null) {
      state = state.copyWith(
        status: LokalRemoteConnectionStatus.unconfigured,
        error: 'Save a Lokal desktop address before connecting.',
      );
      return;
    }
    _generation++;
    _shouldPoll = true;
    _failures = 0;
    _pollTimer?.cancel();
    _linkTimer?.cancel();
    _statsDebounce?.cancel();
    _linkSync = null;
    state = state.copyWith(
      socketConnected: false,
      status: LokalRemoteConnectionStatus.connecting,
      clearError: true,
    );
    if (_credentials?.desktopId != null) {
      await _connectSocket();
    } else {
      await _poll();
    }
  }

  Future<void> refresh() async {
    if (state.socketConnected) {
      // Refreshing playback/connection state must not initiate library sync.
      _refreshSocketSnapshot();
      return;
    }
    if (!_shouldPoll) return connect();
    _pollTimer?.cancel();
    await _poll();
  }

  Future<void> sendCommand(LokalRemoteAction action, {double? value}) {
    final generation = _generation;
    Future<void> run() async {
      if (_disposed || generation != _generation) return;
      if (!state.reachable || _credentials == null) {
        throw const LokalRemoteNetworkException(
          'Connect to Lokal before sending a remote command.',
        );
      }
      final credentials = _credentials!;
      if (!_disposed) {
        state = state.copyWith(commandInFlight: true, clearError: true);
      }
      try {
        if (state.socketConnected) {
          await ref.read(lokalLinkServiceProvider).request('command', {
            'action': action.wireName,
            'value': value,
          });
        } else {
          await ref
              .read(lokalRemoteServiceProvider)
              .sendCommand(credentials, action, value: value);
        }
        if (!_disposed && generation == _generation) {
          if (!state.socketConnected) {
            _pollTimer?.cancel();
            unawaited(_poll());
          }
        }
      } catch (error) {
        if (!_disposed && generation == _generation) {
          _setFailure(error);
        }
        rethrow;
      } finally {
        if (!_disposed && generation == _generation) {
          state = state.copyWith(commandInFlight: false);
        }
      }
    }

    final next = _commandTail.then<void>((_) => run(), onError: (_) => run());
    _commandTail = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  @override
  Future<bool> isFavorite(String songId) async {
    final id = songId.replaceFirst('desktop:', ''), snapshot = state.snapshot;
    if (snapshot?.currentTrack?.id == id) return snapshot!.currentTrack!.liked;
    final matches = snapshot?.queue.where((track) => track.id == id);
    return matches != null && matches.isNotEmpty ? matches.first.liked : false;
  }

  @override
  Future<bool> toggleFavorite(String songId) async {
    final id = songId.replaceFirst('desktop:', ''),
        liked = await isFavorite(songId);
    await sendRawCommand('setTrackLike', {'trackId': id, 'liked': !liked});
    return !liked;
  }

  Future<List<LokalDiscoveredDesktop>> discoverDesktops() =>
      ref.read(lokalLinkServiceProvider).discover();

  Future<void> pairDesktop({
    required String origin,
    required String code,
    String? expectedDesktopId,
    bool syncTheme = false,
  }) async {
    final revision = ++_configurationRevision;
    await _ensureRestored();
    if (_disposed || revision != _configurationRevision) return;
    final credentials = await ref
        .read(lokalLinkServiceProvider)
        .pair(
          origin: LokalRemoteService.normalizeOrigin(origin),
          code: code,
          expectedDesktopId: expectedDesktopId,
        );
    if (_disposed || revision != _configurationRevision) return;
    disconnect();
    await ref.read(lokalRemoteCredentialsStoreProvider).write(credentials);
    if (_disposed || revision != _configurationRevision) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('lokal.link.${credentials.desktopId}.theme', syncTheme);
    if (_disposed || revision != _configurationRevision) return;
    final saved = await ref.read(lokalRemoteCredentialsStoreProvider).read();
    if (_disposed || revision != _configurationRevision) return;
    _credentials = saved;
    ref.invalidate(linkedDesktopProfileProvider);
    state = LokalRemoteControllerState(
      config: LokalRemoteConfig.fromCredentials(credentials),
    );
    await connect();
  }

  Future<void> approveMerge() async {
    if (state.fileCopyProgress.busy)
      throw StateError('Wait for the current file copy to finish.');
    final sync = _linkSync;
    if (sync == null)
      throw const LokalRemoteNetworkException(
        'Connect to the paired desktop first.',
      );
    _syncNotification.begin(deviceName: state.desktopName);
    await sync.enableMerge();
  }

  /// The only post-merge entry point for a full desktop/phone library sync.
  /// Pairing, reconnecting, periodic link polls and local journal edits
  /// intentionally do not call this method.
  Future<void> syncNow() async {
    if (!state.socketConnected || _linkSync == null || !state.mergeApproved) {
      throw StateError('Connect and merge with your desktop before syncing.');
    }
    if (_syncInFlight ||
        _statsSyncInFlight ||
        _linkSync!.busy ||
        state.fileCopyProgress.busy) {
      throw StateError('A desktop sync or file copy is already running.');
    }
    _syncNotification.begin(deviceName: state.desktopName);
    await _syncLink();
  }

  LinkFileCopy _fileCopier() {
    final credentials = _credentials;
    if (credentials == null || !state.socketConnected) {
      throw const LokalRemoteNetworkException(
        'Connect to the paired desktop first.',
      );
    }
    final generation = _generation;
    late final LinkFileCopy copier;
    copier = LinkFileCopy(
      credentials: credentials,
      socket: ref.read(lokalLinkServiceProvider),
      connected: () =>
          !_disposed && generation == _generation && state.socketConnected,
      onProgress: (progress) {
        if (!_disposed && generation == _generation && !copier.cancelled) {
          state = state.copyWith(fileCopyProgress: progress);
          _copyNotification.update(progress);
        }
      },
    );
    return copier;
  }

  Future<LinkCopyPlan> prepareFileCopy() async {
    if (state.syncProgress.busy || state.fileCopyProgress.busy)
      throw StateError('Wait for the current library operation to finish.');
    final copier = _fileCopier();
    _copyPlanner = copier;
    try {
      return await copier.plan();
    } catch (_) {
      if (!_disposed)
        state = state.copyWith(
          fileCopyProgress: const LinkCopyProgress(phase: LinkCopyPhase.paused),
        );
      rethrow;
    } finally {
      if (identical(_copyPlanner, copier)) _copyPlanner = null;
    }
  }

  Future<void> copyMissingFiles(LinkCopyPlan plan) async {
    final copier = _fileCopier();
    try {
      await _copyNotification.begin(state.desktopName);
    } on Object {
      if (!_disposed)
        state = state.copyWith(
          fileCopyProgress: const LinkCopyProgress(phase: LinkCopyPhase.paused),
        );
      throw StateError(
        'Could not start background copying. Keep Lokal open and retry.',
      );
    }
    try {
      await copier.copy(plan);
    } finally {
      await _copyNotification.finish(state.fileCopyProgress);
    }
  }

  void cancelFileCopyPlan() {
    _copyPlanner?.cancel();
    if (state.fileCopyProgress.phase == LinkCopyPhase.checking) {
      state = state.copyWith(fileCopyProgress: const LinkCopyProgress());
    }
  }

  Future<void> setDesktopTarget(bool value) async {
    if (value && !state.reachable)
      throw const LokalRemoteNetworkException('Connect to your desktop first.');
    if (value) {
      if (!state.controlsDesktop) NotificationService().stopCurrentOwner();
      await PlayerService().pause();
    }
    if (_disposed) return;
    state = state.copyWith(
      controlsDesktop: value,
      clearRemoteArtwork: !value,
      clearArtworkServer: !value,
    );
    if (!value) {
      NotificationService().release(_notificationOwner);
      _notificationTrack = null;
      _notificationArtworkKey = null;
      _notificationArtwork = null;
      PlayerService().refreshNotificationState();
    } else {
      _updateRemoteNotification();
      // Queue artwork still uses a registered library source; the current
      // cover itself no longer depends on library/database readiness.
      unawaited(_registerRemoteArtworkSource());
    }
  }

  /// Register the paired desktop as an artwork source even if it is paused or
  /// its current song has no cover. Queue rows require a resolvable server ID.
  Future<void> _registerRemoteArtworkSource() async {
    final credentials = _credentials;
    if (credentials == null ||
        credentials.desktopId == null ||
        !Database.isInitialized)
      return;
    final generation = _generation;
    try {
      final server = await LokalDesktopSource.instance.ensureServer(
        credentials,
      );
      if (!_disposed &&
          state.controlsDesktop &&
          generation == _generation &&
          identical(_credentials, credentials)) {
        state = state.copyWith(artworkServerId: server.id);
      }
    } catch (_) {
      // A missing or offline cover must never block remote playback controls.
    }
  }

  Future<void> sendRawCommand(String action, [Object? value]) async {
    if (state.socketConnected) {
      await ref.read(lokalLinkServiceProvider).request('command', {
        'action': action,
        'value': value,
      });
      return;
    }
    if (action == 'setShuffle' || action == 'setRepeat') {
      final credentials = _credentials;
      if (!state.reachable || credentials == null) {
        throw const LokalRemoteNetworkException(
          'Connect to Lokal before changing a playback mode.',
        );
      }
      await ref
          .read(lokalRemoteServiceProvider)
          .sendPlaybackModeCommand(credentials, action, value);
      // Refresh the confirmed desktop modes after an HTTP command, just as
      // the socket state event does for a paired connection.
      await refresh();
      return;
    }
    // A connected desktop can remain reachable over HTTP after the paired
    // socket closes. Preserve exact recording IDs and queue payloads instead
    // of discarding them through the scalar-only transport action enum.
    if (action == 'playLibraryTrack' || action == 'queueTracks') {
      final credentials = _credentials;
      if (credentials == null || value is! Map) {
        throw const LokalRemoteProtocolException(
          'The paired desktop library command is unavailable.',
        );
      }
      await ref
          .read(lokalRemoteServiceProvider)
          .sendLibraryCommand(
            credentials,
            action,
            Map<String, dynamic>.from(value),
          );
      return;
    }
    final actions = LokalRemoteAction.values.where(
      (item) => item.wireName == action,
    );
    if (actions.isEmpty)
      throw const LokalRemoteProtocolException(
        'Update Lokal on your PC to use this command.',
      );
    await sendCommand(
      actions.first,
      value: value is num ? value.toDouble() : null,
    );
  }

  Future<void> sendSongToDesktop(Song song) async {
    final credentials = _credentials;
    final socket = ref.read(lokalLinkServiceProvider);
    if (credentials == null || !state.socketConnected || !socket.connected) {
      throw const LokalRemoteProtocolException(
        'Reconnect to your paired desktop to send songs.',
      );
    }
    if (song.filePath == null ||
        song.filePath!.isEmpty ||
        song.isExternal ||
        song.isNetworkSource) {
      throw const LokalRemoteProtocolException(
        'This song has no local audio file to send.',
      );
    }
    await LokalDesktopSource.instance.uploadToDesktop(song, credentials);
  }

  Future<void> _connectSocket() async {
    final credentials = _credentials;
    if (credentials == null || _disposed || !_shouldPoll) return;
    final generation = _generation;
    _openingSocket = true;
    _socketWanted = true;
    try {
      final origin = await ref
          .read(lokalLinkServiceProvider)
          .connect(credentials);
      if (_disposed || generation != _generation) return;
      if (origin != credentials.origin) {
        late final LokalRemoteCredentials relocated;
        try {
          relocated = await ref
              .read(lokalRemoteCredentialsStoreProvider)
              .relocateIfMatching(credentials, origin);
        } catch (_) {
          if (!_disposed && generation == _generation) {
            await ref.read(lokalLinkServiceProvider).disconnect();
          }
          rethrow;
        }
        if (_disposed || generation != _generation) return;
        _credentials = relocated;
        state = state.copyWith(
          config: LokalRemoteConfig.fromCredentials(relocated),
        );
        ref.invalidate(linkedDesktopProfileProvider);
      }
      _failures = 0;
      _pollTimer?.cancel();
      final prefs = await SharedPreferences.getInstance();
      if (_disposed || generation != _generation) return;
      if (!ref.read(lokalLinkServiceProvider).connected) {
        throw const LokalRemoteNetworkException('Desktop link disconnected.');
      }
      final activeCredentials = _credentials!;
      final prefix = LinkSyncCoordinator.prefixFor(activeCredentials);
      final lastSync = prefs.getInt('$prefix.last_sync');
      final initialProgress = LinkSyncProgress(
        phase: lastSync == null ? LinkSyncPhase.idle : LinkSyncPhase.complete,
        completedAt: lastSync == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(lastSync),
        catalogSongs: prefs.getInt('$prefix.catalog_songs'),
      );
      late final LinkSyncCoordinator coordinator;
      coordinator = LinkSyncCoordinator(
        socket: ref.read(lokalLinkServiceProvider),
        credentials: activeCredentials,
        favorites: ref.read(favoritesServiceProvider),
        initialProgress: initialProgress,
        onProgress: (progress) {
          if (!_disposed &&
              generation == _generation &&
              identical(_linkSync, coordinator)) {
            state = state.copyWith(syncProgress: progress, mergeApproved: true);
            _syncNotification.update(progress, deviceName: state.desktopName);
          }
        },
        onChanged: () {
          if (!_disposed &&
              generation == _generation &&
              identical(_linkSync, coordinator)) {
            ref.invalidate(favoritesProvider);
            ref.invalidate(playlistsProvider);
          }
        },
        onProfileChanged: () {
          if (!_disposed &&
              generation == _generation &&
              identical(_linkSync, coordinator)) {
            ref.invalidate(linkedDesktopProfileProvider);
          }
        },
      );
      _linkSync = coordinator;
      state = state.copyWith(
        socketConnected: true,
        status: LokalRemoteConnectionStatus.connected,
        syncProgress: initialProgress,
        mergeApproved:
            prefs.getBool(
              '${LinkSyncCoordinator.prefixFor(activeCredentials)}.merge',
            ) ==
            true,
        clearError: true,
      );
      _linkTimer?.cancel();
      _linkTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _tickLink(),
      );
      // Connection alone never starts a full library scan. Defer the first
      // bounded stats exchange until the socket and startup UI have settled.
      _lastStatsSyncAt = DateTime.now();
      _scheduleStatsSync(const Duration(seconds: 8));
      _publishLocalState();
    } catch (error) {
      if (_disposed || generation != _generation) return;
      final statusCode = error is WebSocketException
          ? error.httpStatusCode
          : null;
      if (error is LokalRemoteAuthException || statusCode == 401) {
        _socketWanted = false;
        // The desktop may be temporarily locked or on another profile. Do
        // not abandon a durable pairing or require a new QR scan on return.
        _setFailure(const LokalRemoteAuthException());
        _pollTimer?.cancel();
        _pollTimer = Timer(_maximumBackoff, () => unawaited(_connectSocket()));
        return;
      }
      if (statusCode == 404 || statusCode == 426) {
        _socketWanted = false;
        state = state.copyWith(socketConnected: false);
        await _poll();
      } else {
        _setFailure(error);
        _pollTimer?.cancel();
        _pollTimer = Timer(_nextDelay(), () => unawaited(_connectSocket()));
      }
    } finally {
      if (!_disposed && generation == _generation) _openingSocket = false;
    }
  }

  void _socketConnectionChanged(bool connected) {
    if (_disposed ||
        connected ||
        _openingSocket ||
        !_socketWanted ||
        !_shouldPoll)
      return;
    state = state.copyWith(
      socketConnected: false,
      status: LokalRemoteConnectionStatus.offline,
    );
    _failures++;
    _syncNotification.pause();
    _linkTimer?.cancel();
    _pollTimer?.cancel();
    _pollTimer = Timer(_nextDelay(), () => unawaited(_connectSocket()));
  }

  void _onLinkMessage(LinkMessage message) {
    if (_disposed || !_shouldPoll) return;
    switch (message.type) {
      case 'hello':
        if (message.body['desktopId'] != _credentials?.desktopId) {
          disconnect();
          return;
        }
        state = state.copyWith(
          desktopName: message.body['name'] as String? ?? 'Lokal desktop',
          syncPreview: message.body['syncPreview'] is Map
              ? Map<String, dynamic>.from(message.body['syncPreview'] as Map)
              : null,
        );
        break;
      case 'state':
        _desktopState = Map<String, dynamic>.from(message.body);
        _desktopStateAt = DateTime.now();
        _refreshSocketSnapshot();
        break;
      case 'command':
        unawaited(_queuePhoneCommand(message.body, message.id));
        break;
      case 'theme':
        unawaited(_receiveTheme(message.body));
        break;
    }
  }

  void _refreshSocketSnapshot() {
    final raw = _desktopState, at = _desktopStateAt;
    if (raw == null || at == null || _disposed) return;
    final elapsed = raw['isPlaying'] == true
        ? DateTime.now().difference(at).inMilliseconds / 1000
        : 0.0;
    final progress = (raw['progress'] as num? ?? 0).toDouble() + elapsed;
    try {
      state = state.copyWith(
        snapshot: LokalRemoteSnapshot.fromJson({...raw, 'progress': progress}),
        status: LokalRemoteConnectionStatus.connected,
        lastSeenAt: at,
      );
    } on FormatException {
      state = state.copyWith(error: 'Desktop playback state was invalid.');
    }
    if (state.controlsDesktop) _updateRemoteNotification();
  }

  void _tickLink() {
    if (_disposed || !state.socketConnected) return;
    _refreshSocketSnapshot();
    _publishLocalState();
    if (DateTime.now().difference(_lastStatsSyncAt) >=
        const Duration(minutes: 2)) {
      unawaited(_syncStats());
    }
  }

  void _scheduleStatsSync(Duration delay) {
    if (_disposed || !state.socketConnected || !state.mergeApproved) return;
    _statsDebounce?.cancel();
    _statsDebounce = Timer(delay, () => unawaited(_syncStats()));
  }

  Future<void> _syncStats() async {
    final coordinator = _linkSync;
    if (_disposed ||
        !state.socketConnected ||
        !state.mergeApproved ||
        !Database.isInitialized ||
        _syncInFlight ||
        _statsSyncInFlight ||
        state.fileCopyProgress.busy ||
        coordinator == null ||
        coordinator.busy) {
      return;
    }
    _statsDebounce?.cancel();
    _statsSyncInFlight = true;
    _lastStatsSyncAt = DateTime.now();
    try {
      await coordinator.synchronizeStats();
    } catch (_) {
      // Offline peers or malformed replies must never interrupt playback.
      // Journal cursors checkpoint only acknowledged/committed pages, so the
      // next connected tick or manual Sync now can safely retry.
    } finally {
      _statsSyncInFlight = false;
    }
  }

  Future<void> _syncLink() async {
    if (_syncInFlight || state.fileCopyProgress.busy || _linkSync?.busy == true)
      return;
    _syncInFlight = true;
    final generation = _generation;
    try {
      final credentials = _credentials;
      if (credentials != null)
        await _downloadOutbox.flush(
          credentials,
          connected: () => !_disposed && state.socketConnected,
        );
      // The coordinator deliberately skips when disconnected. For an
      // explicit user action, skipping is not success.
      final coordinator = _linkSync;
      if (_disposed ||
          generation != _generation ||
          !state.socketConnected ||
          coordinator == null ||
          !ref.read(lokalLinkServiceProvider).connected) {
        throw StateError(
          'Desktop disconnected before library sync. Reconnect and retry.',
        );
      }
      await coordinator.synchronize();
      if (_disposed ||
          generation != _generation ||
          !state.socketConnected ||
          !ref.read(lokalLinkServiceProvider).connected ||
          !identical(_linkSync, coordinator)) {
        throw StateError(
          'Desktop disconnected during library sync. Reconnect and retry.',
        );
      }
    } catch (_) {
      if (!_disposed && generation == _generation) {
        state = state.copyWith(
          error: 'Library sync paused. Your local data is safe; tap Sync now when connected.',
        );
      }
      _syncNotification.pause();
      rethrow;
    } finally {
      _syncInFlight = false;
    }
  }

  Future<void> _queuePhoneCommand(
    Map<String, dynamic> body,
    String? messageId,
  ) async {
    Future<void> process() async {
      try {
        await _handlePhoneCommand(body);
        if (body['action'] == 'copyTracksToPhone') {
          final message = state.transferMessage;
          if (message != null) {
            _showTransferToast(message, error: state.transferHasError);
          }
        }
        if (!_disposed && ref.read(lokalLinkServiceProvider).connected) {
          ref.read(lokalLinkServiceProvider).send('ack', {
            'ok': true,
          }, id: messageId);
        }
      } catch (error) {
        final detail = switch (error) {
          LokalRemoteException(:final message) => message,
          FormatException(:final message) => message.toString(),
          _ => 'The phone could not complete this command.',
        };
        if (!_disposed && body['action'] == 'copyTracksToPhone') {
          state = state.copyWith(
            transferMessage: detail.length > 500
                ? detail.substring(0, 500)
                : detail,
            transferHasError: true,
          );
          _showTransferToast(state.transferMessage!, error: true);
        }
        if (!_disposed && ref.read(lokalLinkServiceProvider).connected) {
          ref.read(lokalLinkServiceProvider).send('ack', {
            'ok': false,
            'error': detail.length > 300 ? detail.substring(0, 300) : detail,
          }, id: messageId);
        }
      }
    }

    final next = _incomingCommandTail.then<void>(
      (_) => process(),
      onError: (_) => process(),
    );
    _incomingCommandTail = next.then<void>((_) {}, onError: (_) {});
    await next;
  }

  void _showTransferToast(String message, {required bool error}) {
    final context = rootNavigatorKey.currentState?.overlay?.context;
    if (context == null) return;
    LokalToast.show(
      context,
      message,
      duration: Duration(seconds: error ? 6 : 4),
    );
  }

  void _publishLocalState() {
    final socket = ref.read(lokalLinkServiceProvider);
    if (!socket.connected || !Database.isInitialized) return;
    final player = PlayerService(), song = player.currentSongNotifier.value;
    final queue = player.queueNotifier.value, now = DateTime.now();
    final progress = player.positionNotifier.value.inMilliseconds / 1000;
    final payload = <String, dynamic>{
      'target': 'phone',
      'isPlaying': player.isPlayingNotifier.value,
      'currentTrack': song == null ? null : LinkJournal.instance.songWire(song),
      'currentIndex': player.currentIndexNotifier.value,
      'duration': player.durationNotifier.value.inMilliseconds / 1000,
      'volume': player.currentVolume,
      'shuffle': player.isShuffleNotifier.value,
      'repeat': player.loopModeNotifier.value == LoopMode.one
          ? 'one'
          : player.loopModeNotifier.value == LoopMode.all
          ? 'all'
          : 'none',
    };
    final signature = jsonEncode(payload);
    final expected =
        _lastPhoneProgress +
        (player.isPlayingNotifier.value
            ? now.difference(_lastPhoneStateAt).inMilliseconds / 1000
            : 0);
    if (signature == _lastPhoneSignature &&
        identical(queue, _lastPhoneQueue) &&
        (progress - expected).abs() < 1.5)
      return;
    _lastPhoneSignature = signature;
    _lastPhoneQueue = queue;
    _lastPhoneProgress = progress;
    _lastPhoneStateAt = now;
    socket.send('state', {
      ...payload,
      'queue': queue.map(LinkJournal.instance.songWire).toList(),
      'progress': progress,
      'positionAt': now.millisecondsSinceEpoch,
    });
  }

  Future<void> _handlePhoneCommand(Map<String, dynamic> body) async {
    final player = PlayerService(),
        action = body['action'],
        value = body['value'];
    if (state.controlsDesktop &&
        action != 'handoffToDesktop' &&
        action != 'copyTracksToPhone')
      await setDesktopTarget(false);
    switch (action) {
      case 'togglePlay':
        await player.togglePlayPause();
        break;
      case 'play':
        await player.resume();
        break;
      case 'pause':
        await player.pause();
        break;
      case 'next':
        await player.next();
        break;
      case 'prev':
        await player.previous();
        break;
      case 'seek':
        if (value is! num || !value.isFinite)
          throw const FormatException('Invalid seek.');
        await player.seek(Duration(milliseconds: (value * 1000).round()));
        break;
      case 'volume':
        if (value is! num || !value.isFinite)
          throw const FormatException('Invalid volume.');
        await player.setVolume(value.toDouble().clamp(0, 1));
        break;
      case 'setShuffle':
        if (value is! bool) throw const FormatException('Invalid shuffle.');
        if (player.isShuffleNotifier.value != value)
          await player.toggleShuffle();
        break;
      case 'setRepeat':
        await player.setLoopMode(
          value == 'one'
              ? LoopMode.one
              : value == 'all'
              ? LoopMode.all
              : LoopMode.off,
        );
        break;
      case 'reorderQueue':
        if (value is! Map || value['from'] is! int || value['to'] is! int)
          throw const FormatException('Invalid queue move.');
        await player.moveQueueItem(value['from'] as int, value['to'] as int);
        break;
      case 'removeFromQueue':
        if (value is! Map || value['index'] is! int)
          throw const FormatException('Invalid queue entry.');
        await player.removeFromQueue(value['index'] as int);
        break;
      case 'handoffToDesktop':
        await playOnDesktop();
        break;
      case 'handoff':
        if (value is! Map) throw const FormatException('Invalid handoff.');
        await _receiveHandoff(Map<String, dynamic>.from(value));
        break;
      case 'copyTracksToPhone':
        await _receiveDesktopTrackCopies(value);
        break;
      default:
        throw const FormatException('Unsupported phone command.');
    }
    _publishLocalState();
  }

  Future<void> _receiveDesktopTrackCopies(Object? payload) async {
    if (payload is! Map || payload['tracks'] is! List) {
      throw const FormatException('Invalid desktop song list.');
    }
    final ids = validateDesktopTrackCopyIds(payload['tracks']);
    final credentials = _credentials;
    final socket = ref.read(lokalLinkServiceProvider);
    if (credentials == null || !state.socketConnected || !socket.connected) {
      throw const LokalRemoteProtocolException(
        'Reconnect to your paired desktop to copy songs.',
      );
    }
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      throw const LokalRemoteProtocolException(
        'Keep Lokal open in the foreground to copy songs.',
      );
    }
    final source = LokalDesktopSource.instance;
    final server = await source.ensureServer(credentials);
    state = state.copyWith(
      transferMessage: 'Preparing ${ids.length} songs from desktop…',
      transferHasError: false,
    );
    final result = await copyDesktopCatalogueTracks(
      requestedIds: ids,
      loadCatalogue: () => source.lookupCatalogueTracks(credentials, ids),
      isAlreadyPresent: (id) async {
        final rows = await Database.songs
            .filter()
            .remoteServerIdEqualTo(server.id)
            .remoteIdEqualTo(id)
            .findAll();
        return rows.any(isDownloadedDesktopOriginal);
      },
      copyTrack: (track) => source.copyOriginalToPhone(server, track),
      onProgress: (progress) {
        state = state.copyWith(
          transferMessage:
              'Copying ${progress.processed} of ${progress.total} songs from desktop…',
          transferHasError: false,
        );
      },
    );
    if (result.failures.isNotEmpty) {
      final completed = result.copied + result.alreadyPresent;
      final failures = result.failures.take(3).join('; ');
      final more = result.failures.length > 3
          ? '; and ${result.failures.length - 3} more'
          : '';
      final detail =
          'Copied $completed of ${result.requested} songs from desktop. $failures$more';
      state = state.copyWith(
        transferMessage: detail.length > 500
            ? detail.substring(0, 500)
            : detail,
        transferHasError: true,
      );
      throw LokalRemoteProtocolException(detail);
    }
    final already = result.alreadyPresent == 0
        ? ''
        : ' ${result.alreadyPresent} already on this phone.';
    state = state.copyWith(
      transferMessage: 'Copied ${result.copied} songs from desktop.$already',
      transferHasError: false,
    );
  }

  Future<void> playOnDesktop() async {
    final player = PlayerService(), queue = player.queueNotifier.value;
    if (queue.isEmpty)
      throw const LokalRemoteProtocolException(
        'Choose a song on this phone first.',
      );
    final volume = player.currentVolume;
    final prefs = await SharedPreferences.getInstance();
    if (_credentials != null &&
        prefs.getBool('lokal.link.${_credentials!.desktopId}.send_downloads') ==
            true) {
      final resolved = await ref.read(lokalLinkServiceProvider).request(
        'command',
        {
          'action': 'resolveTracks',
          'value': {'queue': queue.map(LinkJournal.instance.songWire).toList()},
        },
      );
      for (final index in resolved.body['missing'] as List? ?? const []) {
        if (index is int &&
            index >= 0 &&
            index < queue.length &&
            !queue[index].isNetworkSource)
          await LokalDesktopSource.instance.uploadToDesktop(
            queue[index],
            _credentials!,
          );
      }
    }
    // The receiver accepts the queue before the sender gives up playback.
    await sendRawCommand('handoff', {
      'queue': queue.map(LinkJournal.instance.songWire).toList(),
      'index': player.currentIndexNotifier.value,
      'positionMs': player.positionNotifier.value.inMilliseconds,
    });
    for (var step = 9; step >= 0; step--) {
      await player.setVolume(volume * step / 10);
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    await player.pause();
    await player.setVolume(volume);
    await setDesktopTarget(true);
  }

  Future<void> playOnPhone() async {
    final snapshot = state.snapshot;
    if (snapshot == null || snapshot.queue.isEmpty)
      throw const LokalRemoteProtocolException(
        'No desktop queue is available.',
      );
    await _receiveHandoff({
      'queue': snapshot.queue.map((track) => track.toJson()).toList(),
      'index': snapshot.currentIndex,
      'positionMs': (snapshot.progress * 1000).round(),
    });
    await sendRawCommand('fadePause');
  }

  Future<void> _receiveHandoff(Map<String, dynamic> value) => LokalDesktopSource
      .instance
      .runLibraryTransfer(() => _receiveHandoffTracked(value));

  Future<void> _receiveHandoffTracked(Map<String, dynamic> value) async {
    final raw = value['queue'], index = value['index'];
    if (raw is! List ||
        raw.isEmpty ||
        raw.length > 5000 ||
        index is! int ||
        index < 0 ||
        index >= raw.length ||
        _credentials == null)
      throw const FormatException('Invalid handoff queue.');
    final source = LokalDesktopSource.instance,
        server = await LokalDesktopSource.instance.ensureServer(_credentials!);
    final queue = <Song>[];
    for (final track in raw) {
      queue.add(
        await source.importTrack(
          server,
          Map<String, dynamic>.from(track as Map),
        ),
      );
    }
    // Cache the selected desktop file before changing either output.
    final selected = queue[index];
    if (selected.sourceType == 'lokal')
      await source.stream(
        server,
        selected.remoteId!,
        extension: selected.fileType,
      );
    final player = PlayerService(), volume = player.currentVolume;
    await setDesktopTarget(false);
    await player.setVolume(0);
    try {
      await player.play(selected, playlist: queue);
      await player.seek(
        Duration(
          milliseconds: math.max(0, (value['positionMs'] as num? ?? 0).round()),
        ),
      );
    } catch (_) {
      await player.setVolume(volume);
      rethrow;
    }
    for (var step = 1; step <= 10; step++) {
      await player.setVolume(volume * step / 10);
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  void _updateRemoteNotification() {
    final snapshot = state.snapshot, track = snapshot?.currentTrack;
    if (snapshot == null || track == null) return;
    final artworkKey = jsonEncode([
      _generation,
      track.id,
      track.title,
      track.artist,
      track.artworkPath,
      track.hasArtwork,
    ]);
    if (_notificationArtworkKey != artworkKey) {
      _notificationArtworkKey = artworkKey;
      _notificationArtwork = null;
      // Don't flash the previous desktop recording's cover when the queue
      // advances; replace it only after the new image has been resolved.
      if (state.remoteArtworkPath != null) {
        state = state.copyWith(clearRemoteArtwork: true);
      }
      _artworkAttempts = 0;
      _artworkRetryAfter = DateTime.fromMillisecondsSinceEpoch(0);
    }
    if (_notificationArtwork == null &&
        _artworkAttempts < 3 &&
        _loadingArtworkKey != artworkKey &&
        DateTime.now().isAfter(_artworkRetryAfter)) {
      unawaited(_loadNotificationArtwork(artworkKey, track.id));
    }
    final position = Duration(milliseconds: (snapshot.progress * 1000).round());
    final duration = desktopNotificationDuration(snapshot);
    if (_notificationTrack == artworkKey &&
        _notificationPlaying == snapshot.isPlaying &&
        _notificationFavorite == track.liked &&
        NotificationService().isClaimed) {
      unawaited(
        NotificationService().updateFor(
          _notificationOwner,
          position: position,
          isPlaying: snapshot.isPlaying,
          duration: duration,
          remoteVolume: snapshot.volume,
        ),
      );
      return;
    }
    _notificationTrack = artworkKey;
    _notificationPlaying = snapshot.isPlaying;
    _notificationFavorite = track.liked;
    unawaited(
      NotificationService().showFor(
        _notificationOwner,
        outputName: state.desktopName,
        isRemotePlayback: true,
        remoteVolume: snapshot.volume,
        song: Song(
          id: 'desktop:${track.id}',
          title: track.title,
          artist: track.artist,
          album: track.album,
          albumArt: _notificationArtwork,
          duration: duration,
          fileType: track.fileType,
        ),
        isPlaying: snapshot.isPlaying,
        isLive: false,
        isFavorite: track.liked,
        isShuffle: snapshot.shuffle,
        position: position,
      ),
    );
  }

  Future<void> _loadNotificationArtwork(String key, String? trackId) async {
    final credentials = _credentials;
    if (credentials == null || trackId == null) return;
    _loadingArtworkKey = key;
    _artworkAttempts++;
    try {
      final bytes = await ref
          .read(lokalRemoteServiceProvider)
          .fetchArtwork(credentials, trackId);
      if (_disposed || !state.controlsDesktop || _notificationArtworkKey != key)
        return;
      final file = await DefaultCacheManager().putFile(
        credentials.origin
            .replace(pathSegments: ['api', 'artwork', trackId])
            .toString(),
        Uint8List.fromList(bytes),
        fileExtension: 'img',
      );
      if (_disposed || !state.controlsDesktop || _notificationArtworkKey != key)
        return;
      _notificationArtwork = file.path;
      state = state.copyWith(remoteArtworkPath: file.path);
      _notificationTrack = null;
      _updateRemoteNotification();
    } catch (_) {
      // A transient failure must not strand this recording without artwork.
      if (_notificationArtworkKey == key) {
        _artworkRetryAfter = DateTime.now().add(
          Duration(seconds: 5 * _artworkAttempts),
        );
      }
    } finally {
      if (_loadingArtworkKey == key) _loadingArtworkKey = null;
    }
  }

  Future<void> _sendTheme(LokalAppearance appearance) async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed ||
        prefs.getBool('lokal.link.${_credentials?.desktopId}.theme') != true ||
        !ref.read(lokalLinkServiceProvider).connected)
      return;
    final color = appearance.tokens.accent
        .toARGB32()
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2);
    ref.read(lokalLinkServiceProvider).send('theme', {
      'theme': appearance.theme.name,
      'accent': appearance.accent?.name,
      'accentColor': '#$color',
    });
  }

  Future<void> _receiveTheme(Map<String, dynamic> body) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('lokal.link.${_credentials?.desktopId}.theme') != true)
      return;
    // Appearance validates names against the phone's supported Lokal presets.
    _receivingTheme = true;
    try {
      await ref.read(lokalAppearanceProvider.notifier).adoptDesktopTheme(body);
    } finally {
      _receivingTheme = false;
    }
  }

  Future<void> _poll() async {
    if (_polling || _disposed || !_shouldPoll) return;
    final credentials = _credentials;
    if (credentials == null) return;
    _polling = true;
    final generation = _generation;
    try {
      final snapshot = await ref
          .read(lokalRemoteServiceProvider)
          .fetchState(credentials);
      if (_disposed || generation != _generation) return;
      _failures = 0;
      final previous = state.snapshot;
      final stale =
          previous != null &&
          previous.updatedAt > 0 &&
          snapshot.updatedAt > 0 &&
          snapshot.updatedAt < previous.updatedAt;
      if (!stale) {
        state = state.copyWith(
          status: LokalRemoteConnectionStatus.connected,
          snapshot: snapshot,
          clearError: true,
          lastSeenAt: DateTime.now(),
        );
      } else {
        state = state.copyWith(
          status: LokalRemoteConnectionStatus.connected,
          clearError: true,
          lastSeenAt: DateTime.now(),
        );
      }
    } catch (error) {
      if (!_disposed && generation == _generation) _setFailure(error);
    } finally {
      _polling = false;
      if (!_disposed && generation == _generation && _shouldPoll) {
        _schedulePoll(_nextDelay());
      }
    }
  }

  Duration _nextDelay() {
    if (_failures == 0) return _pollInterval;
    final seconds = math.min(
      _maximumBackoff.inSeconds,
      1.2 * math.pow(2, _failures - 1),
    );
    return Duration(milliseconds: (seconds * 1000).round());
  }

  void _schedulePoll(Duration delay) {
    _pollTimer?.cancel();
    _pollTimer = Timer(delay, () {
      _pollTimer = null;
      unawaited(_poll());
    });
  }

  void _setFailure(Object error) {
    _failures++;
    final status = error is LokalRemoteAuthException
        ? LokalRemoteConnectionStatus.unauthorized
        : LokalRemoteConnectionStatus.offline;
    final message = error is LokalRemoteException
        ? error.message
        : 'Could not reach Lokal on the local network.';
    state = state.copyWith(status: status, error: message);
  }
}
