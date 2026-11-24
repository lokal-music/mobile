import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flick/data/entities/folder_entity.dart';
import 'package:flick/data/entities/ios_song_identity_entity.dart';
import 'package:flick/data/entities/ios_transfer_receipt_entity.dart';
import 'package:flick/data/entities/song_entity.dart';
import 'package:flick/data/repositories/folder_repository.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/providers/songs_provider.dart';
import 'package:flick/services/fingerprint_cache_service.dart';
import 'package:flick/services/ios_library_scan_epoch.dart';
import 'package:flick/services/library_scanner_service.dart';
import 'package:flick/services/music_folder_service.dart';
import 'package:flick/services/permission_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePermissionService extends PermissionService {
  _FakePermissionService({required this.pickedUri});

  String? pickedUri;
  final List<String> persistedUris = [];

  @override
  Future<String?> openFolderPicker() async => pickedUri;

  @override
  Future<bool> takePersistablePermission(String uri) async {
    persistedUris.add(uri);
    return true;
  }
}

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

Future<Isar> _openTestIsar(
  Directory dir,
  String name, {
  bool withIosSchemas = false,
}) {
  return Isar.open(
    [
      SongEntitySchema,
      FolderEntitySchema,
      if (withIosSchemas) IosTransferReceiptEntitySchema,
      if (withIosSchemas) IosSongIdentityEntitySchema,
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

  group('LibraryScannerService.shouldFallbackRustScanToSaf', () {
    test('falls back to SAF on Android when Rust finds 0 readable files', () {
      const safUri =
          'content://com.android.externalstorage.documents/tree/primary%3AMusic';
      expect(
        LibraryScannerService.shouldFallbackRustScanToSaf(
          isAndroid: true,
          folderUri: safUri,
          totalFiles: 0,
          processedSongs: 0,
          existingRawSongs: 0,
        ),
        isTrue,
      );
      expect(
        LibraryScannerService.shouldFallbackRustScanToSaf(
          isAndroid: true,
          folderUri: safUri,
          totalFiles: 12,
          processedSongs: 0,
          existingRawSongs: 0,
        ),
        isTrue,
      );
    });

    test('does not fall back when songs were indexed or non-Android/non-SAF', () {
      const safUri =
          'content://com.android.externalstorage.documents/tree/primary%3AMusic';
      expect(
        LibraryScannerService.shouldFallbackRustScanToSaf(
          isAndroid: true,
          folderUri: safUri,
          totalFiles: 12,
          processedSongs: 12,
          existingRawSongs: 0,
        ),
        isFalse,
      );
      expect(
        LibraryScannerService.shouldFallbackRustScanToSaf(
          isAndroid: true,
          folderUri: safUri,
          totalFiles: 12,
          processedSongs: 0,
          existingRawSongs: 12,
        ),
        isFalse,
      );
      expect(
        LibraryScannerService.shouldFallbackRustScanToSaf(
          isAndroid: false,
          folderUri: safUri,
          totalFiles: 0,
          processedSongs: 0,
          existingRawSongs: 0,
        ),
        isFalse,
      );
      expect(
        LibraryScannerService.shouldFallbackRustScanToSaf(
          isAndroid: true,
          folderUri: '/storage/emulated/0/Music',
          totalFiles: 0,
          processedSongs: 0,
          existingRawSongs: 0,
        ),
        isFalse,
      );
    });
  });

  group('MusicFolderService.addFolder re-selection after clear', () {
    test(
      'returns existing folder and refreshes permission when same folder is re-picked',
      () async {
        const folderUri =
            'content://com.android.externalstorage.documents/tree/primary%3AMusic';
        final existing = MusicFolder(
          uri: folderUri,
          displayName: 'Music',
          dateAdded: DateTime.utc(2026, 1, 1),
        );
        SharedPreferences.setMockInitialValues({
          'music_folders': [jsonEncode(existing.toJson())],
        });

        final dir = await Directory.systemTemp.createTemp('lokal-addfolder-');
        final isar = await _openTestIsar(dir, 'folders');
        addTearDown(() async {
          await isar.close();
          await dir.delete(recursive: true);
        });

        final folderRepo = FolderRepository(isar: isar);
        final permissions = _FakePermissionService(pickedUri: folderUri);
        final service = MusicFolderService(
          permissionService: permissions,
          folderRepository: folderRepo,
        );

        final returned = await service.addFolder();
        expect(returned, isNotNull);
        expect(returned!.uri, folderUri);
        expect(permissions.persistedUris, [folderUri]);
        // Also ensures the folder is backfilled into FolderRepository if missing.
        expect(await folderRepo.getFolderByUri(folderUri), isNotNull);

        // Picking a different overlapping child folder still throws.
        permissions.pickedUri =
            'content://com.android.externalstorage.documents/tree/primary%3AMusic%2FSub';
        await expectLater(
          service.addFolder(),
          throwsA(isA<FolderAlreadyExistsException>()),
        );
      },
    );
  });

  group('FileFingerprintCache.clearAll', () {
    test('clears both disk and shared in-memory cache across instances', () async {
      final dir = await Directory.systemTemp.createTemp('lokal-fp-');
      final previousPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TempPathProvider(dir.path);
      addTearDown(() async {
        await FileFingerprintCache().clearAll();
        PathProviderPlatform.instance = previousPaths;
        if (dir.existsSync()) await dir.delete(recursive: true);
      });

      const folderUri = 'content://tree/primary%3AMusic';
      final writer = FileFingerprintCache();
      await writer.save(folderUri, {'/music/a.flac': 12345});
      expect(await writer.load(folderUri), {'/music/a.flac': 12345});

      // Clear through a separate instance (as Clear library does).
      await FileFingerprintCache().clearAll();

      expect(await writer.load(folderUri), isNull);
    });
  });

  group('Native Isar clear -> rescan reactivity & folder stats', () {
    test(
      'watchSongs survives autoDispose re-subscription and surfaces rescanned songs after clear',
      () async {
        SharedPreferences.setMockInitialValues({});
        final dir = await Directory.systemTemp.createTemp('lokal-rescan-');
        final isar = await _openTestIsar(dir, 'rescan');
        addTearDown(() async {
          await isar.close();
          await dir.delete(recursive: true);
        });

        const folderUri =
            'content://com.android.externalstorage.documents/tree/primary%3AMusic';
        final songRepo = SongRepository(isar: isar, iosImportSafety: false);
        final folderRepo = FolderRepository(isar: isar);

        await folderRepo.upsertFolder(
          FolderEntity()
            ..uri = folderUri
            ..displayName = 'Music'
            ..dateAdded = DateTime.utc(2026, 1, 1)
            ..songCount = 1
            ..lastScanned = DateTime.utc(2026, 1, 2),
        );
        await songRepo.upsertScannedSongs([
          SongEntity()
            ..filePath = '/storage/emulated/0/Music/track.flac'
            ..title = 'Track 1'
            ..artist = 'Artist 1'
            ..album = 'Album 1'
            ..folderUri = folderUri
            ..dateAdded = DateTime.utc(2026, 1, 1),
        ]);

        final container = ProviderContainer(
          overrides: [songRepositoryProvider.overrideWithValue(songRepo)],
        );
        addTearDown(container.dispose);

        // Subscribe to libraryChangeRevisionProvider, then close so it auto-disposes.
        final firstSub = container.listen(
          libraryChangeRevisionProvider,
          (_, _) {},
        );
        firstSub.close();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Re-subscribing via songsProvider must NOT fail with "Stream has already been listened to".
        final songsSub = container.listen(songsProvider, (_, _) {});
        final albumsSub = container.listen(songsByAlbumProvider, (_, _) {});
        final artistsSub = container.listen(songsByArtistProvider, (_, _) {});
        addTearDown(() {
          songsSub.close();
          albumsSub.close();
          artistsSub.close();
        });

        expect((await container.read(songsProvider.future)).songs.length, 1);
        expect((await container.read(songsByAlbumProvider.future)).length, 1);
        expect((await container.read(songsByArtistProvider.future)).length, 1);

        // Clear library + reset folder stats.
        await songRepo.deleteAllSongs();
        await folderRepo.resetAllFolderScanStats();

        final resetFolder = await folderRepo.getFolderByUri(folderUri);
        expect(resetFolder?.songCount, 0);
        expect(resetFolder?.lastScanned, isNull);

        await Future<void>.delayed(const Duration(milliseconds: 650));
        expect(container.read(libraryChangeRevisionProvider).hasError, isFalse);
        expect((await container.read(songsProvider.future)).songs, isEmpty);
        expect(await container.read(songsByAlbumProvider.future), isEmpty);
        expect(await container.read(songsByArtistProvider.future), isEmpty);

        // Rescan the same folder (upsert the same track back).
        await songRepo.upsertScannedSongs([
          SongEntity()
            ..filePath = '/storage/emulated/0/Music/track.flac'
            ..title = 'Track 1'
            ..artist = 'Artist 1'
            ..album = 'Album 1'
            ..folderUri = folderUri
            ..dateAdded = DateTime.utc(2026, 1, 3),
        ]);

        await Future<void>.delayed(const Duration(milliseconds: 650));
        expect(container.read(libraryChangeRevisionProvider).hasError, isFalse);
        final rescanned = await container.read(songsProvider.future);
        expect(rescanned.songs.map((s) => s.title).toList(), ['Track 1']);
        expect((await container.read(songsByAlbumProvider.future)).length, 1);
        expect((await container.read(songsByArtistProvider.future)).length, 1);
      },
    );
  });

  group('iOS clear -> rescan with IosTransferScanGuard', () {
    test(
      'allows rescanning both ordinary files and APFS NFD Desktop Copies after clear',
      () async {
        final dir = await Directory.systemTemp.createTemp('lokal-ios-rescan-');
        final isar = await _openTestIsar(dir, 'ios_rescan', withIosSchemas: true);
        addTearDown(() async {
          await isar.close();
          await dir.delete(recursive: true);
        });

        final repo = SongRepository(isar: isar, iosImportSafety: true);
        const jobId = '62dcde21-562f-4417-b660-cd1385ea44ca';
        const nfcRelative = 'Desktop Copies/Café - $jobId-r1.flac';
        const nfdAbsolute =
            '/var/mobile/App/Documents/Music/Desktop Copies/Cafe\u0301 - $jobId-r1.flac';
        const ordinaryPath = '/var/mobile/App/Documents/Music/Import-1/Song.flac';

        // Seed initial committed Desktop Copies song + receipt + ordinary song.
        final initialDesktop = SongEntity()
          ..filePath = '/var/mobile/App/Documents/Music/$nfcRelative'
          ..title = 'Café'
          ..artist = 'Artist'
          ..folderUri = '/var/mobile/App/Documents/Music'
          ..dateAdded = DateTime.utc(2026, 1, 1);
        final initialOrdinary = SongEntity()
          ..filePath = ordinaryPath
          ..title = 'Song'
          ..artist = 'Artist'
          ..folderUri = '/var/mobile/App/Documents/Music'
          ..dateAdded = DateTime.utc(2026, 1, 1);
        await repo.upsertSongs([initialDesktop, initialOrdinary]);

        await isar.writeTxn(() async {
          await isar.iosTransferReceiptEntitys.put(
            IosTransferReceiptEntity()
              ..operationKey = '$jobId:1'
              ..jobId = jobId
              ..revision = 1
              ..localSongId = initialDesktop.id
              ..serverId = 1
              ..desktopId = 'desk-1'
              ..desktopUserId = 'user-1'
              ..pairingId = 'pair-1'
              ..origin = 'http://192.168.1.10:3000'
              ..sourceId = 'src-1'
              ..relativePath = nfcRelative
              ..bytes = 1024
              ..sha256 = 'abc'
              ..state = 'committed'
              ..preparedAt = DateTime.utc(2026, 1, 1)
              ..committedAt = DateTime.utc(2026, 1, 1),
          );
        });

        // Clear library through the scan-epoch mutation barrier.
        await IosLibraryScanEpoch.withMutation(() => repo.deleteAllSongs());
        expect(await repo.getSongCount(), 0);

        // Rescan in a fresh iOS scan epoch, with APFS NFD path for Desktop Copy.
        await IosLibraryScanEpoch.run(() async {
          await repo.upsertScannedSongs([
            SongEntity()
              ..filePath = nfdAbsolute
              ..title = 'Café'
              ..artist = 'Artist'
              ..folderUri = '/var/mobile/App/Documents/Music'
              ..dateAdded = DateTime.utc(2026, 1, 2),
            SongEntity()
              ..filePath = ordinaryPath
              ..title = 'Song'
              ..artist = 'Artist'
              ..folderUri = '/var/mobile/App/Documents/Music'
              ..dateAdded = DateTime.utc(2026, 1, 2),
          ]);
        });

        final restored = await repo.getAllSongs();
        expect(restored.length, 2);
        expect(
          restored.map((s) => s.title).toSet(),
          {'Café', 'Song'},
        );
        for (final song in restored) {
          expect(
            int.parse(song.id),
            greaterThan(initialOrdinary.id),
            reason: 'Rescanned rows must allocate fresh IDs past the retired floor',
          );
        }
      },
    );
  });
}
