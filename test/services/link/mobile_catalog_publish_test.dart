import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flick/data/database.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/models/lokal_remote_state.dart';
import 'package:flick/services/favorites_service.dart';
import 'package:flick/services/link/link_protocol.dart';
import 'package:flick/services/link/link_sync_coordinator.dart';
import 'package:flick/services/link/lokal_link_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _initializeIsarCore() {
  final config = File('.dart_tool/package_config.json').absolute.uri;
  final packages =
      (jsonDecode(File.fromUri(config).readAsStringSync()) as Map)['packages']
          as List;
  final library = packages.cast<Map>().singleWhere(
    (entry) => entry['name'] == 'isar_community_flutter_libs',
  );
  final root = config.resolve('${library['rootUri']}/');
  final binary = Platform.isMacOS
      ? 'macos/libisar.dylib'
      : Platform.isWindows
      ? 'windows/isar.dll'
      : 'linux/libisar.so';
  Isar.initializeIsarCore(
    libraries: {Abi.current(): root.resolve(binary).toFilePath()},
  );
}

class _CapturingLinkService extends LokalLinkService {
  final List<({String type, Map<String, dynamic> body})> requests = [];

  @override
  bool get connected => true;

  @override
  bool get supportsMobileCatalog => true;

  @override
  Future<LinkMessage> request(String type, Map<String, dynamic> body) async {
    requests.add((type: type, body: body));
    return LinkMessage.create('ack', {'ok': true});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _initializeIsarCore();

  late Directory tempDir;
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('mobile_catalog_publish_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (_) async => tempDir.path);
    await Database.init();
  });

  tearDown(() async {
    await Database.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('publishes Android content://, file://, mediaStoreUri fallback and filesystem songs while skipping remote/ghost rows', () async {
    final realFile = File('${tempDir.path}/direct.flac');
    await realFile.writeAsBytes(const [1, 2, 3, 4]);

    final fileUriTarget = File('${tempDir.path}/uri_song.mp3');
    await fileUriTarget.writeAsBytes(const [5, 6, 7, 8]);

    final now = DateTime.now();
    await Database.instance.writeTxn(() async {
      await Database.songs.putAll([
        SongEntity()
          ..filePath = realFile.path
          ..title = 'Direct File'
          ..artist = 'Artist A'
          ..album = 'Album A'
          ..durationMs = 180000
          ..dateAdded = now,
        SongEntity()
          ..filePath = fileUriTarget.uri.toString()
          ..title = 'File URI Song'
          ..artist = 'Artist B'
          ..album = 'Album B'
          ..durationMs = 200000
          ..dateAdded = now,
        SongEntity()
          ..filePath = 'content://com.android.externalstorage.documents/tree/primary%3AMusic/document/primary%3AMusic%2Fsaf_song.flac'
          ..title = 'SAF Scoped Song'
          ..artist = 'Artist C'
          ..album = 'Album C'
          ..albumArtist = 'Owner C'
          ..trackNumber = 3
          ..discNumber = 1
          ..year = 2025
          ..genre = 'Electronic'
          ..durationMs = 240000
          ..dateAdded = now,
        SongEntity()
          ..filePath = '${tempDir.path}/scoped_unreadable_path.m4a'
          ..mediaStoreUri = 'content://media/external/audio/media/42'
          ..title = 'MediaStore Fallback Song'
          ..artist = 'Artist D'
          ..durationMs = 210000
          ..dateAdded = now,
        SongEntity()
          ..filePath = '${tempDir.path}/missing_without_uri.flac'
          ..title = 'Deleted Local Song'
          ..artist = 'Artist E'
          ..durationMs = 190000
          ..dateAdded = now,
        SongEntity()
          ..filePath = 'lokal://1/desktop-track'
          ..sourceType = 'lokal'
          ..remoteServerId = 1
          ..remoteId = 'desktop-track'
          ..title = 'Desktop Stream'
          ..artist = 'Artist F'
          ..durationMs = 175000
          ..dateAdded = now,
        SongEntity()
          ..filePath = 'ghost://desktop/1/ghost-track'
          ..title = 'Desktop Ghost'
          ..artist = 'Artist G'
          ..durationMs = 160000
          ..dateAdded = now,
      ]);
    });

    final socket = _CapturingLinkService();
    final coordinator = LinkSyncCoordinator(
      socket: socket,
      credentials: LokalRemoteCredentials(
        origin: Uri.parse('http://127.0.0.1:3421'),
        remoteToken: 'token-1234567890',
        desktopId: 'desktop-peer-1',
      ),
      favorites: FavoritesService(songRepository: SongRepository()),
    );

    await coordinator.publishMobileCatalogForTesting();

    expect(socket.requests.length, 1);
    final push = socket.requests.single;
    expect(push.type, 'catalog.push');
    expect(push.body['complete'], true);
    final items = (push.body['items'] as List).cast<Map<String, dynamic>>();
    expect(items.map((item) => item['title']).toList(), [
      'Direct File',
      'File URI Song',
      'MediaStore Fallback Song',
      'SAF Scoped Song',
    ]);
    final safItem = items.singleWhere(
      (item) => item['title'] == 'SAF Scoped Song',
    );
    expect(safItem['album_artist'], 'Owner C');
    expect(safItem['track_num'], 3);
    expect(safItem['disc_num'], 1);
    expect(safItem['year'], 2025);
    expect(safItem['genre'], 'Electronic');
    expect(safItem['duration'], 240);
  });
}
