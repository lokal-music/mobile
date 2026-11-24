import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../core/utils/dev_log.dart';
import '../core/utils/app_log.dart';
import '../data/database.dart';
import '../data/repositories/song_repository.dart';
import '../src/rust/api/scanner.dart' as rust_scanner;
import 'music_folder_service.dart';
import 'network_cache_service.dart';
import 'player_service.dart';
import 'sources/network_source_service.dart';

class AlbumArtService {
  AlbumArtService._();

  static final AlbumArtService instance = AlbumArtService._();

  // ponytail: artwork lives in the app *support* dir (durable) instead of
  // flutter_cache_manager's cache dir (OS-evictable). A DB pointer at a file
  // the OS had evicted was the root cause of art vanishing on reopen. The
  // prune below only ever deletes files no song points at, so stored art is
  // permanent; orphan files stay bounded by the 30-day age + 500-entry cap.
  static const Duration _artworkStalePeriod = Duration(days: 30);
  static const int _artworkMaxEntries = 500;
  static const Duration _pruneInterval = Duration(hours: 6);

  Directory? _artworkDir;
  DateTime _lastPrune = DateTime.fromMillisecondsSinceEpoch(0);

  // Lazy so constructing the singleton (or resolving for skipped songs) does
  // not require an initialized database.
  late final SongRepository _songRepository = SongRepository();
  final MusicFolderService _musicFolderService = MusicFolderService();
  final Map<String, Future<String?>> _inFlightResolutions = {};
  final Map<String, String> _resolvedPaths = {};
  final _materializedArtwork = ValueNotifier<({String source, String path})?>(
    null,
  );

  /// Observe only completed owned cache writes; listening never extracts art.
  ValueListenable<({String source, String path})?> get materializedArtwork =>
      _materializedArtwork;

  void _rememberResolvedPath(String source, String path) {
    _resolvedPaths[source] = path;
    _materializedArtwork.value = (source: source, path: path);
  }

  // Once per server/protocol until a successful fetch: network failures must
  // be visible in exported diagnostics without flooding logs for every tile.
  final Set<String> _reportedNetworkCoverErrors = {};

  // SMB and WebDAV each expose the same folder cover to every track in an
  // album. Bound outstanding NAS image operations and share one request per
  // cover marker, rather than creating a connection per visible list tile.
  final List<Future<void>> _networkArtworkSlots = [
    Future<void>.value(),
    Future<void>.value(),
  ];
  int _nextNetworkArtworkSlot = 0;

  String? _networkArtworkKey(String sourcePath, String? marker) {
    final uri = Uri.tryParse(sourcePath);
    if (uri == null ||
        (uri.scheme != 'smb' &&
            uri.scheme != 'webdav' &&
            uri.scheme != 'lokal')) {
      return null;
    }
    // Desktop artwork is also fetched by a stable remote ID. Index the
    // downloaded image in durable support storage, so offline cards can
    // restore it after a force-close without contacting the paired PC again.
    if (uri.scheme == 'lokal') {
      final desktopId = markerForDesktopArtwork(sourcePath, marker);
      if (desktopId == null) return null;
      return 'lokal://${uri.host}/cover/${Uri.encodeComponent(desktopId)}';
    }
    final prefix = '${uri.scheme}-cover://';
    if (marker != null && marker.startsWith(prefix)) {
      return '${uri.scheme}://${uri.host}/$marker';
    }
    // Albums without a separate cover.jpg still share embedded art across
    // their tracks. Do not issue the same prefix read once per track in a
    // 20-song folder; persist one recovered image per NAS album directory.
    final remoteId = networkRemoteIdFromAudioPath(sourcePath);
    if (remoteId == null) return sourcePath;
    try {
      final remotePath = uri.scheme == 'webdav'
          ? Uri.decodeComponent(remoteId)
          : remoteId;
      final slash = remotePath.lastIndexOf('/');
      if (slash <= 0) return sourcePath;
      return '${uri.scheme}://${uri.host}/folder/'
          '${Uri.encodeComponent(remotePath.substring(0, slash))}';
    } catch (_) {
      return sourcePath;
    }
  }

  @visibleForTesting
  static String? markerForDesktopArtwork(
    String audioSourcePath,
    String? coverMarker,
  ) {
    final uri = Uri.tryParse(audioSourcePath);
    if (uri == null || uri.scheme != 'lokal' || uri.host.isEmpty) return null;
    if (coverMarker != null && coverMarker.startsWith('lokal-cover://')) {
      final id = coverMarker.substring('lokal-cover://'.length);
      if (id.isNotEmpty) return id;
    }
    return uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null;
  }

  Future<File> _networkIndexFile(String key) async {
    final art = await _ensureArtworkDir();
    return File(
      '${art.path}/network-index/'
      '${sha256.convert(utf8.encode(key))}.ref',
    );
  }

  Future<String?> _cachedNetworkArtwork(String key) async {
    try {
      final ref = await _networkIndexFile(key);
      final name = (await ref.readAsString()).trim();
      // Never use a filename or path controlled by a remote NAS response.
      if (!RegExp(r'^embedded-artwork:[a-f0-9]{32}$').hasMatch(name)) {
        return null;
      }
      final art = await _ensureArtworkDir();
      final path = '${art.path}/$name';
      if (await _isUsableImagePath(path) && await File(path).length() > 0) {
        return path;
      }
    } catch (_) {
      // An evicted/corrupt index must cause a fresh NAS request, not hide art.
    }
    return null;
  }

  Future<void> _rememberNetworkArtwork(String key, String cacheKey) async {
    try {
      final ref = await _networkIndexFile(key);
      await ref.parent.create(recursive: true);
      await ref.writeAsString(cacheKey, flush: true);
    } catch (_) {
      // Durable index is optional; an available image must still be rendered.
    }
  }

  Future<Uint8List?> _loadArtworkWithNetworkLimit(
    String sourcePath, {
    String? existingPath,
  }) async {
    if (_networkArtworkKey(sourcePath, existingPath) == null) {
      return _loadArtworkBytes(sourcePath, existingPath: existingPath);
    }
    final slot = _nextNetworkArtworkSlot++ % _networkArtworkSlots.length;
    final previous = _networkArtworkSlots[slot];
    final released = Completer<void>();
    _networkArtworkSlots[slot] = released.future;
    await previous;
    try {
      return await _loadArtworkBytes(sourcePath, existingPath: existingPath);
    } finally {
      released.complete();
    }
  }

  /// New/reordered cover cards can paint the already resolved desktop art on
  /// their first frame, instead of flashing a marker-scheme placeholder.
  String? cachedArtworkPathFor(String? audioSourcePath) {
    final path = _resolvedPaths[audioSourcePath];
    if (path != null && File(path).existsSync()) return path;
    _resolvedPaths.remove(audioSourcePath);
    return null;
  }

  // ponytail: album tracks share one folder cover; cache the raw bytes so a
  // 20-track album reads cover.jpg once, not 20 times.
  final Map<String, Uint8List?> _folderCoverCache = {};

  Future<String?> resolveArtworkPath({
    String? existingPath,
    required String audioSourcePath,
  }) async {
    if (audioSourcePath.isEmpty) return null;
    if (await _isUsableImagePath(existingPath)) return existingPath;

    final resolved = cachedArtworkPathFor(audioSourcePath);
    if (resolved != null) return resolved;

    final networkKey = _networkArtworkKey(audioSourcePath, existingPath);
    final resolutionKey = networkKey ?? audioSourcePath;
    final future = _inFlightResolutions.putIfAbsent(resolutionKey, () async {
      if (networkKey != null) {
        final persisted = await _cachedNetworkArtwork(networkKey);
        if (persisted != null) return persisted;
      }

      final raw = await _loadArtworkWithNetworkLimit(
        audioSourcePath,
        existingPath: existingPath,
      );
      if (raw == null || raw.isEmpty) {
        await _persistArtworkPath(audioSourcePath, null);
        return null;
      }

      // A content-addressed image stays shared by different tracks. A tiny
      // durable reference per cover marker survives app restart while the
      // DB keeps the remote marker for recovery after cache eviction.
      final cacheKey = _cacheKey(raw);
      final dir = await _ensureArtworkDir();
      final cachedFile = File('${dir.path}/$cacheKey');
      if (!await _isUsableImagePath(cachedFile.path) ||
          await cachedFile.length() == 0) {
        final bytes = await _normalizeArtworkBytes(raw);
        await cachedFile.writeAsBytes(bytes, flush: true);
      }
      if (networkKey != null) {
        await _rememberNetworkArtwork(networkKey, cacheKey);
      }

      await _persistArtworkPath(audioSourcePath, cachedFile.path);
      unawaited(_pruneIfNeeded(dir));
      return cachedFile.path;
    });

    try {
      final path = await future;
      if (path != null) _rememberResolvedPath(audioSourcePath, path);
      return path;
    } finally {
      // Multiple tiles may await the same album cover. Only remove the exact
      // completed operation, never a newer retry for this marker.
      if (identical(_inFlightResolutions[resolutionKey], future)) {
        _inFlightResolutions.remove(resolutionKey);
      }
    }
  }

  /// Resolves artwork for [songs] that have no usable pointer yet. Safe to
  /// run detached after a scan: already-resolved songs short-circuit on the
  /// [resolveArtworkPath] existence check, network songs are skipped (their
  /// covers resolve lazily via the marker).
  ///
  /// [onProgress] reports `(completed, total)` after every song, including
  /// skipped and failed ones, so callers can show a deterministic count.
  Future<void> resolveMissingArtwork(
    List<SongEntity> songs, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final total = songs.length;
    var completed = 0;
    onProgress?.call(completed, total);
    for (final song in songs) {
      try {
        final path = song.filePath;
        if (path.isEmpty) continue;
        final scheme = Uri.tryParse(path)?.scheme;
        if (isSupportedNetworkProtocol(scheme)) continue;
        // One unreadable/corrupt file must not abort artwork backfill for the
        // rest of the folder.
        try {
          await resolveArtworkPath(
            existingPath: song.albumArtPath,
            audioSourcePath: path,
          );
        } catch (error) {
          debugPrint('Artwork resolve failed for $path: $error');
        }
      } finally {
        completed++;
        onProgress?.call(completed, total);
      }
    }
  }

  Future<int> getCacheSize() async {
    final dir = await _ensureArtworkDir();
    var total = 0;
    try {
      await for (final entity in dir.list(
        recursive: false,
        followLinks: false,
      )) {
        if (entity is File) total += await entity.length();
      }
    } catch (_) {}
    return total;
  }

  void clearMemoryCache() {
    _resolvedPaths.clear();
  }

  Future<void> clearCache() async {
    _resolvedPaths.clear();
    final dir = await _ensureArtworkDir();
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) await entity.delete();
      }
    } catch (_) {}
  }

  Future<Directory> _ensureArtworkDir() async {
    final cached = _artworkDir;
    if (cached != null) return cached;
    final support = await getApplicationSupportDirectory();
    final artwork = Directory('${support.path}/artwork');
    if (!await artwork.exists()) {
      await artwork.create(recursive: true);
    }
    _artworkDir = artwork;
    return artwork;
  }

  // ponytail: throttled best-effort prune — files still referenced by a song
  // in the DB never get deleted (art must persist); orphans beyond
  // _artworkMaxEntries or older than _artworkStalePeriod go.
  Future<void> _pruneIfNeeded(Directory dir) async {
    final now = DateTime.now();
    if (now.difference(_lastPrune) < _pruneInterval) return;
    _lastPrune = now;

    try {
      final referenced = await _songRepository.getReferencedAlbumArtPaths();
      // Remote-song DB rows retain their server markers, not the local image
      // path. Honor the durable cover index too: without this, pruning would
      // evict active NAS artwork as an "orphan" after 500 covers.
      final indexDirectory = Directory('${dir.path}/network-index');
      if (await indexDirectory.exists()) {
        await for (final entity in indexDirectory.list(followLinks: false)) {
          if (entity is! File) continue;
          try {
            final name = (await entity.readAsString()).trim();
            if (RegExp(r'^embedded-artwork:[a-f0-9]{32}$').hasMatch(name)) {
              referenced.add('${dir.path}/$name');
            }
          } catch (_) {}
        }
      }

      final files = <({File file, DateTime modified})>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        files.add((file: entity, modified: stat.modified));
      }
      files.sort((a, b) => b.modified.compareTo(a.modified));

      final staleCut = now.subtract(_artworkStalePeriod);
      var kept = 0;
      for (final entry in files) {
        final beyondCap = kept >= _artworkMaxEntries;
        final isStale = entry.modified.isBefore(staleCut);
        if (!referenced.contains(entry.file.path) && (beyondCap || isStale)) {
          try {
            await entry.file.delete();
          } catch (_) {}
        } else {
          kept++;
        }
      }
    } catch (_) {}
  }

  Future<bool> _isUsableImagePath(String? path) async {
    if (path == null || path.isEmpty) {
      return false;
    }

    if (path.startsWith('http')) {
      return true;
    }

    return File(path).exists();
  }

  /// Fetch raw artwork bytes. Network songs resolve through their protocol
  /// service's cover endpoint using the `<proto>-cover://<marker>` stored in
  /// the entity's albumArtPath. Local songs try embedded art first, then fall
  /// back to a nearby folder cover (`cover.jpg`, `folder.png`, …).
  /// The cache key contains the original opaque remoteId, not Uri.path:
  /// Uri decoding would change WebDAV '%2F' to '/' and miss the FLAC cache.
  @visibleForTesting
  static String? networkRemoteIdFromAudioPath(String audioPath) {
    final scheme = audioPath.indexOf('://');
    if (scheme < 0) return null;
    final slash = audioPath.indexOf('/', scheme + 3);
    if (slash < 0 || slash == audioPath.length - 1) return null;
    return audioPath.substring(slash + 1);
  }

  Future<Uint8List?> _loadArtworkBytes(
    String audioSourcePath, {
    String? existingPath,
  }) async {
    final uri = Uri.tryParse(audioSourcePath);
    if (uri != null && isSupportedNetworkProtocol(uri.scheme)) {
      final service = networkSourceServiceFor(uri.scheme);
      final marker =
          existingPath != null && existingPath.startsWith(service.coverScheme)
          ? existingPath.substring(service.coverScheme.length)
          : uri.scheme == 'lokal' && uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : null;
      final serverId = int.tryParse(uri.host);
      if (serverId == null) return null;
      if (marker != null && marker.isNotEmpty) {
        final server = await Database.networkServers.get(serverId);
        if (server != null) {
          final errorKey = '${uri.scheme}:$serverId';
          try {
            final bytes = await service.getCoverArt(server, marker);
            if (bytes.isNotEmpty) {
              _reportedNetworkCoverErrors.remove(errorKey);
              return Uint8List.fromList(bytes);
            }
          } catch (error) {
            // A missing/unreadable cover.jpg must not suppress embedded art,
            // but silently hiding TLS/auth failures made diagnosis impossible.
            if (_reportedNetworkCoverErrors.add(errorKey)) {
              AppLog.instance.add(
                'NAS cover fetch failed (${uri.scheme}, server $serverId): $error',
              );
            }
          }
        }
      }

      // A NAS listing cannot expose embedded APIC/FLAC PICTURE tags.
      // Reuse cached audio when available. Otherwise fetch at most a small
      // FLAC/MP3 prefix, never the full audio file just to draw a list tile.
      // Preserve the opaque encoded remoteId (especially WebDAV percent URLs).
      if (uri.scheme == 'smb' || uri.scheme == 'webdav') {
        final raw = networkRemoteIdFromAudioPath(audioSourcePath);
        if (raw == null) return null;
        final local = await NetworkCacheService().getPath(serverId, raw);
        if (local != null) {
          final cached = await _loadEmbeddedArtworkBytes(local);
          if (cached != null && cached.isNotEmpty) return cached;
        }
        final server = await Database.networkServers.get(serverId);
        final embeddedSource = service is NetworkEmbeddedArtworkSource
            ? service as NetworkEmbeddedArtworkSource
            : null;
        if (server != null && embeddedSource != null) {
          try {
            final bytes = await embeddedSource.getEmbeddedCoverArt(server, raw);
            if (bytes.isNotEmpty) return Uint8List.fromList(bytes);
          } catch (error) {
            final errorKey = '${uri.scheme}:$serverId:embedded';
            if (_reportedNetworkCoverErrors.add(errorKey)) {
              AppLog.instance.add(
                'NAS embedded cover prefix failed (${uri.scheme}, '
                'server $serverId): $error',
              );
            }
          }
        }
      }
      return null;
    }

    final embedded = await _loadEmbeddedArtworkBytes(audioSourcePath);
    if (embedded != null && embedded.isNotEmpty) {
      return embedded;
    }

    // No embedded cover: many libraries ship a sibling cover/folder image.
    return _loadFolderCoverBytes(audioSourcePath);
  }

  Future<Uint8List?> _loadEmbeddedArtworkBytes(String audioSourcePath) async {
    if (Platform.isAndroid && audioSourcePath.startsWith('content://')) {
      return _loadContentUriArtworkBytes(audioSourcePath);
    }

    // Synthesized scan rows are keyed `file:///storage/...`; Rust needs the
    // plain path or fs::open fails on the scheme. A corrupt/unsupported file
    // must fall through to the folder-cover attempt, not abort the caller.
    try {
      return await rust_scanner.extractEmbeddedArtwork(
        path: _plainPathOf(audioSourcePath),
      );
    } catch (_) {
      return null;
    }
  }

  /// Embedded-art lookup for SAF `content://` rows. WavPack/DSD skip the
  /// retriever (it cannot decode their covers anywhere); everything else
  /// tries the retriever first and falls back to the Rust tag parser when it
  /// comes up empty (hi-res containers with non-standard tags, for example).
  Future<Uint8List?> _loadContentUriArtworkBytes(String audioSourcePath) async {
    final rustOnly = _isRustOnlyAudioUri(audioSourcePath);
    if (!rustOnly) {
      try {
        final direct = await _musicFolderService.fetchEmbeddedArtwork(
          audioSourcePath,
        );
        if (direct != null && direct.isNotEmpty) return direct;
      } catch (_) {
        // Retriever errors fall through to the Rust parser.
      }
      final staged = await _loadStagedRustArtworkBytes(audioSourcePath);
      if (staged != null && staged.isNotEmpty) return staged;
      devLog(
        '[Artwork] no embedded cover for $audioSourcePath '
        '(retriever + Rust parser)',
      );
      return null;
    }

    final staged = await _loadStagedRustArtworkBytes(audioSourcePath);
    if (staged != null && staged.isNotEmpty) return staged;
    // WavPack/DSD: the retriever is the only remaining option. It usually
    // yields nothing for those containers, but keep it as a last resort.
    return _musicFolderService.fetchEmbeddedArtwork(audioSourcePath);
  }

  /// Stages [audioSourcePath] into the shared playback cache and parses its
  /// embedded art with the Rust tag reader. Null when staging is refused
  /// (size cap) or the parser finds nothing.
  Future<Uint8List?> _loadStagedRustArtworkBytes(String audioSourcePath) async {
    final staged = await _musicFolderService.cacheUriForPlayback(
      audioSourcePath,
      extensionHint: _extensionOf(audioSourcePath),
      maxSizeBytes: _artworkStagingMaxBytes,
    );
    if (staged == null) return null;
    try {
      return await rust_scanner.extractEmbeddedArtwork(path: staged);
    } catch (_) {
      return null;
    }
  }

  /// Bounded memory cache for per-folder cover bytes.
  static const int _folderCoverCacheMaxEntries = 64;

  Future<Uint8List?> _loadFolderCoverBytes(String audioSourcePath) async {
    if (audioSourcePath.startsWith('content://')) {
      if (!Platform.isAndroid) return null;
      try {
        return await _musicFolderService.fetchSiblingArtwork(audioSourcePath);
      } catch (_) {
        return null;
      }
    }

    final plainPath = _plainPathOf(audioSourcePath);
    final dir = File(plainPath).parent.path;
    if (_folderCoverCache.containsKey(dir)) {
      return _folderCoverCache[dir];
    }

    Uint8List? bytes;
    var cacheable = true;
    try {
      bytes = await _readFolderCoverFromFilesystem(plainPath);
    } catch (_) {
      // Transient I/O error (e.g. SD card not ready): do not poison the
      // folder cache with a miss, so the next attempt can still find cover.
      cacheable = false;
    }
    if (cacheable) {
      _rememberFolderCover(dir, bytes);
    }
    return bytes;
  }

  /// Drops cached sibling-cover bytes for [audioSourcePath]'s folder so a
  /// reset re-reads a replaced `cover.jpg`. SAF rows are not cached here, so
  /// this only matters for filesystem paths.
  void evictFolderCoverCache(String audioSourcePath) {
    if (audioSourcePath.startsWith('content://')) return;
    _folderCoverCache.remove(File(_plainPathOf(audioSourcePath)).parent.path);
  }

  void _rememberFolderCover(String dir, Uint8List? bytes) {
    if (_folderCoverCache.length >= _folderCoverCacheMaxEntries) {
      _folderCoverCache.remove(_folderCoverCache.keys.first);
    }
    _folderCoverCache[dir] = bytes;
  }

  Future<Uint8List?> _readFolderCoverFromFilesystem(String audioPath) async {
    if (audioPath.isEmpty) return null;
    final parent = File(audioPath).parent;
    if (!await parent.exists()) return null;

    final matches = <File>[];
    await for (final entity in parent.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last.toLowerCase();
      if (!isFolderCoverImageName(name)) continue;
      matches.add(entity);
    }
    if (matches.isEmpty) return null;

    matches.sort((a, b) => a.path.compareTo(b.path));
    try {
      return await matches.first.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Extensions whose embedded art only the Rust parsers can read.
  static const _rustOnlyArtExtensions = {'wv', 'dsf', 'dff'};

  /// Upper bound for staging a document just to extract its cover (256 MB).
  static const _artworkStagingMaxBytes = 256 * 1024 * 1024;

  bool _isRustOnlyAudioUri(String source) {
    final path = _plainPathOf(source);
    return _rustOnlyArtExtensions.contains(_extensionOf(path));
  }

  String _plainPathOf(String source) {
    if (source.startsWith('file://')) {
      return Uri.tryParse(source)?.toFilePath() ?? source;
    }
    return source;
  }

  String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  Future<Uint8List> _normalizeArtworkBytes(Uint8List raw) {
    return compute(_normalizeArtworkIsolate, raw);
  }

  Future<void> _persistArtworkPath(
    String audioSourcePath,
    String? albumArtPath,
  ) async {
    try {
      // Network songs keep their cover-art marker in the DB so a cache
      // eviction can always re-resolve; only the in-memory playlist is
      // updated with the resolved local path.
      final isNetwork = isSupportedNetworkProtocol(
        Uri.tryParse(audioSourcePath)?.scheme,
      );
      if (!isNetwork) {
        await _songRepository.updateAlbumArtPath(audioSourcePath, albumArtPath);
      }
      if (albumArtPath != null) {
        PlayerService().syncAlbumArtPaths(
          filePaths: [audioSourcePath],
          albumArtPath: albumArtPath,
        );
      }
    } catch (_) {
      // Best-effort cache persistence should not break rendering.
    }
  }

  String _cacheKey(Uint8List bytes) {
    final digest = md5.convert(bytes);
    return 'embedded-artwork:${digest.toString()}';
  }
}

const int _artworkMaxDimension = 1000;
const int _artworkPassthroughBytes = 512 * 1024;
const int _artworkJpegQuality = 85;

/// Sibling cover stems, matching the SMB/WebDAV scanners so local folders
/// behave the same.
const List<String> _folderCoverStems = [
  'cover',
  'folder',
  'album',
  'albumart',
  'front',
];

const Set<String> _folderCoverExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'bmp',
};

/// Whether [name] looks like a folder-cover image: `cover.jpg`, `folder.png`,
/// `front.webp`, `album.1.jpg`, …. Case-insensitive.
bool isFolderCoverImageName(String name) {
  final lower = name.toLowerCase();
  final dot = lower.lastIndexOf('.');
  if (dot <= 0) return false;
  final stem = lower.substring(0, dot);
  if (!_folderCoverExtensions.contains(lower.substring(dot + 1))) {
    return false;
  }
  return _folderCoverStems.any((c) => stem == c || stem.startsWith('$c.'));
}

Uint8List _normalizeArtworkIsolate(Uint8List raw) {
  if (raw.length < _artworkPassthroughBytes) {
    return raw;
  }

  final decoded = img.decodeImage(raw);
  if (decoded == null) {
    return raw;
  }

  final img.Image target;
  if (decoded.width >= decoded.height) {
    target = decoded.width > _artworkMaxDimension
        ? img.copyResize(decoded, width: _artworkMaxDimension)
        : decoded;
  } else {
    target = decoded.height > _artworkMaxDimension
        ? img.copyResize(decoded, height: _artworkMaxDimension)
        : decoded;
  }

  return Uint8List.fromList(
    img.encodeJpg(target, quality: _artworkJpegQuality),
  );
}
