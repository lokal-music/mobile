import 'dart:convert';

import 'package:flick/models/lokal_remote_state.dart';
import 'package:flick/services/link/lokal_desktop_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final credentials = LokalRemoteCredentials(
    origin: Uri.parse('http://desktop.local:3000'),
    remoteToken: 'paired-token',
  );

  test(
    'posts exact requested IDs with paired auth and returns found tracks',
    () async {
      final source = LokalDesktopSource(
        catalogueClientFactory: () => MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/remote/library/tracks/lookup');
          expect(request.headers['x-remote-token'], 'paired-token');
          expect(request.headers['content-type'], 'application/json');
          expect(jsonDecode(request.body), {
            'ids': ['track-one', 'missing'],
          });
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'track-one',
                  'title': 'Track',
                  'artist': 'Artist',
                  'duration': 180,
                  'fileType': 'flac',
                },
              ],
            }),
            200,
          );
        }),
      );

      expect(
        await source.lookupCatalogueTracks(credentials, [
          'track-one',
          'missing',
        ]),
        [
          {
            'id': 'track-one',
            'title': 'Track',
            'artist': 'Artist',
            'duration': 180,
            'fileType': 'flac',
          },
        ],
      );
    },
  );

  test('rejects unexpected and duplicate lookup results', () async {
    for (final items in [
      [
        {'id': 'not-requested', 'title': 'Other'},
      ],
      [
        {'id': 'wanted', 'title': 'Track'},
        {'id': 'wanted', 'title': 'Duplicate'},
      ],
    ]) {
      final source = LokalDesktopSource(
        catalogueClientFactory: () => MockClient(
          (_) async => http.Response(jsonEncode({'items': items}), 200),
        ),
      );
      await expectLater(
        source.lookupCatalogueTracks(credentials, ['wanted', 'missing']),
        throwsFormatException,
      );
    }
  });

  test('surfaces desktop lookup rejection and auth failure', () async {
    final rejected = LokalDesktopSource(
      catalogueClientFactory: () => MockClient(
        (_) async => http.Response('{"error":"Invalid track list."}', 400),
      ),
    );
    await expectLater(
      rejected.lookupCatalogueTracks(credentials, ['wanted']),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'desktop error',
          'Invalid track list.',
        ),
      ),
    );

    final unauthorized = LokalDesktopSource(
      catalogueClientFactory: () =>
          MockClient((_) async => http.Response('', 401)),
    );
    await expectLater(
      unauthorized.lookupCatalogueTracks(credentials, ['wanted']),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'auth error',
          contains('rejected this pairing'),
        ),
      ),
    );
  });
}
