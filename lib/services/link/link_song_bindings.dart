import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/song.dart';

class SongLinkBinding {
  const SongLinkBinding({
    required this.servers,
    this.sha256,
    this.filePath,
  });

  final Map<int, String> servers;
  final String? sha256;
  final String? filePath;

  bool get isEmpty =>
      servers.isEmpty &&
      (sha256 == null || sha256!.isEmpty) &&
      (filePath == null || filePath!.isEmpty);

  SongLinkBinding copyWith({
    Map<int, String>? servers,
    String? sha256,
    String? filePath,
  }) => SongLinkBinding(
    servers: servers ?? this.servers,
    sha256: sha256 ?? this.sha256,
    filePath: filePath ?? this.filePath,
  );

  Map<String, dynamic> toJson() => {
    if (servers.isNotEmpty)
      'servers': {
        for (final entry in servers.entries) entry.key.toString(): entry.value,
      },
    if (sha256 != null && sha256!.isNotEmpty) 'sha256': sha256,
    if (filePath != null && filePath!.isNotEmpty) 'filePath': filePath,
  };

  factory SongLinkBinding.fromJson(Map<String, dynamic> json) {
    final rawServers = json['servers'];
    final servers = <int, String>{};
    if (rawServers is Map) {
      for (final entry in rawServers.entries) {
        final serverId = int.tryParse(entry.key.toString());
        final remoteId = entry.value?.toString();
        if (serverId != null && remoteId != null && remoteId.isNotEmpty) {
          servers[serverId] = remoteId;
        }
      }
    }
    final rawHash = json['sha256']?.toString().trim().toLowerCase();
    final sha256 = rawHash != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(rawHash)
        ? rawHash
        : null;
    final rawPath = json['filePath']?.toString().trim();
    return SongLinkBinding(
      servers: servers,
      sha256: sha256,
      filePath: rawPath != null && rawPath.isNotEmpty ? rawPath : null,
    );
  }
}

/// Multi-PC binding store for local songs (`serverId -> remoteId` across all
/// paired desktops, plus content SHA-256 and last-known `filePath`).
///
/// `SongEntity` only holds one `(remoteServerId, remoteId)` pair in Isar; this
/// store preserves bindings for every paired desktop without altering the Isar
/// schema.
class LinkSongBindings {
  LinkSongBindings._();
  static final LinkSongBindings instance = LinkSongBindings._();

  static const String storageKey = 'lokal.link.song_bindings.v1';

  final Map<String, SongLinkBinding> _bySongId = {};
  SharedPreferences? _loadedPrefs;
  Future<void> _tail = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() work) {
    final next = _tail.then((_) => work());
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  @visibleForTesting
  void resetForTesting() {
    _bySongId.clear();
    _loadedPrefs = null;
  }

  void _decodeFromPrefs(SharedPreferences prefs) {
    _bySongId.clear();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final key = entry.key.toString();
        if (key.isEmpty || entry.value is! Map) continue;
        final binding = SongLinkBinding.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
        if (!binding.isEmpty) {
          _bySongId[key] = binding;
        }
      }
    } catch (_) {
      // Corrupt state must never prevent library sync or transfers.
    }
  }

  Future<SharedPreferences> _ensureLoadedInternal() async {
    final prefs = await SharedPreferences.getInstance();
    if (!identical(_loadedPrefs, prefs)) {
      _decodeFromPrefs(prefs);
      _loadedPrefs = prefs;
    }
    return prefs;
  }

  Future<void> ensureLoaded() => _serial(() async {
    await _ensureLoadedInternal();
  });

  Future<void> _persist(SharedPreferences prefs) async {
    _bySongId.removeWhere((_, binding) => binding.isEmpty);
    if (_bySongId.isEmpty) {
      await prefs.remove(storageKey);
      return;
    }
    await prefs.setString(
      storageKey,
      jsonEncode({
        for (final entry in _bySongId.entries) entry.key: entry.value.toJson(),
      }),
    );
  }

  /// Synchronous lookup against the in-memory bindings (call [ensureLoaded]
  /// beforehand in async workflows such as [LinkFileCopy]).
  SongLinkBinding? peek(String songId, {String? filePath}) {
    final direct = _bySongId[songId];
    if (direct != null) return direct;
    if (filePath != null && filePath.isNotEmpty) {
      for (final entry in _bySongId.values) {
        if (entry.filePath == filePath) return entry;
      }
    }
    return null;
  }

  /// Resolves the desktop track ID bound to [song] on [serverId], consulting
  /// both [LinkSongBindings] and [Song.remoteServerId]/[Song.remoteId].
  String? remoteIdForSong(Song song, int serverId) {
    final bound = peek(song.id, filePath: song.filePath)?.servers[serverId];
    if (bound != null && bound.isNotEmpty) return bound;
    if (song.remoteServerId == serverId &&
        song.remoteId != null &&
        song.remoteId!.isNotEmpty) {
      return song.remoteId;
    }
    return null;
  }

  Future<SongLinkBinding?> getBinding(String songId, {String? filePath}) async {
    await ensureLoaded();
    return peek(songId, filePath: filePath);
  }

  Future<void> bind(
    String songId, {
    int? serverId,
    String? remoteId,
    String? sha256,
    String? filePath,
  }) => _serial(() async {
    if (songId.isEmpty) return;
    final prefs = await _ensureLoadedInternal();
    var existing = _bySongId[songId];
    // Re-associate path-bound entries if a local row's Isar ID was rebuilt.
    if (existing == null && filePath != null && filePath.isNotEmpty) {
      String? staleKey;
      for (final entry in _bySongId.entries) {
        if (entry.value.filePath == filePath) {
          existing = entry.value;
          staleKey = entry.key;
          break;
        }
      }
      if (staleKey != null && staleKey != songId) {
        _bySongId.remove(staleKey);
      }
    }
    final nextServers = <int, String>{...?existing?.servers};
    if (serverId != null && remoteId != null && remoteId.isNotEmpty) {
      nextServers[serverId] = remoteId;
    }
    final cleanSha = sha256?.trim().toLowerCase();
    final validSha =
        cleanSha != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(cleanSha)
        ? cleanSha
        : existing?.sha256;
    final nextPath = (filePath != null && filePath.isNotEmpty)
        ? filePath
        : existing?.filePath;
    _bySongId[songId] = SongLinkBinding(
      servers: nextServers,
      sha256: validSha,
      filePath: nextPath,
    );
    await _persist(prefs);
  });

  Future<void> updateFilePath(
    String songId,
    String newFilePath, {
    String? oldFilePath,
  }) => _serial(() async {
    final prefs = await _ensureLoadedInternal();
    final existing =
        _bySongId[songId] ??
        (oldFilePath == null ? null : peek(songId, filePath: oldFilePath));
    if (existing == null) return;
    if (oldFilePath != null) {
      _bySongId.removeWhere(
        (key, value) => key != songId && value.filePath == oldFilePath,
      );
    }
    _bySongId[songId] = existing.copyWith(filePath: newFilePath);
    await _persist(prefs);
  });

  /// Copies all paired-server bindings (and SHA-256 if missing) from
  /// [loserSongIds] onto [keepSongId], then removes [loserSongIds].
  Future<void> mergeInto({
    required String keepSongId,
    required Iterable<String> loserSongIds,
    String? keepFilePath,
    Map<int, String> fallbackServers = const {},
  }) => _serial(() async {
    final prefs = await _ensureLoadedInternal();
    final keepExisting = _bySongId[keepSongId];
    final mergedServers = <int, String>{
      ...fallbackServers,
      ...?keepExisting?.servers,
    };
    var mergedSha = keepExisting?.sha256;
    for (final loserId in loserSongIds) {
      if (loserId == keepSongId) continue;
      final loser = _bySongId.remove(loserId);
      if (loser == null) continue;
      for (final entry in loser.servers.entries) {
        mergedServers.putIfAbsent(entry.key, () => entry.value);
      }
      mergedSha ??= loser.sha256;
    }
    final next = SongLinkBinding(
      servers: mergedServers,
      sha256: mergedSha,
      filePath: keepFilePath ?? keepExisting?.filePath,
    );
    if (!next.isEmpty) {
      _bySongId[keepSongId] = next;
    }
    await _persist(prefs);
  });

  Future<void> removeSong(String songId) => _serial(() async {
    final prefs = await _ensureLoadedInternal();
    if (_bySongId.remove(songId) != null) {
      await _persist(prefs);
    }
  });

  Future<void> removeServer(int serverId) => _serial(() async {
    final prefs = await _ensureLoadedInternal();
    var changed = false;
    final keys = _bySongId.keys.toList();
    for (final key in keys) {
      final current = _bySongId[key]!;
      if (current.servers.containsKey(serverId)) {
        final nextServers = Map<int, String>.from(current.servers)
          ..remove(serverId);
        _bySongId[key] = current.copyWith(servers: nextServers);
        changed = true;
      }
    }
    if (changed) {
      await _persist(prefs);
    }
  });

  Future<List<String>> findLocalSongIdsForServer(
    int serverId,
    String remoteId,
  ) async {
    await ensureLoaded();
    return [
      for (final entry in _bySongId.entries)
        if (entry.value.servers[serverId] == remoteId) entry.key,
    ];
  }

  Future<Set<String>> remoteIdsForServer(
    int serverId, {
    Set<String>? allowedSongIds,
    Set<String>? allowedPaths,
  }) async {
    await ensureLoaded();
    final ids = <String>{};
    for (final entry in _bySongId.entries) {
      final matchesSong =
          allowedSongIds == null || allowedSongIds.contains(entry.key);
      final matchesPath =
          allowedPaths != null &&
          entry.value.filePath != null &&
          allowedPaths.contains(entry.value.filePath);
      if (!matchesSong && !matchesPath) continue;
      final remoteId = entry.value.servers[serverId];
      if (remoteId != null && remoteId.isNotEmpty) {
        ids.add(remoteId);
      }
    }
    return ids;
  }

  Future<String?> findLocalSongIdBySha256(String sha256) async {
    await ensureLoaded();
    final target = sha256.trim().toLowerCase();
    if (target.isEmpty) return null;
    for (final entry in _bySongId.entries) {
      if (entry.value.sha256 == target) return entry.key;
    }
    return null;
  }
}
