import 'package:flick/widgets/lokal/lokal_toast.dart';
import 'package:flick/services/motion_art/moving_cover_settings.dart';
import 'package:flick/services/link/lokal_desktop_source.dart';
import 'package:flick/l10n/l10n.dart';

import 'dart:async';
import 'dart:io';

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/konnekted_home.dart';
import 'package:flick/features/konnekted/library/lokal_navigation.dart';
import 'package:flick/features/konnekted/library/lokal_radio.dart';
import 'package:flick/features/music_videos/music_videos_page.dart';
import 'package:flick/features/player/widgets/add_to_playlist_sheet.dart';
import 'package:flick/features/search/online_song_save.dart';
import 'package:flick/features/player/widgets/share/share_bottom_sheet.dart';
import 'package:flick/features/player/widgets/song_metadata_sheet.dart';
import 'package:flick/features/songs/widgets/album_art_picker_bottom_sheet.dart';
import 'package:flick/features/songs/widgets/metadata_editor_bottom_sheet.dart';
import 'package:flick/models/song.dart';
import 'package:flick/features/konnekted/library/replayable_stream_songs.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/features/discovery/recommendation_match.dart';
import 'package:flick/providers/opt_in_source_provider.dart';
import 'package:flick/providers/providers.dart';
import 'package:flick/services/favorites_service.dart';
import 'package:flick/services/link/link_journal.dart';
import 'package:flick/services/link/link_protocol.dart';
import 'package:flick/services/link/link_song_bindings.dart';
import 'package:flick/services/link/transfer_artifact_cleaner.dart';
import 'package:flick/services/music_folder_service.dart';
import 'package:flick/services/player_service.dart';
import 'package:flick/services/playlist_service.dart';
import 'package:flick/widgets/lokal/settings/lokal_settings_surfaces.dart';
import 'package:flick/widgets/common/ios_transfer_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show ValueListenable, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Records a manual local song deletion in Link:
/// - If another local non-network song matches the same canonical recording
///   (cleaned artist/title + duration within 4s), merges likes, playlists, and
///   [LinkSongBindings] into that survivor and appends `track.deduplicate`.
/// - Otherwise removes the song from likes, playlists, and [LinkSongBindings],
///   and appends `track.delete`.
Future<void> recordLocalSongDeletionInLink(
  Song deletedSong, {
  SongRepository? songRepository,
  FavoritesService? favoritesService,
  PlaylistService? playlistService,
}) async {
  if (deletedSong.isNetworkSource || deletedSong.isExternal) return;
  final path = deletedSong.filePath?.trim() ?? '';
  if (path.startsWith('ghost://') ||
      path.startsWith('pending:') ||
      path.startsWith('lokal://')) {
    return;
  }

  await LinkSongBindings.instance.ensureLoaded();
  final preBinding = LinkSongBindings.instance.peek(
    deletedSong.id,
    filePath: deletedSong.filePath,
  );
  final sha = preBinding?.sha256;
  var deletedBytes = deletedSong.fileSizeBytes ?? 0;
  if (deletedBytes <= 0 &&
      path.isNotEmpty &&
      !path.startsWith('content://')) {
    try {
      final f = File(
        path.startsWith('file://') ? Uri.parse(path).toFilePath() : path,
      );
      if (f.existsSync()) deletedBytes = f.lengthSync();
    } catch (_) {}
  }

  final clean = cleanTransferMetadata(
    title: deletedSong.title,
    artist: deletedSong.artist,
  );
  final cleanKey = linkTrackKey(
    clean.artist,
    clean.title,
    deletedSong.duration,
  );
  final rawKey = linkTrackKey(
    deletedSong.artist,
    deletedSong.title,
    deletedSong.duration,
  );
  final aliasKey = await LinkJournal.instance.trackKeyFor(deletedSong);

  var deletedArtistKey = recommendationKey(leadArtist(clean.artist));
  if (deletedArtistKey.isEmpty) {
    deletedArtistKey = recommendationKey(clean.artist);
  }
  var deletedTitleKey = titleKey(clean.title);
  if (deletedTitleKey.isEmpty) {
    deletedTitleKey = recommendationKey(clean.title);
  }

  final repo = songRepository ?? SongRepository();
  final remaining = await repo.getAllSongs();

  Song? survivor;
  for (final candidate in remaining) {
    if (candidate.id == deletedSong.id ||
        candidate.isNetworkSource ||
        candidate.isExternal) {
      continue;
    }
    final candPath = candidate.filePath?.trim() ?? '';
    if (candPath.isEmpty ||
        candPath.startsWith('ghost://') ||
        candPath.startsWith('pending:') ||
        candPath.startsWith('lokal://')) {
      continue;
    }
    final candClean = cleanTransferMetadata(
      title: candidate.title,
      artist: candidate.artist,
    );
    var candArtistKey = recommendationKey(leadArtist(candClean.artist));
    if (candArtistKey.isEmpty) {
      candArtistKey = recommendationKey(candClean.artist);
    }
    var candTitleKey = titleKey(candClean.title);
    if (candTitleKey.isEmpty) {
      candTitleKey = recommendationKey(candClean.title);
    }
    if (deletedTitleKey.isEmpty ||
        candTitleKey != deletedTitleKey ||
        candArtistKey != deletedArtistKey) {
      continue;
    }
    final dA = deletedSong.duration.inMilliseconds;
    final dB = candidate.duration.inMilliseconds;
    if (dA > 0 && dB > 0 && (dA - dB).abs() > 4000) {
      continue;
    }
    survivor = candidate;
    break;
  }

  final favorites = favoritesService ?? FavoritesService(songRepository: repo);
  final playlists = playlistService ?? PlaylistService.instance;

  if (survivor != null) {
    final likedIds = await favorites.getFavoriteIds();
    if (likedIds.contains(deletedSong.id)) {
      if (!likedIds.contains(survivor.id)) {
        await favorites.addFavorite(survivor.id, song: survivor);
      }
      await favorites.removeFavorite(deletedSong.id);
    }
    for (final pl in await playlists.getPlaylists()) {
      if (pl.isNetworkSource || !pl.songIds.contains(deletedSong.id)) continue;
      final nextIds = <String>[];
      var placedKeep = false;
      for (final id in pl.songIds) {
        if (id == survivor.id || id == deletedSong.id) {
          if (!placedKeep) {
            placedKeep = true;
            nextIds.add(survivor.id);
          }
        } else {
          nextIds.add(id);
        }
      }
      await playlists.putFromLink(
        pl.copyWith(
          songIds: nextIds,
          songAddedAt: {...pl.songAddedAt}..remove(deletedSong.id),
          songSnapshots: {...pl.songSnapshots}..remove(deletedSong.id),
          updatedAt: DateTime.now(),
        ),
      );
    }

    final fallbackServers = <int, String>{
      if (survivor.remoteServerId != null &&
          survivor.remoteId != null &&
          survivor.remoteId!.isNotEmpty)
        survivor.remoteServerId!: survivor.remoteId!,
      if (deletedSong.remoteServerId != null &&
          deletedSong.remoteId != null &&
          deletedSong.remoteId!.isNotEmpty)
        deletedSong.remoteServerId!: deletedSong.remoteId!,
    };
    await LinkSongBindings.instance.mergeInto(
      keepSongId: survivor.id,
      loserSongIds: [deletedSong.id],
      keepFilePath: survivor.filePath,
      fallbackServers: fallbackServers,
    );
    final keepBinding = await LinkSongBindings.instance.getBinding(
      survivor.id,
      filePath: survivor.filePath,
    );
    final keepClean = cleanTransferMetadata(
      title: survivor.title,
      artist: survivor.artist,
    );
    final keepKey = linkTrackKey(
      keepClean.artist,
      keepClean.title,
      survivor.duration,
    );
    final removedKeys = <String>{
      for (final k in [rawKey, cleanKey, aliasKey])
        if (k.isNotEmpty && k != keepKey) k,
    }.toList();
    final removedHashes = <Map<String, dynamic>>[
      if (sha != null &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) &&
          deletedBytes > 0)
        {'sha256': sha, 'bytes': deletedBytes},
    ];
    await LinkJournal.instance.append(
      'track',
      keepKey,
      'track.deduplicate',
      {
        'keep_key': keepKey,
        'keep_hash': keepBinding?.sha256 ?? '',
        'title': keepClean.title,
        'artist': keepClean.artist,
        'album': survivor.album ?? '',
        'duration': (survivor.duration.inMilliseconds / 1000).round(),
        'removed_keys': removedKeys,
        'removed_hashes': removedHashes,
      },
    );
  } else {
    if ((await favorites.getFavoriteIds()).contains(deletedSong.id)) {
      await favorites.setFromLink(deletedSong.id, false);
    }
    for (final pl in await playlists.getPlaylists()) {
      if (!pl.isNetworkSource && pl.songIds.contains(deletedSong.id)) {
        await playlists.putFromLink(
          pl.copyWith(
            songIds: pl.songIds.where((id) => id != deletedSong.id).toList(),
            songAddedAt: {...pl.songAddedAt}..remove(deletedSong.id),
            songSnapshots: {...pl.songSnapshots}..remove(deletedSong.id),
            updatedAt: DateTime.now(),
          ),
        );
      }
    }
    await LinkSongBindings.instance.removeSong(deletedSong.id);
    await LinkJournal.instance.append(
      'track',
      cleanKey,
      'track.delete',
      {
        'track_key': cleanKey,
        if (rawKey != cleanKey) 'raw_track_key': rawKey,
        'file_hash': sha ?? '',
        'title': clean.title,
        'artist': clean.artist,
        'album': deletedSong.album ?? '',
        'duration': (deletedSong.duration.inMilliseconds / 1000).round(),
      },
    );
  }
}

/// One extra row in a song's menu for an action specific to its caller,
/// such as removing a queued song or restarting a connected USB DAC.
@immutable
class LokalSongMenuAction {
  const LokalSongMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;

  /// Runs after the menu closes.
  final VoidCallback onTap;
  final bool destructive;
}

/// The library/queue menu targets its explicitly selected song. The Now
/// Playing menu follows the live current song while it remains on screen.
/// Motion-art and video controls have dedicated, track-aware full-player
/// surfaces. They should not be repeated as unconditional song-menu rows.
@visibleForTesting
bool showMovingCoverMenuAction({
  required bool nowPlaying,
  bool hideMediaActions = false,
}) => !nowPlaying && !hideMediaActions;

@visibleForTesting
bool showWatchVideoMenuAction({
  required bool nowPlaying,
  required bool videosEnabled,
  bool hideMediaActions = false,
}) => !nowPlaying && !hideMediaActions && videosEnabled;

@visibleForTesting
bool showSendToDesktopMenuAction({
  required bool localFile,
  required bool connected,
}) => localFile && connected;

@visibleForTesting
Song? songForOpenMenu({
  required bool nowPlaying,
  required Song openedSong,
  required Song? currentSong,
}) => nowPlaying ? currentSong : openedSong;

class SongActionsBottomSheet extends ConsumerWidget {
  const SongActionsBottomSheet({
    super.key,
    required this.song,
    required this.rootContext,
    this.onSelect,
    this.onRemoveFromPlaylist,
    this.extras = const [],
    this.queueActions = true,
    this.nowPlaying = false,
    this.hideMediaActions = false,
  });

  final Song song;

  /// Where the menu was opened from; follow-up sheets and pages use it.
  final BuildContext rootContext;
  final VoidCallback? onSelect;
  final VoidCallback? onRemoveFromPlaylist;
  final List<LokalSongMenuAction> extras;

  /// Shows Play next and Add to queue (off inside the queue itself).
  final bool queueActions;

  /// Hides browsing actions that have dedicated controls in Now Playing.
  final bool nowPlaying;

  /// Full-player variants can retain their existing browse actions while
  /// hiding motion/video rows already surfaced on the player footer.
  final bool hideMediaActions;

  /// Opens the menu for [song].
  static Future<void> show(
    BuildContext context,
    Song song, {
    VoidCallback? onSelect,
    VoidCallback? onRemoveFromPlaylist,
    List<LokalSongMenuAction> extras = const [],
    bool queueActions = true,
    bool nowPlaying = false,
    bool hideMediaActions = false,
    bool followPlaybackSong = false,
    ValueListenable<Song?>? playbackSong,
  }) {
    final t = context.lokal;
    return showModalBottomSheet<void>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: t.surface,
      barrierColor: Colors.black.withValues(alpha: t.isLight ? .25 : .5),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: t.border),
      ),
      builder: (_) {
        Widget forSong(Song current) => SongActionsBottomSheet(
          key: ValueKey(current.id),
          song: current,
          rootContext: context,
          onSelect: onSelect,
          onRemoveFromPlaylist: onRemoveFromPlaylist,
          extras: extras,
          queueActions: queueActions,
          nowPlaying: nowPlaying,
          hideMediaActions: hideMediaActions,
        );
        if (!nowPlaying && !followPlaybackSong) return forSong(song);
        // The sheet can remain open while playback auto-advances. Do not
        // leave source-specific actions, metadata, or Like state stuck on
        // the song for which it was first opened.
        return ValueListenableBuilder<Song?>(
          valueListenable: playbackSong ?? PlayerService().currentSongNotifier,
          builder: (_, currentSong, __) {
            final liveSong = songForOpenMenu(
              nowPlaying: nowPlaying || followPlaybackSong,
              openedSong: song,
              currentSong: currentSong,
            );
            return liveSong == null
                ? const SizedBox.shrink()
                : forSong(liveSong);
          },
        );
      },
    );
  }

  bool get _isLocalFile =>
      song.filePath != null &&
      song.filePath!.isNotEmpty &&
      !song.isExternal &&
      !song.isNetworkSource;

  bool get _canEdit => _isLocalFile && song.startOffsetMs == null;

  bool get _canDelete => !song.isNetworkSource && int.tryParse(song.id) != null;

  void _say(String message) {
    if (!rootContext.mounted) return;
    LokalToast.show(rootContext, message, duration: const Duration(seconds: 2));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.lokal;
    final liked = ref.watch(isSongFavoriteProvider(song.id));
    final videos = ref.watch(musicVideosEnabledProvider);
    final desktopLink = ref.watch(lokalRemoteControllerProvider);
    final hasAlbum = song.album?.trim().isNotEmpty == true;
    // Actions run after the menu closes, so they read through the container,
    // not this widget's ref.
    final container = ProviderScope.containerOf(context, listen: false);

    /// Closes the menu, then runs [action].
    VoidCallback close(FutureOr<void> Function() action) => () {
      Navigator.of(context).pop();
      unawaited(Future<void>.sync(action));
    };

    final motionOff = ref
        .watch(movingCoverSettingsProvider)
        .disabledSongs
        .contains(movingCoverSongKey(song));
    final rows = <Widget>[
      if (showMovingCoverMenuAction(
        nowPlaying: nowPlaying,
        hideMediaActions: hideMediaActions,
      ))
        _MenuRow(
          icon: motionOff ? Icons.motion_photos_on : Icons.motion_photos_off,
          label: motionOff
              ? 'Enable moving cover for this song'
              : 'Disable moving cover for this song',
          onTap: close(
            () => container
                .read(movingCoverSettingsProvider.notifier)
                .setSongEnabled(movingCoverSongKey(song), motionOff),
          ),
        ),
      if (onRemoveFromPlaylist != null)
        _MenuRow(
          icon: Icons.playlist_remove_rounded,
          label: lokalText('Remove from playlist'),
          onTap: close(onRemoveFromPlaylist!),
        ),
      if (onSelect != null)
        _MenuRow(
          icon: Icons.checklist_rounded,
          label: lokalText('Select'),
          onTap: close(onSelect!),
        ),
      if (!nowPlaying && queueActions && !song.isFromLocker) ...[
        _MenuRow(
          icon: Icons.playlist_play_rounded,
          label: lokalText('Play next'),
          onTap: close(() async {
            final player = container.read(playerProvider.notifier);
            final index = await player.addToQueue(replayableStreamSong(song));
            if (index > 0) await player.moveQueueItemToNext(index);
            _say(lokalText("“{arg0}” plays next", args: {'arg0': song.title}));
          }),
        ),
        _MenuRow(
          icon: Icons.queue_music_rounded,
          label: lokalText('Add to queue'),
          onTap: close(() async {
            await container
                .read(playerProvider.notifier)
                .addToQueue(replayableStreamSong(song));
            _say(
              lokalText(
                "Added “{arg0}” to the queue",
                args: {'arg0': song.title},
              ),
            );
          }),
        ),
      ],
      if (OnlineSongSaveRegistry.instance.canSave(song))
        _MenuRow(
          icon: Icons.download_rounded,
          label: 'Download to library',
          onTap: close(() async {
            try {
              await OnlineSongSaveRegistry.instance.save(song);
              _say('Saved ${song.title} to your library');
            } catch (error) {
              _say('Could not save ${song.title}: $error');
            }
          }),
        ),
      if (song.sourceType == 'lokal')
        _MenuRow(
          icon: Icons.download_rounded,
          label: l10n.linkDownloadToPhone,
          onTap: close(() async {
            await LokalDesktopSource.instance.downloadToPhone(song);
            _say(l10n.linkDownloaded);
          }),
        ),
      if (showSendToDesktopMenuAction(
        localFile: _isLocalFile,
        connected: desktopLink.socketConnected,
      ))
        _MenuRow(
          icon: Icons.send_rounded,
          label: lokalText('Send to desktop'),
          onTap: close(() async {
            try {
              await container
                  .read(lokalRemoteControllerProvider.notifier)
                  .sendSongToDesktop(song);
              _say(
                lokalText(
                  'Sent “{arg0}” to desktop',
                  args: {'arg0': song.title},
                ),
              );
            } catch (error) {
              final reason = error is StateError
                  ? error.message
                  : 'Could not read or send the audio file. Reconnect and retry.';
              _say(
                lokalText(
                  'Could not send “{arg0}” to desktop: {arg1}',
                  args: {
                    'arg0': song.title,
                    'arg1': reason.length > 140
                        ? reason.substring(0, 140)
                        : reason,
                  },
                ),
              );
            }
          }),
        ),
      _MenuRow(
        icon: Icons.radio_rounded,
        label: lokalText('Start radio'),
        onTap: close(() => startLokalRadio(rootContext, seed: song)),
      ),
      _MenuRow(
        icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        label: liked ? lokalText('Unlike') : lokalText('Like'),
        highlighted: liked,
        onTap: close(() async {
          await container
              .read(favoritesProvider.notifier)
              .toggleFavorite(song.id, song: song);
          PlayerService().refreshNotificationState();
        }),
      ),
      _MenuRow(
        icon: Icons.playlist_add_rounded,
        label: lokalText('Add to a playlist'),
        onTap: close(() => AddToPlaylistSheet.show(rootContext, song)),
      ),
      if (!nowPlaying && hasAlbum)
        _MenuRow(
          icon: Icons.album_rounded,
          label: lokalText('Go to album'),
          onTap: close(() => openLokalAlbumForSong(rootContext, song)),
        ),
      if (!nowPlaying && song.artist.trim().isNotEmpty)
        _MenuRow(
          icon: Icons.person_rounded,
          label: lokalText('Go to artist'),
          onTap: close(() => openLokalArtist(rootContext, song: song)),
        ),
      // The full player already owns the track-verified Video footer chip.
      // The shared menu still offers Watch video from library/search rows.
      if (showWatchVideoMenuAction(
        nowPlaying: nowPlaying,
        videosEnabled: videos,
        hideMediaActions: hideMediaActions,
      ))
        _MenuRow(
          icon: Icons.smart_display_rounded,
          label: lokalText('Watch video'),
          onTap: close(() => watchMusicVideo(rootContext, song)),
        ),
      if (_canEdit)
        _MenuRow(
          icon: Icons.edit_rounded,
          label: lokalText('Edit info'),
          onTap: close(() async {
            final saved = await MetadataEditorBottomSheet.show(
              rootContext,
              song,
            );
            if (saved) container.invalidate(songsProvider);
          }),
        ),
      _MenuRow(
        icon: Icons.image_rounded,
        label: lokalText('Change artwork'),
        onTap: close(() async {
          final changed = await AlbumArtPickerBottomSheet.show(
            rootContext,
            song,
          );
          if (changed) container.invalidate(songsProvider);
        }),
      ),
      if (!nowPlaying)
        _MenuRow(
          icon: Icons.info_outline_rounded,
          label: lokalText('Song info'),
          onTap: close(() => SongMetadataSheet.show(rootContext, song)),
        ),
      if (_isLocalFile)
        _MenuRow(
          icon: Icons.ios_share_rounded,
          label: lokalText('Share'),
          onTap: close(
            () => SharePlus.instance.share(
              ShareParams(files: [XFile(song.filePath!)]),
            ),
          ),
        ),
      if (!nowPlaying)
        _MenuRow(
          icon: Icons.style_rounded,
          label: lokalText('Share as card'),
          onTap: close(
            () => showModalBottomSheet<void>(
              useRootNavigator: true,
              context: rootContext,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (_) => ShareBottomSheet(song: song),
            ),
          ),
        ),
      for (final extra in extras)
        _MenuRow(
          icon: extra.icon,
          label: extra.label,
          destructive: extra.destructive,
          onTap: close(extra.onTap),
        ),
      if (!nowPlaying && _canDelete) ...[
        Divider(height: 17, color: t.border, indent: 24, endIndent: 24),
        _MenuRow(
          icon: Icons.delete_outline_rounded,
          label: _isLocalFile
              ? lokalText('Delete from device')
              : lokalText('Remove from library'),
          destructive: true,
          onTap: close(_confirmDelete),
        ),
      ],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Row(
            children: [
              KonnektedArtwork(song: song, size: 52, radius: 8),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: LokalTheme.sans,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                    Text(
                      [
                        song.artist,
                        if (hasAlbum) song.album!.trim(),
                      ].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: t.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: t.border),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              top: 6,
              bottom: 12 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete() async {
    if (!rootContext.mounted) return;
    final container = ProviderScope.containerOf(rootContext, listen: false);
    final choice = await showLokalSettingsSheet<String>(
      context: rootContext,
      title: lokalText("Delete “{arg0}”?", args: {'arg0': song.title}),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LokalSheetOption(
            icon: Icons.library_music_outlined,
            label: lokalText('Remove from library'),
            description: _isLocalFile
                ? lokalText('The file stays on your device.')
                : lokalText('You can add it again by rescanning.'),
            onTap: () => Navigator.of(context).pop('remove'),
          ),
          if (_isLocalFile)
            LokalSheetOption(
              icon: Icons.delete_forever_rounded,
              label: lokalText('Delete from device'),
              description: lokalText(
                'Deletes the file too. This can’t be undone.',
              ),
              onTap: () => Navigator.of(context).pop('file'),
            ),
          LokalSheetOption(
            label: lokalText('Cancel'),
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
    if (choice == null || !rootContext.mounted) return;
    await IosTransferRoot.withMutationBarrier(
      rootContext,
      () => _delete(container, deleteFile: choice == 'file'),
    );
  }

  Future<void> _delete(
    ProviderContainer container, {
    required bool deleteFile,
  }) async {
    final songId = int.tryParse(song.id);
    if (songId == null) return;
    final repo = container.read(songRepositoryProvider);
    await repo.deleteSong(songId);
    var deleted = !deleteFile;
    if (deleteFile && song.filePath != null) {
      try {
        deleted = await MusicFolderService.deleteDocument(
          folderTreeUri: song.folderUri ?? song.filePath!,
          filePath: song.filePath!,
        );
      } catch (_) {}
      if (!deleted) {
        try {
          final file = File(song.filePath!);
          if (await file.exists()) await file.delete();
          deleted = true;
        } catch (_) {}
      }
      if (deleted) {
        await MusicFolderService.removeFromMediaStore(song.filePath!);
      }
    }
    if (deleteFile && deleted) {
      await recordLocalSongDeletionInLink(
        song,
        songRepository: repo,
        favoritesService: container.read(favoritesServiceProvider),
        playlistService: container.read(playlistServiceProvider),
      );
    }
    container.invalidate(songsProvider);
    container.invalidate(favoritesProvider);
    container.invalidate(playlistsProvider);
    _say(
      !deleteFile
          ? lokalText(
              "Removed “{arg0}” from your library",
              args: {'arg0': song.title},
            )
          : deleted
          ? lokalText("Deleted “{arg0}”", args: {'arg0': song.title})
          : lokalText(
              'Removed from your library, but couldn’t delete the file',
            ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final color = destructive ? t.red : t.text;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: destructive
                      ? t.red
                      : (highlighted ? t.accent : t.muted),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: LokalTheme.sans,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: color,
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
}
