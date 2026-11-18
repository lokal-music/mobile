import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flick/core/utils/app_log.dart';
import 'package:flick/features/spotify/spotify_storage.dart';
import 'package:flick/services/graceful_http_client.dart';
import 'package:flick/services/playback_source_priority.dart';

import 'animated_artwork_service.dart';
import 'moving_cover_matcher.dart';
import 'motion_art_offline_cache.dart';
import 'moving_cover_settings.dart';
import 'spotify_canvas_service.dart';

/// Desktop's source order, with each added provider explicitly selectable.
/// Stream first frames immediately, then save bounded clips for offline replay.
class MovingCoverService {
  MovingCoverService({
    http.Client? client,
    AnimatedArtworkService? apple,
    SpotifyCanvasService? spotify,
    MotionArtOfflineCache? offlineCache,
    Future<bool> Function()? ecoActive,
    Future<bool> Function()? offline,
  }) : _client = client ?? GracefulHttpClient(),
       _apple = apple ?? AnimatedArtworkService.instance,
       _offlineCache = offlineCache ?? MotionArtOfflineCache.instance,
       _ecoActive = ecoActive ?? EcoDataMode.activeOnCellular,
       _offline = offline ?? EcoDataMode.isOffline {
    _spotify = spotify ?? SpotifyCanvasService(client: _client);
  }
  static final instance = MovingCoverService();
  final http.Client _client;
  final AnimatedArtworkService _apple;
  final MotionArtOfflineCache _offlineCache;
  final Future<bool> Function() _ecoActive;
  final Future<bool> Function() _offline;
  late final SpotifyCanvasService _spotify;
  final _cache = <String, (DateTime, MotionArtLookup)>{};
  final _jobs = <String, Future<MotionArtLookup>>{};
  String? _jwt;
  DateTime _jwtExpires = DateTime(2000);
  DateTime _jwtRetry = DateTime(2000);
  List<dynamic>? _community;
  DateTime _communityAt = DateTime(2000);
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/122.0.0.0 Safari/537.36';

  /// Stable per-source indexes survive changes to provider priority, session
  /// renewal and airplane mode. Other providers stay opt-in: a cached Spotify
  /// Canvas must not override Apple when Spotify is disabled in Appearance.
  String _offlineKey(
    String title,
    String artist,
    String album,
    String source,
  ) => 'v2|${motionName(title)}|${motionName(artist)}|'
      '${motionName(motionAlbum(album))}|$source';

  /// Read older completed caches without forcing users to re-download clips.
  String _legacyOfflineKey(
    String title,
    String artist,
    String album,
    MovingCoverSettings settings,
  ) => 'v1|${motionName(title)}|${motionName(artist)}|'
      '${motionName(motionAlbum(album))}|${settings.order.join(',')}';

  static String _artworkSource(AnimatedArtwork artwork) {
    final prefix = artwork.albumId.split(':').first;
    return movingCoverSources.containsKey(prefix) ? prefix : 'apple';
  }

  /// Start warming a chosen playback clip while its native decoder opens.
  /// It remains bounded and runs off the first-frame path; only completed
  /// content receives a durable index. Never issue downloads in airplane mode.
  Future<void> cachePlayedClip({
    required String title,
    required String artist,
    String? album,
    required AnimatedArtwork artwork,
    required bool preferVertical,
    String? alternateArtist,
  }) async {
    if (await _ecoActive() || await _offline()) return;
    final source = _artworkSource(artwork);
    Future<bool> mayDownload() async =>
        !await _ecoActive() && !await _offline();
    await _offlineCache.remember(
      _offlineKey(title, artist, album ?? '', source),
      artwork,
      preferVertical: preferVertical,
      canDownload: mayDownload,
    );
    // Album artist, song artist and fullscreen player can have different
    // lookup identities. Point them to the same completed on-disk clip.
    if (alternateArtist != null &&
        motionName(alternateArtist) != motionName(artist)) {
      await _offlineCache.remember(
        _offlineKey(title, alternateArtist, album ?? '', source),
        artwork,
        preferVertical: preferVertical,
        canDownload: mayDownload,
      );
    }
  }

  Future<MotionArtLookup> lookup({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
    MovingCoverSettings? settings,
    String? alternateArtist,
  }) async {
    final prefs = settings ?? await MovingCoverSettings.load();
    final cleanAlbum = motionAlbum(album);
    final cacheOnly = await _ecoActive() || await _offline();
    final key =
        '${motionName(title)}|${motionName(artist)}|${motionName(cleanAlbum)}|${prefs.order.join(',')}|${_apple.revision.value}|${SecureSpotifyTokenStore.sessionRevision.value}';
    Future<AnimatedArtwork?> offlineArtwork() async {
      for (final source in prefs.order) {
        for (final candidate in {
          artist,
          if (alternateArtist != null) alternateArtist,
        }) {
          final artwork = await _offlineCache.find(
            _offlineKey(title, candidate, cleanAlbum, source),
          );
          if (artwork != null && _artworkSource(artwork) == source) {
            return artwork;
          }
        }
      }
      // Legacy v1 files include the full source list in their hash.
      for (final candidate in {
        artist,
        if (alternateArtist != null) alternateArtist,
      }) {
        final artwork = await _offlineCache.find(
          _legacyOfflineKey(title, candidate, cleanAlbum, prefs),
        );
        if (artwork != null && prefs.sources.contains(_artworkSource(artwork))) {
          return artwork;
        }
      }
      if (cacheOnly) {
        // v1 hashed the *whole* source list. Rebuild only plausible historic
        // orders (five sources, Spotify-first optional) so existing downloads
        // aren't stranded when a user adjusts Appearance before going offline.
        // A successful match is reindexed under v2, making this a one-off cost.
        final ids = movingCoverSources.keys.toList();
        for (var mask = 1; mask < (1 << ids.length); mask++) {
          final enabled = {
            for (var i = 0; i < ids.length; i++)
              if ((mask & (1 << i)) != 0) ids[i],
          };
          for (final spotifyFirst in [
            false,
            if (enabled.contains('spotify')) true,
          ]) {
            final oldSettings = MovingCoverSettings(
              sources: enabled,
              spotifyFirst: spotifyFirst,
            );
            if (oldSettings.order.join(',') == prefs.order.join(',')) continue;
            for (final candidate in {
              artist,
              if (alternateArtist != null) alternateArtist,
            }) {
              final artwork = await _offlineCache.find(
                _legacyOfflineKey(title, candidate, cleanAlbum, oldSettings),
              );
              if (artwork == null ||
                  !prefs.sources.contains(_artworkSource(artwork))) continue;
              await _offlineCache.indexExisting(
                _offlineKey(
                  title, candidate, cleanAlbum, _artworkSource(artwork),
                ),
                artwork,
              );
              return artwork;
            }
          }
        }
      }
      return null;
    }

    // Airplane mode and cellular Eco are cache-only, even if the in-memory
    // online lookup previously succeeded with a now-unusable provider URL.
    if (cacheOnly) {
      return MotionArtLookup(artwork: await offlineArtwork());
    }
    final cached = _cache[key];
    if (cached != null && cached.$1.isAfter(DateTime.now())) return cached.$2;
    final active = _jobs[key];
    if (active != null) return active;

    // The completed local video is authoritative for offline playback. This
    // check runs before any Apple/Tidal/Spotify/provider HTTP request.
    final offline = await offlineArtwork();
    if (offline != null) {
      final result = MotionArtLookup(artwork: offline);
      _cache[key] = (DateTime.now().add(const Duration(minutes: 30)), result);
      return result;
    }
    final job = _resolve(
      title: motionTitle(title),
      artist: artist,
      album: cleanAlbum,
      duration: duration,
      settings: prefs,
    );
    _jobs[key] = job;
    try {
      final result = await job;
      _cache[key] = (
        DateTime.now().add(
          result.transient
              ? const Duration(seconds: 30)
              : result.artwork != null
              ? const Duration(minutes: 30)
              : const Duration(minutes: 15),
        ),
        result,
      );
      while (_cache.length > 50) {
        _cache.remove(_cache.keys.first);
      }
      return result;
    } finally {
      _jobs.remove(key);
    }
  }

  Future<MotionArtLookup> _resolve({
    required String title,
    required String artist,
    required String album,
    Duration? duration,
    required MovingCoverSettings settings,
  }) async {
    var transient = false;
    for (final source in settings.order) {
      try {
        AnimatedArtwork? artwork;
        if (source == 'apple') {
          artwork = await _directApple(title, artist, album);
          if (artwork == null) {
            final result = await _apple.lookupAnimatedArtwork(
              songTitle: title,
              artist: artist,
              albumName: album,
              duration: duration,
            );
            transient |= result.transient;
            artwork = result.artwork;
          }
        } else {
          String? url;
          if (source == 'tidal') url = await _tidal(title, artist, album);
          if (source == 'community')
            url = await _fromCommunity(title, artist, album);
          if (source == 'm8tec') url = await _m8tec(title, artist, album);
          if (source == 'spotify')
            url = await _spotify.lookup(
              title: title,
              artist: artist,
              album: album,
            );
          if (_safe(url))
            artwork = AnimatedArtwork(
              name: album.isEmpty ? title : album,
              artist: artist,
              albumId: '$source:${motionName(title)}',
              animatedUrl: url,
              animatedVerticalUrl: source == 'spotify' ? url : null,
            );
        }
        if (artwork?.hasMotion == true) {
          final bounded = await _boundedVideo(artwork!);
          AppLog.instance.add('[MotionArt] matched source=$source');
          return MotionArtLookup(artwork: bounded);
        }
      } catch (_) {
        transient = true;
        AppLog.instance.add(
          '[MotionArt] source=$source unavailable; trying next enabled source',
        );
      }
    }
    return MotionArtLookup(transient: transient);
  }

  static bool _safe(String? url) {
    final uri = Uri.tryParse(url ?? '');
    return uri?.scheme == 'https' &&
        uri!.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  Future<http.Response> _get(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    if (!_safe(url)) throw StateError('Invalid motion artwork URL');
    final response = await _client
        .get(Uri.parse(url), headers: {'User-Agent': _ua, ...headers})
        .timeout(const Duration(seconds: 12));
    if (response.statusCode == 404) return response;
    if (response.statusCode != 200)
      throw StateError('Motion source HTTP ${response.statusCode}');
    if (response.bodyBytes.length > 8 * 1024 * 1024)
      throw StateError('Motion source response too large');
    return response;
  }

  Future<dynamic> _json(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    final response = await _get(url, headers: headers);
    return response.statusCode == 404
        ? null
        : jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<String?> _tidal(String title, String artist, String album) async {
    final uri = Uri.https('api.tidal.com', '/v1/search', {
      'query': [album, artist, title].where((s) => s.isNotEmpty).join(' '),
      'limit': '10',
      'types': 'TRACKS',
      'countryCode': 'US',
    });
    final data = await _json(
      uri.toString(),
      headers: {'X-Tidal-Token': 'vNVdglQOjFJJGG2U'},
    );
    for (final item
        in (data?['tracks']?['items'] as List? ?? []).whereType<Map>()) {
      if (motionName(item['title']) != motionName(title) ||
          !motionArtistsMatch(
            artist,
            (item['artists'] as List? ?? [])
                .whereType<Map>()
                .map((a) => a['name'])
                .toList(),
          ))
        continue;
      if (album.isNotEmpty &&
          motionName(item['album']?['title']) != motionName(album))
        continue;
      final uuid = item['album']?['videoCover']?.toString() ?? '';
      if (RegExp(r'^[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$')
          .hasMatch(uuid))
        return 'https://resources.tidal.com/videos/${uuid.replaceAll('-', '/')}/1280x1280.mp4';
    }
    return null;
  }

  Future<String?> _fromCommunity(
    String title,
    String artist,
    String album,
  ) async {
    if (_community == null ||
        DateTime.now().difference(_communityAt) > const Duration(minutes: 30)) {
      final data = await _json(
        'https://vivimusicanvas.mkmdevilmi.workers.dev/canvas.json',
      );
      _community = data is List
          ? data
          : data?['items'] is List
          ? data['items'] as List
          : [];
      _communityAt = DateTime.now();
    }
    for (final item in _community!.whereType<Map>()) {
      final name = motionName(item['song']), want = motionName(title);
      if (name.isEmpty ||
          !(name == want || name.contains(want) || want.contains(name)))
        continue;
      if (!motionArtistsMatch(artist, item['artist']) &&
          !motionArtistsMatch(item['artist']?.toString() ?? '', artist))
        continue;
      if (album.isNotEmpty &&
          item['album'] != null &&
          motionName(item['album']) != motionName(album))
        continue;
      final url = item['url']?.toString();
      if (_safe(url)) return url;
    }
    return null;
  }

  Future<String?> _m8tec(String title, String artist, String album) async {
    final data = await _json(
      Uri.https('artwork.m8tec.top', '/api/v1/artwork/search', {
        'artist': artist,
        'title': title,
        if (album.isNotEmpty) 'album': album,
      }).toString(),
    );
    if (data == null) return null;
    if (data['artist'] != null && !motionArtistsMatch(artist, data['artist']))
      return null;
    if (album.isNotEmpty &&
        data['album'] != null &&
        motionName(data['album']) != motionName(album))
      return null;
    return (data['url'] ?? data['url_tall'])?.toString();
  }

  Future<String?> _appleToken() async {
    if (_jwt != null &&
        _jwtExpires.isAfter(DateTime.now().add(const Duration(minutes: 1))))
      return _jwt;
    if (_jwtRetry.isAfter(DateTime.now())) return null;
    _jwtRetry = DateTime.now().add(const Duration(minutes: 10));
    try {
      final html = (await _get('https://music.apple.com/us/browse')).body;
      final bundles = RegExp(r'/assets/index(?:-legacy)?[~-][A-Za-z0-9_-]+\.js')
          .allMatches(html)
          .map((m) => m[0]!)
          .toSet();
      for (final bundle in bundles.take(2)) {
        final js = (await _get('https://music.apple.com$bundle')).body;
        for (final hit in RegExp(
          r'ey[\w-]+\.ey[\w-]+\.[\w-]+',
        ).allMatches(js)) {
          final jwt = hit[0]!, pieces = jwt.split('.');
          try {
            final payload = jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(pieces[1]))),
            ) as Map;
            final header = utf8.decode(
              base64Url.decode(base64Url.normalize(pieces[0])),
            );
            final exp = payload['exp'];
            if (exp is! num ||
                !'$header${jsonEncode(payload)}'.contains('WebPlay'))
              continue;
            final expires = DateTime.fromMillisecondsSinceEpoch(
              exp.toInt() * 1000,
            );
            if (!expires.isAfter(DateTime.now())) continue;
            _jwt = jwt;
            _jwtExpires = expires;
            return jwt;
          } catch (_) {
            /* Not the catalogue JWT. */
          }
        }
      }
    } catch (_) {
      /* Retain the existing album/edition-aware Apple proxy fallback. */
    }
    return null;
  }

  Future<AnimatedArtwork?> _directApple(
    String title,
    String artist,
    String album,
  ) async {
    final token = await _appleToken();
    if (token == null) return null;
    try {
      final headers = {
        'Authorization': 'Bearer $token',
        'Origin': 'https://music.apple.com',
        'Referer': 'https://music.apple.com/',
      };
      final data = await _json(
        Uri.https('amp-api.music.apple.com', '/v1/catalog/us/search', {
          'term': [artist, title, album].where((s) => s.isNotEmpty).join(' '),
          'types': 'songs',
          'limit': '10',
          'extend': 'editorialVideo',
          'include': 'albums',
        }).toString(),
        headers: headers,
      );
      final matches = (data?['results']?['songs']?['data'] as List? ?? [])
          .whereType<Map>()
          .where(
            (s) =>
                motionArtistsMatch(artist, s['attributes']?['artistName']) &&
                motionName(s['attributes']?['name']) == motionName(title),
          )
          .toList();
      matches.sort(
        (a, b) =>
            (motionName(a['attributes']?['albumName']) == motionName(album)
                    ? 0
                    : 1)
                .compareTo(
                  motionName(b['attributes']?['albumName']) == motionName(album)
                      ? 0
                      : 1,
                ),
      );
      String? video(Object? object) {
        if (object is! Map) return null;
        for (final key in [
          'motionDetailSquare',
          'motionSquareVideo1x1',
          'motionDetailRaw',
          'motionDetailTall',
          'motionTallVideo3x4',
        ]) {
          final v = object[key];
          if (v is Map) {
            final url = (v['video'] ?? v['videoUrl'] ?? v['hlsUrl'] ?? v['url'])
                ?.toString();
            if (_safe(url)) return url;
          }
        }
        return null;
      }

      for (final song in matches.take(4)) {
        var url = video(song['attributes']?['editorialVideo']);
        if (url == null) {
          final albums = song['relationships']?['albums']?['data'];
          final id = albums is List && albums.isNotEmpty
              ? albums.first['id']?.toString()
              : null;
          if (id == null || !RegExp(r'^\d+$').hasMatch(id)) continue;
          final body = await _json(
            'https://amp-api.music.apple.com/v1/catalog/us/albums/$id?extend=editorialVideo',
            headers: headers,
          );
          final rows = body?['data'];
          if (rows is List && rows.isNotEmpty)
            url = video(rows.first['attributes']?['editorialVideo']);
        }
        if (url != null)
          return AnimatedArtwork(
            name: album,
            artist: artist,
            albumId: song['id'].toString(),
            animatedUrl: url,
          );
      }
    } catch (_) {
      _jwt = null;
    }
    return null;
  }

  Future<AnimatedArtwork> _boundedVideo(AnimatedArtwork art) async {
    final url = art.playbackUrl;
    if (url == null || !Uri.parse(url).path.toLowerCase().endsWith('.m3u8'))
      return art;
    try {
      final text = (await _get(url)).body;
      final lines = text.split('\n');
      final variants = <(int, String)>[];
      for (var i = 0; i < lines.length - 1; i++) {
        if (!lines[i].startsWith('#EXT-X-STREAM-INF:') ||
            !lines[i].contains('avc1'))
          continue;
        final res = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(lines[i]);
        final next = lines
            .skip(i + 1)
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && !s.startsWith('#'))
            .firstOrNull;
        if (res != null && next != null)
          variants.add((
            int.parse(res[1]!) * int.parse(res[2]!),
            Uri.parse(url).resolve(next).toString(),
          ));
      }
      variants.sort((a, b) => a.$1.compareTo(b.$1));
      final choice =
          variants
              .where((v) => v.$1 >= 480 * 480 && v.$1 <= 960 * 960)
              .lastOrNull ??
          variants.firstOrNull;
      if (choice != null && _safe(choice.$2))
        return AnimatedArtwork(
          name: art.name,
          artist: art.artist,
          albumId: art.albumId,
          animatedUrl: choice.$2,
        );
    } catch (_) {
      /* Let the video player choose if this was already a media playlist. */
    }
    return art;
  }
}
