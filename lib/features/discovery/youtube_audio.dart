import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/services.dart';
import 'package:http/http.dart' as net;
import 'package:flick/services/catalogue_quality.dart';

import '../../core/utils/app_log.dart';
import 'discovery_http.dart';
import 'discovery_models.dart';
import 'discovery_sources.dart';
import 'youtube_music_account.dart';
import 'youtube_music_store.dart';
import 'discovery_playback.dart';
import 'youtube_player_cipher.dart';
import '../../models/song.dart';

/// Android prefers InnerTubeX/cipher/PoToken. Both phones can recover through
/// direct clients with the shared sandboxed player-signature decoder.
class YoutubeAudio {
  YoutubeAudio(
    this.http, {
    this.session,
    this.nativeFallback,
    YoutubePlayerCipher? cipher,
    bool? isIOS,
  }) : cipher =
           cipher ??
           ((io.Platform.isIOS || io.Platform.isAndroid)
               ? YoutubePlayerCipher(http)
               : null),
       _isIOS = isIOS ?? io.Platform.isIOS;

  final DiscoveryHttp http;
  final YoutubePlayerCipher? cipher;
  final bool _isIOS;

  /// Existing browser sign-in is reused when available. Anonymous playback
  /// still tries the public clients, and cookie material is only sent to
  /// YouTube Music itself.
  final YoutubeMusicSession? session;

  /// Injectable seam for tests; production Android tries InnerTubeX first.
  final Future<ResolvedDiscoveryAudio?> Function(
    String videoId,
    YoutubeMusicSession? session,
  )?
  nativeFallback;

  static const MethodChannel _nativeChannel = MethodChannel(
    'com.mossapps.flick/youtube_stream',
  );

  Future<YoutubeMusicSession?>? _sessionFuture;
  Future<String?>? _webRemixVersionFuture;
  static int _requestSerial = 0;
  final _refusedClients = <String>{};

  /// Retry a media refusal through a different client, rather than reusing an
  /// URL whose tiny probe succeeded but whose actual audio download failed.
  Future<Song> prepare(
    DiscoveryTrack track,
    DiscoveryPlaybackCache cache, {
    Future<void>? cancel,
    void Function(int received, int? total)? onProgress,
  }) async {
    for (var attempt = 0; ; attempt++) {
      // The full media transfer immediately below verifies this URL too. A
      // separate first-byte probe adds another request/round trip to startup.
      final audio = await resolve(track.id, cancel: cancel, verifyMedia: false);
      try {
        return await cache.prepare(
          track, audio, cancel: cancel,
          onProgress: onProgress == null ? null :
              (received) => onProgress(received, audio.length),
        );
      } on DiscoveryException catch (error) {
        if (error.message == 'Request cancelled.' || attempt >= 2) rethrow;
        final reason = error.message.toLowerCase();
        if (!reason.contains('refused') &&
            !reason.contains('incomplete') &&
            !reason.contains('non-audio') &&
            !reason.contains('http 403') &&
            !reason.contains('http 401') &&
            !reason.contains('http 404') &&
            !reason.contains('http 429') &&
            !RegExp(r'http 5\d\d').hasMatch(reason) &&
            !reason.contains('invalid media range') &&
            !reason.contains('download size limit') &&
            !reason.contains('could not verify this audio file') &&
            !reason.contains('not a supported progressive audio file') &&
            !reason.contains('could not reach the source securely') &&
            !reason.contains('source timed out')) {
          rethrow;
        }
        final client = audio.url.queryParameters['c'];
        if (client != null) _refusedClients.add(client.toUpperCase());
        if (io.Platform.isAndroid) {
          try {
            await _nativeChannel.invokeMethod<void>('streamRefused', {
              'url': audio.url.toString(),
            });
          } on PlatformException {
            /* Older native side still has public-client fallback. */
          } on MissingPluginException {
            /* Other hosts and tests. */
          }
        }
      }
    }
  }

  Future<YoutubeMusicSession?> _loadSession() =>
      _sessionFuture ??= _readSession();

  /// YouTube rotates WEB_REMIX versions; use the version from the live shell
  /// rather than relying on the stale version shipped in this app.
  Future<String?> _liveWebRemixVersion() =>
      _webRemixVersionFuture ??= _readLiveWebRemixVersion();

  Future<String?> _readLiveWebRemixVersion() async {
    try {
      final response = await http.client
          .get(
            Uri.https('music.youtube.com', '/'),
            headers: {
              'User-Agent': clients.last.userAgent,
              'Accept-Language': 'en-US,en;q=0.9',
            },
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      cipher?.readPlayerUrl(response.body);
      return RegExp(r'"INNERTUBE_CLIENT_VERSION"\s*:\s*"([^"]+)"')
          .firstMatch(response.body)
          ?.group(1);
    } catch (_) {
      // The live version is an optimization. Keep the last known working
      // client version when YouTube's landing page cannot be reached.
      return null;
    }
  }

  Future<YoutubeMusicSession?> _readSession() async {
    final provided = session;
    if (provided != null && provided.signedIn) return provided;
    try {
      return await YoutubeMusicSessionStore().read();
    } catch (_) {
      return null;
    }
  }

  /// Prefer clients which can return directly fetchable media URLs. YouTube
  /// periodically retires player versions and changes which clients need
  /// BotGuard/PO tokens, so one client's refusal must not imply the video is
  /// region-blocked or age-restricted.
  static const clients = [
    YoutubeClient(
      name: 'VISIONOS',
      id: 101,
      version: '1.02',
      userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
      extra: {
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
      },
    ),
    YoutubeClient(
      name: 'ANDROID_VR',
      id: 28,
      version: '1.65.10',
      userAgent: 'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
      extra: {
        'deviceMake': 'Oculus',
        'deviceModel': 'Quest 3',
        'androidSdkVersion': 32,
        'osName': 'Android',
        'osVersion': '12L',
      },
    ),
    YoutubeClient(
      name: 'ANDROID',
      id: 3,
      version: '20.10.38',
      // The SDK-less client does not request Android device attestation.
      // This fallback runs on iOS too; advertising an SDK without providing
      // its attestation can yield OK player responses with unusable media.
      userAgent:
          'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
      extra: {'osName': 'Android', 'osVersion': '11'},
    ),
    YoutubeClient(
      name: 'IOS',
      id: 5,
      version: '20.10.4',
      userAgent: 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_0 like Mac OS X;)',
      extra: {
        'deviceMake': 'Apple',
        'deviceModel': 'iPhone16,2',
        'osName': 'iOS',
        'osVersion': '18.0',
      },
    ),
    YoutubeClient(
      name: 'WEB_EMBEDDED_PLAYER',
      id: 56,
      version: '1.20260115.01.00',
      userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36',
      embedUrl: 'https://www.youtube.com/',
    ),
    YoutubeClient(
      name: 'TVHTML5',
      id: 7,
      version: '7.20251105.10.00',
      userAgent: 'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version,gzip(gfe)',
      extra: {'platform': 'DESKTOP'},
    ),
    YoutubeClient(
      name: 'WEB_REMIX',
      id: 67,
      version: '1.20260114.03.00',
      host: 'music.youtube.com',
      userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36',
    ),
  ];

  static final _videoId = RegExp(r'^[\w-]{11}$');

  /// The audio for [videoId], ready for `DiscoveryPlaybackCache.prepare`.
  Future<ResolvedDiscoveryAudio> resolve(
    String videoId, {
    Future<void>? cancel,
    bool verifyMedia = true,
  }) async {
    if (!_videoId.hasMatch(videoId)) {
      throw const DiscoveryException('This isn’t a YouTube recording.');
    }
    var cancelled = false;
    if (cancel != null) unawaited(cancel.then((_) => cancelled = true));
    await Future<void>.value();
    if (cancelled) throw const DiscoveryException('Request cancelled.');
    DiscoveryException? failure;
    final signedInSession = await _loadSession();
    final signedInHeaders = signedInSession == null
        ? null
        : youtubeMusicHeaders(signedInSession);
    // Android's maintained cipher/PoToken-aware catalogue handles guest
    // clients as well. Do not spend six stale direct-client attempts first.
    if (io.Platform.isAndroid || nativeFallback != null) {
      try {
        final audio = await _resolveWithNativeFallback(
          videoId,
          signedInSession,
          cancel: cancel,
        );
        if (audio != null) return audio;
      } on DiscoveryException catch (error) {
        if (error.message == 'Request cancelled.') rethrow;
        failure = error;
        _logFailure('native', error);
        // A native client/cipher outage must not disable every public song.
        // Recover through the independent direct path once, without invoking
        // the same failed native walk again at the end.
      }
    }
    final directClients = _isIOS
        ? [
            clients.firstWhere((client) => client.name == 'IOS'),
            ...clients.where((client) => client.name != 'IOS'),
          ]
        : clients;
    for (final client in directClients) {
      if (_refusedClients.contains(client.name)) continue;
      try {
        final useSignedInMusicClient =
            client.name == 'WEB_REMIX' && signedInHeaders != null;
        final liveVersion = client.name == 'WEB_REMIX'
            ? await _liveWebRemixVersion()
            : null;
        final version =
            liveVersion ??
            (useSignedInMusicClient ? signedInSession!.clientVersion : null) ??
            client.version;
        final signatureTimestamp =
            client.name == 'WEB_REMIX' || client.name == 'TVHTML5'
            ? await cipher?.signatureTimestamp(cancel: cancel)
            : null;
        final requestClient = useSignedInMusicClient
            ? YoutubeClient(
                name: client.name,
                id: client.id,
                version: version,
                userAgent: signedInSession!.userAgent,
                extra: client.extra,
                host: client.host,
                embedUrl: client.embedUrl,
              )
            : YoutubeClient(
                name: client.name,
                id: client.id,
                version: version,
                userAgent: client.userAgent,
                extra: client.extra,
                host: client.host,
                embedUrl: client.embedUrl,
              );
        final response = await http.json(
          Uri.https(client.host, '/youtubei/v1/player', {
            'prettyPrint': 'false',
          }),
          headers: {
            'User-Agent': requestClient.userAgent,
            'Origin': 'https://${client.host}',
            'X-YouTube-Client-Name': '${client.id}',
            'X-YouTube-Client-Version': version,
            if (useSignedInMusicClient) ...signedInHeaders,
          },
          body: {
            'context': {
              'client': {
                'clientName': client.name,
                'clientVersion': version,
                'userAgent': requestClient.userAgent,
                ...client.extra,
                'hl': 'en',
                if (useSignedInMusicClient &&
                    signedInSession!.visitorData != null)
                  'visitorData': signedInSession.visitorData!,
              },
              if (client.embedUrl != null)
                'thirdParty': {'embedUrl': client.embedUrl},
            },
            'videoId': videoId,
            'contentCheckOk': true,
            'racyCheckOk': true,
            if (signatureTimestamp != null)
              'playbackContext': {
                'contentPlaybackContext': {
                  'signatureTimestamp': signatureTimestamp,
                },
              },
          },
          cancel: cancel,
        );
        final decoded = await cipher?.decipher(response, cancel: cancel);
        final audio = pick(decoded ?? response, requestClient);
        // A player response can say OK while its URL is already dead or is
        // bound to a different client identity. Verify actual media access
        // before handing the link to the downloader; a 403 from one client
        // must not prevent the next client from being tried.
        if (verifyMedia) await _probeMedia(audio, cancel: cancel);
        return audio;
      } on DiscoveryException catch (error) {
        if (error.message == 'Request cancelled.') rethrow;
        failure = error;
        _logFailure(client.name, error);
      }
    }
    throw failure ??
        const DiscoveryException('YouTube didn’t give this song’s audio.');
  }

  Future<ResolvedDiscoveryAudio?> _resolveWithNativeFallback(
    String videoId,
    YoutubeMusicSession? signedInSession, {
    Future<void>? cancel,
  }) async {
    final injected = nativeFallback;
    if (injected != null) return injected(videoId, signedInSession);
    if (!io.Platform.isAndroid) return null;

    final cookies = signedInSession?.cookies;
    final cookie = cookies == null || cookies.isEmpty
        ? null
        : cookies.entries
              .map((entry) => '${entry.key}=${entry.value}')
              .join('; ');
    final requestId =
        'youtube_${DateTime.now().microsecondsSinceEpoch}_${++_requestSerial}';
    var finished = false;
    Future<void> stopNative() async {
      if (finished) return;
      try {
        await _nativeChannel.invokeMethod<void>('cancelResolve', {
          'requestId': requestId,
        });
      } on Object {
        /* Cancellation must work with older native builds too. */
      }
    }

    if (cancel != null) unawaited(cancel.then((_) => stopNative()));
    final request = _nativeChannel
        .invokeMapMethod<String, Object?>('resolveStream', {
          'videoId': videoId,
          'requestId': requestId,
          'cookie': ?cookie,
          'visitorData': ?signedInSession?.visitorData,
        })
        .timeout(const Duration(seconds: 50));
    final Map<String, Object?>? response;
    try {
      response = cancel == null
          ? await request
          : await Future.any([
              request,
              cancel.then<Map<String, Object?>?>(
                (_) => throw const DiscoveryException('Request cancelled.'),
              ),
            ]);
    } on DiscoveryException {
      rethrow;
    } on PlatformException catch (error) {
      if (error.code == 'CANCELLED') {
        throw const DiscoveryException('Request cancelled.');
      }
      throw DiscoveryException(
        error.code == 'RESOLVE_TIMEOUT'
            ? 'YouTube stream resolution timed out. Try again.'
            : 'YouTube could not resolve playable audio. Try again or choose another source.',
      );
    } on MissingPluginException {
      return null;
    } on TimeoutException {
      await stopNative();
      throw const DiscoveryException(
        'YouTube advanced stream resolution timed out. Try again.',
      );
    } finally {
      finished = true;
    }
    if (response == null) return null;
    final urlText = response['url'];
    if (urlText is! String) return null;
    final url = Uri.tryParse(urlText);
    if (url == null ||
        url.scheme != 'https' ||
        !url.host.toLowerCase().endsWith('.googlevideo.com')) {
      throw const DiscoveryException(
        'YouTube returned an invalid media URL from its advanced resolver.',
      );
    }
    final rawHeaders = response['headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        if (entry.key is String && entry.value is String) {
          headers[entry.key as String] = entry.value as String;
        }
      }
    }
    final rawLength = response['length'];
    return ResolvedDiscoveryAudio(
      url,
      length: rawLength is num && rawLength > 0 ? rawLength.toInt() : null,
      headers: headers,
      codec: verifiedAudioCodec(response['mime']),
      bitrate: response['bitrate'] is num
          ? (response['bitrate'] as num).toInt()
          : null,
    );
  }

  Future<void> _probeMedia(
    ResolvedDiscoveryAudio audio, {
    Future<void>? cancel,
  }) async {
    final abort = Completer<void>();
    var timedOut = false;
    var cancelled = false;
    final timer = Timer(const Duration(seconds: 7), () {
      timedOut = true;
      if (!abort.isCompleted) abort.complete();
    });
    if (cancel != null) {
      unawaited(
        cancel.then((_) {
          cancelled = true;
          if (!abort.isCompleted) abort.complete();
        }),
      );
    }
    final request =
        net.AbortableRequest('GET', audio.url, abortTrigger: abort.future)
          ..followRedirects = true
          // This response is deliberately cut short after its first bytes.
          // Never race an abort against IOClient returning it to the pool
          // (_HttpClient._returnConnection crashes in both supplied logs).
          ..persistentConnection = false
          ..headers.addAll({
            'Accept': '*/*',
            'Range': 'bytes=0-16383',
            ...audio.headers,
          });
    StreamIterator<List<int>>? chunks;
    try {
      if (abort.isCompleted) {
        throw const DiscoveryException('Request cancelled.');
      }
      final pending = http.client.send(request).then((response) {
        if (abort.isCompleted) {
          unawaited(response.stream.listen(null).cancel());
          throw const DiscoveryException('Request cancelled.');
        }
        return response;
      });
      final response = await Future.any([
        pending,
        abort.future.then<net.StreamedResponse>(
          (_) => throw const DiscoveryException('Request cancelled.'),
        ),
      ]);
      if (response.statusCode != 200 && response.statusCode != 206) {
        unawaited(response.stream.listen(null).cancel());
        throw DiscoveryException(
          'YouTube refused the media URL (HTTP ${response.statusCode}).',
        );
      }
      final contentType = response.headers['content-type']?.toLowerCase();
      if (contentType != null &&
          contentType.isNotEmpty &&
          !contentType.startsWith('audio/') &&
          !contentType.startsWith('video/') &&
          !contentType.contains('octet-stream')) {
        unawaited(response.stream.listen(null).cancel());
        throw const DiscoveryException(
          'YouTube returned a non-audio response for this recording.',
        );
      }
      chunks = StreamIterator(response.stream);
      final hasChunk = await Future.any([
        chunks.moveNext().timeout(const Duration(seconds: 5)),
        abort.future.then<bool>(
          (_) => throw const DiscoveryException('Request cancelled.'),
        ),
      ]);
      if (!hasChunk ||
          chunks.current.isEmpty ||
          _looksLikeHtml(chunks.current)) {
        throw const DiscoveryException(
          'YouTube returned no playable audio bytes for this recording.',
        );
      }
    } catch (error) {
      if (timedOut) {
        throw const DiscoveryException('YouTube media verification timed out.');
      }
      if (cancelled) throw const DiscoveryException('Request cancelled.');
      if (error is DiscoveryException) rethrow;
      throw const DiscoveryException(
        'Could not verify the YouTube media URL. Trying another player client.',
      );
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
      await chunks?.cancel();
    }
  }

  static bool _looksLikeHtml(List<int> bytes) {
    final prefix = String.fromCharCodes(bytes.take(96))
        .trimLeft()
        .toLowerCase();
    return prefix.startsWith('<!doctype html') ||
        prefix.startsWith('<html') ||
        prefix.startsWith('<?xml');
  }

  static void _logFailure(String client, DiscoveryException error) {
    AppLog.instance.add(
      '[YouTube playback] client=$client reason=${youtubeFailureKind(error)}',
    );
  }

  /// The best AAC audio in a player [response]: the player plays MP4 audio,
  /// not WebM, so Opus formats are skipped.
  static ResolvedDiscoveryAudio pick(
    Map<String, dynamic> response,
    YoutubeClient client,
  ) {
    final status = response['playabilityStatus'];
    if (status is! Map || status['status'] != 'OK') {
      throw DiscoveryException(_playabilityMessage(status));
    }
    final data = response['streamingData'];
    final formats = data is Map ? data['adaptiveFormats'] : null;
    final usable = <({Uri url, int length, int bitrate, String? codec})>[];
    for (final format in formats is List ? formats : const []) {
      if (format is! Map) continue;
      final mime = '${format['mimeType'] ?? ''}';
      final url = Uri.tryParse('${format['url'] ?? ''}');
      final length =
          int.tryParse(
            '${format['contentLength'] ?? url?.queryParameters['clen'] ?? ''}',
          ) ??
          0;
      // Ciphered links are decoded before selection; no raw cipher may reach
      // the downloader or be mistaken for a playable URL.
      if (!mime.startsWith('audio/mp4') ||
          url == null ||
          url.scheme != 'https' ||
          !url.host.endsWith('.googlevideo.com') ||
          length <= 0) {
        continue;
      }
      final bitrate = format['bitrate'];
      usable.add((
        url: url,
        length: length,
        bitrate: bitrate is num ? bitrate.toInt() : 0,
        codec: verifiedAudioCodec(mime),
      ));
    }
    if (usable.isEmpty) {
      throw const DiscoveryException(
        'YouTube didn’t give this song’s audio in a format the player plays.',
      );
    }
    usable.sort((a, b) => b.bitrate.compareTo(a.bitrate));
    final best = usable.first;
    return ResolvedDiscoveryAudio(
      best.url,
      length: best.length,
      bitrate: best.bitrate > 0 ? best.bitrate : null,
      codec: best.codec,
      headers: {
        'User-Agent': client.userAgent,
        // Web playback URLs are tied to the requesting origin as well as
        // the client version; mirror BitChord's media headers.
        if (client.name == 'WEB_REMIX' || client.name == 'WEB_EMBEDDED_PLAYER')
          'Origin': 'https://${client.host}',
        if (client.name == 'WEB_REMIX' || client.name == 'WEB_EMBEDDED_PLAYER')
          'Referer': client.embedUrl ?? 'https://${client.host}/',
      },
    );
  }
}

String _playabilityMessage(Object? value) {
  if (value is! Map) {
    return 'YouTube returned no playback status. Try again or choose another source.';
  }
  final status = '${value['status'] ?? 'UNKNOWN'}';
  final rawReason = value['reason'];
  final reason = rawReason is String ? rawReason.trim() : '';
  final lower = reason.toLowerCase();
  if (status == 'AGE_CHECK_REQUIRED' ||
      status == 'AGE_VERIFICATION_REQUIRED' ||
      lower.contains('age-restricted') ||
      lower.contains('age restricted') ||
      lower.contains('age verification')) {
    return 'YouTube requires age verification for this recording.';
  }
  if (lower.contains('not available in your country') ||
      lower.contains('not available in your region') ||
      lower.contains('geographic')) {
    return 'YouTube reports that this recording is unavailable in your region.';
  }
  if (status == 'LOGIN_REQUIRED' ||
      lower.contains('sign in to confirm') ||
      lower.contains('confirm you’re not a bot') ||
      lower.contains("confirm you're not a bot")) {
    return 'YouTube requires additional verification before this recording can play. Try again or use another source.';
  }
  if (status == 'UNPLAYABLE' || status == 'ERROR') {
    return 'YouTube refused playback ($status)${reason.isEmpty ? '' : ': $reason'}';
  }
  return 'YouTube refused playback ($status)${reason.isEmpty ? '' : ': $reason'}';
}

class YoutubeClient {
  const YoutubeClient({
    required this.name,
    required this.id,
    required this.version,
    required this.userAgent,
    this.extra = const {},
    this.host = 'www.youtube.com',
    this.embedUrl,
  });

  final String name;
  final int id;
  final String version;
  final String userAgent;
  final Map<String, Object> extra;
  final String host;
  final String? embedUrl;
}

/// Fixed diagnostic labels only: never copy provider text, signed URLs or
/// account material to exported logs.
String youtubeFailureKind(DiscoveryException error) {
  final message = error.message.toLowerCase();
  if (message == 'request cancelled.') return 'cancelled';
  if (message.contains('signature') || message.contains('player script')) {
    return 'player_cipher';
  }
  if (message.contains('age verification')) return 'age_verification';
  if (message.contains('verification')) return 'verification_required';
  if (message.contains('region')) return 'region_unavailable';
  if (message.contains('format')) return 'no_direct_aac';
  final status = RegExp(r'http (\d{3})').firstMatch(message)?.group(1);
  if (status != null) return 'http_$status';
  if (message.contains('timed out')) return 'timeout';
  if (message.contains('non-audio') ||
      message.contains('no playable audio bytes')) {
    return 'invalid_media';
  }
  if (message.contains('securely') || message.contains('connection')) {
    return 'network';
  }
  if (message.contains('refused playback')) return 'player_refused';
  return 'resolve_failed';
}
