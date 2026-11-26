import 'dart:convert';
import 'dart:io';

import 'package:flick/services/link/link_audio_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late HttpClient client;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lokal-link-audio-');
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await LinkAudioServer.instance.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('serves byte ranges without transferring the full phone file', () async {
    final file = File('${directory.path}/sample.flac');
    await file.writeAsString('abcdefghijklmnopqrstuvwxyz');
    final uri = Uri.parse(await LinkAudioServer.instance.publish(file.path));

    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=5-9');
    final response = await request.close();

    expect(response.statusCode, HttpStatus.partialContent);
    expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
    expect(response.headers.value(HttpHeaders.contentRangeHeader), 'bytes 5-9/26');
    expect(response.headers.value(HttpHeaders.contentLengthHeader), '5');
    expect(await utf8.decoder.bind(response).join(), 'fghij');
  });

  test('rejects unknown stream tokens', () async {
    final file = File('${directory.path}/sample.mp3');
    await file.writeAsString('audio');
    final uri = Uri.parse(await LinkAudioServer.instance.publish(file.path));
    final invalid = uri.replace(path: '/z' + uri.path.substring(2));

    final response = await (await client.getUrl(invalid)).close();
    expect(response.statusCode, HttpStatus.notFound);
    await response.drain<void>();
  });

  test('supports HEAD without returning audio bytes', () async {
    final file = File('${directory.path}/sample.wav');
    await file.writeAsString('12345678');
    final uri = Uri.parse(await LinkAudioServer.instance.publish(file.path));

    final response = await (await client.headUrl(uri)).close();
    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.value(HttpHeaders.contentLengthHeader), '8');
    expect(await response.drain<List<int>>(), isEmpty);
  });
}
