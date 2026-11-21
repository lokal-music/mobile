import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flick/features/discovery/discovery_http.dart';
import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/discovery/discovery_playback.dart';
import 'package:flick/features/discovery/discovery_sources.dart';
import 'package:flick/features/discovery/youtube_audio.dart';
import 'package:flick/features/discovery/youtube_music_account.dart';
import 'package:flick/core/utils/app_log.dart';
import 'package:flick/src/rust/api/audio_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _player(List<Map<String, dynamic>> formats) => {
  'playabilityStatus': {'status': 'OK'},
  'streamingData': {'adaptiveFormats': formats},
};

Map<String, dynamic> _format(
  int itag,
  String mime,
  int bitrate, {
  bool ciphered = false,
  String host = 'rr1---sn-abc.googlevideo.com',
}) => {
  'itag': itag,
  'mimeType': mime,
  'bitrate': bitrate,
  'contentLength': '${bitrate * 30}',
  if (ciphered)
    'signatureCipher': 's=abc&url=https%3A%2F%2F$host'
  else
    'url': 'https://$host/videoplayback?itag=$itag&expire=1',
};

void main() {
  final client = YoutubeAudio.clients.first;

  test('picks the best plain AAC audio', () {
    final audio = YoutubeAudio.pick(
      _player([
        _format(251, 'audio/webm; codecs="opus"', 160000),
        _format(141, 'audio/mp4; codecs="mp4a.40.2"', 256000, ciphered: true),
        _format(140, 'audio/mp4; codecs="mp4a.40.2"', 130000),
        _format(139, 'audio/mp4; codecs="mp4a.40.5"', 48000),
        _format(137, 'video/mp4; codecs="avc1"', 4000000),
        _format(
          999,
          'audio/mp4; codecs="mp4a.40.2"',
          900000,
          host: 'evil.example',
        ),
      ]),
      client,
    );
    expect(audio.url.queryParameters['itag'], '140');
    expect(audio.length, 130000 * 30);
    expect(audio.headers['User-Agent'], client.userAgent);
  });

  test('iOS playback uses the iOS client and transfers media only once', () async {
    final asked = <String>[];
    var mediaRequests = 0;
    final fake = MockClient((request) async {
      if (request.method == 'GET') {
        mediaRequests++;
        return http.Response.bytes(
          [0, 0, 0, 16, 102, 116, 121, 112, 77, 52, 65, 32, 0, 0, 0, 0],
          206,
          headers: {
            'content-range': 'bytes 0-15/16',
            'content-type': 'audio/mp4',
          },
        );
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      asked.add(body['context']['client']['clientName'] as String);
      return http.Response(
        jsonEncode({
          'playabilityStatus': {'status': 'OK'},
          'streamingData': {
            'adaptiveFormats': [
              {
                'itag': 140,
                'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
                'bitrate': 130000,
                'contentLength': '16',
                'url':
                    'https://rr1---sn-abc.googlevideo.com/videoplayback?itag=140',
              },
            ],
          },
        }),
        200,
      );
    });
    addTearDown(fake.close);
    final directory = await Directory.systemTemp.createTemp(
      'youtube_audio_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final httpClient = DiscoveryHttp(fake);
    final cache = DiscoveryPlaybackCache(
      http: httpClient,
      directory: () async => directory,
      probe: (_) async => const AudioProbeFormat(sampleRate: 44100, channels: 2),
    );
    final audio = YoutubeAudio(httpClient, isIOS: true);

    await audio.prepare(
      const DiscoveryTrack(
        id: 'dQw4w9WgXcQ',
        title: 'Track',
        artist: 'Artist',
        source: DiscoverySource.youtubeMusic,
      ),
      cache,
    );

    expect(asked, ['IOS']);
    expect(mediaRequests, 1, reason: 'the transfer replaces the first-byte probe');
  });

  test('says why YouTube refused', () {
    expect(
      () => YoutubeAudio.pick({
        'playabilityStatus': {'status': 'LOGIN_REQUIRED'},
      }, client),
      throwsA(
        isA<DiscoveryException>().having(
          (e) => e.message,
          'message',
          contains('requires additional verification'),
        ),
      ),
    );
    expect(
      () => YoutubeAudio.pick(
        _player([_format(251, 'audio/webm; codecs="opus"', 160000)]),
        client,
      ),
      throwsA(isA<DiscoveryException>()),
    );
  });


  test('uses the saved YouTube Music account for the WEB_REMIX fallback', () async {
    final session = YoutubeMusicSession(
      cookies: {'SAPISID': 'signed-in-cookie'},
      userAgent: 'Browser session UA',
      visitorData: 'visitor-data',
      clientVersion: '1.20261001.01.00',
    );
    final asked = <String>[];
    final authorization = <String>[];
    final cookies = <String>[];
    final http.Client fake = MockClient((request) async {
      if (request.method == 'GET' && request.url.host == 'music.youtube.com') {
        return http.Response(
          '<script>var ytcfg = {"INNERTUBE_CLIENT_VERSION":"1.20261001.01.00"};</script>',
          200,
          headers: {'content-type': 'text/html'},
        );
      }
      if (request.method == 'GET') {
        return http.Response.bytes(
          [0, 0, 0, 24, 102, 116, 121, 112, 77, 52, 65, 32, 32],
          206,
          headers: {'content-type': 'audio/mp4'},
        );
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final client = body['context']['client'] as Map<String, dynamic>;
      final name = '${client['clientName']}';
      asked.add(name);
      if (name == 'WEB_REMIX') {
        expect(request.url.host, 'music.youtube.com');
        expect(client['visitorData'], 'visitor-data');
        expect(client['clientVersion'], '1.20261001.01.00');
        authorization.add(request.headers['authorization'] ?? '');
        cookies.add(request.headers['cookie'] ?? '');
        return http.Response(
          jsonEncode(_player([
            _format(140, 'audio/mp4; codecs="mp4a.40.2"', 130000),
          ])),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'playabilityStatus': {
            'status': 'UNPLAYABLE',
            'reason': 'This client cannot play the recording',
          },
        }),
        200,
      );
    });
    addTearDown(fake.close);

    final audio = await YoutubeAudio(
      DiscoveryHttp(fake),
      session: session,
    ).resolve('dQw4w9WgXcQ');
    expect(asked.last, 'WEB_REMIX');
    expect(audio.url.queryParameters['itag'], '140');
    expect(audio.headers['Origin'], 'https://music.youtube.com');
    expect(audio.headers['Referer'], 'https://music.youtube.com/');
    expect(authorization.single, startsWith('SAPISIDHASH '));
    expect(cookies.single, contains('SAPISID=signed-in-cookie'));
  });

  test('does not mislabel every YouTube refusal as a country or age block', () {
    expect(
      () => YoutubeAudio.pick({
        'playabilityStatus': {
          'status': 'UNPLAYABLE',
          'reason': 'Playback is not available for this client',
        },
      }, client),
      throwsA(
        isA<DiscoveryException>()
            .having((e) => e.message, 'message', contains('UNPLAYABLE'))
            .having((e) => e.message, 'message', isNot(contains('age-restricted')))
            .having((e) => e.message, 'message', isNot(contains('country'))),
      ),
    );
  });

  test('falls back to the current Android client when older clients are refused', () async {
    final asked = <String>[];
    final http.Client fake = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response.bytes(
          [0, 0, 0, 24, 102, 116, 121, 112, 77, 52, 65, 32, 32],
          206,
          headers: {'content-type': 'audio/mp4'},
        );
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final name = body['context']['client']['clientName'] as String;
      asked.add(name);
      if (name == 'VISIONOS' || name == 'ANDROID_VR') {
        return http.Response(
          jsonEncode({
            'playabilityStatus': {
              'status': 'UNPLAYABLE',
              'reason': 'This client cannot play the recording',
            },
          }),
          200,
        );
      }
      expect(name, 'ANDROID');
      expect(body['context']['client'], isNot(contains('androidSdkVersion')));
      return http.Response(
        jsonEncode(_player([_format(140, 'audio/mp4; codecs="mp4a.40.2"', 130000)])),
        200,
      );
    });
    addTearDown(fake.close);

    final audio = await YoutubeAudio(DiscoveryHttp(fake)).resolve('dQw4w9WgXcQ');
    expect(asked, ['VISIONOS', 'ANDROID_VR', 'ANDROID']);
    expect(audio.url.queryParameters['itag'], '140');
    expect(audio.headers['User-Agent'], contains('com.google.android.youtube'));
  });

  test('tries another client when a valid player response has a denied media URL', () async {
    final asked = <String>[];
    const deniedHost = 'rr1---sn-abc.googlevideo.com';
    const allowedHost = 'rr2---sn-abc.googlevideo.com';
    final http.Client fake = MockClient((request) async {
      if (request.method == 'GET') {
        if (request.url.host == deniedHost) return http.Response('', 403);
        expect(request.headers['range'], 'bytes=0-16383');
        return http.Response.bytes(
          [0, 0, 0, 24, 102, 116, 121, 112, 77, 52, 65, 32, 32],
          206,
          headers: {'content-type': 'audio/mp4'},
        );
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final name = body['context']['client']['clientName'] as String;
      asked.add(name);
      if (name == 'VISIONOS') {
        return http.Response(
          jsonEncode(_player([
            _format(140, 'audio/mp4; codecs="mp4a.40.2"', 130000, host: deniedHost),
          ])),
          200,
        );
      }
      if (name == 'ANDROID_VR') {
        return http.Response(
          jsonEncode(_player([
            _format(140, 'audio/mp4; codecs="mp4a.40.2"', 130000, host: allowedHost),
          ])),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'playabilityStatus': {'status': 'UNPLAYABLE'},
        }),
        200,
      );
    });
    addTearDown(fake.close);

    final audio = await YoutubeAudio(DiscoveryHttp(fake)).resolve('dQw4w9WgXcQ');
    expect(asked, ['VISIONOS', 'ANDROID_VR']);
    expect(audio.url.host, allowedHost);
  });

  test('prefers native InnerTubeX without redundant public client requests', () async {
    final asked = <String>[];
    final http.Client fake = MockClient((request) async {
      if (request.method == 'GET' && request.url.host == 'music.youtube.com') {
        return http.Response(
          '<script>var ytcfg = {"INNERTUBE_CLIENT_VERSION":"1.20261001.01.00"};</script>',
          200,
          headers: {'content-type': 'text/html'},
        );
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final name = body['context']['client']['clientName'] as String;
      asked.add(name);
      return http.Response(
        jsonEncode({
          'playabilityStatus': {
            'status': 'UNPLAYABLE',
            'reason': 'This client cannot play this recording',
          },
        }),
        200,
      );
    });
    addTearDown(fake.close);
    var fallbackCalls = 0;
    final audio = await YoutubeAudio(
      DiscoveryHttp(fake),
      nativeFallback: (id, session) async {
        fallbackCalls++;
        expect(id, 'dQw4w9WgXcQ');
        expect(session, isNull);
        return ResolvedDiscoveryAudio(
          Uri.parse('https://rr1---sn-abc.googlevideo.com/videoplayback?clen=16384'),
          length: 16384,
          headers: const {'User-Agent': 'InnerTubeX client'},
        );
      },
    ).resolve('dQw4w9WgXcQ');

    expect(asked, isEmpty);
    expect(fallbackCalls, 1);
    expect(audio.url.host, 'rr1---sn-abc.googlevideo.com');
    expect(audio.headers['User-Agent'], 'InnerTubeX client');
  });

  test('recovers from native resolver failure without repeating it', () async {
    var nativeCalls = 0;
    final asked = <String>[];
    final fake = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response.bytes(
          [0, 0, 0, 24, 102, 116, 121, 112],
          206,
          headers: {'content-type': 'audio/mp4'},
        );
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      asked.add(body['context']['client']['clientName'] as String);
      return http.Response(
        jsonEncode(
          _player([_format(140, 'audio/mp4; codecs="mp4a.40.2"', 130000)]),
        ),
        200,
      );
    });
    addTearDown(fake.close);
    final audio = await YoutubeAudio(
      DiscoveryHttp(fake),
      nativeFallback: (_, _) async {
        nativeCalls++;
        throw const DiscoveryException(
          'YouTube could not resolve playable audio.',
        );
      },
    ).resolve('dQw4w9WgXcQ');
    expect(nativeCalls, 1);
    expect(asked, ['VISIONOS']);
    expect(audio.url.queryParameters['itag'], '140');
    expect(
      AppLog.instance.entries.last.message,
      contains('client=native reason=resolve_failed'),
    );
  });

  test('native cancellation never starts a fallback', () async {
    final fake = MockClient(
      (_) async => throw StateError('unexpected fallback'),
    );
    addTearDown(fake.close);
    await expectLater(
      YoutubeAudio(
        DiscoveryHttp(fake),
        nativeFallback: (_, _) async {
          throw const DiscoveryException('Request cancelled.');
        },
      ).resolve('dQw4w9WgXcQ'),
      throwsA(
        isA<DiscoveryException>().having(
          (e) => e.message,
          'message',
          'Request cancelled.',
        ),
      ),
    );
  });

  test(
    'already cancelled resolution never starts the native resolver',
    () async {
      final fake = MockClient(
        (_) async => throw StateError('unexpected request'),
      );
      addTearDown(fake.close);
      await expectLater(
        YoutubeAudio(
          DiscoveryHttp(fake),
          nativeFallback: (_, _) async {
            throw StateError('unexpected native request');
          },
        ).resolve('dQw4w9WgXcQ', cancel: Future<void>.value()),
        throwsA(
          isA<DiscoveryException>().having(
            (e) => e.message,
            'message',
            'Request cancelled.',
          ),
        ),
      );
    },
  );

  test(
    'media probe cannot return an aborted connection to the keep-alive pool',
    () async {
      final fake = MockClient.streaming((request, body) async {
        await body.drain<void>();
        if (request.method == 'GET') {
          expect(request.persistentConnection, isFalse);
          return http.StreamedResponse(
            Stream.value([0, 0, 0, 24, 102, 116, 121, 112]),
            206,
            headers: {'content-type': 'audio/mp4'},
          );
        }
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              jsonEncode(
                _player([
                  _format(140, 'audio/mp4; codecs="mp4a.40.2"', 130000),
                ]),
              ),
            ),
          ),
          200,
        );
      });
      addTearDown(fake.close);
      await YoutubeAudio(DiscoveryHttp(fake)).resolve('dQw4w9WgXcQ');
    },
  );

  test('diagnostics classify failures without logging provider secrets', () {
    expect(
      youtubeFailureKind(
        const DiscoveryException(
          'YouTube refused the media URL (HTTP 403). https://private/?token=secret',
        ),
      ),
      'http_403',
    );
    expect(
      youtubeFailureKind(
        const DiscoveryException('YouTube player signature decoding failed.'),
      ),
      'player_cipher',
    );
    expect(
      youtubeFailureKind(
        const DiscoveryException(
          'YouTube requires additional verification before this recording can play.',
        ),
      ),
      'verification_required',
    );
  });

  test('asks as visionOS first, then the Quest app', () async {
    final asked = <String>[];
    final http.Client fake = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response.bytes(
          [0, 0, 0, 24, 102, 116, 121, 112, 77, 52, 65, 32, 32],
          206,
          headers: {'content-type': 'audio/mp4'},
        );
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final name = body['context']['client']['clientName'] as String;
      asked.add(name);
      expect(body['videoId'], 'dQw4w9WgXcQ');
      expect(request.url.host, 'www.youtube.com');
      expect(request.headers['X-YouTube-Client-Name'], isNotEmpty);
      return http.Response(
        jsonEncode(
          name == 'VISIONOS'
              ? {
                  'playabilityStatus': {'status': 'UNPLAYABLE'},
                }
              : _player([_format(140, 'audio/mp4; codecs="mp4a"', 130000)]),
        ),
        200,
      );
    });
    addTearDown(fake.close);
    final audio = await YoutubeAudio(DiscoveryHttp(fake))
        .resolve('dQw4w9WgXcQ');
    expect(asked, ['VISIONOS', 'ANDROID_VR']);
    expect(audio.headers['User-Agent'], YoutubeAudio.clients[1].userAgent);
    expect(
      () => YoutubeAudio(DiscoveryHttp(fake)).resolve('not a video id'),
      throwsA(isA<DiscoveryException>()),
    );
  });
}
