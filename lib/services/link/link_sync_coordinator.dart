import '../milestone_service.dart';
import '../local_metadata_repair.dart';
import '../../models/song.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/database.dart';
import '../../data/repositories/recently_played_repository.dart';
import '../../data/repositories/song_repository.dart';
import '../../models/lokal_remote_state.dart';
import '../../models/playlist.dart';
import '../duplicate_cleaner_service.dart';
import '../favorites_service.dart';
import '../playlist_service.dart';
import '../online_playlist_reference.dart';
import 'link_journal.dart';
import 'link_protocol.dart';
import 'link_song_bindings.dart';
import 'copied_track_clip.dart';
import 'link_playlist_order.dart';
import 'link_profile_service.dart';
import 'lokal_desktop_source.dart';
import 'lokal_link_service.dart';
import 'transfer_artifact_cleaner.dart';

/// Symmetric, cursor-based merge. Only explicit operations remove playlist items;
/// a missing desktop row can never delete a phone file, like, or playlist.
class LinkSyncCoordinator {
  LinkSyncCoordinator({
    required this.socket,
    required this.credentials,
    required this.favorites,
    this.onChanged,
    this.onProfileChanged,
    this.onProgress,
    this.initialProgress = const LinkSyncProgress(),
    this.deletePhysicalFile,
  });
  final LokalLinkService socket;
  final LokalRemoteCredentials credentials;
  final FavoritesService favorites;
  final void Function()? onChanged;
  final void Function()? onProfileChanged;
  final void Function(LinkSyncProgress)? onProgress;
  final LinkSyncProgress initialProgress;
  final Future<void> Function(SongEntity)? deletePhysicalFile;
  late LinkSyncProgress _progress = initialProgress;
  Future<void>? _active;
  bool _background = false;
  List<Song>? _matchCandidates;
  final _matchCache = <String, Song?>{};
  bool get busy => _active != null;

  Future<Song?> _match(Map<String, dynamic> track) async {
    final key = track['track_key']?.toString();
    if (key != null && _matchCache.containsKey(key)) return _matchCache[key];
    final song = await LinkJournal.instance.match(
      track,
      candidates: _matchCandidates,
    );
    if (key != null) _matchCache[key] = song;
    return song;
  }

  static String prefixFor(LokalRemoteCredentials value) =>
      'lokal.link.${value.desktopId}.user.${value.desktopUserId ?? 'guest'}';
  String get _prefix => prefixFor(credentials);
  Future<void> enableMerge() async {
    final active = _active;
    if (active != null) await active;
    await _run(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_prefix.merge', true);
      final ids = (prefs.getStringList('favorite_song_ids') ?? []).toSet();
      await LinkJournal.instance.captureFavorites(ids);
      await LinkJournal.instance.capturePlaylists(
        await PlaylistService.instance.getPlaylists(),
      );
      await _synchronize(importCatalog: true);
    });
  }

  void _report(
    LinkSyncPhase phase, {
    int processed = 0,
    int? total,
    int? catalogSongs,
    DateTime? completedAt,
  }) {
    if (_background) return;
    _progress = LinkSyncProgress(
      phase: phase,
      processed: processed,
      total: total,
      catalogSongs: catalogSongs ?? _progress.catalogSongs,
      completedAt: completedAt ?? _progress.completedAt,
    );
    onProgress?.call(_progress);
  }

  void _requireReady() {
    if (!socket.connected) throw StateError('Desktop link disconnected.');
    if (!Database.isInitialized) {
      throw StateError('The music library is not ready.');
    }
  }

  Future<void> _run(Future<void> Function() action, {bool fullSync = true}) {
    final active = _active;
    if (active != null) return active;
    final task = LokalDesktopSource.instance.runLibraryTransfer(() {
      LokalDesktopSource.instance.cancelLibraryTransferOnPause(() {
        unawaited(socket.disconnect().catchError((Object _) {}));
      });
      return _execute(action, fullSync: fullSync);
    });
    _active = task;
    return task.whenComplete(() {
      if (identical(_active, task)) _active = null;
    });
  }

  Future<void> _execute(
    Future<void> Function() action, {
    bool fullSync = true,
  }) async {
    if (fullSync) _report(LinkSyncPhase.preparing);
    try {
      _requireReady();
      await action();
      _requireReady();
      // Statistics do not advance the full-library sync timestamp.
      if (fullSync) {
        final completedAt = DateTime.now();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
          '$_prefix.last_sync',
          completedAt.millisecondsSinceEpoch,
        );
        if (_progress.catalogSongs case final count?) {
          await prefs.setInt('$_prefix.catalog_songs', count);
        }
        _report(LinkSyncPhase.complete, completedAt: completedAt);
      }
    } catch (_) {
      _report(
        LinkSyncPhase.paused,
        processed: _progress.processed,
        total: _progress.total,
      );
      rethrow;
    } finally {
      _matchCandidates = null;
      _matchCache.clear();
    }
  }

  Future<void> _backfillHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('lokal.link.history_backfilled') == true) return;
    final device = await LinkJournal.instance.deviceId();
    final rows = await Database.recentlyPlayed
        .filter()
        .eventIdIsNull()
        .findAll();
    final songs = {
      for (final song in await SongRepository().getAllSongs()) song.id: song,
    };
    for (final row in rows) {
      final song = songs[row.songId.toString()];
      if (song == null) continue;
      final id = 'mobile_${device}_${row.id}';
      // Legacy history retained song duration, not measured listen time. Keep
      // that existing estimate rather than inventing a new historic measurement.
      await LinkJournal.instance.recordPlay(
        eventId: id,
        songId: song.id,
        playedAt: row.playedAt.millisecondsSinceEpoch,
        msPlayed: row.listenedMs ?? song.duration.inMilliseconds,
      );
      row.eventId = id;
      await Database.instance.writeTxn(() => Database.recentlyPlayed.put(row));
    }
    await prefs.setBool('lokal.link.history_backfilled', true);
  }

  Future<void> synchronize({
    bool importCatalog = false,
    bool background = false,
  }) async {
    final active = _active;
    if (active != null) return active;
    if (!socket.connected || !Database.isInitialized) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('$_prefix.merge') != true) return;
    _background = background;
    try {
      await _run(() => _synchronize(importCatalog: importCatalog));
    } finally {
      _background = false;
    }
  }

  /// Automatic listening-statistics synchronization: one bounded journal page
  /// in each direction, no catalog, file, playlist, tag or lyrics operations.
  /// Older listening history is left for a later tick or manual full sync.
  Future<void> synchronizeStats() async {
    if (_active != null || !socket.connected || !Database.isInitialized) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('$_prefix.merge') != true || _active != null) return;
    _background = true;
    try {
      await _run(_syncStatsBatch, fullSync: false);
    } finally {
      _background = false;
    }
  }

  Future<void> _syncStatsBatch() async {
    _requireReady();
    final prefs = await SharedPreferences.getInstance();
    final journal = LinkJournal.instance;
    const pageSize = 50;

    // One acknowledged outbound page per run, then checkpoint the cursor.
    final pushKey = '$_prefix.history.push';
    final outgoing = await journal.historyAfter(
      prefs.getInt(pushKey) ?? 0,
      limit: pageSize,
    );
    final pushed = outgoing['items'] as List;
    if (pushed.isNotEmpty) {
      await socket.request('history.push', {'items': pushed});
      _requireReady();
      await prefs.setInt(pushKey, outgoing['cursor'] as int);
      // The history cursor never waits on cover decoding or image transfer.
      // Art upload is bounded and can retry separately from listening stats.
      unawaited(
        LokalDesktopSource.instance.uploadHistoryArtwork(
          credentials,
          pushed,
          maxCovers: 2,
        ),
      );
    }

    // The desktop currently caps replies at 250 events. Consume only one
    // response per cycle to avoid monopolizing launch or playback resources.
    final pullKey = '$_prefix.history.pull';
    final reply = await socket.request('history.pull', {
      'cursor': prefs.getInt(pullKey) ?? 0,
    });
    _requireReady();
    final incoming = reply.body['items'];
    final nextCursor = reply.body['cursor'];
    if (incoming is! List || incoming.length > 250 || nextCursor is! int) {
      throw const FormatException('Invalid desktop listening-history page.');
    }
    if (incoming.isNotEmpty) {
      final accepted = await journal.mergeHistory(incoming);
      final songs = SongRepository();
      final candidatesByTitle = <String, List<Song>>{};
      final projected =
          <
            ({String songId, String eventId, DateTime playedAt, int listenedMs})
          >[];
      for (final item in accepted) {
        // The journal always retains remote-only plays. Local recent history
        // is updated only for bounded, matching phone songs.
        final rawTrack = item['track'];
        Object? track = rawTrack;
        if (track is! Map && item['track_json'] is String) {
          try {
            track = jsonDecode(item['track_json'] as String);
          } on FormatException {
            // Keep the play in the stats journal even if its optional
            // track metadata cannot be projected to local recent history.
            continue;
          }
        }
        if (track is! Map) continue;
        final wire = Map<String, dynamic>.from(track);
        final title = wire['title'] as String? ?? '';
        if (title.isEmpty) continue;
        final candidates = candidatesByTitle[title] ??= await songs
            .getHistoryMatchCandidates(title);
        if (candidates.isEmpty) continue;
        final song = await journal.match(wire, candidates: candidates);
        if (song == null) continue;
        projected.add((
          songId: song.id,
          eventId: item['event_id'] as String,
          playedAt: DateTime.fromMillisecondsSinceEpoch(
            item['played_at'] as int,
          ),
          listenedMs: item['ms_played'] as int,
        ));
      }
      await RecentlyPlayedRepository().recordLinkPlays(projected);
      MilestoneService.changes.add(null);
    }
    // Only advance after journal and any matching local-history projections
    // were committed; interrupted runs can safely replay deduplicated events.
    await prefs.setInt(pullKey, nextCursor);
  }

  Future<void> _synchronize({required bool importCatalog}) async {
    final prefs = await SharedPreferences.getInstance();
    final source = LokalDesktopSource.instance,
        server = await LokalDesktopSource.instance.ensureServer(credentials);
    // Startup remains lightweight: only an explicit user-triggered full sync
    // or a first-time merge walks the desktop catalogue. A one-time import
    // prevents subsequently added PC tracks from ever reaching mobile.
    final refreshCatalog =
        importCatalog ||
        !_background ||
        prefs.getBool('$_prefix.catalog') != true ||
        prefs.getBool('$_prefix.owned_catalog_v2') != true;
    final reconcileGenres =
        !refreshCatalog &&
        prefs.getBool('$_prefix.catalog') == true &&
        prefs.getBool('$_prefix.owned_catalog_v2') == true;
    if (refreshCatalog) {
      _report(LinkSyncPhase.catalog);
      await for (final progress in source.syncLibrary(server)) {
        _requireReady();
        _report(
          LinkSyncPhase.catalog,
          processed: progress.filesProcessed,
          total: progress.totalFiles,
          catalogSongs: progress.totalFiles,
        );
      }
      await prefs.setBool('$_prefix.catalog', true);
      await prefs.setBool('$_prefix.owned_catalog_v2', true);
      onChanged?.call();
    }
    if (!_background) {
      await LocalMetadataRepair.instance.repairDesktopCopies(
        onProgress: (done, total) {
          _report(LinkSyncPhase.metadata, processed: done, total: total);
        },
      );
      _report(LinkSyncPhase.lyrics);
      await source.syncCopiedLyrics(
        server,
        stillCurrent: () => socket.connected,
        onProgress: (done, total) =>
            _report(LinkSyncPhase.lyrics, processed: done, total: total),
      );
    }
    _requireReady();
    var changed = false;
    for (final kind in ['library', 'history']) {
      if (kind == 'history') await _backfillHistory();
      if (kind == 'library') {
        // Older clients recorded some online-only IDs in the favorites
        // baseline without journaling their like. Reconcile durable hearts
        // before reading the outgoing cursor so Sync Now repairs them.
        final likedIds =
            (prefs.getStringList('favorite_song_ids') ?? []).toSet();
        await LinkJournal.instance.captureFavorites(likedIds);
      }
      _requireReady();
      final phase = kind == 'history'
          ? LinkSyncPhase.history
          : LinkSyncPhase.library;
      var processed = 0;
      _report(phase);
      final pushKey = '$_prefix.$kind.push';
      while (socket.connected) {
        final cursor = prefs.getInt(pushKey) ?? 0;
        final batch = kind == 'history'
            ? await LinkJournal.instance.historyAfter(cursor)
            : await LinkJournal.instance.libraryAfter(
                cursor,
                includeTrackLifecycle: socket.supportsTrackLifecycle,
              );
        final items = batch['items'] as List;
        final nextCursor = batch['cursor'] as int;
        if (items.isNotEmpty) {
          await socket.request('$kind.push', {'items': items});
          processed += items.length;
          _report(phase, processed: processed);
        }
        if (nextCursor == cursor) break;
        await prefs.setInt(pushKey, nextCursor);
        if (batch['hasMore'] != true) break;
      }
      final pullKey = '$_prefix.$kind.pull';
      while (socket.connected) {
        final reply = await socket.request('$kind.pull', {
          'cursor': prefs.getInt(pullKey) ?? 0,
          if (kind == 'library') 'trackLifecycle': true,
        });
        final items = reply.body['items'];
        if (items is! List || reply.body['cursor'] is! int) {
          throw const FormatException('Invalid desktop sync page.');
        }
        if (items.isNotEmpty) {
          changed = true;
          _matchCandidates ??= List<Song>.of(
            await SongRepository().getAllSongs(),
          );
        }
        if (kind == 'history') {
          final added = await LinkJournal.instance.mergeHistory(items);
          for (final item in added) {
            var song = await _match(item);
            // History is not ownership: retain the play event in the journal,
            // but never create a library song just because it was streamed.
            if (song != null) {
              await RecentlyPlayedRepository().recordPlay(
                song.id,
                eventId: item['event_id'] as String,
                playedAt: DateTime.fromMillisecondsSinceEpoch(
                  item['played_at'] as int,
                ),
                listenedMs: item['ms_played'] as int,
              );
            }
          }
        } else {
          final added = await LinkJournal.instance.mergeLibrary(items);
          if (added.isNotEmpty) {
            await _materializeLibraryPage(added);
            onChanged?.call();
          }
        }
        await prefs.setInt(pullKey, reply.body['cursor'] as int);
        processed += items.length;
        _report(phase, processed: processed);
        if (reply.body['hasMore'] != true) break;
      }
    }
    if (!_background && reconcileGenres) {
      _report(LinkSyncPhase.metadata);
      final repaired = await source.reconcileMissingGenres(
        server,
        stillCurrent: () => socket.connected,
      );
      if (repaired > 0) {
        changed = true;
        onChanged?.call();
      }
    }
    // A cursor only returns new events. Explicit Sync Now must also rebuild
    // playlists missing from the mobile store after a legacy or partial merge.
    // Replaying their durable operation history also repairs order and deletes.
    if (!_background) {
      await _reconcileDesktopPlaylists();
      await _reconcileRecentDesktopHistory();
      // Backfill cover art for plays acknowledged by older desktop versions.
      // Do not make a successful full sync wait for optional image uploads.
      unawaited(source.uploadRecentHistoryArtwork(credentials, maxCovers: 8));
    }
    _requireReady();
    _report(LinkSyncPhase.finalizing);
    if (!_background) {
      await LinkProfileService.sync(credentials);
      onProfileChanged?.call();
    }
    if (changed || !_background) MilestoneService.changes.add(null);
  }

  /// Repair history which was received before its PC songs were in the
  /// phone's catalogue. Pull cursors are append-only, so those old events
  /// would otherwise never be projected into the visible Recent history.
  /// Only the latest 500 events are checked; all older events remain safely
  /// stored in the journal for listening statistics.
  Future<void> _reconcileRecentDesktopHistory() async {
    final rows = await Database.instance.playEventEntitys
        .where()
        .sortByPlayedAtDesc()
        .limit(500)
        .findAll();
    if (rows.isEmpty) return;
    final songs = SongRepository();
    final journal = LinkJournal.instance;
    final byTitle = <String, List<Song>>{};
    final byTrack = <String, Song?>{};
    final projected =
        <
          ({String songId, String eventId, DateTime playedAt, int listenedMs})
        >[];
    for (final event in rows) {
      if (event.source != 'desktop') continue;
      Map<String, dynamic> track;
      try {
        track = Map<String, dynamic>.from(jsonDecode(event.trackJson) as Map);
      } on Object {
        continue;
      }
      final title = track['title']?.toString() ?? '';
      if (title.isEmpty) continue;
      final song = byTrack.containsKey(event.trackKey)
          ? byTrack[event.trackKey]
          : await journal.match(
              {...track, 'track_key': event.trackKey},
              candidates: byTitle[title] ??= await songs
                  .getHistoryMatchCandidates(title),
            );
      byTrack[event.trackKey] = song;
      if (song == null) continue;
      projected.add((
        songId: song.id,
        eventId: event.eventId,
        playedAt: DateTime.fromMillisecondsSinceEpoch(event.playedAt),
        listenedMs: event.msPlayed,
      ));
    }
    await RecentlyPlayedRepository().recordLinkPlays(projected);
  }

  /// Recover every playlist owned by the paired desktop on an explicit sync,
  /// even when the pull cursor has advanced or its local copy disappeared.
  /// The journal is authoritative for deletes, so this does not resurrect
  /// intentionally removed playlists. Mobile-origin and other desktop users'
  /// playlists are not reconstructed from unrelated operations.
  Future<void> _reconcileDesktopPlaylists() async {
    final desktopId = credentials.desktopId;
    if (desktopId == null || desktopId.isEmpty) return;

    final operations = await Database.instance.libraryOpEntitys
        .filter()
        .entityEqualTo('playlist')
        .findAll();
    final desktopPlaylistIds = <String>{};
    final desktopDeletions = <String>{};
    for (final operation in operations) {
      if (operation.deviceId != desktopId) continue;
      if (operation.op == 'playlist.create') {
        desktopPlaylistIds.add(operation.entityId);
      } else if (operation.op == 'playlist.delete') {
        desktopDeletions.add(operation.entityId);
      }
    }
    // A playlist originally created on the phone can later be deleted on
    // desktop. Include mapped deletions so an old consumed cursor cannot
    // silently leave the deleted mobile copy behind.
    final prefs = await SharedPreferences.getInstance();
    for (final id in desktopDeletions) {
      if (prefs.getString('lokal.link.playlist_local.$id') != null) {
        desktopPlaylistIds.add(id);
      }
    }
    var reconciled = false;
    for (final id in desktopPlaylistIds) {
      _requireReady();
      await _materialize({
        'entity': 'playlist',
        'entity_id': id,
        'op': 'playlist.create',
        'fields': <String, dynamic>{},
      });
      reconciled = true;
    }
    if (reconciled) onChanged?.call();
  }

  @visibleForTesting
  Future<void> materializeLibraryPageForTesting(
    List<Map<String, dynamic>> items,
  ) => _materializeLibraryPage(items);

  Future<void> _materializeLibraryPage(List<Map<String, dynamic>> items) async {
    final prevApplying = LinkJournal.instance.applyingRemote;
    LinkJournal.instance.applyingRemote = true;
    try {
      final playlists = <String, Map<String, dynamic>>{};
      final likes = <String, bool>{};
      for (final item in items) {
        if (item['entity'] == 'playlist') {
          playlists[item['entity_id'] as String] = item;
        } else if (item['entity'] == 'like') {
          if (!await LinkJournal.instance.wins(item, 'liked')) continue;
          final song = await _match({
            ...Map<String, dynamic>.from(item['fields'] as Map),
            'track_key': item['entity_id'],
          });
          if (song != null) likes[song.id] = item['op'] == 'like';
        } else {
          await _materialize(item);
        }
      }
      if (likes.isNotEmpty) await favorites.setManyFromLink(likes);
      // mergeLibrary has already persisted every operation in this page. One
      // replay per playlist produces the same state as replaying it per member.
      for (final item in playlists.values) {
        await _materialize(item);
      }
    } finally {
      LinkJournal.instance.applyingRemote = prevApplying;
    }
  }

  Future<void> _applyTrackDeduplicate(
    Map<String, dynamic> item,
    Map<String, dynamic> fields,
  ) async {
    final journal = LinkJournal.instance;
    final keepKey =
        fields['keep_key']?.toString().trim() ??
        item['entity_id']?.toString().trim() ??
        '';
    final rawRemoved = fields['removed_keys'];
    final removedKeys = <String>[
      if (rawRemoved is List)
        for (final entry in rawRemoved.take(200))
          if (entry != null && entry.toString().trim().isNotEmpty)
            entry.toString().trim(),
    ];
    if (keepKey.isNotEmpty && removedKeys.isNotEmpty) {
      await journal.registerKeyRedirects(removedKeys, keepKey);
    }

    await LinkSongBindings.instance.ensureLoaded();
    final keepHash = fields['keep_hash']?.toString().trim().toLowerCase() ?? '';
    final rawHashes = fields['removed_hashes'];
    final hashSet = <String>{
      if (RegExp(r'^[0-9a-f]{64}$').hasMatch(keepHash)) keepHash,
      if (rawHashes is List)
        for (final entry in rawHashes.take(200))
          if (entry is Map)
            if (RegExp(
              r'^[0-9a-f]{64}$',
            ).hasMatch(entry['sha256']?.toString().trim().toLowerCase() ?? ''))
              entry['sha256'].toString().trim().toLowerCase(),
    };

    final allKeys = <String>{
      if (keepKey.isNotEmpty) keepKey,
      ...removedKeys,
    };

    final probeTitle = fields['title']?.toString() ?? '';
    final probeArtist = fields['artist']?.toString() ?? '';
    final probeDurationSec = (fields['duration'] as num?)?.toDouble() ?? 0;
    final probeIdentity = canonicalDuplicateIdentity(
      title: probeTitle,
      artist: probeArtist,
    );

    final repo = SongRepository();
    final allEntities = await repo.getAllSongEntities();
    final matchedLocal = <int, SongEntity>{};

    for (final entity in allEntities) {
      if (!isLocalDuplicateCandidate(entity)) continue;
      final songIdStr = entity.id.toString();
      final binding = LinkSongBindings.instance.peek(
        songIdStr,
        filePath: entity.filePath,
      );
      if (binding?.sha256 != null && hashSet.contains(binding!.sha256)) {
        matchedLocal[entity.id] = entity;
        continue;
      }

      final songModel = repo.songFromEntity(entity);
      final songTrackKey = await journal.trackKeyFor(songModel);
      final rawSongKey = linkTrackKey(
        entity.artist,
        entity.title,
        Duration(milliseconds: entity.durationMs ?? 0),
      );
      final cleanMeta = cleanTransferMetadata(
        title: entity.title,
        artist: entity.artist,
      );
      final cleanSongKey = linkTrackKey(
        cleanMeta.artist,
        cleanMeta.title,
        Duration(milliseconds: entity.durationMs ?? 0),
      );
      if (allKeys.contains(songTrackKey) ||
          allKeys.contains(rawSongKey) ||
          allKeys.contains(cleanSongKey)) {
        matchedLocal[entity.id] = entity;
        continue;
      }

      if (probeIdentity.titleKey.isNotEmpty) {
        final candIdentity = canonicalDuplicateIdentity(
          title: entity.title,
          artist: entity.artist,
        );
        if (candIdentity.titleKey == probeIdentity.titleKey &&
            candIdentity.artistKey == probeIdentity.artistKey) {
          final candSec = (entity.durationMs ?? 0) / 1000.0;
          if (probeDurationSec <= 0 ||
              candSec <= 0 ||
              (candSec - probeDurationSec).abs() <= 4.0) {
            matchedLocal[entity.id] = entity;
          }
        }
      }
    }

    if (matchedLocal.isEmpty) return;

    final candidates = matchedLocal.values.toList();
    if (candidates.length == 1) {
      // NEVER delete the sole local copy — only teach its canonical alias and
      // clean transfer artifacts on its metadata if needed.
      final sole = candidates.single;
      if (keepKey.isNotEmpty) {
        await journal.registerTrackAlias(
          sole.id.toString(),
          keepKey,
          overwrite: true,
        );
      }
      final cleaned = cleanTransferMetadata(
        title: sole.title,
        artist: sole.artist,
      );
      if (cleaned.changed) {
        await Database.instance.writeTxn(() async {
          final current = await Database.songs.get(sole.id);
          if (current == null) return;
          current.title = cleaned.title;
          current.artist = cleaned.artist;
          await Database.songs.put(current);
        });
      }
      _matchCandidates = null;
      _matchCache.clear();
      return;
    }

    // >= 2 local copies exist: merge them via DuplicateCleanerService
    // (emitJournal: false) keeping the 1 best-quality local copy and deleting
    // redundant duplicate file(s)!
    final playCountMap = await RecentlyPlayedRepository().getPlayCounts();
    final groupPlayCounts = <int, int>{
      for (final c in candidates)
        c.id: playCountMap[c.id.toString()] ?? 0,
    };
    final group = DuplicateGroup(
      key: keepKey.isNotEmpty ? keepKey : 'remote_dedup',
      songs: candidates,
      playCounts: groupPlayCounts,
    );
    final cleaner = DuplicateCleanerService(
      songRepository: repo,
      favoritesService: favorites,
      playlistService: PlaylistService.instance,
      deletePhysicalFile: deletePhysicalFile,
      emitJournal: false,
    );
    final keeperId = group.recommendedKeep.id;
    await cleaner.mergeAndRemoveGroup(
      group,
      keepId: keeperId,
      emitJournal: false,
    );
    if (keepKey.isNotEmpty) {
      await journal.registerTrackAlias(
        keeperId.toString(),
        keepKey,
        overwrite: true,
      );
    }
    _matchCandidates = null;
    _matchCache.clear();
  }

  Future<void> _applyTrackDelete(
    Map<String, dynamic> item,
    Map<String, dynamic> fields,
  ) async {
    final journal = LinkJournal.instance;
    if (!await journal.wins(item, 'deleted')) return;

    final hlcStr = item['hlc']?.toString() ?? '';
    final hlcMs = int.tryParse(hlcStr.split(':').first) ?? 0;
    final limitMs = hlcMs + 5000;

    final key =
        fields['track_key']?.toString().trim() ??
        item['entity_id']?.toString().trim() ??
        '';
    final rawKey = fields['raw_track_key']?.toString().trim() ?? '';
    final fileHash = fields['file_hash']?.toString().trim().toLowerCase() ?? '';
    final targetKeys = <String>{
      if (key.isNotEmpty) key,
      if (rawKey.isNotEmpty) rawKey,
      if (item['entity_id'] != null &&
          item['entity_id'].toString().trim().isNotEmpty)
        item['entity_id'].toString().trim(),
    };

    final parts = key.split('|');
    final parsedDur = parts.isNotEmpty
        ? double.tryParse(parts.removeLast()) ?? 0
        : 0;
    final parsedTitle = parts.isNotEmpty ? parts.removeLast() : '';
    final parsedArtist = parts.join('|');

    final probeTitle = fields['title']?.toString().trim().isNotEmpty == true
        ? fields['title'].toString().trim()
        : parsedTitle;
    final probeArtist = fields['artist']?.toString().trim().isNotEmpty == true
        ? fields['artist'].toString().trim()
        : parsedArtist;
    final probeDurSec = (fields['duration'] as num?)?.toDouble() ?? parsedDur;
    final probeIdentity = canonicalDuplicateIdentity(
      title: probeTitle,
      artist: probeArtist,
    );

    await LinkSongBindings.instance.ensureLoaded();
    final repo = SongRepository();
    final allEntities = await repo.getAllSongEntities();

    final remoteStreamVictimIds = <int>[];
    final localVictims = <SongEntity>[];

    for (final entity in allEntities) {
      final songIdStr = entity.id.toString();
      final binding = LinkSongBindings.instance.peek(
        songIdStr,
        filePath: entity.filePath,
      );
      var matched = false;
      if (fileHash.isNotEmpty &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(fileHash) &&
          binding?.sha256 == fileHash) {
        matched = true;
      }
      if (!matched) {
        final songModel = repo.songFromEntity(entity);
        final alias = await journal.trackKeyFor(songModel);
        final entityRawKey = linkTrackKey(
          entity.artist,
          entity.title,
          Duration(milliseconds: entity.durationMs ?? 0),
        );
        final cleanMeta = cleanTransferMetadata(
          title: entity.title,
          artist: entity.artist,
        );
        final entityCleanKey = linkTrackKey(
          cleanMeta.artist,
          cleanMeta.title,
          Duration(milliseconds: entity.durationMs ?? 0),
        );
        if (targetKeys.contains(alias) ||
            targetKeys.contains(entityRawKey) ||
            targetKeys.contains(entityCleanKey)) {
          matched = true;
        }
      }
      if (!matched && probeIdentity.titleKey.isNotEmpty) {
        final candIdentity = canonicalDuplicateIdentity(
          title: entity.title,
          artist: entity.artist,
        );
        if (candIdentity.titleKey == probeIdentity.titleKey &&
            candIdentity.artistKey == probeIdentity.artistKey) {
          final candSec = (entity.durationMs ?? 0) / 1000.0;
          if (probeDurSec <= 0 ||
              candSec <= 0 ||
              (candSec - probeDurSec).abs() <= 2.0) {
            matched = true;
          }
        }
      }
      if (!matched) continue;

      if (entity.sourceType == 'lokal' ||
          entity.filePath.startsWith('ghost://desktop/') ||
          entity.filePath.startsWith('lokal://')) {
        remoteStreamVictimIds.add(entity.id);
      } else if (isLocalDuplicateCandidate(entity)) {
        if (entity.dateAdded.millisecondsSinceEpoch <= limitMs) {
          localVictims.add(entity);
        }
      }
    }

    if (remoteStreamVictimIds.isEmpty && localVictims.isEmpty) return;

    final allRemovedIds = <int>{
      ...remoteStreamVictimIds,
      for (final v in localVictims) v.id,
    };
    final allRemovedStrs = allRemovedIds.map((id) => id.toString()).toSet();

    // Remove from FavoritesService, PlaylistService, LinkSongBindings
    final likedIds = await favorites.getFavoriteIds();
    final favChanges = <String, bool>{
      for (final idStr in allRemovedStrs)
        if (likedIds.contains(idStr)) idStr: false,
    };
    if (favChanges.isNotEmpty) {
      await favorites.setManyFromLink(favChanges);
    }

    final playlists = PlaylistService.instance;
    for (final pl in await playlists.getPlaylists()) {
      if (pl.isNetworkSource) continue;
      if (!pl.songIds.any(allRemovedStrs.contains)) continue;
      await playlists.putFromLink(
        pl.copyWith(
          songIds: pl.songIds
              .where((id) => !allRemovedStrs.contains(id))
              .toList(),
          songAddedAt: Map.of(pl.songAddedAt)
            ..removeWhere((k, _) => allRemovedStrs.contains(k)),
          songSnapshots: Map.of(pl.songSnapshots)
            ..removeWhere((k, _) => allRemovedStrs.contains(k)),
          updatedAt: DateTime.now(),
        ),
      );
    }

    for (final idStr in allRemovedStrs) {
      await LinkSongBindings.instance.removeSong(idStr);
    }

    final deleter =
        deletePhysicalFile ?? DuplicateCleanerService.defaultDeletePhysicalFile;
    for (final victim in localVictims) {
      final sharing = await Database.songs
          .where()
          .filePathEqualToAnyStartOffsetMs(victim.filePath)
          .findAll();
      final sharedWithSurvivor = sharing.any(
        (row) => !allRemovedIds.contains(row.id),
      );
      if (!sharedWithSurvivor) {
        await deleter(victim);
      }
    }

    await repo.deleteSongsByIds(allRemovedIds.toList());
    _matchCandidates = null;
    _matchCache.clear();
  }

  Future<void> _materialize(Map<String, dynamic> item) async {
    final journal = LinkJournal.instance,
        fields = Map<String, dynamic>.from(item['fields'] as Map);
    switch (item['entity']) {
      case 'like':
        if (!await journal.wins(item, 'liked')) return;
        final song = await _match({...fields, 'track_key': item['entity_id']});
        if (song != null) {
          await favorites.setFromLink(song.id, item['op'] == 'like');
        }
        break;
      case 'playlist':
        final id = item['entity_id'] as String;
        final prefs = await SharedPreferences.getInstance();
        final localId = prefs.getString('lokal.link.playlist_local.$id') ?? id;
        await prefs.setString('lokal.link.playlist_uuid.$localId', id);
        await prefs.setString('lokal.link.playlist_local.$id', localId);
        final all = await Database.instance.libraryOpEntitys
            .filter()
            .entityIdEqualTo(id)
            .findAll();
        final state = LinkPlaylistOrder.replay([
          for (final op in all) journal.wireOp(op),
        ]);
        final name = state.name;
        if (name == null) return;
        // Retroactive replay can contain hundreds of members even when the
        // pull cursor returned no new rows. Share one library snapshot across
        // those matches; empty playlists should not read the library at all.
        if (state.members.isNotEmpty) {
          _matchCandidates ??= List<Song>.of(
            await SongRepository().getAllSongs(),
          );
        }
        final onlineSnapshots = <String, PlaylistSongSnapshot>{};
        final projection = await state.resolveMembers((member) async {
          final song = await _match({
            ...member.fields,
            'track_key': member.trackKey,
          });
          if (song != null) return song.id;

          // Desktop playlists must retain entries even when their original
          // audio has not been copied or the mobile catalogue cannot match it.
          // Keep a metadata-backed pending reference, rather than silently
          // shortening the list until the next explicit file copy.
          final fields = member.fields;
          final title = fields['title']?.toString().trim() ?? '';
          final artist = fields['artist']?.toString().trim() ?? '';
          if (title.isEmpty || artist.isEmpty) return null;
          final duration = (fields['duration'] as num?)?.toDouble() ?? 0;
          final rawArt = fields['artwork_url']?.toString() ?? '';
          final image = Uri.tryParse(rawArt);
          final publicArt =
              image != null &&
              image.scheme == 'https' &&
              !image.queryParameters.keys.any(
                (name) => RegExp(
                  r'token|signature|expires|auth',
                  caseSensitive: false,
                ).hasMatch(name),
              );
          final reference = stableOnlinePlaylistSong(
            Song(
              id: 'online-link:${member.trackKey}',
              title: title,
              artist: artist,
              album: fields['album']?.toString(),
              albumArt: publicArt ? rawArt : null,
              duration: Duration(
                milliseconds: (duration.clamp(0, 86400) * 1000).round(),
              ),
              fileType: 'ONLINE',
              sourcePackage: Song.pendingSourcePackage,
              remoteId: fields['source_ref']?.toString(),
            ),
          );
          onlineSnapshots[reference.id] = PlaylistSongSnapshot.fromSong(
            reference,
          );
          return reference.id;
        });
        final songIds = projection.songIds;
        final old = await PlaylistService.instance.getPlaylist(localId);
        final sameOrder =
            old != null &&
            old.songIds.length == songIds.length &&
            List.generate(
              songIds.length,
              (i) => i,
            ).every((i) => old.songIds[i] == songIds[i]);
        final missingSnapshots = onlineSnapshots.keys.any(
          (id) => !(old?.songSnapshots.containsKey(id) ?? false),
        );
        if (state.deleted ||
            old == null ||
            old.name != name ||
            !sameOrder ||
            missingSnapshots) {
          final snapshots = {...?old?.songSnapshots, ...onlineSnapshots}
            ..removeWhere((id, _) => !songIds.contains(id));
          final playlist =
              old?.copyWith(
                name: name,
                songIds: songIds,
                songSnapshots: snapshots,
                updatedAt: DateTime.now(),
              ) ??
              Playlist(
                id: localId,
                name: name,
                songIds: songIds,
                songSnapshots: snapshots,
                createdAt: DateTime.now(),
              );
          await PlaylistService.instance.putFromLink(
            playlist,
            deleted: state.deleted,
          );
        }
        // Store the merged baseline so a later local edit only journals its delta.
        final snapshot = Map<String, dynamic>.from(
          jsonDecode(prefs.getString('lokal.link.playlists_snapshot') ?? '{}')
              as Map,
        );
        if (state.deleted) {
          snapshot.remove(id);
        } else {
          snapshot[id] = {
            'name': name,
            // Snapshot is the *local projection*, not all remote entries:
            // unmatched desktop tracks must never look locally removed on
            // the next capture and be deleted remotely.
            'members': projection.matchedKeys,
          };
        }
        await prefs.setString(
          'lokal.link.playlists_snapshot',
          jsonEncode(snapshot),
        );
        break;
      case 'track':
        final op = item['op']?.toString() ?? 'track.edit';
        if (op == 'track.deduplicate') {
          await _applyTrackDeduplicate(item, fields);
          break;
        }
        if (op == 'track.delete') {
          await _applyTrackDelete(item, fields);
          break;
        }
        const editable = [
          'title',
          'artist',
          'album',
          'album_artist',
          'genre',
          'year',
          'track_num',
        ];
        final editedClip = fields.containsKey('video_clip');
        final editedTags = editable.any(fields.containsKey);
        // Hash-only operations must not rewrite every phone row.
        if (!editedClip && !editedTags) return;
        final identity = fields['track'];
        final song = await _match({
          if (identity is Map) ...Map<String, dynamic>.from(identity),
          ...fields,
          'track_key': item['entity_id'],
        });
        if (song == null) return;
        await journal.registerTrackAlias(song.id, item['entity_id'] as String);
        if (editedClip) CopiedTrackClip.revision.value++;
        if (!editedTags || song.filePath == null) return;
        final winning = <String, dynamic>{};
        for (final field in [
          'title',
          'artist',
          'album',
          'album_artist',
          'genre',
          'year',
          'track_num',
        ]) {
          if (fields.containsKey(field) && await journal.wins(item, field)) {
            winning[field] = fields[field];
          }
        }
        // The matching snapshot identifies rows; edits earlier in this sync
        // may already have changed their metadata, so compare the current row.
        final currentRow = await Database.songs
            .filter()
            .filePathEqualTo(song.filePath!)
            .findFirst();
        if (currentRow == null) return;
        final current = <String, dynamic>{
          'title': currentRow.title,
          'artist': currentRow.artist,
          'album': currentRow.album,
          'album_artist': currentRow.albumArtist,
          'genre': currentRow.genre,
          'year': currentRow.year,
          'track_num': currentRow.trackNumber,
        };
        winning.removeWhere(
          (field, value) => value == null || value == current[field],
        );
        if (winning.isEmpty) return;
        await SongRepository().updateSongMetadata(
          song.filePath!,
          title: winning['title'] as String?,
          artist: winning['artist'] as String?,
          album: winning['album'] as String?,
          albumArtist: winning['album_artist'] as String?,
          genre: winning['genre'] as String?,
          year: (winning['year'] as num?)?.toInt(),
          trackNumber: (winning['track_num'] as num?)?.toInt(),
          recordLink: false,
        );
        break;
    }
  }
}
