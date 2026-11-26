import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flick/models/lokal_remote_state.dart';
import 'package:flick/services/link/link_protocol.dart';
import 'package:flick/services/link/lokal_link_service.dart';

class _Network extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'lokal.link.device_id': 'name-test-device',
    }),
  );
  tearDown(
    () => messenger.setMockMethodCallHandler(LokalLinkService.channel, null),
  );

  test(
    'new pairing sends the native device name and preserves its existing ID',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        var nativeReads = 0;
        messenger.setMockMethodCallHandler(LokalLinkService.channel, (
          call,
        ) async {
          if (call.method == 'getDeviceName') {
            nativeReads++;
            return '  Galaxy\n Tab S9 📱  ';
          }
          return true;
        });
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requests = <Map>[];
        server.listen((request) async {
          requests.add(
            jsonDecode(await utf8.decoder.bind(request).join()) as Map,
          );
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'token': 'synthetic-device-token',
              'desktopId': 'desktop-name-test',
            }),
          );
          await request.response.close();
        });
        final service = LokalLinkService();
        final origin = Uri(
          scheme: 'http',
          host: server.address.address,
          port: server.port,
        );
        try {
          await service.pair(origin: origin, code: '123456');
          expect(requests.single['deviceName'], 'Galaxy Tab S9 📱');
          expect(requests.single['deviceId'], 'name-test-device');
          await service.pair(
            origin: origin,
            code: '123456',
            deviceName: 'Living room iPad',
          );
          expect(requests.last['deviceName'], 'Living room iPad');
          expect(nativeReads, 1);
        } finally {
          await service.close();
          await server.close(force: true);
        }
      }, _Network());
    },
  );

  test('a reconnect advertises a renamed device without pairing or changing credentials', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      var name = 'Pixel Tablet';
      messenger.setMockMethodCallHandler(
        LokalLinkService.channel,
        (call) async => call.method == 'getDeviceName' ? name : true,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      var received = Completer<LinkMessage>();
      server.listen((request) async {
        expect(request.headers.value('x-remote-token'), 'same-pairing-token');
        expect(request.uri.path, '/api/remote/ws');
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((raw) {
          if (!received.isCompleted) received.complete(LinkMessage.decode(raw));
        });
      });
      final service = LokalLinkService();
      final credentials = LokalRemoteCredentials(
        origin: Uri(
          scheme: 'http',
          host: server.address.address,
          port: server.port,
        ),
        remoteToken: 'same-pairing-token',
        desktopId: 'desktop-name-test',
      );
      try {
        await service.connect(credentials);
        final first = await received.future.timeout(const Duration(seconds: 3));
        expect(first.type, 'hello');
        expect(first.body, {
          'capabilities': ['track_lifecycle'],
          'deviceName': 'Pixel Tablet',
        });
        await service.disconnect();
        name = 'Kitchen tablet';
        received = Completer<LinkMessage>();
        await service.connect(credentials);
        expect(
          (await received.future.timeout(const Duration(seconds: 3))).body,
          {
            'capabilities': ['track_lifecycle'],
            'deviceName': 'Kitchen tablet',
          },
        );
      } finally {
        await service.close();
        for (final socket in sockets) {
          await socket.close();
        }
        await server.close(force: true);
      }
    }, _Network());
  });

  test(
    'missing native metadata keeps ordinary legacy link commands working',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        messenger.setMockMethodCallHandler(LokalLinkService.channel, (
          call,
        ) async {
          if (call.method == 'getDeviceName') throw MissingPluginException();
          return true;
        });
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final sockets = <WebSocket>[], types = <String>[];
        server.listen((request) async {
          final socket = await WebSocketTransformer.upgrade(request);
          sockets.add(socket);
          socket.listen((raw) {
            final message = LinkMessage.decode(raw);
            types.add(message.type);
            socket.add(
              LinkMessage.create('ack', {'ok': true}, id: message.id).encode(),
            );
          });
        });
        final service = LokalLinkService();
        try {
          await service.connect(
            LokalRemoteCredentials(
              origin: Uri(
                scheme: 'http',
                host: server.address.address,
                port: server.port,
              ),
              remoteToken: 'same-pairing-token',
              desktopId: 'desktop-name-test',
            ),
          );
          expect((await service.request('queue', {})).body['ok'], isTrue);
          expect(types.where((type) => type != 'hello'), ['queue']);
          expect(types.first, 'hello');
        } finally {
          await service.close();
          for (final socket in sockets) {
            await socket.close();
          }
          await server.close(force: true);
        }
      }, _Network());
    },
  );

  test(
    'invalid platform names are ignored and Unicode names stay bounded',
    () async {
      final service = LokalLinkService();
      try {
        for (final value in <Object?>[null, 123, '', '\u0000\n ']) {
          messenger.setMockMethodCallHandler(
            LokalLinkService.channel,
            (_) async => value,
          );
          expect(await service.deviceDisplayName(), isNull);
        }
        messenger.setMockMethodCallHandler(
          LokalLinkService.channel,
          (_) async => '📱' * 101,
        );
        expect(await service.deviceDisplayName(), '📱' * 100);
        messenger.setMockMethodCallHandler(
          LokalLinkService.channel,
          (_) async => throw PlatformException(code: 'unavailable'),
        );
        expect(await service.deviceDisplayName(), isNull);
      } finally {
        await service.close();
      }
    },
  );
}
