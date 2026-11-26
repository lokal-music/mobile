import 'dart:io';

import 'package:flick/core/utils/dev_log.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;

import '../core/utils/audio_metadata_utils.dart';
import '../data/database.dart';
import '../data/repositories/song_repository.dart';
import '../features/discovery/recommendation_match.dart';
import 'favorites_service.dart';
import 'link/link_journal.dart';
import 'link/link_protocol.dart';
import 'link/link_song_bindings.dart';
import 'link/transfer_artifact_cleaner.dart';
import 'music_folder_service.dart';
import 'playlist_service.dart';

const Set<String> _losslessExtensions = {
  'flac',
  'wav',
  'alac',
  'aiff',
  'aif',
  'dsf',
  'dff',
  'wv',
  'ape',
};

/// Returns true if [entity] is a real local file candidate (not network, ghost,
/// or pending).
bool isLocalDuplicateCandidate(SongEntity entity) {
  if (entity.sourceType != null) return false;
  final path = entity.filePath.trim();
  if (path.isEmpty) return false;
  if (path.startsWith('ghost://') ||
      path.startsWith('pending:') ||
      path.startsWith('lokal://')) {
    return false;
  }
  return true;
}

/// Canonical `(artistKey, titleKey)` pair after cleaning transfer artifacts
/// and normalizing with Unicode-preserving keys.
({String artistKey, String titleKey, String cleanArtist, String cleanTitle})
canonicalDuplicateIdentity({
  required String title,
  required String artist,
}) {
  final cleaned = cleanTransferMetadata(title: title, artist: artist);
  var aKey = recommendationKey(leadArtist(cleaned.artist));
  if (aKey.isEmpty) {
    aKey = recommendationKey(cleaned.artist);
  }
  var tKey = titleKey(cleaned.title);
  if (tKey.isEmpty) {
    tKey = recommendationKey(cleaned.title);
  }
  return (
    artistKey: aKey,
    titleKey: tKey,
    cleanArtist: cleaned.artist,
    cleanTitle: cleaned.title,
  );
}

bool _isReadableLocalSong(SongEntity s) {
  final path = s.filePath.trim();
  if (path.startsWith('content://')) return true;
  if ((s.mediaStoreUri ?? '').startsWith('content://')) return true;
  final resolved = path.startsWith('file://')
      ? (Uri.tryParse(path)?.toFilePath() ?? path)
      : path;
  try {
    return File(resolved).existsSync();
  } on FileSystemException {
    return false;
  }
}

bool _isLosslessSong(SongEntity s) {
  final ft = (s.fileType ?? '').trim().toLowerCase().replaceFirst(
    RegExp(r'^\.'),
    '',
  );
  if (_losslessExtensions.contains(ft) || ft == 'wv-dsd' || ft == 'dsd') {
    return true;
  }
  final ext = p
      .extension(s.filePath)
      .trim()
      .toLowerCase()
      .replaceFirst(RegExp(r'^\.'), '');
  return _losslessExtensions.contains(ext);
}

bool _hasCleanMetadataAndStem(SongEntity s) {
  if (hasTransferArtifact(s.title)) return false;
  if (!s.filePath.startsWith('content://')) {
    final stem = p.basenameWithoutExtension(s.filePath);
    if (hasTransferArtifact(stem)) return false;
  }
  return true;
}

int _normalizedBitrate(SongEntity s) =>
    AudioMetadataUtils.normalizeStoredBitrateKbps(
      s.bitrate,
      sampleRate: s.sampleRate,
      bitDepth: s.bitDepth,
    ) ??
    0;

/// Represents a group of duplicate songs.
class DuplicateGroup {
  final String key; // The common identifier (artistKey + titleKey [+ subindex])
  final List<SongEntity> songs;
  final Map<int, int> playCounts;

  DuplicateGroup({
    required this.key,
    required this.songs,
    this.playCounts = const {},
  });

  SongEntity? _cachedRecommended;

  /// The automatically recommended song to keep:
  /// 1. Readable local file on disk (or `content://` URI)
  /// 2. Lossless format > lossy, then higher bitDepth, sampleRate, and bitrate
  /// 3. Clean title & filename (no transfer UUID / hash suffix) > artifact copy
  /// 4. Has `albumArtPath != null`
  /// 5. Higher `playCount`
  /// Computed once and cached — never mutates [songs].
  SongEntity get recommendedKeep =>
      _cachedRecommended ??= _computeRecommendedKeep();

  /// Backwards-compatible alias for [recommendedKeep].
  SongEntity get songToKeep => recommendedKeep;

  SongEntity _computeRecommendedKeep() {
    final readability = <int, bool>{
      for (final s in songs) s.id: _isReadableLocalSong(s),
    };
    final copy = List<SongEntity>.from(songs);
    copy.sort((a, b) => compareKeeperPriority(
      a,
      b,
      readableA: readability[a.id] ?? false,
      readableB: readability[b.id] ?? false,
      playCountA: playCounts[a.id] ?? 0,
      playCountB: playCounts[b.id] ?? 0,
    ));
    return copy.first;
  }

  /// Comparator returning negative when [a] is preferred over [b].
  static int compareKeeperPriority(
    SongEntity a,
    SongEntity b, {
    bool? readableA,
    bool? readableB,
    int playCountA = 0,
    int playCountB = 0,
  }) {
    final rA = (readableA ?? _isReadableLocalSong(a)) ? 1 : 0;
    final rB = (readableB ?? _isReadableLocalSong(b)) ? 1 : 0;
    if (rA != rB) return rB.compareTo(rA);

    final losslessA = _isLosslessSong(a) ? 1 : 0;
    final losslessB = _isLosslessSong(b) ? 1 : 0;
    if (losslessA != losslessB) return losslessB.compareTo(losslessA);

    final bdA = a.bitDepth ?? 0;
    final bdB = b.bitDepth ?? 0;
    if (bdA != bdB) return bdB.compareTo(bdA);

    final srA = a.sampleRate ?? 0;
    final srB = b.sampleRate ?? 0;
    if (srA != srB) return srB.compareTo(srA);

    final brA = _normalizedBitrate(a);
    final brB = _normalizedBitrate(b);
    if (brA != brB) return brB.compareTo(brA);

    final cleanA = _hasCleanMetadataAndStem(a) ? 1 : 0;
    final cleanB = _hasCleanMetadataAndStem(b) ? 1 : 0;
    if (cleanA != cleanB) return cleanB.compareTo(cleanA);

    final artA = (a.albumArtPath != null && a.albumArtPath!.isNotEmpty) ? 1 : 0;
    final artB = (b.albumArtPath != null && b.albumArtPath!.isNotEmpty) ? 1 : 0;
    if (artA != artB) return artB.compareTo(artA);

    if (playCountA != playCountB) return playCountB.compareTo(playCountA);

    return a.id.compareTo(b.id);
  }

  /// Songs that would be removed if [keepId] (or the recommended one) is kept.
  List<SongEntity> songsToRemoveFor(int keepId) =>
      songs.where((s) => s.id != keepId).toList();

  /// Songs that would be removed if the set [keepIds] is kept.
  List<SongEntity> songsToRemoveForSet(Set<int> keepIds) =>
      songs.where((s) => !keepIds.contains(s.id)).toList();

  /// Default removal list (keeps the recommended song).
  List<SongEntity> get songsToRemove => songsToRemoveFor(recommendedKeep.id);
}

/// Result of duplicate scan operation.
class DuplicateScanResult {
  final List<DuplicateGroup> duplicateGroups;
  final int totalDuplicates;
  final int totalGroups;

  DuplicateScanResult({
    required this.duplicateGroups,
    required this.totalDuplicates,
    required this.totalGroups,
  });
}

/// Result of duplicate removal operation.
class DuplicateRemovalResult {
  final int removedCount;
  final int keptCount;
  final List<String> errors;

  DuplicateRemovalResult({
    required this.removedCount,
    required this.keptCount,
    required this.errors,
  });
}

/// Service for detecting and removing duplicate songs.
class DuplicateCleanerService {
  final SongRepository _songRepository;
  final FavoritesService? _favoritesService;
  final PlaylistService? _playlistService;
  final Future<void> Function(SongEntity)? _deletePhysicalFile;
  final bool _defaultEmitJournal;

  DuplicateCleanerService({
    SongRepository? songRepository,
    FavoritesService? favoritesService,
    PlaylistService? playlistService,
    Future<void> Function(SongEntity)? deletePhysicalFile,
    bool emitJournal = true,
  }) : _songRepository = songRepository ?? SongRepository(),
       _favoritesService = favoritesService,
       _playlistService = playlistService,
       _deletePhysicalFile = deletePhysicalFile,
       _defaultEmitJournal = emitJournal;

  Isar get _isar => _songRepository.isar;

  Future<Map<int, int>> _loadPlayCounts() async {
    final ids = await _isar.recentlyPlayedEntitys
        .where()
        .songIdProperty()
        .findAll();
    final counts = <int, int>{};
    for (final id in ids) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
  }

  static bool _durationsCompatible(SongEntity a, SongEntity b) {
    final da = a.durationMs ?? 0;
    final db = b.durationMs ?? 0;
    if (da <= 0 || db <= 0) return true;
    return (da - db).abs() <= 10000;
  }

  static List<List<SongEntity>> _clusterByDuration(List<SongEntity> bucket) {
    if (bucket.length < 2) return const [];
    final visited = List<bool>.filled(bucket.length, false);
    final clusters = <List<SongEntity>>[];
    for (var i = 0; i < bucket.length; i++) {
      if (visited[i]) continue;
      visited[i] = true;
      final cluster = <SongEntity>[bucket[i]];
      final queue = <int>[i];
      while (queue.isNotEmpty) {
        final current = bucket[queue.removeLast()];
        for (var j = 0; j < bucket.length; j++) {
          if (visited[j]) continue;
          if (_durationsCompatible(current, bucket[j])) {
            visited[j] = true;
            cluster.add(bucket[j]);
            queue.add(j);
          }
        }
      }
      if (cluster.length > 1) {
        clusters.add(cluster);
      }
    }
    return clusters;
  }

  /// Scan the library for duplicate local songs.
  /// Duplicates are identified by cleaned, Unicode-normalized `(artist, title)`
  /// and compatible durations (`<= 10s` when both durations are positive).
  Future<DuplicateScanResult> scanForDuplicates() async {
    devLog('Starting duplicate scan...');

    final allSongs = await _songRepository.getAllSongEntities();
    final playCounts = await _loadPlayCounts();
    final buckets = <String, List<SongEntity>>{};

    for (final song in allSongs) {
      if (!isLocalDuplicateCandidate(song)) continue;
      final identity = canonicalDuplicateIdentity(
        title: song.title,
        artist: song.artist,
      );
      if (identity.titleKey.isEmpty) continue;
      final key = '${identity.artistKey}|${identity.titleKey}';
      buckets.putIfAbsent(key, () => []).add(song);
    }

    final duplicateGroups = <DuplicateGroup>[];
    for (final entry in buckets.entries) {
      if (entry.value.length < 2) continue;
      final clusters = _clusterByDuration(entry.value);
      for (var index = 0; index < clusters.length; index++) {
        final cluster = clusters[index];
        final groupKey = clusters.length == 1
            ? entry.key
            : '${entry.key}#${index + 1}';
        final groupPlayCounts = <int, int>{
          for (final s in cluster)
            if (playCounts.containsKey(s.id)) s.id: playCounts[s.id]!,
        };
        duplicateGroups.add(
          DuplicateGroup(
            key: groupKey,
            songs: cluster,
            playCounts: groupPlayCounts,
          ),
        );
      }
    }

    // Sort by number of duplicates (descending)
    duplicateGroups.sort((a, b) => b.songs.length.compareTo(a.songs.length));

    final totalDuplicates = duplicateGroups.fold<int>(
      0,
      (sum, group) => sum + group.songsToRemove.length,
    );

    devLog(
      'Duplicate scan complete: Found $totalDuplicates duplicates in ${duplicateGroups.length} groups',
    );

    return DuplicateScanResult(
      duplicateGroups: duplicateGroups,
      totalDuplicates: totalDuplicates,
      totalGroups: duplicateGroups.length,
    );
  }

  /// Default physical file deletion helper for Android/iOS/desktop local files.
  ///
  /// This must fail closed: callers delete the library row only after this
  /// method completes. Silently swallowing a SAF/MediaStore failure leaves the
  /// audio file on disk, so the next scan imports it again as a "new" track.
  static Future<void> defaultDeletePhysicalFile(SongEntity loser) async {
    final path = loser.filePath.trim();
    if (path.isEmpty ||
        path.startsWith('ghost://') ||
        path.startsWith('lokal://') ||
        path.startsWith('pending:')) {
      return;
    }

    var deleted = false;
    final hasSafOrContent =
        path.startsWith('content://') ||
        (loser.mediaStoreUri ?? '').startsWith('content://') ||
        (loser.folderUri ?? '').startsWith('content://');

    if (hasSafOrContent) {
      final targetUri = path.startsWith('content://')
          ? path
          : (loser.mediaStoreUri != null &&
                    loser.mediaStoreUri!.startsWith('content://')
                ? loser.mediaStoreUri!
                : path);
      final treeUri =
          (loser.folderUri != null && loser.folderUri!.isNotEmpty)
          ? loser.folderUri!
          : targetUri;

      deleted = await MusicFolderService.deleteDocument(
        folderTreeUri: treeUri,
        filePath: targetUri,
      );
    }

    if (!path.startsWith('content://')) {
      final resolved = path.startsWith('file://')
          ? (Uri.tryParse(path)?.toFilePath() ?? path)
          : path;
      final file = File(resolved);
      if (await file.exists()) {
        await file.delete();
        if (await file.exists()) {
          throw FileSystemException(
            'Duplicate audio file still exists after deletion',
            resolved,
          );
        }
        deleted = true;
      } else if (!hasSafOrContent) {
        // Already absent is a successful deletion; there is nothing to rescan.
        deleted = true;
      }
    }

    if (!deleted) {
      throw FileSystemException(
        'Could not delete duplicate audio file from device storage',
        path,
      );
    }

    // Refresh the index only after the physical file is gone. Never use this
    // operation as a substitute for deleting the underlying audio bytes.
    if (!path.startsWith('content://')) {
      final mediaStorePath = path.startsWith('file://')
          ? (Uri.tryParse(path)?.toFilePath() ?? path)
          : path;
      try {
        await MusicFolderService.removeFromMediaStore(mediaStorePath);
      } catch (_) {
        // The physical file is already gone; index refresh is best-effort.
      }
    }
  }

  Future<bool> _isFileSharedWithSurvivors(
    String filePath,
    Set<int> removingIds,
  ) async {
    if (filePath.isEmpty) return false;
    final sharing = await _isar.songEntitys
        .where()
        .filePathEqualToAnyStartOffsetMs(filePath)
        .findAll();
    return sharing.any((row) => !removingIds.contains(row.id));
  }

  Future<void> _mergePlaylistsToKeeper({
    required String keepIdStr,
    required Set<String> loserIdStrs,
    required bool captureLink,
  }) async {
    if (loserIdStrs.isEmpty) return;
    final playlists = _playlistService ?? PlaylistService.instance;
    final all = await playlists.getPlaylists();
    var anyChanged = false;
    for (final playlist in all) {
      if (playlist.isNetworkSource) continue;
      if (!playlist.songIds.any(loserIdStrs.contains)) continue;

      final nextIds = <String>[];
      final seenKeep = <bool>[false];
      // Check if keepIdStr is already present anywhere; we replace the first
      // occurrence of (keepIdStr or any loserIdStr) with keepIdStr and drop
      // subsequent duplicates.
      for (final id in playlist.songIds) {
        if (id == keepIdStr || loserIdStrs.contains(id)) {
          if (!seenKeep[0]) {
            seenKeep[0] = true;
            nextIds.add(keepIdStr);
          }
        } else {
          nextIds.add(id);
        }
      }

      final nextAddedAt = Map<String, DateTime>.from(playlist.songAddedAt);
      DateTime? earliestAdded = nextAddedAt[keepIdStr];
      for (final loserId in loserIdStrs) {
        final removed = nextAddedAt.remove(loserId);
        if (removed != null &&
            (earliestAdded == null || removed.isBefore(earliestAdded))) {
          earliestAdded = removed;
        }
      }
      if (earliestAdded != null) {
        nextAddedAt[keepIdStr] = earliestAdded;
      }

      final nextSnapshots = Map.of(playlist.songSnapshots)
        ..removeWhere((key, _) => loserIdStrs.contains(key));

      final updated = playlist.copyWith(
        songIds: nextIds,
        songAddedAt: nextAddedAt,
        songSnapshots: nextSnapshots,
        updatedAt: DateTime.now(),
      );

      if (captureLink) {
        // Re-save through putFromLink? Wait: if !applyingRemote, we want local
        // playlist snapshot updated cleanly or captured. Using putFromLink
        // avoids emitting playlist.remove for the deduplicated track when
        // track.deduplicate already merges references on Desktop!
        await playlists.putFromLink(updated);
      } else {
        await playlists.putFromLink(updated);
      }
      anyChanged = true;
    }
    if (anyChanged && captureLink && !LinkJournal.instance.applyingRemote) {
      await LinkJournal.instance.capturePlaylists(
        await playlists.getPlaylists(),
      );
    }
  }

  /// Merge play counts/history, likes, playlists, and multi-PC Link bindings
  /// from losers in [group] onto the kept song, delete loser files from storage
  /// (unless shared by a surviving CUE/row), delete losers from Isar, and emit
  /// `track.deduplicate` to [LinkJournal].
  Future<int> mergeAndRemoveGroup(
    DuplicateGroup group, {
    int? keepId,
    Set<int>? keepIds,
    bool? emitJournal,
  }) async {
    final shouldEmit = emitJournal ?? _defaultEmitJournal;
    final effectiveKeepIds =
        keepIds != null && keepIds.isNotEmpty
        ? keepIds
        : {keepId ?? group.recommendedKeep.id};

    final survivors = group.songs
        .where((s) => effectiveKeepIds.contains(s.id))
        .toList();
    if (survivors.isEmpty) return 0;

    // Pick primary keeper among survivors using keeper priority.
    survivors.sort(
      (a, b) => DuplicateGroup.compareKeeperPriority(
        a,
        b,
        playCountA: group.playCounts[a.id] ?? 0,
        playCountB: group.playCounts[b.id] ?? 0,
      ),
    );
    final primary = await _isar.songEntitys.get(survivors.first.id) ??
        survivors.first;

    final losers = <SongEntity>[];
    for (final candidate in group.songs) {
      if (effectiveKeepIds.contains(candidate.id)) continue;
      final fresh = await _isar.songEntitys.get(candidate.id);
      if (fresh != null) {
        losers.add(fresh);
      }
    }
    if (losers.isEmpty) return 0;

    final loserIdInts = losers.map((l) => l.id).toSet();
    final loserIdStrs = losers.map((l) => l.id.toString()).toSet();
    final keepIdStr = primary.id.toString();

    await LinkSongBindings.instance.ensureLoaded();
    final primaryPreBinding = LinkSongBindings.instance.peek(
      keepIdStr,
      filePath: primary.filePath,
    );
    final loserPreBindings = <int, SongLinkBinding?>{
      for (final loser in losers)
        loser.id: LinkSongBindings.instance.peek(
          loser.id.toString(),
          filePath: loser.filePath,
        ),
    };

    // Snapshot loser track keys & content hashes BEFORE mutating/deleting.
    final keepClean = cleanTransferMetadata(
      title: primary.title,
      artist: primary.artist,
    );
    final keepDuration = Duration(milliseconds: primary.durationMs ?? 0);
    final keepKey = linkTrackKey(
      keepClean.artist,
      keepClean.title,
      keepDuration,
    );
    final keepRawKey = linkTrackKey(
      primary.artist,
      primary.title,
      keepDuration,
    );

    final removedKeysSet = <String>{};
    if (keepRawKey != keepKey) {
      removedKeysSet.add(keepRawKey);
    }
    final existingKeepAlias = await LinkJournal.instance.trackKeyFor(
      _songRepository.songFromEntity(primary),
    );
    if (existingKeepAlias != keepKey) {
      removedKeysSet.add(existingKeepAlias);
    }

    final removedHashes = <Map<String, dynamic>>[];
    final seenHashes = <String>{};

    for (final loser in losers) {
      final loserSong = _songRepository.songFromEntity(loser);
      final rawKey = linkTrackKey(
        loser.artist,
        loser.title,
        Duration(milliseconds: loser.durationMs ?? 0),
      );
      final aliasKey = await LinkJournal.instance.trackKeyFor(loserSong);
      final cleanedLoser = cleanTransferMetadata(
        title: loser.title,
        artist: loser.artist,
      );
      final cleanLoserKey = linkTrackKey(
        cleanedLoser.artist,
        cleanedLoser.title,
        Duration(milliseconds: loser.durationMs ?? 0),
      );
      for (final k in [rawKey, aliasKey, cleanLoserKey]) {
        if (k.isNotEmpty && k != keepKey) {
          removedKeysSet.add(k);
        }
      }

      final sha = loserPreBindings[loser.id]?.sha256;
      var bytes = loser.fileSize ?? 0;
      if (bytes <= 0 && !loser.filePath.startsWith('content://')) {
        try {
          final f = File(loser.filePath);
          if (f.existsSync()) bytes = f.lengthSync();
        } catch (_) {}
      }
      if (sha != null &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) &&
          bytes > 0 &&
          seenHashes.add('$sha:$bytes')) {
        removedHashes.add({'sha256': sha, 'bytes': bytes});
      }
    }

    // 1. Merge play history (RecentlyPlayedEntity rows -> primary.id) so
    //    playCount = keep.playCount + sum(loser.playCount) and lastPlayed is
    //    the latest across all copies! Also inherit local albumArtPath & clean
    //    transfer artifacts on keeper.
    var keeperModified = false;
    if (keepClean.changed) {
      primary.title = keepClean.title;
      primary.artist = keepClean.artist;
      keeperModified = true;
    }
    if (primary.albumArtPath == null || primary.albumArtPath!.isEmpty) {
      for (final loser in losers) {
        final art = loser.albumArtPath;
        if (art != null &&
            art.isNotEmpty &&
            !art.startsWith('lokal-cover://')) {
          primary.albumArtPath = art;
          keeperModified = true;
          break;
        }
      }
    }
    if (primary.remoteServerId == null || primary.remoteId == null) {
      for (final loser in losers) {
        if (loser.remoteServerId != null &&
            loser.remoteId != null &&
            loser.remoteId!.isNotEmpty) {
          primary.remoteServerId = loser.remoteServerId;
          primary.remoteId = loser.remoteId;
          keeperModified = true;
          break;
        }
      }
    }

    await _isar.writeTxn(() async {
      final loserPlays = await _isar.recentlyPlayedEntitys
          .where()
          .anyOf(loserIdInts.toList(), (q, id) => q.songIdEqualTo(id))
          .findAll();
      if (loserPlays.isNotEmpty) {
        for (final entry in loserPlays) {
          entry.songId = primary.id;
        }
        await _isar.recentlyPlayedEntitys.putAll(loserPlays);
      }
      if (keeperModified) {
        await _isar.songEntitys.put(primary);
      }
    });

    // 2. Merge FavoritesService and PlaylistService
    final favorites =
        _favoritesService ?? FavoritesService(songRepository: _songRepository);
    final likedIds = await favorites.getFavoriteIds();
    final anyLoserLiked = loserIdStrs.any(likedIds.contains);
    final keeperSong = _songRepository.songFromEntity(primary);

    if (LinkJournal.instance.applyingRemote) {
      final favChanges = <String, bool>{
        for (final loserId in loserIdStrs)
          if (likedIds.contains(loserId)) loserId: false,
        if (anyLoserLiked && !likedIds.contains(keepIdStr)) keepIdStr: true,
      };
      if (favChanges.isNotEmpty) {
        await favorites.setManyFromLink(favChanges);
      }
    } else {
      if (anyLoserLiked && !likedIds.contains(keepIdStr)) {
        await favorites.addFavorite(keepIdStr, song: keeperSong);
      }
      for (final loserId in loserIdStrs) {
        if (likedIds.contains(loserId)) {
          await favorites.removeFavorite(loserId);
        }
      }
    }

    await _mergePlaylistsToKeeper(
      keepIdStr: keepIdStr,
      loserIdStrs: loserIdStrs,
      captureLink: shouldEmit && !LinkJournal.instance.applyingRemote,
    );

    // 3. Merge LinkSongBindings
    final fallbackServers = <int, String>{
      if (primary.remoteServerId != null &&
          primary.remoteId != null &&
          primary.remoteId!.isNotEmpty)
        primary.remoteServerId!: primary.remoteId!,
      for (final loser in losers)
        if (loser.remoteServerId != null &&
            loser.remoteId != null &&
            loser.remoteId!.isNotEmpty)
          loser.remoteServerId!: loser.remoteId!,
    };
    await LinkSongBindings.instance.mergeInto(
      keepSongId: keepIdStr,
      loserSongIds: loserIdStrs,
      keepFilePath: primary.filePath,
      fallbackServers: fallbackServers,
    );

    final mergedBinding = await LinkSongBindings.instance.getBinding(
      keepIdStr,
      filePath: primary.filePath,
    );
    final keepSha = mergedBinding?.sha256 ?? primaryPreBinding?.sha256;

    // 4. Physically delete each loser's file (unless shared by a surviving row,
    //    such as a CUE sheet orprimary keeper itself), then delete from Isar.
    final deleter = _deletePhysicalFile ?? defaultDeletePhysicalFile;
    var removedCount = 0;
    for (final loser in losers) {
      final sharedWithSurvivor =
          loser.filePath == primary.filePath ||
          await _isFileSharedWithSurvivors(loser.filePath, loserIdInts);
      if (!sharedWithSurvivor) {
        await deleter(loser);
      }
      await _songRepository.deleteSong(loser.id);
      removedCount++;
    }

    // 5. Append track.deduplicate to LinkJournal if local user action.
    if (shouldEmit && !LinkJournal.instance.applyingRemote) {
      await LinkJournal.instance.append(
        'track',
        keepKey,
        'track.deduplicate',
        {
          'keep_key': keepKey,
          'keep_hash': keepSha ?? '',
          'title': keepClean.title,
          'artist': keepClean.artist,
          'album': primary.album ?? '',
          'duration': ((primary.durationMs ?? 0) / 1000).round(),
          'removed_keys': removedKeysSet.take(200).toList(),
          'removed_hashes': removedHashes.take(200).toList(),
        },
      );
    }

    return removedCount;
  }

  /// Remove all duplicate songs, keeping the best quality version in each group.
  Future<DuplicateRemovalResult> removeAllDuplicates(
    List<DuplicateGroup> groups,
  ) async {
    devLog('Starting duplicate removal...');

    int removedCount = 0;
    int keptCount = 0;
    final errors = <String>[];

    for (final group in groups) {
      try {
        final removed = await mergeAndRemoveGroup(
          group,
          keepId: group.recommendedKeep.id,
        );
        removedCount += removed;
        keptCount++;
        devLog(
          'Removed $removed duplicates of "${group.songToKeep.title}"',
        );
      } catch (e) {
        final error = 'Failed to remove duplicates for "${group.key}": $e';
        errors.add(error);
        devLog(error);
      }
    }

    devLog(
      'Duplicate removal complete: Removed $removedCount songs, kept $keptCount',
    );

    return DuplicateRemovalResult(
      removedCount: removedCount,
      keptCount: keptCount,
      errors: errors,
    );
  }

  /// Remove specific duplicate songs by their IDs, merging into surviving group
  /// keepers when a matching duplicate group exists.
  Future<int> removeSpecificDuplicates(
    List<int> songIds, {
    List<DuplicateGroup>? groups,
  }) async {
    if (songIds.isEmpty) return 0;
    final removeSet = songIds.toSet();
    final activeGroups = groups ?? (await scanForDuplicates()).duplicateGroups;
    int removedCount = 0;
    final handledIds = <int>{};

    for (final group in activeGroups) {
      final groupLoserIds = group.songs
          .where((s) => removeSet.contains(s.id))
          .map((s) => s.id)
          .toSet();
      if (groupLoserIds.isEmpty) continue;
      final groupKeepIds = group.songs
          .where((s) => !removeSet.contains(s.id))
          .map((s) => s.id)
          .toSet();
      if (groupKeepIds.isEmpty) continue;

      try {
        final removed = await mergeAndRemoveGroup(
          group,
          keepIds: groupKeepIds,
        );
        removedCount += removed;
        handledIds.addAll(groupLoserIds);
      } catch (e) {
        devLog('Failed to merge duplicate group "${group.key}": $e');
      }
    }

    // Fallback for any explicitly passed IDs that were not part of a 2+ group.
    for (final id in removeSet) {
      if (handledIds.contains(id)) continue;
      try {
        final entity = await _isar.songEntitys.get(id);
        if (entity != null) {
          final deleter = _deletePhysicalFile ?? defaultDeletePhysicalFile;
          final shared = await _isFileSharedWithSurvivors(
            entity.filePath,
            {id},
          );
          if (!shared) {
            await deleter(entity);
          }
          await LinkSongBindings.instance.removeSong(id.toString());
        }
        await _songRepository.deleteSong(id);
        removedCount++;
      } catch (e) {
        devLog('Failed to remove song $id: $e');
      }
    }

    return removedCount;
  }
}
