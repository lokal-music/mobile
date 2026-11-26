import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flick/data/database.dart';
import 'package:flick/data/entities/ios_song_identity_entity.dart';
import 'package:flick/data/entities/ios_transfer_receipt_entity.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/features/link/lokal_ghost_availability.dart';
import 'package:flick/models/ios_transfer_import.dart';
import 'package:flick/models/ios_transfer_models.dart';
import 'package:flick/models/lokal_remote_state.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/songs_provider.dart';
import 'package:flick/services/ios_transfer_import_store.dart';
import 'package:flick/services/library_scanner_service.dart';
import 'package:flick/services/link/link_copy_identity.dart';
import 'package:flick/services/link/link_song_bindings.dart';
import 'package:flick/services/link/lokal_desktop_source.dart';
import 'package:flick/services/link/transfer_artifact_repair.dart';
import 'package:flick/services/lokal_paired_desktops_store.dart';
import 'package:flick/services/lokal_remote_credentials_store.dart';
import 'package:flick/services/lokal_remote_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getApplicationCachePath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

class _InMemoryCredentialsStore implements LokalRemoteCredentialsStore {
  _InMemoryCredentialsStore(this.current);
  LokalRemoteCredentials? current;

  @override
  Future<LokalRemoteCredentials?> read() async => current;

  @override
  Future<void> write(LokalRemoteCredentials credentials) async {
    current = credentials;
  }

  @override
  Future<void> clear() async {
    current = null;
  }

  @override
  Future<void> clearIfMatching(LokalRemoteCredentials? expected) async {
    current = null;
  }

  @override
  Future<LokalRemoteCredentials> relocateIfMatching(
    LokalRemoteCredentials expected,
    Uri origin,
  ) async {
    current = LokalRemoteCredentials(
      origin: origin,
      remoteToken: expected.remoteToken,
      apiKey: expected.apiKey,
      desktopId: expected.desktopId,
      desktopUserId: expected.desktopUserId,
      pairingID: expected.pairingID,
    );
    return current!;
  }
}

Future<Isar> _openTestIsar(Directory dir, String name) {
  return Isar.open(
    [
      SongEntitySchema,
      FolderEntitySchema,
      NetworkServerEntitySchema,
      IosTransferReceiptEntitySchema,
      IosSongIdentityEntitySchema,
    ],
    directory: dir.path,
    name: name,
    relaxedDurability: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final config = File('.dart_tool/package_config.json').absolute.uri;
    final packages =
        (jsonDecode(await File.fromUri(config).readAsString())
                as Map)['packages']
            as List;
    final package = packages.cast<Map>().singleWhere(
      (row) => row['name'] == 'isar_community_flutter_libs',
    );
    final root = config.resolve('${package['rootUri']}/');
    final path = root
        .resolve(Platform.isMacOS ? 'macos/libisar.dylib' : 'linux/libisar.so')
        .toFilePath();
    expect(await File(path).exists(), isTrue);
    Isar.initializeIsarCore(libraries: {Abi.current(): path});
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LinkSongBindings.instance.resetForTesting();
    TransferArtifactRepairService.instance.resetForTesting();
  });

  group('LibraryScannerService filename and artwork pointer helpers', () {
    test(
      'extractTitleFromFilename strips UUID, -rN, and [16-hex] suffixes first',
      () {
        expect(
          LibraryScannerService.extractTitleFromFilename(
            '01 - Digital Love - 11111111-2222-3333-4444-555555555555-r1.flac',
          ),
          'Digital Love',
        );
        expect(
          LibraryScannerService.extractTitleFromFilename(
            'Artist - Song (2) - 11111111-2222-3333-4444-555555555555.mp3',
          ),
          'Artist - Song',
        );
        expect(
          LibraryScannerService.extractTitleFromFilename(
            '03_Veridis_Quo [0123456789abcdef].wav',
          ),
          'Veridis Quo',
        );
      },
    );

    test(
      'canCarryArtworkPointer keeps lokal-cover:// and null existingLastModified when size matches',
      () {
        final ts = DateTime.fromMillisecondsSinceEpoch(1700000000000);
        expect(
          LibraryScannerService.canCarryArtworkPointer(
            albumArtPath: 'lokal-cover://track-99',
            isCustom: false,
            existingLastModified: ts,
            existingFileSize: 100,
            lastModified: ts.add(const Duration(minutes: 5)),
            fileSize: 200,
          ),
          isTrue,
        );
        expect(
          LibraryScannerService.canCarryArtworkPointer(
            albumArtPath: '/artwork/embedded-artwork:abc',
            isCustom: false,
            existingLastModified: null,
            existingFileSize: null,
            lastModified: ts,
            fileSize: 5000,
          ),
          isTrue,
        );
        expect(
          LibraryScannerService.canCarryArtworkPointer(
            albumArtPath: '/artwork/embedded-artwork:abc',
            isCustom: false,
            existingLastModified: null,
            existingFileSize: 5000,
            lastModified: ts,
            fileSize: 5000,
          ),
          isTrue,
        );
        expect(
          LibraryScannerService.canCarryArtworkPointer(
            albumArtPath: '/artwork/embedded-artwork:abc',
            isCustom: false,
            existingLastModified: null,
            existingFileSize: 5000,
            lastModified: ts,
            fileSize: 9999,
          ),
          isFalse,
        );
      },
    );
  });

  group('LinkCopyIdentity multi-PC bindings and cleaned keys', () {
    test(
      'resolves multi-PC LinkSongBindings even when Song.remoteServerId points to another PC',
      () async {
        await LinkSongBindings.instance.bind(
          'phone-42',
          serverId: 1,
          remoteId: 'pc1-track',
          filePath: '/music/Artist - Song.flac',
        );
        await LinkSongBindings.instance.bind(
          'phone-42',
          serverId: 2,
          remoteId: 'pc2-track',
          filePath: '/music/Artist - Song.flac',
        );

        // Song.remoteServerId in Isar only stores server 2, but PC 1 lookup still finds pc1-track!
        const phoneSong = Song(
          id: 'phone-42',
          title: 'Locally Edited Title',
          artist: 'Locally Edited Artist',
          duration: Duration(seconds: 200),
          fileType: 'FLAC',
          filePath: '/music/Artist - Song.flac',
          remoteServerId: 2,
          remoteId: 'pc2-track',
        );

        final pc1Identity = LinkCopyIdentity(
          serverId: 1,
          tracks: const [
            {
              'id': 'pc1-track',
              'title': 'Original Song',
              'artist': 'Original Artist',
              'duration': 200,
            },
          ],
        );
        expect(pc1Identity.candidates(phoneSong), ['pc1-track']);
        expect(
          pc1Identity.resolverKey(phoneSong),
          'original artist|original song|200',
        );
      },
    );

    test(
      'cleans transfer artifacts in phone and desktop metadata for _byName fallback',
      () {
        final identity = LinkCopyIdentity(
          serverId: 5,
          tracks: const [
            {
              'id': 'pc-clean',
              'title': 'Voyager [0123456789abcdef]',
              'artist': 'Daft Punk',
              'duration': 227,
            },
          ],
        );
        const corruptPhone = Song(
          id: 'phone-99',
          title:
              'Daft Punk - Voyager - 11111111-2222-3333-4444-555555555555-r1',
          artist: '<unknown>',
          duration: Duration(seconds: 227),
          fileType: 'FLAC',
          filePath: '/music/Voyager.flac',
        );
        expect(identity.candidates(corruptPhone), ['pc-clean']);
      },
    );
  });

  group('Multi-PC provider consistency (songsProvider / albums / artists)', () {
    test(
      'songsProvider, songsByAlbumProvider, and songsByArtistProvider deduplicate phone + multi-PC lokal:// rows',
      () async {
        final dir = await Directory.systemTemp.createTemp('lokal-multipcdedup-');
        final isar = await _openTestIsar(dir, 'multipcdedup');
        addTearDown(() async {
          await isar.close();
          await dir.delete(recursive: true);
        });

        final repo = SongRepository(isar: isar, iosImportSafety: false);
        await repo.upsertSongs([
          // Shared track on phone + PC 1 + PC 2 -> phone copy wins everywhere
          SongEntity()
            ..filePath = '/storage/emulated/0/Music/Daft Punk - One More Time.flac'
            ..title = 'One More Time'
            ..artist = 'Daft Punk'
            ..album = 'Discovery'
            ..durationMs = 320000
            ..fileType = 'FLAC'
            ..dateAdded = DateTime.utc(2026, 1, 1),
          SongEntity()
            ..filePath = 'lokal://1/omt-pc1'
            ..title = 'One More Time'
            ..artist = 'Daft Punk'
            ..album = 'Discovery'
            ..durationMs = 320500
            ..fileType = 'FLAC'
            ..sourceType = 'lokal'
            ..remoteServerId = 1
            ..remoteId = 'omt-pc1'
            ..dateAdded = DateTime.utc(2026, 1, 2),
          SongEntity()
            ..filePath = 'lokal://2/omt-pc2'
            ..title = 'One More Time'
            ..artist = 'Daft Punk'
            ..album = 'Discovery'
            ..durationMs = 320000
            ..fileType = 'MP3'
            ..sourceType = 'lokal'
            ..remoteServerId = 2
            ..remoteId = 'omt-pc2'
            ..dateAdded = DateTime.utc(2026, 1, 3),
          // Remote-only track on PC 1 (16-bit) and PC 2 (24-bit) -> only PC 2 kept
          SongEntity()
            ..filePath = 'lokal://1/aerodynamic-pc1'
            ..title = 'Aerodynamic'
            ..artist = 'Daft Punk'
            ..album = 'Discovery'
            ..durationMs = 212000
            ..fileType = 'FLAC'
            ..bitDepth = 16
            ..sampleRate = 44100
            ..sourceType = 'lokal'
            ..remoteServerId = 1
            ..remoteId = 'aero-1'
            ..dateAdded = DateTime.utc(2026, 1, 4),
          SongEntity()
            ..filePath = 'lokal://2/aerodynamic-pc2'
            ..title = 'Aerodynamic'
            ..artist = 'Daft Punk'
            ..album = 'Discovery'
            ..durationMs = 212400
            ..fileType = 'FLAC'
            ..bitDepth = 24
            ..sampleRate = 96000
            ..sourceType = 'lokal'
            ..remoteServerId = 2
            ..remoteId = 'aero-2'
            ..dateAdded = DateTime.utc(2026, 1, 5),
        ]);

        final container = ProviderContainer(
          overrides: [
            songRepositoryProvider.overrideWithValue(repo),
            songLibraryWatchProvider.overrideWithValue(const Stream.empty()),
          ],
        );
        addTearDown(container.dispose);

        final songsState = await container.read(songsProvider.future);
        expect(songsState.songs.length, 2);
        expect(
          songsState.songs.map((s) => s.filePath).toSet(),
          {
            '/storage/emulated/0/Music/Daft Punk - One More Time.flac',
            'lokal://2/aerodynamic-pc2',
          },
        );

        final albums = await container.read(songsByAlbumProvider.future);
        expect(albums.length, 1);
        expect(albums.single.albumName, 'Discovery');
        expect(albums.single.songs.length, 2);

        final artists = await container.read(songsByArtistProvider.future);
        expect(artists.keys.toList(), ['Daft Punk']);
        expect(artists['Daft Punk']!.length, 2);
      },
    );
  });

  group('TransferArtifactRepairService & IosTransferImportStore.commit', () {
    test(
      'repairIfNeeded is a safe no-op when Database is not initialized',
      () async {
        expect(Database.isInitialized, isFalse);
        await TransferArtifactRepairService.instance.repairIfNeeded();
      },
    );

    test(
      'repairs corrupted titles/artists and renames legacy UUID/[16-hex] files in-place while preserving IDs and skipping iOS operation paths',
      () async {
        final dir = await Directory.systemTemp.createTemp('lokal-repair-');
        final musicDir = await Directory(p.join(dir.path, 'Music')).create();
        final iosCopiesDir = await Directory(
          p.join(dir.path, 'Desktop Copies'),
        ).create();
        final isar = await _openTestIsar(dir, 'repair');
        addTearDown(() async {
          await isar.close();
          await dir.delete(recursive: true);
        });

        const uuid = '11111111-2222-3333-4444-555555555555';
        final legacyFile1 = await File(
          p.join(musicDir.path, 'Justice - Genesis - $uuid.flac'),
        ).writeAsBytes([1, 2, 3, 4]);
        // Pre-existing file to trigger (2) collision suffix on second legacy file:
        await File(
          p.join(musicDir.path, 'Justice - Phantom.flac'),
        ).writeAsBytes([9, 9, 9]);
        final legacyFile2 = await File(
          p.join(musicDir.path, 'Phantom [0123456789abcdef].flac'),
        ).writeAsBytes([5, 6, 7, 8]);
        final iosProtectedFile = await File(
          p.join(iosCopiesDir.path, 'Stress - $uuid-r1.flac'),
        ).writeAsBytes([10, 11, 12]);

        late int id1, id2, idIos;
        await isar.writeTxn(() async {
          id1 = await isar.songEntitys.put(
            SongEntity()
              ..filePath = legacyFile1.path
              ..title = 'Justice - Genesis - $uuid'
              ..artist = '<unknown>'
              ..fileType = 'FLAC'
              ..dateAdded = DateTime.utc(2026, 1, 1),
          );
          id2 = await isar.songEntitys.put(
            SongEntity()
              ..filePath = legacyFile2.path
              ..title = 'Phantom [0123456789abcdef]'
              ..artist = 'Justice'
              ..fileType = 'FLAC'
              ..dateAdded = DateTime.utc(2026, 1, 2),
          );
          idIos = await isar.songEntitys.put(
            SongEntity()
              ..filePath = iosProtectedFile.path
              ..title = 'Justice - Stress - $uuid-r1'
              ..artist = 'Unknown Artist'
              ..fileType = 'FLAC'
              ..dateAdded = DateTime.utc(2026, 1, 3),
          );
        });

        await LinkSongBindings.instance.bind(
          id1.toString(),
          serverId: 1,
          remoteId: 'pc-genesis',
          filePath: legacyFile1.path,
        );

        final indexedPaths = <String>[];
        var runs = 0;
        final repair = TransferArtifactRepairService(
          isar: isar,
          indexMedia: (paths) async {
            runs++;
            indexedPaths.addAll(paths);
          },
        );

        await repair.repairIfNeeded();
        // Second invocation in same session is idempotent.
        await repair.repairIfNeeded();
        expect(runs, 1);

        final repaired1 = (await isar.songEntitys.get(id1))!;
        expect(repaired1.id, id1);
        expect(repaired1.artist, 'Justice');
        expect(repaired1.title, 'Genesis');
        expect(repaired1.hasLocalEdits, isTrue);
        expect(repaired1.fileSize, 4);
        expect(repaired1.lastModified, isNotNull);
        expect(
          repaired1.filePath,
          p.join(musicDir.path, 'Justice - Genesis.flac'),
        );
        expect(await File(repaired1.filePath).exists(), isTrue);
        expect(await legacyFile1.exists(), isFalse);
        expect(
          (await LinkSongBindings.instance.getBinding(id1.toString()))
              ?.filePath,
          repaired1.filePath,
        );

        final repaired2 = (await isar.songEntitys.get(id2))!;
        expect(repaired2.id, id2);
        expect(repaired2.artist, 'Justice');
        expect(repaired2.title, 'Phantom');
        expect(repaired2.hasLocalEdits, isTrue);
        expect(
          repaired2.filePath,
          p.join(musicDir.path, 'Justice - Phantom (2).flac'),
        );
        expect(await File(repaired2.filePath).exists(), isTrue);
        expect(await legacyFile2.exists(), isFalse);

        // iOS operation key path is NOT renamed on disk, though its DB metadata is cleaned!
        final repairedIos = (await isar.songEntitys.get(idIos))!;
        expect(repairedIos.filePath, iosProtectedFile.path);
        expect(await iosProtectedFile.exists(), isTrue);
        expect(repairedIos.artist, 'Justice');
        expect(repairedIos.title, 'Stress');
        expect(repairedIos.hasLocalEdits, isTrue);
        expect(indexedPaths, contains(repaired1.filePath));
        expect(indexedPaths, contains(repaired2.filePath));
      },
    );

    test(
      'IosTransferImportStore.commit records actual file mtime/size and sets hasLocalEdits=true when untagged',
      () async {
        final dir = await Directory.systemTemp.createTemp('lokal-ios-commit-');
        final musicRoot = await Directory(p.join(dir.path, 'Music')).create();
        final copiesDir = await Directory(
          p.join(musicRoot.path, 'Desktop Copies'),
        ).create();
        final isar = await _openTestIsar(dir, 'ios_commit');
        addTearDown(() async {
          await isar.close();
          await dir.delete(recursive: true);
        });

        final intentRaw = Map<String, dynamic>.from(
          (jsonDecode(
                File(
                  'test/fixtures/ios_transfer_intents_v1.json',
                ).readAsStringSync(),
              ) as List)
              .single as Map,
        );
        final jobId = intentRaw['id'] as String;
        final identityMap = Map<String, dynamic>.from(
          intentRaw['identity'] as Map,
        );

        late int serverId;
        await isar.writeTxn(() async {
          serverId = await isar.networkServerEntitys.put(
            NetworkServerEntity()
              ..protocol = 'lokal'
              ..label = 'Desktop'
              ..baseUrl = identityMap['origin'] as String
              ..username =
                  '${identityMap['desktopID']}:${identityMap['desktopUserID'] ?? 'guest'}',
          );
        });
        identityMap['localServerID'] = serverId;
        identityMap.remove('localSongID');
        intentRaw['identity'] = identityMap;
        intentRaw['expectedBytes'] = 12;
        intentRaw['expectedSHA256'] = 'a' * 64;

        final relativePath = 'Desktop Copies/Fixture - $jobId-r1.flac';
        final physicalFile = File(
          p.join(copiesDir.path, 'Fixture - $jobId-r1.flac'),
        );
        await physicalFile.writeAsBytes(List<int>.filled(12, 7));
        final customMtime = DateTime.fromMillisecondsSinceEpoch(1710000000000);
        physicalFile.setLastModifiedSync(customMtime);

        final store = IosTransferImportStore(
          isar,
          musicRoot: musicRoot.path,
          now: () => DateTime.fromMillisecondsSinceEpoch(1790000000000),
        );

        final validatingJob = IosTransferJob.fromJson({
          ...intentRaw,
          'direction': 'download',
          'revision': 1,
          'updatedMs': 2000,
          'phase': 'validating',
          'receivedBytes': 12,
          'receivedSHA256': 'a' * 64,
        });
        final target = IosTransferLibraryTarget(relativePath);
        const media = IosTransferMediaInfo(
          recognized: true,
          codec: 'FLAC',
          format: 'FLAC',
          durationMs: 180000,
          sampleRate: 44100,
          bitDepth: 16,
          bitrate: 900,
          channels: 2,
        );

        await store.prepare(
          validatingJob,
          target,
          isCurrent: () => true,
          validateOwnership: () async {},
        );
        await store.recordMediaValidation(
          validatingJob,
          target,
          media,
          isCurrent: () => true,
          validateOwnership: () async {},
        );

        final importingJob = IosTransferJob.fromJson({
          ...intentRaw,
          'direction': 'download',
          'revision': 1,
          'updatedMs': 3000,
          'phase': 'importing',
          'receivedBytes': 12,
          'receivedSHA256': 'a' * 64,
        });
        final receipt = IosTransferLibraryReceipt(
          relativePath: relativePath,
          bytes: 12,
          sha256: 'a' * 64,
        );

        final committed = await store.commit(
          importingJob,
          receipt,
          media,
          isCurrent: () => true,
          validateOwnership: () async {},
        );

        expect(committed.committed, isTrue);
        expect(committed.song!.fileSize, 12);
        expect(
          committed.song!.lastModified,
          physicalFile.statSync().modified,
        );
        expect(committed.song!.hasLocalEdits, isTrue);
      },
    );
  });

  group('LokalDesktopSource upload cleaning & multi-PC paired availability', () {
    test(
      'uploadToDesktop cleans legacy UUID originalFilename & metadata and records sha256 in LinkSongBindings',
      () async {
        final dir = await Directory.systemTemp.createTemp('lokal-clean-upload-');
        addTearDown(() => dir.delete(recursive: true));

        const uuid = '11111111-2222-3333-4444-555555555555';
        final audioBytes = [102, 76, 97, 67, 1, 2, 3, 4, 5];
        final legacyFile = await File(
          p.join(dir.path, 'Daft Punk - Harder Better - $uuid.flac'),
        ).writeAsBytes(audioBytes);

        final credentials = LokalRemoteCredentials(
          origin: Uri.parse('http://desktop.local:3000'),
          remoteToken: 'token-1',
          desktopId: 'pc-1',
        );
        final source = LokalDesktopSource(
          uploadClientFactory: () =>
              MockClient.streaming((request, stream) async {
                final metadata = jsonDecode(
                  utf8.decode(
                    base64Url.decode(request.headers['x-link-metadata']!),
                  ),
                ) as Map;
                expect(metadata['artist'], 'Daft Punk');
                expect(metadata['title'], 'Harder Better');
                expect(
                  metadata['originalFilename'],
                  'Daft Punk - Harder Better.flac',
                );
                await stream.drain<void>();
                return http.StreamedResponse(
                  Stream.value(utf8.encode('{"ok":true,"trackId":"pc-hb-1"}')),
                  200,
                );
              }),
        );

        await source.uploadToDesktop(
          Song(
            id: '77',
            title: 'Daft Punk - Harder Better - $uuid',
            artist: '<unknown>',
            duration: const Duration(minutes: 3),
            fileType: 'FLAC',
            filePath: legacyFile.path,
          ),
          credentials,
        );

        final binding = await LinkSongBindings.instance.getBinding('77');
        expect(binding, isNotNull);
        expect(binding!.sha256, sha256.convert(audioBytes).toString());
        expect(binding.filePath, legacyFile.path);
      },
    );

    test(
      'LokalDesktopSource and lokalPairedDesktopsStore fallback resolve PC 1 credentials when PC 2 is active',
      () async {
        final dir = await Directory.systemTemp.createTemp('lokal-multipc-cred-');
        final prevPaths = PathProviderPlatform.instance;
        PathProviderPlatform.instance = _TempPathProvider(dir.path);
        addTearDown(() async {
          PathProviderPlatform.instance = prevPaths;
          await dir.delete(recursive: true);
        });

        FlutterSecureStorage.setMockInitialValues({});
        final pc1 = LokalRemoteCredentials(
          origin: Uri.parse('http://192.168.1.10:7860'),
          remoteToken: 'token-pc1',
          desktopId: 'desktop-1',
          pairingID: '11111111-1111-4111-8111-111111111111',
        );
        final pc2 = LokalRemoteCredentials(
          origin: Uri.parse('http://192.168.1.20:7860'),
          remoteToken: 'token-pc2',
          desktopId: 'desktop-2',
          pairingID: '22222222-2222-4222-8222-222222222222',
        );

        final pairedStore = LokalPairedDesktopsStore(
          storage: const FlutterSecureStorage(),
        );
        await pairedStore.add(pc1);
        await pairedStore.add(pc2); // pc2 is active in paired store!

        final activeStore = SecureLokalRemoteCredentialsStore(
          secureStorage: const FlutterSecureStorage(),
        );
        await activeStore.write(pc2); // pc2 is active in legacy store too!
        expect((await activeStore.read())?.desktopId, 'desktop-2');

        final server1 = NetworkServerEntity()
          ..id = 101
          ..protocol = 'lokal'
          ..label = 'PC 1'
          ..baseUrl = 'http://192.168.1.10:7860'
          ..username = 'desktop-1:guest';

        final descriptor = await LokalDesktopSource.instance.streamDescriptor(
          server1,
          'track-on-pc1',
        );
        expect(descriptor, isNotNull);
        expect(descriptor!.url, 'http://192.168.1.10:7860/api/stream/track-on-pc1');
        expect(descriptor.headers['x-remote-token'], 'token-pc1');

        final inMemoryActive = _InMemoryCredentialsStore(pc2);
        expect((await inMemoryActive.read())?.desktopId, 'desktop-2');

        final allPaired = await pairedStore.readAll();
        final matchedPc1 = allPaired.firstWhere(
          (d) => desktopStreamingCredentialsMatch(
            storedUsername: 'desktop-1:guest',
            storedBaseUrl: 'http://192.168.1.10:7860/',
            desktopId: d.credentials.desktopId,
            desktopUserId: d.credentials.desktopUserId,
            credentialOrigin: d.credentials.origin.toString(),
          ),
        );
        expect(matchedPc1.credentials.remoteToken, 'token-pc1');

        final service = LokalRemoteService(
          client: MockClient((req) async {
            expect(req.url.origin, 'http://192.168.1.10:7860');
            expect(req.headers['x-remote-token'], 'token-pc1');
            return http.Response(jsonEncode({'playing': false}), 200);
          }),
        );
        addTearDown(service.close);
        expect(
          await desktopHttpReachable(
            () async => service.fetchState(matchedPc1.credentials),
          ),
          isTrue,
        );
      },
    );
  });
}
