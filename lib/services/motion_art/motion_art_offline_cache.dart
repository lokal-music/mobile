import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flick/core/utils/dev_log.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'animated_artwork_service.dart';
import 'local_motion_hls_server.dart';

/// Persistent, completed video clips (not merely cached motion-art URLs).
///
/// Downloads happen after network playback starts, never on the critical path
/// to the first frame. Files live in application support rather than the OS's
/// evictable temporary cache. HLS playlists and their segments are committed
/// together; interrupted downloads can never masquerade as offline clips.
class MotionArtOfflineCache {
  MotionArtOfflineCache._({http.Client? client, Directory? directory})
      : _client = client ?? http.Client(),
        _directoryOverride = directory;

  static final instance = MotionArtOfflineCache._();

  @visibleForTesting
  static MotionArtOfflineCache create({
    http.Client? client,
    Directory? directory,
  }) => MotionArtOfflineCache._(client: client, directory: directory);

  static const int maxClipBytes = 35 * 1024 * 1024;
  static const int maxCacheBytes = 250 * 1024 * 1024;
  static const Duration _timeout = Duration(seconds: 20);

  final http.Client _client;
  final Directory? _directoryOverride;
  final Map<String, Future<File?>> _downloads = {};
  final Map<String, int> _inUse = {};

  static String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static bool _secureUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  Future<Directory> _root() async {
    final base = _directoryOverride ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/motion_art_offline');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _lookupFile(String key) async =>
      File('${(await _root()).path}/lookup-${_hash(key)}.json');

  Future<Directory> _clipDir(String url) async =>
      Directory('${(await _root()).path}/clip-${_hash(url)}');

  /// Only return a saved lookup if at least one of its videos is fully cached.
  /// This lets offline playback bypass provider search after an app restart.
  Future<AnimatedArtwork?> find(String key) async {
    try {
      final file = await _lookupFile(key);
      if (!await file.exists()) return null;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic> ||
          data['artwork'] is! Map<String, dynamic>) {
        return null;
      }
      final artwork = AnimatedArtwork.fromJson(
        data['artwork'] as Map<String, dynamic>,
      );
      final urls = {
        if (artwork.playbackUrl != null) artwork.playbackUrl!,
        if (artwork.verticalPlaybackUrl != null) artwork.verticalPlaybackUrl!,
      };
      for (final url in urls) {
        if (await localFile(url) != null) return artwork;
      }
    } catch (error) {
      devLog('[MotionArt] offline lookup ignored: $error');
    }
    return null;
  }

  /// Prefer an already downloaded video (including a square fallback when a
  /// portrait variant was never cached). Otherwise preserve online quality.
  Future<({String url, String? cachedSource})?> playable(
    AnimatedArtwork artwork, {
    required bool preferVertical,
  }) async {
    final preferred = preferVertical
        ? artwork.verticalPlaybackUrl
        : artwork.playbackUrl;
    final alternate = preferVertical
        ? artwork.playbackUrl
        : artwork.verticalPlaybackUrl;
    for (final source in {if (preferred != null) preferred, if (alternate != null) alternate}) {
      final file = await localFile(source);
      if (file != null) {
        try {
          // AVPlayer needs an HTTP HLS source even when every segment is on
          // disk. The loopback-only server serves these files without data.
          final url = file.path.endsWith('.m3u8')
              ? (await LocalMotionHlsServer.serve(file)).toString()
              : file.uri.toString();
          return (url: url, cachedSource: source);
        } catch (error) {
          devLog('[MotionArt] local HLS playback unavailable: $error');
        }
      }
    }
    if (preferred == null) return null;
    return (url: preferred, cachedSource: null);
  }

  /// Check the completed marker, not just a playlist or partial segment.
  Future<File?> localFile(String source) async {
    if (!_secureUrl(source)) return null;
    try {
      final dir = await _clipDir(source);
      final marker = File('${dir.path}/complete.json');
      if (!await marker.exists()) return null;
      final decoded = jsonDecode(await marker.readAsString());
      if (decoded is! Map || decoded['url'] != source) return null;
      final name = decoded['entry'];
      if (name != 'clip.mp4' &&
          name != 'clip.webm' &&
          name != 'clip.mov' &&
          name != 'playlist.m3u8') return null;
      final file = File('${dir.path}/$name');
      if (!await file.exists() || await file.length() == 0) return null;
      if (name == 'playlist.m3u8' && !await _hasCompleteHlsAssets(file)) {
        return null;
      }
      await file.setLastModified(DateTime.now());
      return file;
    } catch (_) {
      return null;
    }
  }

  /// HLS requires every local media segment and initialization map.
  /// Reject incomplete caches before a native decoder opens them offline.
  Future<bool> _hasCompleteHlsAssets(File playlist) async {
    final body = await playlist.readAsString();
    if (!body.contains('#EXT-X-ENDLIST')) return false;
    final names = <String>{};
    for (final raw in body.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.startsWith('#EXT-X-MAP:')) {
        final match = RegExp(r'URI="([^"]+)"').firstMatch(line);
        if (match == null) return false;
        names.add(match[1]!);
      } else if (line.isNotEmpty && !line.startsWith('#')) {
        names.add(line);
      }
    }
    if (names.isEmpty || names.length > 150) return false;
    final allowed = RegExp(r'^asset_[0-9]+\.(?:mp4|m4s|ts|aac|bin)$');
    for (final name in names) {
      if (!allowed.hasMatch(name)) return false;
      final segment = File('${playlist.parent.path}/$name');
      if (!await segment.exists() || await segment.length() == 0) {
        return false;
      }
    }
    return true;
  }

  /// Invalidate a video that a native decoder could not open. Future plays
  /// fall back to the network instead of repeatedly using a broken local file.
  Future<void> discard(String source) async {
    if (!_secureUrl(source) || _inUse.containsKey(source)) return;
    try {
      final dir = await _clipDir(source);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (error) {
      devLog('[MotionArt] offline clip discard failed: $error');
    }
  }

  void retain(String source) {
    _inUse[source] = (_inUse[source] ?? 0) + 1;
  }

  void release(String source) {
    final count = _inUse[source] ?? 0;
    if (count <= 1) {
      _inUse.remove(source);
    } else {
      _inUse[source] = count - 1;
    }
  }

  /// Called only after playback has successfully initialized. A failed or
  /// interrupted download is ignored, with normal streamed playback intact.
  Future<void> remember(
    String lookupKey,
    AnimatedArtwork artwork, {
    required bool preferVertical,
    Future<bool> Function()? canDownload,
  }) async {
    if (canDownload != null && !await canDownload()) return;
    final url = preferVertical
        ? artwork.verticalPlaybackUrl
        : artwork.playbackUrl;
    if (url == null || !_secureUrl(url)) return;
    try {
      final clip = await _ensureClip(url, canDownload: canDownload);
      if (clip == null) return;
      final file = await _lookupFile(lookupKey);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({'artwork': artwork.toJson()}),
        flush: true,
      );
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
    } catch (error) {
      devLog('[MotionArt] offline cache write failed: $error');
    }
  }

  /// Upgrade an earlier lookup index using the existing complete media,
  /// without making a request. Useful when a user has since reordered the
  /// enabled motion-art sources.
  Future<bool> indexExisting(String key, AnimatedArtwork artwork) async {
    for (final source in {
      if (artwork.playbackUrl != null) artwork.playbackUrl!,
      if (artwork.verticalPlaybackUrl != null) artwork.verticalPlaybackUrl!,
    }) {
      if (await localFile(source) != null) {
        try {
          final file = await _lookupFile(key);
          final temp = File('${file.path}.tmp');
          await temp.writeAsString(
            jsonEncode({'artwork': artwork.toJson()}),
            flush: true,
          );
          if (await file.exists()) await file.delete();
          await temp.rename(file.path);
          return true;
        } catch (error) {
          devLog('[MotionArt] offline index migration failed: $error');
          return false;
        }
      }
    }
    return false;
  }

  Future<File?> _ensureClip(
    String url, {
    Future<bool> Function()? canDownload,
  }) async {
    final cached = await localFile(url);
    if (cached != null) return cached;
    final existing = _downloads[url];
    if (existing != null) return existing;
    if (canDownload != null && !await canDownload()) return null;
    final job = _download(url, canDownload: canDownload);
    _downloads[url] = job;
    try {
      return await job;
    } finally {
      if (identical(_downloads[url], job)) _downloads.remove(url);
    }
  }

  Future<File?> _download(
    String url, {
    Future<bool> Function()? canDownload,
  }) async {
    final target = await _clipDir(url);
    final temp = Directory('${target.path}.partial');
    try {
      if (await temp.exists()) await temp.delete(recursive: true);
      await temp.create(recursive: true);
      final entry = Uri.parse(url).path.toLowerCase().endsWith('.m3u8')
          ? await _downloadHls(url, temp, canDownload: canDownload)
          : await _downloadProgressive(url, temp, canDownload: canDownload);
      if (entry == null || (canDownload != null && !await canDownload())) {
        return null;
      }
      await File('${temp.path}/complete.json').writeAsString(
        jsonEncode({'url': url, 'entry': entry}),
        flush: true,
      );
      if (await target.exists()) await target.delete(recursive: true);
      await temp.rename(target.path);
      final result = File('${target.path}/$entry');
      // Protect this new clip, and any clips currently opened by a player.
      await _trim(exclude: url);
      devLog('[MotionArt] saved offline clip: ${Uri.parse(url).host}');
      return await result.exists() ? result : null;
    } catch (error) {
      devLog('[MotionArt] video not cached ($url): $error');
      return null;
    } finally {
      if (await temp.exists()) {
        try {
          await temp.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<List<int>?> _getBytes(
    String url,
    int remaining, {
    Future<bool> Function()? canDownload,
  }) async {
    if (!_secureUrl(url) ||
        remaining <= 0 ||
        (canDownload != null && !await canDownload())) {
      return null;
    }
    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request).timeout(_timeout);
    if (response.statusCode != 200 ||
        (response.contentLength != null &&
            response.contentLength! > remaining)) {
      return null;
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(_timeout)) {
      if (canDownload != null && !await canDownload()) return null;
      if (bytes.length + chunk.length > remaining) return null;
      bytes.addAll(chunk);
    }
    return bytes;
  }

  Future<String?> _downloadProgressive(
    String url,
    Directory temp, {
    Future<bool> Function()? canDownload,
  }) async {
    final bytes = await _getBytes(
      url,
      maxClipBytes,
      canDownload: canDownload,
    );
    if (bytes == null || bytes.isEmpty) return null;
    // Preserve the source extension so native video_player selects a decoder.
    final extension = Uri.parse(url).path.toLowerCase();
    if (!(extension.endsWith('.mp4') ||
        extension.endsWith('.m4v') ||
        extension.endsWith('.mov') ||
        extension.endsWith('.webm'))) {
      return null;
    }
    final fileName = extension.endsWith('.webm')
        ? 'clip.webm'
        : extension.endsWith('.mov')
        ? 'clip.mov'
        : 'clip.mp4';
    await File('${temp.path}/$fileName').writeAsBytes(bytes, flush: true);
    return fileName;
  }

  Future<String?> _downloadHls(
    String url,
    Directory temp, {
    Future<bool> Function()? canDownload,
  }) async {
    var playlistUrl = url;
    var body = await _getBytes(
      playlistUrl,
      256 * 1024,
      canDownload: canDownload,
    );
    if (body == null) return null;
    var playlist = utf8.decode(body, allowMalformed: true);
    if (!playlist.trimLeft().startsWith('#EXTM3U')) return null;

    // The service usually selects a bounded rendition already; handle a
    // remaining master playlist without downloading every quality variant.
    if (playlist.contains('#EXT-X-STREAM-INF:')) {
      final rows = playlist.split(RegExp(r'\r?\n'));
      final variants = <(int, String)>[];
      for (var i = 0; i < rows.length - 1; i++) {
        if (!rows[i].startsWith('#EXT-X-STREAM-INF:')) continue;
        final resolution = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(rows[i]);
        final link = rows.skip(i + 1).map((s) => s.trim())
            .where((s) => s.isNotEmpty && !s.startsWith('#')).firstOrNull;
        if (link == null) continue;
        final pixels = resolution == null
            ? 0
            : int.parse(resolution[1]!) * int.parse(resolution[2]!);
        variants.add((pixels, Uri.parse(playlistUrl).resolve(link).toString()));
      }
      variants.sort((a, b) => a.$1.compareTo(b.$1));
      final selected = variants.where((v) => v.$1 >= 480 * 480 &&
          v.$1 <= 960 * 960).lastOrNull ?? variants.firstOrNull;
      if (selected == null || !_secureUrl(selected.$2)) return null;
      playlistUrl = selected.$2;
      body = await _getBytes(
        playlistUrl,
        256 * 1024,
        canDownload: canDownload,
      );
      if (body == null) return null;
      playlist = utf8.decode(body, allowMalformed: true);
    }

    // Offline HLS must be finite, clear, and self-contained.
    if (!playlist.contains('#EXT-X-ENDLIST') ||
        playlist.contains('#EXT-X-BYTERANGE') ||
        playlist.contains('#EXT-X-I-FRAMES-ONLY') ||
        playlist.contains('#EXT-X-PART:') ||
        playlist.contains('#EXT-X-PRELOAD-HINT:') ||
        playlist.contains('#EXT-X-SESSION-KEY:') ||
        RegExp(r'#EXT-X-KEY:(?!METHOD=NONE)').hasMatch(playlist) ||
        RegExp(r'#EXT-X-(?!MAP:)[^\r\n]*URI=').hasMatch(playlist)) {
      return null;
    }
    final rows = playlist.split(RegExp(r'\r?\n'));
    var totalBytes = 0;
    var assets = 0;
    final rewritten = <String>[];
    final assetNames = <String, String>{};

    Future<String?> copyAsset(String reference) async {
      final remote = Uri.parse(playlistUrl).resolve(reference).toString();
      if (!_secureUrl(remote)) return null;
      final existing = assetNames[remote];
      if (existing != null) return existing;
      if (assets >= 150) return null;
      final extension = Uri.parse(remote).path.toLowerCase();
      final suffix = extension.endsWith('.m4s')
          ? '.m4s'
          : extension.endsWith('.mp4')
          ? '.mp4'
          : extension.endsWith('.ts')
          ? '.ts'
          : extension.endsWith('.aac')
          ? '.aac'
          : '.bin';
      final local = 'asset_${assets++}$suffix';
      final bytes = await _getBytes(
        remote,
        maxClipBytes - totalBytes,
        canDownload: canDownload,
      );
      if (bytes == null || bytes.isEmpty) return null;
      totalBytes += bytes.length;
      await File('${temp.path}/$local').writeAsBytes(bytes, flush: true);
      assetNames[remote] = local;
      return local;
    }

    for (final raw in rows) {
      final line = raw.trim();
      if (line.isEmpty) {
        rewritten.add(raw);
      } else if (line.startsWith('#EXT-X-MAP:')) {
        final match = RegExp(r'URI="([^"]+)"').firstMatch(line);
        if (match == null) return null;
        final local = await copyAsset(match[1]!);
        if (local == null) return null;
        rewritten.add(line.replaceRange(match.start, match.end, 'URI="$local"'));
      } else if (line.startsWith('#')) {
        rewritten.add(raw);
      } else {
        final local = await copyAsset(line);
        if (local == null) return null;
        rewritten.add(local);
      }
    }
    if (assets == 0) return null;
    await File('${temp.path}/playlist.m3u8').writeAsString(
      rewritten.join('\n'),
      flush: true,
    );
    return 'playlist.m3u8';
  }

  Future<void> _trim({required String exclude}) async {
    final root = await _root();
    final dirs = await root.list().where((e) =>
        e is Directory && e.path.split(Platform.pathSeparator).last
            .startsWith('clip-') && !e.path.endsWith('.partial')).cast<Directory>().toList();
    final entries = <({Directory dir, File file, int bytes, DateTime used})>[];
    var total = 0;
    for (final dir in dirs) {
      final marker = File('${dir.path}/complete.json');
      if (!await marker.exists()) continue;
      try {
        final data = jsonDecode(await marker.readAsString()) as Map;
        final file = File('${dir.path}/${data['entry']}');
        var bytes = 0;
        await for (final item in dir.list()) {
          if (item is File) bytes += await item.length();
        }
        total += bytes;
        entries.add((dir: dir, file: file, bytes: bytes,
            used: (await file.stat()).modified));
      } catch (_) {}
    }
    entries.sort((a, b) => a.used.compareTo(b.used));
    for (final item in entries) {
      if (total <= maxCacheBytes) break;
      try {
        final marker = jsonDecode(await File(
          '${item.dir.path}/complete.json',
        ).readAsString()) as Map;
        final source = marker['url'];
        if (source == exclude || _inUse.containsKey(source) ||
            _downloads.containsKey(source)) continue;
        await item.dir.delete(recursive: true);
        total -= item.bytes;
      } catch (_) {}
    }
  }
}
