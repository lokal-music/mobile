import 'dart:async';

import '../lyrics_service.dart';
import '../ios_foreground_transfer_barrier.dart';
import '../ios_library_scan_epoch.dart';
import '../ios_transfer_song_identity.dart';
import 'desktop_music_storage.dart';
import 'copied_track_clip.dart';
import 'desktop_catalogue_import.dart';
import 'desktop_genre_reconciliation.dart';

import 'package:path/path.dart' as p;

import '../graceful_http_client.dart';
import '../local_metadata_repair.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:image/image.dart' as img;

import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:crypto/crypto.dart';

import 'package:http/http.dart' as http;
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/database.dart';
import '../../data/repositories/song_repository.dart';
import '../../models/song.dart';
import '../library_scanner_service.dart' show ScanProgress;
import '../lokal_remote_credentials_store.dart';
import '../../models/lokal_remote_state.dart';
import '../network_cache_service.dart';
import '../sources/network_source_service.dart';
import 'link_journal.dart';
import 'link_protocol.dart';
import '../album_art_service.dart';

/// A small independent artwork thumbnail for a history-only phone play.
/// Never send a source file URI or embed megabytes of art in the link journal.
@visibleForTesting
Uint8List? linkHistoryCoverJpeg(Uint8List source) {
  try {
    final decoded = img.decodeImage(source);
    if (decoded == null) return null;
    final scale = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;
    final resized = scale > 384
        ? img.copyResize(
            decoded,
            width: (decoded.width * 384 / scale).round().clamp(1, 384).toInt(),
            height: (decoded.height * 384 / scale)
                .round()
                .clamp(1, 384)
                .toInt(),
          )
        : decoded;
    final encoded = Uint8List.fromList(img.encodeJpg(resized, quality: 72));
    return encoded.isNotEmpty && encoded.length <= 180000 ? encoded : null;
  } on Object {
    return null;
  }
}

/// Desktop songs use the existing ranged network-player and bounded audio cache.
/// The server row contains no token; encrypted storage remains the only token owner.
class LokalDesktopSource extends NetworkSourceService {
  LokalDesktopSource({
    http.Client Function()? uploadClientFactory,
    http.Client Function()? originalClientFactory,
    bool? iosLibraryMutations,
  }) : _iosLibraryMutations = iosLibraryMutations ?? Platform.isIOS,
       _uploadClientFactory = uploadClientFactory ?? GracefulHttpClient.new,
       _originalClientFactory = originalClientFactory ?? GracefulHttpClient.new;
  final bool _iosLibraryMutations;
  final http.Client Function() _uploadClientFactory;
  final http.Client Function() _originalClientFactory;
  static final instance = LokalDesktopSource();
  final _libraryTransfers = IosForegroundTransferBarrier();
  int get libraryTransferEpoch => _libraryTransfers.epoch;
  bool get libraryTransfersPaused => _libraryTransfers.paused;
  Future<T> withLibraryTransfersDrained<T>(Future<T> Function() mutation) =>
      _libraryTransfers.withMutation(mutation);

  void Function() registerLibraryMutationParticipant(
    Future<void> Function() retire,
  ) => _libraryTransfers.registerMutationParticipant(retire);

  /// Include peer sync's final database writes in the same iPhone drain.
  Future<T> runLibraryTransfer<T>(Future<T> Function() operation) =>
      _trackLibraryTransfer(operation);
  void cancelLibraryTransferOnPause(void Function() cancel) {
    if (_iosLibraryMutations) _libraryTransfers.cancelOnPause(cancel);
  }

  Future<T> _trackLibraryTransfer<T>(Future<T> Function() operation) =>
      _iosLibraryMutations ? _libraryTransfers.run(operation) : operation();
  Future<void> _putLibrarySong(SongEntity row) =>
      Database.instance.writeTxn(() async {
        if (_iosLibraryMutations) {
          await retainIosImportSongIdentitiesInTransaction(Database.instance, [
            row,
          ]);
        }
        await Database.songs.put(row);
      });

  final _cache = NetworkCacheService();
  final _musicStorage = DesktopMusicStorage();
  Future<String>? _legacyDirectory;
  final Map<String, Future<String>> _downloads = {};

  bool supportsSizeMatching = false;
  bool _historyArtworkUploading = false;

  Future<bool> requireOriginalFileSupport(
    LokalRemoteCredentials credentials,
  ) async {
    final response = await http
        .get(
          credentials.origin.replace(path: '/api/remote/files'),
          headers: _headers(credentials),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200 ||
        (jsonDecode(response.body) as Map)['originalFiles'] != true) {
      throw StateError(
        'Update Lokal on your PC to copy missing song files both ways.',
      );
    }
    final capabilities = jsonDecode(response.body) as Map;
    supportsSizeMatching = capabilities['sizeMatching'] == true;
    return capabilities['contentMatching'] == true;
  }

  Future<Uint8List?> _phoneCoverThumbnail(Song song) async {
    final sourcePath = song.filePath;
    if (sourcePath == null || sourcePath.isEmpty || song.isNetworkSource) {
      return null;
    }
    var art = song.albumArt;
    if (art == null || !await File(art).exists()) {
      art = await AlbumArtService.instance.resolveArtworkPath(
        existingPath: art,
        audioSourcePath: sourcePath,
      );
    }
    if (art == null || !await File(art).exists()) return null;
    final file = File(art);
    final stat = await file.stat();
    if (stat.size <= 0 || stat.size > 8 * 1024 * 1024) return null;
    return compute(
      linkHistoryCoverJpeg,
      Uint8List.fromList(await file.readAsBytes()),
    );
  }

  /// The audio copy can have an independent folder cover rather than an
  /// embedded tag. Export that cover separately under the paired recording ID.
  Future<void> _uploadCopiedArtwork(
    Song song,
    LokalRemoteCredentials credentials,
    String desktopTrackId,
  ) async {
    try {
      final jpg = await _phoneCoverThumbnail(song);
      if (jpg == null) return;
      await http
          .post(
            credentials.origin.replace(
              pathSegments: [
                'api',
                'remote',
                'files',
                desktopTrackId,
                'artwork',
              ],
            ),
            headers: {
              ..._headers(credentials),
              'content-type': 'application/json',
            },
            body: jsonEncode({'image_base64': base64Encode(jpg)}),
          )
          .timeout(const Duration(seconds: 6));
    } on Object {
      // Cover failure cannot invalidate an already verified audio transfer.
    }
  }

  /// Upload a few small album covers for history-only phone recordings.
  /// A ghost is non-playable until its original audio is copied; this only
  /// preserves its artwork. History sync must succeed independently of art.
  Future<void> uploadHistoryArtwork(
    LokalRemoteCredentials credentials,
    List<dynamic> events, {
    int maxCovers = 2,
  }) async {
    if (_historyArtworkUploading || !Database.isInitialized || maxCovers <= 0) {
      return;
    }
    _historyArtworkUploading = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = <String>{};
      final repository = SongRepository();
      var uploaded = 0, attempted = 0;
      for (final raw in events) {
        if (uploaded >= maxCovers) break;
        if (raw is! Map || raw['source'] != 'phone') continue;
        final key = raw['track_key']?.toString() ?? '';
        if (key.isEmpty || key.length > 1500 || !seen.add(key)) continue;
        final wire = raw['track'];
        if (wire is! Map) continue;
        final id = int.tryParse(wire['id']?.toString() ?? '');
        if (id == null) continue;
        final row = await Database.songs.get(id);
        if (row == null || row.sourceType != null || row.filePath.isEmpty) {
          continue;
        }
        final cacheKey =
            'lokal.link.artwork.${credentials.desktopId}.'
            '${sha256.convert(utf8.encode(key))}';
        final lastSent = prefs.getInt(cacheKey) ?? 0;
        if (DateTime.now().millisecondsSinceEpoch - lastSent <
            const Duration(days: 30).inMilliseconds)
          continue;
        // A single stats tick must not decode 50 large image files just
        // because the first few songs lack artwork.
        if (++attempted > maxCovers + 2) break;
        try {
          final jpg = await _phoneCoverThumbnail(
            repository.songFromEntity(row),
          );
          if (jpg == null) continue;
          final response = await http
              .post(
                credentials.origin.replace(path: '/api/remote/history/artwork'),
                headers: {
                  ..._headers(credentials),
                  'content-type': 'application/json',
                },
                body: jsonEncode({
                  'track_key': key,
                  'image_base64': base64Encode(jpg),
                }),
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200) {
            await prefs.setInt(cacheKey, DateTime.now().millisecondsSinceEpoch);
            uploaded++;
          }
        } on Object {
          // A missing/corrupt cover or rejected image is isolated per song.
          continue;
        }
      }
    } on Object {
      // This auxiliary transfer must never block listening statistics.
    } finally {
      _historyArtworkUploading = false;
    }
  }

  /// Replay a small, recent window during explicit Sync now. Older mobile
  /// plays may have been acknowledged before album artwork was supported.
  Future<void> uploadRecentHistoryArtwork(
    LokalRemoteCredentials credentials, {
    int maxCovers = 8,
  }) async {
    if (!Database.isInitialized) return;
    final rows = await Database.instance.playEventEntitys
        .where()
        .sortByPlayedAtDesc()
        .limit(100)
        .findAll();
    final events = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (row.source != 'phone') continue;
      try {
        events.add({
          'source': row.source,
          'track_key': row.trackKey,
          'track': jsonDecode(row.trackJson),
        });
      } on FormatException {
        // A malformed legacy journal row cannot break full library sync.
      }
    }
    await uploadHistoryArtwork(credentials, events, maxCovers: maxCovers);
  }

  /// Only look up a desktop file's size when its metadata is opened.
  /// Measuring every remote file during a catalogue import is especially
  /// expensive for NAS libraries; this paired endpoint never streams audio.
  Future<int?> linkedFileSize(Song song) async {
    if (song.sourceType != 'lokal' ||
        song.remoteId == null ||
        song.remoteServerId == null ||
        !Database.isInitialized)
      return null;
    try {
      final server = await Database.networkServers.get(song.remoteServerId!);
      if (server == null) return null;
      final credentials = await _credentials(server);
      final response = await http
          .get(
            credentials.origin.replace(
              pathSegments: [
                'api',
                'remote',
                'library',
                'file-size',
                song.remoteId!,
              ],
            ),
            headers: _headers(credentials),
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final bytes = (jsonDecode(response.body) as Map)['bytes'];
      if (bytes is! int || bytes <= 0) return null;
      // Make the result available offline on subsequent visits. Identity is
      // checked again after the network round-trip to avoid stale writes.
      final numericId = int.tryParse(song.id);
      if (numericId != null) {
        await Database.instance.writeTxn(() async {
          final row = await Database.songs.get(numericId);
          if (row == null ||
              row.remoteId != song.remoteId ||
              row.remoteServerId != song.remoteServerId)
            return;
          row.fileSize = bytes;
          await Database.songs.put(row);
        });
      }
      return bytes;
    } on Object {
      return null;
    }
  }

  /// Run only for metadata misses. Content URIs are staged with the same grant
  /// as uploads; a filesystem path/filename is never used as a fingerprint.
  Future<Map<String, dynamic>?> originalFingerprint(
    Song song, {
    void Function()? check,
  }) async {
    var path = song.filePath;
    if (path == null) return null;
    String? staged;
    try {
      if (path.startsWith('content://')) {
        staged = await const MethodChannel('lokal/desktop_link')
            .invokeMethod<String>('stageAudio', {
              'uri': path,
              'extension': song.fileType.toLowerCase(),
            });
        if (staged == null) return null;
        path = staged;
      } else if (path.startsWith('file://')) {
        path = Uri.parse(path).toFilePath();
      }
      final file = File(path);
      final before = await file.stat();
      if (before.size <= 0 || before.size > 1024 * 1024 * 1024) return null;
      check?.call();
      final digest = await sha256
          .bind(
            file.openRead().map((bytes) {
              check?.call();
              return bytes;
            }),
          )
          .first;
      final after = await file.stat();
      if (before.size != after.size || before.modified != after.modified) {
        return null;
      }
      return {'size': before.size, 'sha256': digest.toString()};
    } on Object {
      return null; // The actual upload reports inaccessible audio normally.
    } finally {
      if (staged != null) {
        try {
          await File(staged).delete();
        } on FileSystemException {
          /* Already cleaned. */
        }
      }
    }
  }

  Future<int?> originalFileSize(Song song) async {
    final raw = song.filePath;
    if (raw == null || raw.startsWith('content://')) return null;
    try {
      final path = raw.startsWith('file://')
          ? Uri.parse(raw).toFilePath()
          : raw;
      final stat = await File(path).stat();
      return stat.type == FileSystemEntityType.file && stat.size > 0
          ? stat.size
          : null;
    } on FileSystemException {
      return null;
    }
  }

  /// Select the whole-plan foreground path before native admission on older
  /// peers. Native admission independently checks this capability again; this
  /// read-only query confers no upload authority.
  Future<bool> supportsDurableUploadOperations(
    LokalRemoteCredentials credentials,
  ) => _trackLibraryTransfer(() async {
    final client = _originalClientFactory();
    if (_iosLibraryMutations) _libraryTransfers.cancelOnPause(client.close);
    try {
      return await (() async {
        final request = http.Request(
          'GET',
          credentials.origin.replace(path: '/api/remote/files/operations'),
        )..followRedirects = false;
        request.headers.addAll({
          ..._headers(credentials),
          'accept': 'application/json',
        });
        final response = await client.send(request);
        if (response.statusCode != 200 ||
            (response.contentLength ?? 0) > 16384 ||
            response.headers['content-type']
                    ?.split(';')
                    .first
                    .trim()
                    .toLowerCase() !=
                'application/json') {
          return false;
        }
        final body = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (body.length + chunk.length > 16384) return false;
          body.add(chunk);
        }
        final document = jsonDecode(utf8.decode(body.takeBytes()));
        return document is Map<String, dynamic> &&
            document.length == 2 &&
            document['protocolVersion'] is int &&
            document['protocolVersion'] == 1 &&
            document['uploadOperations'] is int &&
            document['uploadOperations'] == 1;
      })().timeout(const Duration(seconds: 5));
    } on Object {
      return false;
    } finally {
      client.close();
    }
  });

  Future<Set<int>> matchOriginalSizes(
    LokalRemoteCredentials credentials,
    List<int> sizes,
  ) async {
    final client = _originalClientFactory();
    if (_iosLibraryMutations) _libraryTransfers.cancelOnPause(client.close);
    try {
      final response = await client
          .post(
            credentials.origin.replace(path: '/api/remote/files/sizes'),
            headers: {
              ..._headers(credentials),
              'content-type': 'application/json',
            },
            body: jsonEncode({'sizes': sizes}),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw StateError(
          'Desktop file-size check failed. Reconnect and retry.',
        );
      }
      final values = (jsonDecode(response.body) as Map)['sizes'] as List;
      if (values.any((value) => value is! int || !sizes.contains(value))) {
        throw const FormatException('Invalid desktop size comparison.');
      }
      return values.cast<int>().toSet();
    } finally {
      client.close();
    }
  }

  Future<Map<int, String>> matchOriginalFingerprints(
    LokalRemoteCredentials credentials,
    List<Map<String, dynamic>> fingerprints,
  ) async {
    final client = _originalClientFactory();
    if (_iosLibraryMutations) _libraryTransfers.cancelOnPause(client.close);
    try {
      final response = await client
          .post(
            credentials.origin.replace(path: '/api/remote/files/match'),
            headers: {
              ..._headers(credentials),
              'content-type': 'application/json',
            },
            body: jsonEncode({'items': fingerprints}),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw StateError(
          'Could not compare desktop originals (HTTP ${response.statusCode}). Retry before copying.',
        );
      }
      final matches = (jsonDecode(response.body) as Map)['matches'] as List;
      final result = <int, String>{};
      for (final item in matches.cast<Map>()) {
        final index = item['index'];
        final id = item['trackId'];
        if (index is! int ||
            index < 0 ||
            index >= fingerprints.length ||
            id is! String ||
            id.isEmpty) {
          throw const FormatException('Invalid desktop file comparison.');
        }
        result[index] = id;
      }
      return result;
    } finally {
      client.close();
    }
  }

  Future<void> rememberDesktopOriginal(
    Song song,
    int serverId,
    String remoteId, {
    bool Function()? stillCurrent,
  }) => _trackLibraryTransfer(
    () => _rememberDesktopOriginal(
      song,
      serverId,
      remoteId,
      stillCurrent: stillCurrent,
    ),
  );

  Future<void> _rememberDesktopOriginal(
    Song song,
    int serverId,
    String remoteId, {
    bool Function()? stillCurrent,
  }) async {
    if (!Database.isInitialized) return;
    final id = int.tryParse(song.id);
    if (id == null) return;
    await Database.instance.writeTxn(() async {
      final row = await Database.songs.get(id);
      if (stillCurrent?.call() == false ||
          row == null ||
          !isDownloadedDesktopOriginal(row))
        return;
      row.remoteServerId = serverId;
      row.remoteId = remoteId;
      await Database.songs.put(row);
    });
  }

  /// HEAD runs the desktop's paired-original route but sends no audio bytes.
  Future<bool> hasOriginalFile(
    LokalRemoteCredentials credentials,
    String id,
  ) async {
    final client = _originalClientFactory();
    if (_iosLibraryMutations) _libraryTransfers.cancelOnPause(client.close);
    try {
      final response = await client
          .head(
            credentials.origin.replace(
              pathSegments: ['api', 'remote', 'files', id],
            ),
            headers: _headers(credentials),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return true;
      if (response.statusCode == 404) return false;
      throw StateError(
        'Could not verify the desktop original (HTTP ${response.statusCode}). Reconnect and retry.',
      );
    } finally {
      client.close();
    }
  }

  Future<List<Map<String, dynamic>>> readCatalogue(
    LokalRemoteCredentials credentials, {
    void Function(int)? onPage,
    Set<String>? trackIds,
  }) async {
    final tracks = <Map<String, dynamic>>[];
    final remaining = trackIds == null ? null : Set<String>.of(trackIds);
    var offset = 0;
    while (true) {
      final response = await http
          .get(
            credentials.origin.replace(
              path: '/api/remote/library/tracks',
              queryParameters: {'offset': '$offset', 'limit': '250'},
            ),
            headers: _headers(credentials),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw const HttpException('Desktop library is unavailable.');
      }
      final body = jsonDecode(response.body) as Map;
      final items = (body['items'] as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      if (remaining == null) {
        tracks.addAll(items);
      } else {
        for (final item in items) {
          final id = item['id']?.toString();
          if (id != null && remaining.remove(id)) tracks.add(item);
        }
        if (remaining.isEmpty) return tracks;
      }
      onPage?.call(tracks.length);
      if (body['hasMore'] != true) return tracks;
      if (items.isEmpty || offset >= 100000) {
        throw const FormatException(
          'Desktop library pagination did not advance.',
        );
      }
      offset += items.length;
    }
  }

  Future<void> copyOriginalToPhone(
    NetworkServerEntity server,
    Map<String, dynamic> track, {
    Song? existing,
  }) => _trackLibraryTransfer(
    () => _copyOriginalToPhone(server, track, existing: existing),
  );

  Future<void> _copyOriginalToPhone(
    NetworkServerEntity server,
    Map<String, dynamic> track, {
    Song? existing,
  }) async {
    final id = track['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const FormatException('Desktop song has no identifier.');
    }
    final credentials = await _credentials(server);
    final matching = await Database.songs
        .filter()
        .remoteServerIdEqualTo(server.id)
        .remoteIdEqualTo(id)
        .findAll();
    // A retry after a completed copy must not create another durable file.
    if (matching.any(isDownloadedDesktopOriginal)) return;
    await _musicStorage.requireFolder();
    final extension = track['fileType']?.toString().toLowerCase() ?? 'bin';
    if (!RegExp(r'^[a-z0-9]{1,8}$').hasMatch(extension)) {
      throw const FormatException('Invalid audio format.');
    }
    final directory = Directory(
      '${(await getTemporaryDirectory()).path}/desktop_transfers',
    );
    await directory.create(recursive: true);
    final file = File('${directory.path}/${linkUuid()}.$extension');
    final part = File('${file.path}.part');
    final client = GracefulHttpClient();
    if (_iosLibraryMutations) _libraryTransfers.cancelOnPause(client.close);
    try {
      final request =
          http.Request(
              'GET',
              credentials.origin.replace(
                pathSegments: ['api', 'remote', 'files', id],
              ),
            )
            ..headers.addAll(_headers(credentials))
            ..followRedirects = false;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw const HttpException('Desktop audio file is unavailable.');
      }
      var received = 0;
      final sink = part.openWrite();
      try {
        await for (final bytes in response.stream.timeout(
          const Duration(seconds: 30),
        )) {
          sink.add(bytes);
          received += bytes.length;
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received == 0 ||
          (response.contentLength != null &&
              received != response.contentLength)) {
        throw const HttpException('Desktop file transfer was incomplete.');
      }
      final expected = response.headers['x-content-sha256'];
      if (expected != null &&
          (await sha256.bind(part.openRead()).first).toString() !=
              expected.toLowerCase()) {
        throw const FormatException('Desktop file checksum did not match.');
      }
      final artwork = await AlbumArtService.instance.resolveArtworkPath(
        existingPath: 'lokal-cover://$id',
        audioSourcePath: 'lokal://${server.id}/$id',
      );
      await part.rename(file.path);
      var entity = existing == null
          ? null
          : await Database.songs.get(int.parse(existing.id));
      // The merge may already have created a streamable desktop row. Reuse
      // its local ID (and hence its likes/playlists/history) on original copy.
      // The preview's 'existing' can be null when the copy plan was refreshed.
      if (entity == null) {
        for (final candidate in matching) {
          if (isDownloadedDesktopOriginal(candidate)) {
            entity = candidate;
            break;
          }
        }
        entity ??= matching.isEmpty ? null : matching.first;
      }
      entity ??= SongEntity()..dateAdded = DateTime.now();
      entity.filePath = file.path;
      entity.title = track['title'] as String? ?? 'Unknown track';
      entity.artist = track['artist'] as String? ?? 'Unknown artist';
      entity.albumArtist =
          (track['album_artist'] ??
                  track['albumArtist'] ??
                  existing?.albumArtist)
              ?.toString();
      entity.album = track['album'] as String?;
      entity.durationMs = ((track['duration'] as num? ?? 0) * 1000).round();
      entity.fileType = extension;
      entity.sourceType = null;

      entity.remoteId = id;
      entity.remoteServerId = server.id;
      // A temporary offline/HTTP failure must not erase a previously
      // downloaded album cover. The old marker can still be resolved later.
      entity.albumArtPath = artwork ?? entity.albumArtPath;
      entity.sampleRate =
          (track['sample_rate'] as num?)?.toInt() ?? entity.sampleRate;
      entity.bitDepth =
          (track['bit_depth'] as num?)?.toInt() ?? entity.bitDepth;
      entity.bitrate = (track['bitrate'] as num?)?.toInt() ?? entity.bitrate;
      entity.genre = _genre(track) ?? entity.genre;
      await LocalMetadataRepair.probe(entity, persist: false);
      final saved = entity;
      await _musicStorage.saveEntity(
        saved,
        persist: (row) async {
          await _putLibrarySong(row);
        },
      );
      await _copyTrackClip(credentials, server.id, id, client);
      await syncCopiedLyrics(server, copies: [saved]);
    } finally {
      client.close();
      if (await part.exists()) await part.delete();
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> _copyTrackClip(
    LokalRemoteCredentials credentials,
    int serverId,
    String trackId,
    http.Client client, {
    bool Function()? stillCurrent,
  }) async {
    final uri = credentials.origin.replace(
      pathSegments: ['api', 'remote', 'files', trackId, 'clip'],
    );
    final response = await client
        .get(uri, headers: _headers(credentials))
        .timeout(const Duration(seconds: 15));
    // Earlier desktop releases do not have the sidecar endpoint.
    if (response.statusCode == 404 || stillCurrent?.call() == false) return;
    if (response.statusCode != 200) {
      throw const HttpException('Could not read the desktop video clip.');
    }
    final data =
        (jsonDecode(response.body) as Map<String, dynamic>)['clip']
            as Map<String, dynamic>?;
    final extension = data?['extension'];
    if (extension == null) {
      await CopiedTrackClip.save(serverId, trackId, data);
      return;
    }
    final version = data?['version'];
    if (extension is! String ||
        !CopiedTrackClip.validExtension(extension) ||
        version is! String) {
      throw const FormatException('Invalid copied video format.');
    }
    final directory = await CopiedTrackClip.directory();
    await directory.create(recursive: true);
    final name = '${linkUuid()}.$extension';
    final part = File(p.join(directory.path, '$name.part'));
    final file = File(p.join(directory.path, name));
    var committed = false;
    try {
      final request =
          http.Request(
              'GET',
              uri.replace(queryParameters: {'media': '1', 'version': version}),
            )
            ..headers.addAll(_headers(credentials))
            ..followRedirects = false;
      final media = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      if (media.statusCode != 200) {
        throw const HttpException('The desktop video file is unavailable.');
      }
      var received = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk in media.stream.timeout(
          const Duration(seconds: 30),
        )) {
          if (stillCurrent?.call() == false) return;
          sink.add(chunk);
          received += chunk.length;
        }
      } finally {
        await sink.close();
      }
      if (received == 0 ||
          (media.contentLength != null && received != media.contentLength)) {
        throw const HttpException('Desktop video transfer was incomplete.');
      }
      if (stillCurrent?.call() == false) return;
      await part.rename(file.path);
      if (stillCurrent?.call() == false) return;
      await CopiedTrackClip.save(serverId, trackId, {...data!, 'file': name});
      committed = true;
    } finally {
      if (await part.exists()) await part.delete();
      if (!committed && await file.exists()) await file.delete();
    }
  }

  Future<void> completeNativeCopySidecars(
    NetworkServerEntity server,
    SongEntity song, {
    required bool Function() stillCurrent,
  }) => _trackLibraryTransfer(() async {
    if (!stillCurrent() ||
        song.remoteId == null ||
        song.remoteServerId != server.id)
      return;
    // Resolve through the existing desktop artwork path. Passing the remote
    // source keeps its cache writes from asynchronously changing a local row.
    try {
      final source =
          'lokal://${server.id}/${Uri.encodeComponent(song.remoteId!)}';
      final artwork = await AlbumArtService.instance.resolveArtworkPath(
        existingPath: song.albumArtPath,
        audioSourcePath: source,
      );
      if (artwork != null && stillCurrent()) {
        await Database.instance.writeTxn(() async {
          if (!stillCurrent()) return;
          final current = await Database.songs.get(song.id);
          if (current == null ||
              current.filePath != song.filePath ||
              current.remoteId != song.remoteId ||
              current.remoteServerId != server.id ||
              current.albumArtPath != song.albumArtPath) {
            return;
          }
          current.albumArtPath = artwork;
          await Database.songs.put(current);
        });
      }
    } catch (_) {
      /* Optional artwork cannot invalidate committed audio. */
    }
    if (stillCurrent()) {
      final client = GracefulHttpClient();
      _libraryTransfers.cancelOnPause(client.close);
      try {
        await _copyTrackClip(
          await _credentials(server),
          server.id,
          song.remoteId!,
          client,
          stillCurrent: stillCurrent,
        );
      } finally {
        client.close();
      }
    }
    if (stillCurrent())
      await syncCopiedLyrics(
        server,
        copies: [song],
        stillCurrent: stillCurrent,
      );
  });
  // Coalesce concurrent requests for the same desktop song. A reconnect
  // waits for an in-flight request rather than silently skipping its retry.
  final Map<String, Future<bool>> _lyricsRequests = {};

  Future<bool> syncPlayingDesktopLyrics(Song song) async {
    if (song.sourceType != 'lokal' ||
        song.remoteServerId == null ||
        song.remoteId == null)
      return false;
    final key = '${song.remoteServerId}:${song.remoteId}';
    final pending = _lyricsRequests[key];
    if (pending != null) return pending;

    final operation = _fetchPlayingDesktopLyrics(song);
    _lyricsRequests[key] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_lyricsRequests[key], operation))
        _lyricsRequests.remove(key);
    }
  }

  Future<bool> _fetchPlayingDesktopLyrics(Song song) async {
    try {
      final server = await Database.networkServers.get(song.remoteServerId!);
      final id = int.tryParse(song.id);
      if (server == null || id == null) return false;
      final row = await Database.songs.get(id);
      if (row?.remoteId != song.remoteId ||
          row?.remoteServerId != song.remoteServerId)
        return false;
      await syncCopiedLyrics(server, copies: [row!], throwOnFailure: true);
      return true;
    } catch (_) {
      // An offline desktop must not interrupt playback; caller may retry.
      return false;
    }
  }

  Future<void> syncCopiedLyrics(
    NetworkServerEntity server, {
    List<SongEntity>? copies,
    bool Function()? stillCurrent,
    void Function(int, int)? onProgress,
    bool throwOnFailure = false,
  }) async {
    final client = GracefulHttpClient();
    if (_iosLibraryMutations) _libraryTransfers.cancelOnPause(client.close);
    try {
      final rows =
          copies ??
          await Database.songs
              .filter()
              .remoteServerIdEqualTo(server.id)
              .sourceTypeIsNull()
              .findAll();
      final credentials = await _credentials(server);
      for (var offset = 0; offset < rows.length; offset += 50) {
        if (stillCurrent?.call() == false) return;
        final page = rows
            .skip(offset)
            .take(50)
            .where((row) => row.remoteId != null)
            .toList();
        if (page.isEmpty) continue;
        final response = await client
            .post(
              credentials.origin.replace(path: '/api/remote/library/lyrics'),
              headers: {
                ..._headers(credentials),
                'content-type': 'application/json',
              },
              body: jsonEncode({
                'ids': page.map((row) => row.remoteId!).toList(),
              }),
            )
            .timeout(const Duration(seconds: 15));
        if (stillCurrent?.call() == false) return;
        if (response.statusCode != 200 ||
            response.bodyBytes.length > 4 * 1024 * 1024) {
          if (throwOnFailure)
            throw StateError(
              'Desktop lyrics request failed with HTTP ${response.statusCode}.',
            );
          return;
        }
        final body = jsonDecode(response.body);
        if (body['items'] is! List) {
          if (throwOnFailure)
            throw const FormatException('Invalid lyrics response.');
          return;
        }
        for (final item in (body['items'] as List).whereType<Map>()) {
          if (item['lyrics'] is! Map) continue;
          for (final row in page.where(
            (row) => row.remoteId == item['id']?.toString(),
          )) {
            await LyricsService.storeDesktopLyrics(
              SongRepository().songFromEntity(row),
              Map<String, dynamic>.from(item['lyrics'] as Map),
            );
          }
        }
        onProgress?.call((offset + 50).clamp(0, rows.length), rows.length);
      }
    } catch (_) {
      if (throwOnFailure) rethrow;
      /* Lyrics are optional; an older/offline PC must not fail file copy. */
    } finally {
      client.close();
    }
  }

  @override
  String get protocol => 'lokal';
  @override
  String get coverScheme => 'lokal-cover://';
  Future<LokalRemoteCredentials> _credentials(
    NetworkServerEntity server,
  ) async {
    final value = await SecureLokalRemoteCredentialsStore().read();
    if (value == null ||
        '${value.desktopId}:${value.desktopUserId ?? 'guest'}' !=
            server.username ||
        value.origin.toString() != server.baseUrl) {
      throw StateError('Reconnect to this Lokal desktop to stream its songs.');
    }
    return value;
  }

  String? _genre(Map<String, dynamic> track) => desktopLinkGenres(track);

  Map<String, String> _headers(LokalRemoteCredentials credentials) => {
    'x-remote-token': credentials.remoteToken,
    if (credentials.apiKey.isNotEmpty) 'x-api-key': credentials.apiKey,
  };
  @override
  Future<String?> resolveToken(
    NetworkServerEntity server,
    String password,
  ) async => null;
  @override
  Future<bool> ping(NetworkServerEntity server) async {
    try {
      final credentials = await _credentials(server);
      final response = await http
          .get(
            credentials.origin.replace(path: '/api/remote/state'),
            headers: _headers(credentials),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } on Object {
      return false;
    }
  }

  @override
  Future<List<int>> getCoverArt(
    NetworkServerEntity server,
    String marker,
  ) async {
    final credentials = await _credentials(server);
    final client = GracefulHttpClient();
    if (_iosLibraryMutations) _libraryTransfers.cancelOnPause(client.close);
    try {
      final request =
          http.Request(
              'GET',
              credentials.origin.replace(
                pathSegments: ['api', 'artwork', marker],
                queryParameters: {'full': '1'},
              ),
            )
            ..headers.addAll(_headers(credentials))
            ..followRedirects = false;
      var response = await client
          .send(request)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 301 ||
          response.statusCode == 302 ||
          response.statusCode == 307 ||
          response.statusCode == 308) {
        final target = Uri.tryParse(response.headers['location'] ?? '');
        await response.stream.drain<void>();
        if (target == null ||
            target.scheme != 'https' ||
            target.host.isEmpty ||
            target.userInfo.isNotEmpty) {
          throw const HttpException('Desktop artwork redirect is invalid.');
        }
        // Desktop credentials must never accompany an external image request.
        response = await client
            .send(http.Request('GET', target))
            .timeout(const Duration(seconds: 10));
      }
      if (response.statusCode != 200) {
        throw const HttpException('Desktop artwork is unavailable.');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 10),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 10 * 1024 * 1024) {
          throw const FormatException('Desktop artwork is too large.');
        }
      }
      return bytes;
    } finally {
      client.close();
    }
  }

  @override
  Future<({String url, Map<String, String> headers})?> streamDescriptor(
    NetworkServerEntity server,
    String remoteId, {
    String? extension,
  }) async {
    final cached = await _cache.getPath(server.id, remoteId);
    if (cached != null) return null; // ensureLocal returns the offline copy.
    final credentials = await _credentials(server);
    return (
      url: credentials.origin
          .replace(pathSegments: ['api', 'stream', remoteId])
          .toString(),
      headers: _headers(credentials),
    );
  }

  @override
  Future<String> stream(
    NetworkServerEntity server,
    String remoteId, {
    String? extension,
    void Function(double)? onProgress,
  }) async {
    final cached = await _cache.getPath(server.id, remoteId);
    if (cached != null) return cached;
    final key = '${server.id}:$remoteId';
    return _downloads.putIfAbsent(
      key,
      () => _download(
        server,
        remoteId,
        extension,
        onProgress,
      ).whenComplete(() => _downloads.remove(key)),
    );
  }

  Future<String> _download(
    NetworkServerEntity server,
    String remoteId,
    String? extension,
    void Function(double)? onProgress,
  ) async {
    final credentials = await _credentials(server),
        client = GracefulHttpClient();
    final ext = RegExp(r'^[a-zA-Z0-9]{1,8}$').hasMatch(extension ?? '')
        ? extension
        : 'bin';
    final path = await _cache.pathFor(server.id, remoteId, extension: ext),
        part = File('$path.part');
    try {
      final request = http.Request(
        'GET',
        credentials.origin.replace(pathSegments: ['api', 'stream', remoteId]),
      )..headers.addAll(_headers(credentials));
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw HttpException('Desktop returned HTTP ${response.statusCode}.');
      }
      final output = part.openWrite();
      var received = 0;
      try {
        await for (final bytes in response.stream.timeout(
          const Duration(seconds: 30),
        )) {
          received += bytes.length;
          output.add(bytes);
          if (response.contentLength != null && response.contentLength! > 0) {
            onProgress?.call((received / response.contentLength!).clamp(0, 1));
          }
        }
        await output.flush();
      } finally {
        await output.close();
      }
      if (response.contentLength != null &&
          received != response.contentLength) {
        throw const HttpException(
          'Desktop stream ended before the file was complete.',
        );
      }
      await part.rename(path);
      await _cache.commitDownload(path);
      onProgress?.call(1);
      return path;
    } finally {
      client.close();
      if (await part.exists()) await part.delete();
    }
  }

  Future<NetworkServerEntity> ensureServer(
    LokalRemoteCredentials credentials, {
    String name = 'Lokal desktop',
  }) async {
    if (credentials.desktopId == null) {
      throw StateError('Pair this desktop first.');
    }
    var server = await Database.networkServers
        .filter()
        .protocolEqualTo('lokal')
        .usernameEqualTo(
          '${credentials.desktopId}:${credentials.desktopUserId ?? 'guest'}',
        )
        .findFirst();
    // Polling a journal must not write the server row or wake library watchers
    // when the connection credentials have not changed.
    final username =
        '${credentials.desktopId}:${credentials.desktopUserId ?? 'guest'}';
    if (server != null &&
        server.baseUrl == credentials.origin.toString() &&
        server.username == username &&
        server.token == null) {
      return server;
    }
    server ??= NetworkServerEntity()
      ..protocol = 'lokal'
      ..label = name;
    server.baseUrl = credentials.origin.toString();
    server.username =
        '${credentials.desktopId}:${credentials.desktopUserId ?? 'guest'}';
    server.token = null;
    await Database.instance.writeTxn(
      () => Database.networkServers.put(server!),
    );
    return server;
  }

  Future<Song> importTrack(
    NetworkServerEntity server,
    Map<String, dynamic> track, {
    List<Song>? matchCandidates,
  }) => _trackLibraryTransfer(
    () => _importTrack(server, track, matchCandidates: matchCandidates),
  );

  Future<Song> _importTrack(
    NetworkServerEntity server,
    Map<String, dynamic> track, {
    List<Song>? matchCandidates,
  }) async {
    final remoteId = track['id']?.toString();
    if (remoteId == null || remoteId.isEmpty) {
      throw const FormatException('Desktop song is missing its identifier.');
    }
    // A copied original keeps its desktop ID when its filename/tags change.
    // Resolve that identity before the fuzzy catalogue matcher.
    var entity = await Database.songs
        .filter()
        .remoteServerIdEqualTo(server.id)
        .remoteIdEqualTo(remoteId)
        .findFirst();
    if (entity != null && isDownloadedDesktopOriginal(entity)) {
      final genre = _genre(track);
      if (isUnclassifiedLinkGenre(entity.genre) && genre?.isNotEmpty == true) {
        entity.genre = genre;
        final localRow = entity;
        await _putLibrarySong(localRow);
      }
      return SongRepository().songFromEntity(entity);
    }
    final journal = LinkJournal.instance;
    final key =
        track['track_key'] ??
        '${track['artist']?.toString().trim().toLowerCase()}|${track['title']?.toString().trim().toLowerCase()}|${(track['duration'] as num? ?? 0).round()}';
    // Existing remote IDs can be updated directly. Avoid reading and
    // re-matching the entire phone library for every desktop track.
    final local = entity == null
        ? await journal.match({
            ...track,
            'track_key': key,
          }, candidates: matchCandidates)
        : null;
    if (local != null && local.sourceType != 'lokal') {
      final row = await Database.songs.get(int.parse(local.id));
      final genre = _genre(track);
      if (row != null &&
          isUnclassifiedLinkGenre(row.genre) &&
          genre?.isNotEmpty == true) {
        row.genre = genre;
        await _putLibrarySong(row);
        return SongRepository().songFromEntity(row);
      }
      return local;
    }
    entity ??= SongEntity()
      ..filePath = 'lokal://${server.id}/$remoteId'
      ..dateAdded = DateTime.now();
    entity.title = track['title']?.toString() ?? 'Unknown track';
    entity.artist = track['artist']?.toString() ?? 'Unknown artist';
    entity.albumArtist = (track['album_artist'] ?? track['albumArtist'])
        ?.toString();
    entity.album = track['album']?.toString();
    entity.genre = _genre(track) ?? entity.genre;
    entity.durationMs = ((track['duration'] as num? ?? 0) * 1000).round();
    entity.fileType = track['fileType']?.toString() ?? entity.fileType ?? 'bin';
    int? number(String camel, String snake) =>
        (track[camel] as num? ?? track[snake] as num?)?.toInt();
    entity.sampleRate =
        number('sampleRate', 'sample_rate') ?? entity.sampleRate;
    entity.bitDepth = number('bitDepth', 'bit_depth') ?? entity.bitDepth;
    entity.bitrate = (track['bitrate'] as num?)?.toInt() ?? entity.bitrate;
    entity.filePath = 'lokal://${server.id}/$remoteId';
    entity.sourceType = 'lokal';
    entity.remoteId = remoteId;
    entity.remoteServerId = server.id;
    entity.metadataComplete = true;
    // A desktop row can have embedded art even before its thumbnail is indexed.
    // Always retain a resolvable marker; artwork failure must not erase it.
    entity.albumArtPath ??= 'lokal-cover://$remoteId';
    final saved = entity;
    await _putLibrarySong(saved);
    return SongRepository().songFromEntity(saved);
  }

  Future<void> uploadToDesktop(Song song, LokalRemoteCredentials credentials) =>
      _trackLibraryTransfer(() => _uploadToDesktop(song, credentials));

  Future<void> _uploadToDesktop(
    Song song,
    LokalRemoteCredentials credentials,
  ) async {
    if (song.filePath == null || song.isNetworkSource) {
      throw StateError('This song has no local audio file to send.');
    }
    const formats = {
      'flac',
      'mp3',
      'm4a',
      'aac',
      'ogg',
      'opus',
      'wav',
      'aiff',
      'aif',
      'alac',
      'ape',
      'wv',
      'dsf',
      'dff',
      'webm',
    };
    String normalize(String value) {
      final raw = value.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), '');
      return const {
            'mpeg': 'mp3',
            'mp4': 'm4a',
            'wave': 'wav',
            'wavpack': 'wv',
            'wv-dsd': 'wv',
          }[raw] ??
          raw;
    }

    var path = song.filePath!;
    if (path.startsWith('file://')) path = Uri.parse(path).toFilePath();
    // Preserve the real library filename before staging a scoped-storage URI.
    // Staging paths use temporary UUIDs and must never become desktop names.
    final originalFilename = path.startsWith('content://')
        ? null
        : p.basename(path);
    final pathExtension = normalize(
      Uri.tryParse(path)?.path.split('.').last ?? '',
    );
    final extension = formats.contains(pathExtension)
        ? pathExtension
        : normalize(song.fileType);
    if (!formats.contains(extension)) {
      throw StateError('This audio format cannot be sent to the desktop.');
    }
    var temporary = false;
    Future<String> stage(String uri) async {
      try {
        final staged = await const MethodChannel('lokal/desktop_link')
            .invokeMethod<String>('stageAudio', {
              'uri': uri,
              'extension': extension,
            });
        if (staged == null || staged.isEmpty) {
          throw StateError('The audio document could not be read.');
        }
        temporary = true;
        return staged;
      } on PlatformException {
        throw StateError(
          'Android denied access to this audio file. Re-select its music folder and retry.',
        );
      }
    }

    if (path.startsWith('content://')) {
      path = await stage(path);
    } else {
      // MediaStore may permit URI reads even when scoped storage denies a
      // direct filesystem path. Use the grant already saved by the scanner.
      try {
        final handle = await File(path).open();
        await handle.close();
      } on FileSystemException {
        final id = int.tryParse(song.id);
        final row = id == null || !Database.isInitialized
            ? null
            : await Database.songs.get(id);
        final uri = row?.mediaStoreUri;
        if (uri == null || !uri.startsWith('content://')) {
          throw StateError('This song is not stored as a readable local file.');
        }
        path = await stage(uri);
      }
    }
    final file = File(path);
    try {
      if (!await file.exists()) {
        throw StateError('This song is not stored as a readable local file.');
      }
      final digest = await sha256.bind(file.openRead()).first;
      final request = http.StreamedRequest(
        'POST',
        credentials.origin.replace(path: '/api/remote/files'),
      );
      request.headers.addAll({
        ..._headers(credentials),
        'content-type': 'application/octet-stream',
        'x-link-metadata': base64Url.encode(
          utf8.encode(
            jsonEncode({
              'title': song.title,
              'artist': song.artist,
              'album': song.album,
              'extension': extension,
              'originalFilename': ?originalFilename,
              'sha256': digest.toString(),
            }),
          ),
        ),
      });
      request.contentLength = await file.length();
      if (request.contentLength == 0) {
        throw StateError(
          'This audio file is empty. Re-select its music folder and retry.',
        );
      }
      final client = _uploadClientFactory();
      if (_iosLibraryMutations) _libraryTransfers.cancelOnPause(client.close);
      try {
        // Bound the upload itself as well as the response: a desktop refusal
        // must not leave the streamed request waiting indefinitely for a sink.
        await (() async {
          final results = await Future.wait<http.StreamedResponse?>([
            client.send(request),
            (() async {
              await request.sink.addStream(file.openRead());
              await request.sink.close();
              return null;
            })(),
          ], eagerError: true);
          final response = results.first!;
          final bytes = <int>[];
          await for (final chunk in response.stream) {
            bytes.addAll(chunk);
            if (bytes.length > 64 * 1024) {
              throw StateError(
                'The desktop returned an invalid upload response.',
              );
            }
          }
          Map? body;
          try {
            body = jsonDecode(utf8.decode(bytes)) as Map;
          } on Object {
            /* Handle by status below. */
          }
          if (response.statusCode == 401 || response.statusCode == 403) {
            throw StateError(
              'The desktop rejected this pairing. Reconnect and retry.',
            );
          }
          if (response.statusCode == 413) {
            throw StateError('The file exceeds the desktop upload size limit.');
          }
          if (response.statusCode != 200 ||
              body?['ok'] != true ||
              body?['trackId'] is! String) {
            final unsupported =
                body?['error']?.toString().toLowerCase().contains(
                  'unsupported audio format',
                ) ==
                true;
            final rawReason = body?['error'];
            final reason = rawReason is String
                ? rawReason.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim()
                : '';
            final detail = reason.isEmpty
                ? ''
                : ' ${reason.length > 300 ? reason.substring(0, 300) : reason}';
            throw StateError(
              unsupported
                  ? 'Update Lokal desktop to accept this audio format ($extension).'
                  : 'The desktop could not save this file (HTTP ${response.statusCode}).$detail',
            );
          }
          if (Database.isInitialized) {
            final server = await ensureServer(credentials);
            await rememberDesktopOriginal(
              song,
              server.id,
              body!['trackId'] as String,
            );
          }
          // Do not lose a separate album cover (cover.jpg/folder.png) when
          // the phone's audio container has no embedded picture.
          await _uploadCopiedArtwork(
            song,
            credentials,
            body!['trackId'] as String,
          );
        })().timeout(
          const Duration(minutes: 3),
          onTimeout: () {
            client.close();
            throw StateError(
              'Sending the file timed out. Reconnect and retry.',
            );
          },
        );
      } finally {
        client.close();
      }
    } finally {
      if (temporary && await file.exists()) await file.delete();
    }
  }

  Future<void> downloadToPhone(Song song) async {
    final server = await Database.networkServers.get(song.remoteServerId!);
    if (server == null) throw StateError('Reconnect to this desktop first.');
    await copyOriginalToPhone(server, {
      'id': song.remoteId,
      'title': song.title,
      'artist': song.artist,
      'album': song.album,
      'duration': song.duration.inMilliseconds / 1000,
      'fileType': song.fileType,
      'sample_rate': song.sampleRate,
      'bit_depth': song.bitDepth,
      'genre': song.genre,
    }, existing: song);
  }

  Future<bool> isPrivateDesktopCopy(Song song) async {
    final path = song.filePath;
    if (path == null ||
        !path.contains('/desktop_music/') ||
        Uri.tryParse(path)?.hasScheme == true) {
      return false;
    }
    final root = await (_legacyDirectory ??= getApplicationDocumentsDirectory()
        .then((directory) => p.join(directory.path, 'desktop_music')));
    return p.isWithin(root, path);
  }

  /// Recover existing app-private copies locally: no network download and the
  /// database ID stays stable so playlists, favorites and listening history do.
  Future<void> recoverPrivateCopy(Song song) =>
      _trackLibraryTransfer(() => _recoverPrivateCopy(song));

  Future<void> _recoverPrivateCopy(Song song) async {
    if (!await isPrivateDesktopCopy(song)) return;
    final entity = await Database.songs.get(int.parse(song.id));
    if (entity == null) {
      throw StateError('The library song is no longer available.');
    }
    await _musicStorage.saveEntity(
      entity,
      persist: (row) async {
        await _putLibrarySong(row);
      },
    );
  }

  /// Repair genres missed by the one-time catalogue import or journal replay.
  /// Sync Now reads desktop's current tags using the existing authenticated
  /// catalogue API; no audio files are downloaded or rewritten. Only missing
  /// or placeholder phone genres are filled, preserving real local edits.
  Future<int> reconcileMissingGenres(
    NetworkServerEntity server, {
    bool Function()? stillCurrent,
  }) async {
    final database = Database.instance;
    void checkCurrent() {
      if (!Database.isInitialized ||
          !identical(Database.instance, database) ||
          !(stillCurrent?.call() ?? true)) {
        throw StateError('Desktop genre sync was retired.');
      }
    }

    checkCurrent();
    final credentials = await _credentials(server);
    checkCurrent();
    final rows = await database.songEntitys.where().findAll();
    checkCurrent();
    final matcher = DesktopGenreMatcher([
      for (final row in rows)
        DesktopGenreIdentity(
          id: row.id,
          title: row.title,
          artist: row.artist,
          album: row.album,
          durationMs: row.durationMs ?? 0,
          remoteServerId: row.remoteServerId,
          remoteId: row.remoteId,
          isLocalFile:
              row.sourceType == null &&
              !row.filePath.startsWith('ghost://') &&
              !row.filePath.startsWith('lokal://'),
        ),
    ]);
    final existing = {for (final row in rows) row.id: row};
    final changes = <int, String>{};
    var offset = 0;
    // Desktop caps this endpoint at 50 records/page, regardless of requested
    // limit. Progress by the actual number received, never by the hint.
    while (true) {
      checkCurrent();
      final response = await http
          .get(
            credentials.origin.replace(
              path: '/api/remote/library/tracks',
              queryParameters: {'offset': '$offset', 'limit': '50'},
            ),
            headers: _headers(credentials),
          )
          .timeout(const Duration(seconds: 10));
      checkCurrent();
      if (response.statusCode != 200) {
        throw const HttpException('Desktop genres are unavailable.');
      }
      final body = jsonDecode(response.body) as Map;
      final items = body['items'] as List;
      for (final raw in items) {
        final track = Map<String, dynamic>.from(raw as Map);
        final genre = desktopLinkGenres(track);
        if (genre == null) continue;
        for (final id in matcher.matchingIds(server.id, track)) {
          final local = existing[id];
          if (local != null && isUnclassifiedLinkGenre(local.genre)) {
            changes[id] = genre;
          }
        }
      }
      offset += items.length;
      if (body['hasMore'] != true || items.isEmpty) break;
    }
    if (changes.isEmpty) return 0;
    final currentCredentials = await _credentials(server);
    checkCurrent();
    if (currentCredentials.origin != credentials.origin ||
        currentCredentials.desktopId != credentials.desktopId ||
        currentCredentials.desktopUserId != credentials.desktopUserId ||
        currentCredentials.pairingID != credentials.pairingID ||
        currentCredentials.remoteToken != credentials.remoteToken ||
        currentCredentials.apiKey != credentials.apiKey) {
      throw StateError('Desktop genre sync was retired.');
    }
    var updated = 0;
    // Re-read under the write transaction: user edits or scanning may have
    // filled a genre while the paginated desktop snapshot was being fetched.
    await database.writeTxn(() async {
      checkCurrent();
      final currentServer = await database.networkServerEntitys.get(server.id);
      if (currentServer == null ||
          currentServer.protocol != server.protocol ||
          currentServer.baseUrl != server.baseUrl ||
          currentServer.username != server.username) {
        throw StateError('Desktop genre sync was retired.');
      }
      for (final update in changes.entries) {
        final row = await database.songEntitys.get(update.key);
        if (row == null || !isUnclassifiedLinkGenre(row.genre)) continue;
        // A numeric ID alone is insufficient after a clear, rescan or rebind
        // during the network snapshot. Retry changed recordings next Sync Now.
        final original = existing[update.key]!;
        if (row.filePath != original.filePath ||
            row.sourceType != original.sourceType ||
            row.remoteServerId != original.remoteServerId ||
            row.remoteId != original.remoteId ||
            row.title != original.title ||
            row.artist != original.artist ||
            row.album != original.album ||
            row.durationMs != original.durationMs ||
            row.dateAdded != original.dateAdded) {
          continue;
        }
        row.genre = update.value;
        await database.songEntitys.put(row);
        updated++;
      }
      checkCurrent();
    });
    return updated;
  }

  @override
  Stream<ScanProgress> syncLibrary(NetworkServerEntity server) =>
      _iosLibraryMutations
      ? IosLibraryScanEpoch.bind(() => _syncLibrary(server))
      : _syncLibrary(server);

  Stream<ScanProgress> _syncLibrary(NetworkServerEntity server) async* {
    final credentials = await _credentials(server);
    var offset = 0, imported = 0, total = 0;
    final owned = <String>{};
    // One snapshot of matching candidates per manual sync, not one expensive
    // full-library read per newly imported desktop track.
    final matchCandidates = await SongRepository().getAllSongs();
    do {
      final response = await http
          .get(
            credentials.origin.replace(
              path: '/api/remote/library/tracks',
              queryParameters: {'offset': '$offset', 'limit': '500'},
            ),
            headers: _headers(credentials),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw const HttpException('Desktop library is unavailable.');
      }
      final body = jsonDecode(response.body) as Map,
          items = body['items'] as List;
      total = (body['total'] as num? ?? 0).toInt();
      for (final raw in items) {
        if (_iosLibraryMutations) IosLibraryScanEpoch.requireCurrent();
        final track = Map<String, dynamic>.from(raw as Map);
        owned.add(track['id'].toString());
        await importTrack(server, track, matchCandidates: matchCandidates);
        imported++;
      }
      offset += items.length;
      yield ScanProgress(
        songsFound: imported,
        totalFiles: total,
        filesProcessed: imported,
        isComplete: body['hasMore'] != true,
      );
      if (body['hasMore'] != true || items.isEmpty) break;
    } while (offset < total);
    // Archive history-only/removed placeholders, never local downloaded files.
    final remoteRows = await Database.songs
        .filter()
        .remoteServerIdEqualTo(server.id)
        .sourceTypeEqualTo('lokal')
        .findAll();
    await Database.instance.writeTxn(() async {
      if (_iosLibraryMutations) IosLibraryScanEpoch.requireCurrent();
      for (final row in remoteRows) {
        if (!owned.contains(row.remoteId)) {
          row.filePath = 'ghost://desktop/${server.id}/${row.remoteId}';
          await Database.songs.put(row);
        }
      }
    });
    server.lastSyncedAt = DateTime.now();
    await Database.instance.writeTxn(() => Database.networkServers.put(server));
  }
}
