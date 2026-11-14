import 'link/link_journal.dart';
import 'link/desktop_copy_favorite_identity.dart';
import 'dart:convert';
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flick/models/song.dart';
import 'package:flick/data/repositories/song_repository.dart';

/// Service for managing favorite songs.
/// Stores favorite song IDs in SharedPreferences for persistence.
abstract interface class RemoteFavoritesDelegate {
  Future<bool> isFavorite(String songId);
  Future<bool> toggleFavorite(String songId);
}

class FavoritesService {
  static RemoteFavoritesDelegate? remoteDelegate;
  static const String _favoritesKey = 'favorite_song_ids';
  // Retain this key for backward compatibility; it now stores local snapshots too.
  static const String _onlineMetadataKey = 'favorite_online_song_metadata_v1';
  static const String _likedOrderKey = 'favorite_song_liked_order_v1';

  static Map<String, Object?> _capture(Song song) => {
    'id': song.id, 'title': song.title, 'artist': song.artist,
    'album': song.album, 'albumArt': song.albumArt,
    'durationMs': song.duration.inMilliseconds, 'codec': song.fileType,
    'startOffsetMs': song.startOffsetMs, 'endOffsetMs': song.endOffsetMs,
    'isExternal': song.isExternal,
    'resolution': song.resolution, 'sampleRate': song.sampleRate,
    'bitDepth': song.bitDepth, 'filePath': song.filePath,
    'sourcePackage': song.sourcePackage, 'sourceType': song.sourceType,
    'sourceDisplayName': song.sourceDisplayName,
    'atmosAvailable': song.atmosAvailable,
    'atmosEncoded': song.atmosEncoded,
    'remoteId': song.remoteId,
    'remoteServerId': song.remoteServerId,
  };

  /// Keep a durable display snapshot and exact local-file identity for every
  /// heart. Local Isar IDs can be reassigned after a library rescan; saving
  /// IDs alone made those likes disappear even though the IDs were persisted.
  /// Reuse the original online metadata key to preserve existing installs.
  Future<void> _rememberSong(Song song) async {
    final prefs = await SharedPreferences.getInstance();
    final known = _savedMetadata(prefs);
    known[song.id] = _capture(song);
    await prefs.setString(_onlineMetadataKey, jsonEncode(known));
  }

  static Map<String, dynamic> _savedMetadata(SharedPreferences prefs) {
    try {
      final raw = jsonDecode(prefs.getString(_onlineMetadataKey) ?? '{}');
      if (raw is Map<String, dynamic>) return raw;
    } catch (_) {
      // Corrupt snapshots must not affect the persisted liked-ID set.
    }
    return {};
  }

  Future<void> _forgetSong(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final known = _savedMetadata(prefs);
    if (known.remove(id) != null) {
      await prefs.setString(_onlineMetadataKey, jsonEncode(known));
    }
  }

  /// A remembered local recording has an exact path and CUE segment; titles,
  /// artists and durations alone are not strong enough to move a heart.
  static bool _sameLocalRecording(Song song, Object? raw) {
    if (raw is! Map || raw['isExternal'] != false ||
        raw['sourceType'] != null || raw['filePath'] is! String) {
      return true; // Legacy online snapshots have no local identity.
    }
    return song.filePath == raw['filePath'] &&
        song.startOffsetMs == raw['startOffsetMs'] &&
        song.endOffsetMs == raw['endOffsetMs'];
  }

  /// Reassociate a liked local file when a scan deletes/recreates its Isar
  /// row. Do not take a now-reused numeric ID as proof that it's the same file.
  /// Missing/unmounted files keep their saved IDs and display snapshots.
  Future<void> _repairLocalIds(List<Song> library) async {
    final prefs = await SharedPreferences.getInstance();
    final known = _savedMetadata(prefs);
    if (known.isEmpty || _favoriteIds.isEmpty) return;

    final byPath = <String, List<Song>>{};
    final byId = {for (final song in library) song.id: song};
    for (final song in library) {
      if (song.isExternal || song.isNetworkSource ||
          song.filePath == null || song.filePath!.isEmpty) continue;
      (byPath[song.filePath!] ??= <Song>[]).add(song);
    }
    final redirects = <String, String>{};
    for (final id in _favoriteIds) {
      final snapshot = known[id];
      if (snapshot is! Map || snapshot['isExternal'] != false ||
          snapshot['sourceType'] != null ||
          snapshot['filePath'] is! String) continue;
      if (byId[id] != null && _sameLocalRecording(byId[id]!, snapshot)) {
        continue;
      }
      final candidates = (byPath[snapshot['filePath']] ?? const <Song>[])
          .where((song) => _sameLocalRecording(song, snapshot))
          .toList();
      // Ambiguous path/segment matches must not silently change a like.
      if (candidates.length == 1 && candidates.single.id != id) {
        redirects[id] = candidates.single.id;
      }
    }
    if (redirects.isEmpty) return;

    final ranks = await getFavoriteRanks();
    for (final entry in redirects.entries) {
      final oldRank = ranks.remove(entry.key);
      final currentRank = ranks[entry.value];
      if (oldRank != null &&
          (currentRank == null || oldRank < currentRank)) {
        ranks[entry.value] = oldRank;
      }
      known.remove(entry.key);
      known[entry.value] = _capture(byId[entry.value]!);
    }
    _favoriteIds = {
      for (final id in _favoriteIds) redirects[id] ?? id,
    };
    await prefs.setString(_onlineMetadataKey, jsonEncode(known));
    await prefs.setString(_likedOrderKey, jsonEncode(ranks));
    // The link baseline is an ID projection, not a remote unlike operation.
    final baseline = prefs.getStringList('lokal.link.favorites_snapshot');
    if (baseline != null) {
      await prefs.setStringList('lokal.link.favorites_snapshot', {
        for (final id in baseline) redirects[id] ?? id,
      }.toList());
    }
    await _saveFavorites(captureLink: false);
  }

  static Song? _restore(Object? raw) {
    if (raw is! Map || raw['id'] is! String ||
        raw['title'] is! String || raw['artist'] is! String) return null;
    final song = raw.cast<String, dynamic>();
    return Song(
      id: song['id'] as String,
      title: song['title'] as String,
      artist: song['artist'] as String,
      album: song['album'] as String?,
      albumArt: song['albumArt'] as String?,
      duration: Duration(milliseconds: (song['durationMs'] as num?)?.toInt() ?? 0),
      fileType: song['codec'] as String? ?? 'ONLINE',
      resolution: song['resolution'] as String?,
      sampleRate: (song['sampleRate'] as num?)?.toInt(),
      bitDepth: (song['bitDepth'] as num?)?.toInt(),
      filePath: song['filePath'] as String?,
      sourcePackage: song['sourcePackage'] as String?,
      sourceType: song['sourceType'] as String?,
      sourceDisplayName: song['sourceDisplayName'] as String?,
      atmosAvailable: song['atmosAvailable'] == true,
      atmosEncoded: song['atmosEncoded'] == true,
      remoteId: song['remoteId'] as String?,
      remoteServerId: (song['remoteServerId'] as num?)?.toInt(),
      startOffsetMs: (song['startOffsetMs'] as num?)?.toInt(),
      endOffsetMs: (song['endOffsetMs'] as num?)?.toInt(),
      isExternal: song['isExternal'] != false,
    );
  }

  final SongRepository _songRepository;

  // Cached set of favorite IDs for quick lookup
  Set<String> _favoriteIds = {};
  Map<String, String> _desktopCopyRedirects = const {};
  static Map<String, String> _latestDesktopCopyRedirects = const {};

  String _canonicalId(String id) => _desktopCopyRedirects[id] ?? id;

  /// Repair legacy double-likes without removing a song, playlist member, or
  /// changing the link journal. The two database rows stay addressable.
  Future<void> _repairDesktopCopyLikes() async {
    List<Song> songs;
    try {
      songs = await _songRepository.getAllSongs();
    } catch (_) {
      return; // Never damage a saved favorite when the library is offline.
    }
    await _repairLocalIds(songs);
    _desktopCopyRedirects = desktopCopyFavoriteRedirects(songs);
    _latestDesktopCopyRedirects = _desktopCopyRedirects;
    if (_desktopCopyRedirects.isEmpty) return;
    final normalized = canonicalDesktopCopyFavoriteIds(
      _favoriteIds, _desktopCopyRedirects,
    );
    if (normalized.length == _favoriteIds.length &&
        normalized.containsAll(_favoriteIds)) return;

    final prefs = await SharedPreferences.getInstance();
    final ordered = prefs.getStringList(_favoritesKey) ?? const <String>[];
    Map<String, dynamic> ranks = {};
    try {
      final raw = jsonDecode(prefs.getString(_likedOrderKey) ?? '{}');
      if (raw is Map<String, dynamic>) ranks = raw;
    } catch (_) {}
    // Keep the earliest of the two original heart dates, including legacy
    // insertion-order timestamps, instead of treating repair as a new like.
    for (var i = 0; i < ordered.length; i++) {
      final id = ordered[i];
      final canonical = _canonicalId(id);
      if (!normalized.contains(canonical)) continue;
      final rank = (ranks[id] is num && (ranks[id] as num) > 0)
          ? (ranks[id] as num).toInt() : i + 1;
      final existing = ranks[canonical];
      if (existing is! num || existing <= 0 || rank < existing) {
        ranks[canonical] = rank;
      }
    }
    ranks.removeWhere((key, _) => !normalized.contains(key));
    await prefs.setString(_likedOrderKey, jsonEncode(ranks));
    final known = _savedMetadata(prefs);
    for (final redirect in _desktopCopyRedirects.entries) {
      if (known.containsKey(redirect.key)) {
        known.remove(redirect.key);
        final canonicalSong = songs.where(
          (song) => song.id == redirect.value,
        ).firstOrNull;
        if (canonicalSong != null) {
          known[redirect.value] = _capture(canonicalSong);
        }
      }
    }
    await prefs.setString(_onlineMetadataKey, jsonEncode(known));
    _favoriteIds = normalized;
    // Baselines must be redirected too. Otherwise a later unrelated heart
    // would journal a spurious remote unlike for the duplicate's old row.
    final snapshot = canonicalDesktopCopyFavoriteIds(
      prefs.getStringList('lokal.link.favorites_snapshot') ?? const <String>[],
      _desktopCopyRedirects,
    );
    await prefs.setStringList('lokal.link.favorites_snapshot', snapshot.toList());
    await _saveFavorites(captureLink: false);
  }

  /// Aliases are only populated from confirmed desktop server/track pairs.
  Map<String, String> get desktopCopyRedirects =>
      Map<String, String>.unmodifiable(_desktopCopyRedirects);
  // The classic player, modern player, notification actions and Riverpod
  // each own a service instance. Serialize writes across all instances to
  // avoid lost likes during rapid taps or simultaneous remote sync.
  static Future<void> _writeTail = Future<void>.value();

  Future<T> _mutate<T>(Future<T> Function() action) {
    final result = _writeTail.then((_) async {
      _favoriteIds = await _readIds();
      await _repairDesktopCopyLikes();
      return action();
    });
    _writeTail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  FavoritesService({SongRepository? songRepository})
    : _songRepository = songRepository ?? SongRepository();

  /// Return an independent snapshot; reads must never mutate the shared
  /// in-memory set while an asynchronous favorite write is in flight.
  Future<Set<String>> _readIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_favoritesKey) ?? []).toSet();
  }

  /// The saved IDs (including old online likes without recoverable metadata).
  Future<Set<String>> getFavoriteIds() => _readIds();

  /// Stable like chronology, **not** the song's library import date.
  /// Existing installs never recorded the time of the heart tap. Keep their
  /// persisted favorite-ID insertion order (positive ranks starting at 1),
  /// then place all newly liked songs after them using UTC microsecond stamps.
  /// Do not backdate old likes to now, which would move them above new likes.
  Future<Map<String, int>> getFavoriteRanks() async {
    final prefs = await SharedPreferences.getInstance();
    final orderedIds = prefs.getStringList(_favoritesKey) ?? const <String>[];
    Map<String, dynamic> saved = {};
    try {
      final raw = jsonDecode(prefs.getString(_likedOrderKey) ?? '{}');
      if (raw is Map<String, dynamic>) saved = raw;
    } catch (_) {
      // Broken/stale chronology must not hide any liked songs.
    }
    return {
      for (var index = 0; index < orderedIds.length; index++)
        orderedIds[index]: (saved[orderedIds[index]] is num &&
                (saved[orderedIds[index]] as num) > 0)
            ? (saved[orderedIds[index]] as num).toInt()
            : index + 1,
    };
  }

  Future<void> _saveLikeRanks({
    required Set<String> before,
    required Set<String> after,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await getFavoriteRanks();
    // Re-read persisted IDs before _saveFavorites overwrites the list so
    // legacy IDs keep their historical ordinal ranks.
    final ordered = after.toList(growable: false);
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    // Even multiple likes inside one clock tick must remain ordered.
    var next = existing.values.fold<int>(
      now, (highest, rank) => rank > highest ? rank : highest,
    );
    for (final id in ordered) {
      if (!before.contains(id)) {
        next++;
        existing[id] = next;
      }
    }
    existing.removeWhere((id, _) => !after.contains(id));
    await prefs.setString(_likedOrderKey, jsonEncode(existing));
  }

  /// Get all favorite songs.
  Future<List<Song>> getFavorites() async {
    // Called on initial Liked load: repair existing users once idempotently,
    // before the provider reads IDs and ranks for the same snapshot.
    await _mutate(() async {});
    final ids = await _readIds();
    if (ids.isEmpty) return [];

    // A local-library read failure must not hide independently saved online
    // favorites (offline devices can still show their metadata).
    List<Song> allSongs;
    try {
      allSongs = await _songRepository.getAllSongs();
    } catch (_) {
      allSongs = [];
    }
    final prefs = await SharedPreferences.getInstance();
    final snapshots = _savedMetadata(prefs);
    final liked = allSongs.where((song) =>
        ids.contains(song.id) &&
        _sameLocalRecording(song, snapshots[song.id])).toList();
    final inLibrary = liked.map((song) => song.id).toSet();
    for (final id in ids) {
      if (inLibrary.contains(id)) continue;
      // Retain offline/unscanned local files as well as online references.
      // This also prevents an unrelated track reusing an old Isar ID from
      // appearing as liked after the next scan.
      final song = _restore(snapshots[id]);
      if (song != null) liked.add(song);
    }
    return liked;
  }

  /// Check if a song is a favorite.
  Future<bool> isFavorite(String songId) async {
    if (songId.startsWith('desktop:'))
      return (await remoteDelegate?.isFavorite(songId)) ?? false;
    // Heart lookups happen on every rendered row. The full identity repair
    // runs on the Liked load and on writes, not on every read-only lookup.
    final ids = await _readIds();
    return ids.contains(songId) ||
        ids.contains(_latestDesktopCopyRedirects[songId] ?? songId);
  }

  /// Add a song to favorites.
  Future<void> addFavorite(String songId, {Song? song}) async {
    if (songId.startsWith('desktop:')) {
      if (!await isFavorite(songId))
        await remoteDelegate?.toggleFavorite(songId);
      return;
    }
    await _mutate(() async {
      if (song != null) await _rememberSong(song);
      final before = Set<String>.of(_favoriteIds);
      _favoriteIds.add(_canonicalId(songId));
      await _saveLikeRanks(before: before, after: _favoriteIds);
      await _saveFavorites();
    });
  }

  /// Remove a song from favorites.
  Future<void> removeFavorite(String songId) async {
    if (songId.startsWith('desktop:')) {
      if (await isFavorite(songId))
        await remoteDelegate?.toggleFavorite(songId);
      return;
    }
    await _mutate(() async {
      final before = Set<String>.of(_favoriteIds);
      _favoriteIds.remove(_canonicalId(songId));
      await _forgetSong(songId);
      await _saveLikeRanks(before: before, after: _favoriteIds);
      await _saveFavorites();
    });
  }

  /// Toggle favorite status for a song.
  /// Returns true if the song is now a favorite, false otherwise.
  Future<bool> toggleFavorite(String songId, {Song? song}) async {
    if (songId.startsWith('desktop:')) {
      final remote = remoteDelegate;
      if (remote == null) throw StateError('Connect to your desktop first.');
      return remote.toggleFavorite(songId);
    }
    return _mutate(() async {
      final canonicalId = _canonicalId(songId);
      if (_favoriteIds.contains(canonicalId)) {
        final before = Set<String>.of(_favoriteIds);
        _favoriteIds.remove(canonicalId);
        await _forgetSong(songId);
        await _saveLikeRanks(before: before, after: _favoriteIds);
        await _saveFavorites();
        return false;
      }
      if (song != null) await _rememberSong(song);
      final before = Set<String>.of(_favoriteIds);
      _favoriteIds.add(canonicalId);
      await _saveLikeRanks(before: before, after: _favoriteIds);
      await _saveFavorites();
      return true;
    });
  }

  /// Get the count of favorite songs.
  Future<int> getFavoritesCount() async => (await _readIds()).length;

  /// Save favorites to SharedPreferences.
  Future<void> _saveFavorites({bool captureLink = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, _favoriteIds.toList());
    if (captureLink) await LinkJournal.instance.captureFavorites(_favoriteIds);
  }

  /// Apply one winning remote intent without producing a new local operation.
  Future<void> setFromLink(String songId, bool liked) =>
      setManyFromLink({songId: liked});

  Future<void> setManyFromLink(Map<String, bool> changes) async {
    await _mutate(() async {
      final before = Set<String>.of(_favoriteIds);
      for (final entry in changes.entries) {
        final id = _canonicalId(entry.key);
        entry.value
            ? _favoriteIds.add(id)
            : _favoriteIds.remove(id);
        if (!entry.value) await _forgetSong(entry.key);
      }
      await _saveLikeRanks(before: before, after: _favoriteIds);
      await _saveFavorites(captureLink: false);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'lokal.link.favorites_snapshot',
        _favoriteIds.toList(),
      );
    });
  }

  /// Clear all favorites.
  Future<void> clearFavorites() async {
    await _mutate(() async {
      _favoriteIds.clear();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_onlineMetadataKey);
      await prefs.remove(_likedOrderKey);
      await _saveFavorites();
    });
  }
}
