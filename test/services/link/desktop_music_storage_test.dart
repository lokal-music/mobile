import 'dart:io';

import 'package:flick/data/entities/song_entity.dart';
import 'package:flick/services/link/desktop_music_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, music;
  late File source;
  SongEntity row() => SongEntity()
    ..id = 42
    ..filePath = source.path
    ..folderUri = source.parent.path
    ..title = '駅/../Song'
    ..artist = 'Artist'
    ..album = 'Album'
    ..dateAdded = DateTime(2026)
    ..fileType = 'FLAC'
    ..sampleRate = 96000
    ..bitDepth = 24
    ..remoteId = 'pc-song'
    ..remoteServerId = 3;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('desktop_music_storage');
    music = await Directory(p.join(root.path, 'chosen-music')).create();
    source = await File(p.join(root.path, 'private.flac'))
        .writeAsBytes([0, 1, 2, 3, 255]);
  });
  tearDown(() async => root.delete(recursive: true));
  test('recovers exact bytes to the chosen library folder and preserves song identity and quality', () async {
    final entity = row();
    final indexed = <String>[];
    final store = DesktopMusicStorage(
      folders: () async => [DesktopMusicFolder('chosen-uri', path: music.path)],
      indexMedia: (paths) async => indexed.addAll(paths),
    );
    SongEntity? saved;
    await store.saveEntity(entity, persist: (r) async => saved = r);
    expect(saved?.id, 42);
    expect(p.dirname(entity.filePath), p.join(music.path, 'Artist', 'Album'));
    expect(p.basename(entity.filePath), 'Artist - 駅 .. Song.flac');
    expect(
      RegExp(
        r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
        caseSensitive: false,
      ).hasMatch(p.basename(entity.filePath)),
      isFalse,
    );
    expect(entity.folderUri, 'chosen-uri');
    expect(entity.relativeFolderPath, 'Artist/Album');
    expect(entity.remoteId, 'pc-song');
    expect(entity.remoteServerId, 3);
    expect(entity.sampleRate, 96000);
    expect(entity.bitDepth, 24);
    expect(entity.album, 'Album');
    expect(entity.fileSize, source.lengthSync());
    expect(entity.lastModified, isNotNull);
    expect(File(entity.filePath).readAsBytesSync(), source.readAsBytesSync());
    expect(indexed, [entity.filePath]);
    expect(
      source.existsSync(),
      isTrue,
      reason: 'old queued playback and recovery retain their input',
    );
  });
  test('no selected folder fails explicitly and does not persist app-private paths', () async {
    var persisted = false;
    final store = DesktopMusicStorage(
      folders: () async => [],
      indexMedia: (_) async {},
    );
    await expectLater(
      store.saveEntity(
        row(),
        persist: (_) async {
          persisted = true;
        },
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Choose a music folder'),
        ),
      ),
    );
    expect(persisted, isFalse);
    expect(source.existsSync(), isTrue);
  });
  test('SAF-only folder stores its granted document URI for playback and future scans', () async {
    const channel = MethodChannel('test/desktop-copy-saf');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return {'uri': 'content://documents/tree/music/document/song.flac'};
        });
    final store = DesktopMusicStorage(
      channel: channel,
      folders: () async => [
        const DesktopMusicFolder('content://documents/tree/music'),
      ],
      indexMedia: (_) async {},
    );
    final entity = row();
    await store.saveEntity(entity, persist: (_) async {});
    expect(
      entity.filePath,
      'content://documents/tree/music/document/song.flac',
    );
    expect(entity.mediaStoreUri, entity.filePath);
    expect(entity.folderUri, 'content://documents/tree/music');
    expect(calls.single.method, 'copyMusicToFolder');
    expect((calls.single.arguments as Map)['sourcePath'], source.path);
    expect((calls.single.arguments as Map)['directorySegments'], [
      'Artist',
      'Album',
    ]);
    expect(
      (calls.single.arguments as Map)['fileName'],
      'Artist - 駅 .. Song.flac',
    );
  });
  test('revoked folder grant fails without falling back to app data', () async {
    const channel = MethodChannel('test/desktop-copy-revoked');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'MUSIC_COPY_FAILED'),
        );
    final store = DesktopMusicStorage(
      channel: channel,
      folders: () async => [
        const DesktopMusicFolder('content://documents/tree/music'),
      ],
      indexMedia: (_) async {},
    );
    await expectLater(
      store.saveEntity(row(), persist: (_) async => fail('must not persist')),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Re-select'),
        ),
      ),
    );
    expect(source.readAsBytesSync(), [0, 1, 2, 3, 255]);
  });
  test(
    'failed database save restores the old row and removes the new copy',
    () async {
      final entity = row();
      final store = DesktopMusicStorage(
        folders: () async => [
          DesktopMusicFolder('chosen-uri', path: music.path),
        ],
        indexMedia: (_) async => fail('do not index an uncommitted copy'),
      );
      await expectLater(
        store.saveEntity(
          entity,
          persist: (_) async => throw StateError('db failure'),
        ),
        throwsStateError,
      );
      expect(entity.filePath, source.path);
      expect(entity.folderUri, source.parent.path);
      expect(entity.mediaStoreUri, isNull);
      expect(
        Directory(p.join(music.path, 'Artist', 'Album')).listSync(),
        isEmpty,
      );
      expect(source.existsSync(), isTrue);
    },
  );
  test('same-named songs use clean Artist - Title.ext and (2) collision suffix without overwriting', () async {
    final store = DesktopMusicStorage(
      folders: () async => [DesktopMusicFolder('chosen-uri', path: music.path)],
      indexMedia: (_) async {},
    );
    final a = await store.save(
      source,
      title: 'Song - 11111111-2222-3333-4444-555555555555',
      artist: 'Artist',
      extension: 'flac',
    );
    final b = await store.save(
      source,
      title: 'Song [0123456789abcdef]',
      artist: 'Artist',
      extension: 'flac',
    );
    final c = await store.save(
      source,
      title: 'Artist - Song',
      artist: '<unknown>',
      extension: 'flac',
    );
    expect(p.basename(a.path), 'Artist - Song.flac');
    expect(p.basename(b.path), 'Artist - Song (2).flac');
    expect(p.basename(c.path), 'Artist - Song (3).flac');
    expect(a.path, isNot(b.path));
    expect(File(a.path).readAsBytesSync(), File(b.path).readAsBytesSync());
    expect(File(a.path).readAsBytesSync(), File(c.path).readAsBytesSync());
  });
}
