import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flick/data/database.dart';
import 'package:flick/data/repositories/recently_played_repository.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/features/songs/widgets/song_actions_bottom_sheet.dart';
import 'package:flick/models/lokal_remote_state.dart';
import 'package:flick/providers/favorites_provider.dart';
import 'package:flick/providers/lokal_remote_provider.dart';
import 'package:flick/services/duplicate_cleaner_service.dart';
import 'package:flick/services/favorites_service.dart';
import 'package:flick/services/link/link_journal.dart';
import 'package:flick/services/link/link_protocol.dart';
import 'package:flick/services/link/link_song_bindings.dart';
import 'package:flick/services/link/link_sync_coordinator.dart';
import 'package:flick/services/link/lokal_link_service.dart';
import 'package:flick/services/lokal_paired_desktops_store.dart';
import 'package:flick/services/lokal_remote_credentials_store.dart';
import 'package:flick/services/playlist_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class _FakeCredStore implements LokalRemoteCredentialsStore {
  LokalRemoteCredentials? value;

  @override
  Future<LokalRemoteCredentials?> read() async => value;

  @override
  Future<void> write(LokalRemoteCredentials credentials) async {
    value = credentials;
  }

  @override
  Future<void> clearIfMatching(LokalRemoteCredentials? expected) async {
    value = null;
  }

  @override
  Future<LokalRemoteCredentials> relocateIfMatching(
    LokalRemoteCredentials expected,
    Uri origin,
  ) async {
    final next = LokalRemoteCredentials(
      origin: origin,
      remoteToken: expected.remoteToken,
      apiKey: expected.apiKey,
      desktopId: expected.desktopId,
      desktopUserId: expected.desktopUserId,
      pairingID: expected.pairingID,
    );
    value = next;
    return next;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class _FakePairedStore extends LokalPairedDesktopsStore {
  final Map<String, LokalRemoteCredentials> entries = {};
  String? selected;

  @override
  Future<List<LokalPairedDesktop>> readAll({
    LokalRemoteCredentials? legacyActive,
  }) async => [
    for (final e in entries.entries)
      LokalPairedDesktop(
        id: e.key,
        name: e.value.origin.host,
        credentials: e.value,
      ),
  ];

  @override
  Future<LokalRemoteCredentials?> resolveActive({
    LokalRemoteCredentials? legacyActive,
  }) async => entries[selected] ?? legacyActive;

  @override
  Future<void> add(LokalRemoteCredentials credentials) async {
    final id = LokalPairedDesktopsStore.identity(credentials);
    entries[id] = credentials;
    selected = id;
  }

  @override
  Future<String?> activeId() async => selected;

  @override
  Future<LokalRemoteCredentials?> select(String id) async {
    selected = id;
    return entries[id];
  }

  @override
  Future<LokalRemoteCredentials?> remove(
    LokalRemoteCredentials expected,
  ) async {
    final id = LokalPairedDesktopsStore.identity(expected);
    entries.remove(id);
    selected = entries.isEmpty ? null : entries.keys.last;
    return selected == null ? null : entries[selected];
  }
}

class _NoopLinkService extends LokalLinkService {
  @override
  bool get connected => false;

  @override
  void send(String type, Map<String, dynamic> body, {String? id}) {}

  @override
  Future<Uri> connect(LokalRemoteCredentials credentials) async =>
      credentials.origin;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _initializeIsarCore();

  late Directory tempDir;
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lokal-dedup-sync-test-');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      pathChannel,
      (_) async => tempDir.path,
    );
    SharedPreferences.setMockInitialValues({});
    LinkSongBindings.instance.resetForTesting();
    LinkJournal.instance.resetForTesting();
    PlaylistService.instance = PlaylistService();
    await Database.init();
  });

  tearDown(() async {
    await Database.close();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathChannel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<SongEntity> insertSong({
    required String filePath,
    required String title,
    required String artist,
    String? album,
    int durationMs = 210000,
    String? fileType,
    int? bitDepth,
    int? sampleRate,
    int? bitrate,
    String? albumArtPath,
    String? sourceType,
    String? remoteId,
    int? remoteServerId,
    DateTime? dateAdded,
    int? startOffsetMs,
    bool createFile = false,
    String fileContents = 'audio-bytes',
  }) async {
    if (createFile) {
      final f = File(filePath);
      await f.parent.create(recursive: true);
      await f.writeAsString(fileContents);
    }
    final entity = SongEntity()
      ..filePath = filePath
      ..title = title
      ..artist = artist
      ..album = album
      ..durationMs = durationMs
      ..fileType = fileType
      ..bitDepth = bitDepth
      ..sampleRate = sampleRate
      ..bitrate = bitrate
      ..albumArtPath = albumArtPath
      ..sourceType = sourceType
      ..remoteId = remoteId
      ..remoteServerId = remoteServerId
      ..startOffsetMs = startOffsetMs
      ..dateAdded = dateAdded ?? DateTime.now();
    await Database.instance.writeTxn(() => Database.songs.put(entity));
    return entity;
  }

  test(
    'DuplicateCleanerService excludes network/ghost/pending rows, preserves Unicode titles, groups transfer artifacts, and ranks smart keepers',
    () async {
      // Distinct Japanese songs must NOT collapse into empty keys!
      await insertSong(
        filePath: '${tempDir.path}/jp1.flac',
        title: '夜に駆ける',
        artist: 'YOASOBI',
        durationMs: 260000,
        fileType: 'flac',
        createFile: true,
      );
      await insertSong(
        filePath: '${tempDir.path}/jp2.flac',
        title: 'アイドル',
        artist: 'YOASOBI',
        durationMs: 213000,
        fileType: 'flac',
        createFile: true,
      );

      // Network / ghost / pending copies of 夜に駆ける must be ignored.
      await insertSong(
        filePath: 'lokal://1/track-jp1',
        title: '夜に駆ける',
        artist: 'YOASOBI',
        durationMs: 260000,
        sourceType: 'lokal',
        remoteServerId: 1,
        remoteId: 'track-jp1',
      );
      await insertSong(
        filePath: 'ghost://desktop/1/track-jp1',
        title: '夜に駆ける',
        artist: 'YOASOBI',
        durationMs: 260000,
      );
      await insertSong(
        filePath: 'pending:playlist:jp1',
        title: '夜に駆ける',
        artist: 'YOASOBI',
        durationMs: 260000,
      );

      // Incompatible duration (>10s difference) is NOT grouped as a duplicate.
      await insertSong(
        filePath: '${tempDir.path}/jp1_extended.flac',
        title: '夜に駆ける',
        artist: 'YOASOBI',
        durationMs: 320000,
        fileType: 'flac',
        createFile: true,
      );

      // Real duplicate pair: clean FLAC vs transfer-UUID MP3 copy.
      final lossyArtifact = await insertSong(
        filePath:
            '${tempDir.path}/Cyberpunk - 12345678-1234-4123-8123-123456789abc.mp3',
        title:
            'ArtistA - Cyberpunk - 12345678-1234-4123-8123-123456789abc',
        artist: 'lokal phone',
        durationMs: 200000,
        fileType: 'mp3',
        bitrate: 320,
        albumArtPath: '${tempDir.path}/cover.jpg',
        createFile: true,
      );
      final losslessClean = await insertSong(
        filePath: '${tempDir.path}/Cyberpunk.flac',
        title: 'Cyberpunk',
        artist: 'ArtistA',
        durationMs: 201000,
        fileType: 'flac',
        bitDepth: 24,
        sampleRate: 96000,
        bitrate: 2800,
        createFile: true,
      );

      final cleaner = DuplicateCleanerService();
      final scan = await cleaner.scanForDuplicates();

      expect(scan.totalGroups, 1);
      expect(scan.totalDuplicates, 1);
      final group = scan.duplicateGroups.single;
      expect(
        group.songs.map((s) => s.id).toSet(),
        {lossyArtifact.id, losslessClean.id},
      );
      // Lossless clean file wins over lossy copy even when lossy has albumArtPath.
      expect(group.recommendedKeep.id, losslessClean.id);
    },
  );

  test(
    'mergeAndRemoveGroup merges plays, likes, playlists, multi-PC LinkSongBindings, deletes loser file (preserving shared CUE files), and emits track.deduplicate',
    () async {
      final repo = SongRepository();
      final favorites = FavoritesService(songRepository: repo);
      final playlists = PlaylistService(songRepository: repo);
      PlaylistService.instance = playlists;
      final recentRepo = RecentlyPlayedRepository(songRepository: repo);

      final keep = await insertSong(
        filePath: '${tempDir.path}/keep.flac',
        title: '信号 - 87654321-4321-4321-8321-abcdefabcdef',
        artist: '流線',
        album: 'Tokyo Sniper',
        durationMs: 240000,
        fileType: 'flac',
        bitDepth: 16,
        sampleRate: 44100,
        createFile: true,
      );
      final loser = await insertSong(
        filePath: '${tempDir.path}/loser.mp3',
        title: '流線 - 信号 [0123456789abcdef]',
        artist: '<unknown>',
        album: 'Tokyo Sniper',
        durationMs: 240500,
        fileType: 'mp3',
        bitrate: 256,
        albumArtPath: '${tempDir.path}/art.jpg',
        createFile: true,
        fileContents: 'loser-mp3-payload',
      );

      // Record plays: 1 on keep, 2 on loser (latest on loser).
      final t1 = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final t2 = DateTime.fromMillisecondsSinceEpoch(1700005000000);
      final t3 = DateTime.fromMillisecondsSinceEpoch(1700010000000);
      await recentRepo.recordPlay(keep.id.toString(), playedAt: t1);
      await recentRepo.recordPlay(loser.id.toString(), playedAt: t2);
      await recentRepo.recordPlay(loser.id.toString(), playedAt: t3);

      // Like only the loser.
      await favorites.addFavorite(
        loser.id.toString(),
        song: repo.songFromEntity(loser),
      );

      // Playlist has both keep and loser -> should deduplicate to single keep!
      final pl = (await playlists.createPlaylist('Favorites Mix'))!;
      await playlists.addSongToPlaylist(pl.id, loser.id.toString());
      await playlists.addSongToPlaylist(pl.id, keep.id.toString());

      // Bind keep to PC 1 and loser to PC 2 + SHA-256.
      const shaLoser =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      await LinkSongBindings.instance.bind(
        keep.id.toString(),
        serverId: 1,
        remoteId: 'pc1-track-99',
        filePath: keep.filePath,
      );
      await LinkSongBindings.instance.bind(
        loser.id.toString(),
        serverId: 2,
        remoteId: 'pc2-track-77',
        sha256: shaLoser,
        filePath: loser.filePath,
      );

      final deletedPaths = <String>[];
      final cleaner = DuplicateCleanerService(
        songRepository: repo,
        favoritesService: favorites,
        playlistService: playlists,
        deletePhysicalFile: (entity) async {
          deletedPaths.add(entity.filePath);
          final f = File(entity.filePath);
          if (await f.exists()) await f.delete();
        },
      );

      final scan = await cleaner.scanForDuplicates();
      expect(scan.totalGroups, 1);
      final removed = await cleaner.mergeAndRemoveGroup(
        scan.duplicateGroups.single,
        keepId: keep.id,
      );
      expect(removed, 1);

      // Physical file deleted for loser, preserved for keeper.
      expect(deletedPaths, [loser.filePath]);
      expect(await File(loser.filePath).exists(), isFalse);
      expect(await File(keep.filePath).exists(), isTrue);
      expect(await Database.songs.get(loser.id), isNull);

      // Keeper metadata cleaned and inherited local art.
      final updatedKeep = (await Database.songs.get(keep.id))!;
      expect(updatedKeep.title, '信号');
      expect(updatedKeep.artist, '流線');
      expect(updatedKeep.albumArtPath, '${tempDir.path}/art.jpg');

      // Play count merged (1 + 2 = 3) and latest playedAt preserved.
      final counts = await recentRepo.getPlayCounts();
      expect(counts[keep.id.toString()], 3);
      final history = await recentRepo.getRecentHistory(limit: 5);
      expect(history.first.song.id, keep.id.toString());
      expect(history.first.playedAt, t3);

      // Favorites transferred to keeper, loser removed.
      expect(await favorites.isFavorite(keep.id.toString()), isTrue);
      expect(await favorites.isFavorite(loser.id.toString()), isFalse);

      // Playlist deduplicated to single keeper ID.
      final updatedPl = (await playlists.getPlaylist(pl.id))!;
      expect(updatedPl.songIds, [keep.id.toString()]);

      // Multi-PC bindings preserved on keeper!
      final binding = await LinkSongBindings.instance.getBinding(
        keep.id.toString(),
      );
      expect(binding?.servers, {1: 'pc1-track-99', 2: 'pc2-track-77'});
      expect(binding?.sha256, shaLoser);

      // Journal has track.deduplicate op.
      final opsPage = await LinkJournal.instance.libraryAfter(0);
      final dedupOps = (opsPage['items'] as List)
          .cast<Map<String, dynamic>>()
          .where((op) => op['op'] == 'track.deduplicate')
          .toList();
      expect(dedupOps, hasLength(1));
      final dedup = dedupOps.single;
      expect(dedup['fields']['keep_key'], '流線|信号|240');
      expect(dedup['fields']['title'], '信号');
      expect(dedup['fields']['artist'], '流線');
      expect(
        (dedup['fields']['removed_keys'] as List),
        contains('流線|信号 - 87654321-4321-4321-8321-abcdefabcdef|240'),
      );
      expect(
        (dedup['fields']['removed_hashes'] as List),
        contains(equals({'sha256': shaLoser, 'bytes': 'loser-mp3-payload'.length})),
      );
    },
  );

  test(
    'manual single-song deletion emits track.deduplicate when a local twin survives and track.delete when deleting the last copy',
    () async {
      final repo = SongRepository();
      final copyA = await insertSong(
        filePath: '${tempDir.path}/twin_a.flac',
        title: 'Starlight',
        artist: 'Muse',
        durationMs: 240000,
        fileType: 'flac',
        createFile: true,
      );
      final copyB = await insertSong(
        filePath: '${tempDir.path}/twin_b.mp3',
        title: 'Muse - Starlight - 11111111-2222-4333-8444-555555555555',
        artist: 'unknown artist',
        durationMs: 241000,
        fileType: 'mp3',
        createFile: true,
      );
      await LinkSongBindings.instance.bind(
        copyB.id.toString(),
        serverId: 5,
        remoteId: 'pc5-starlight',
        filePath: copyB.filePath,
      );

      // Delete copyB first while copyA survives -> emits track.deduplicate & merges bindings.
      final songB = repo.songFromEntity(copyB);
      await repo.deleteSong(copyB.id);
      await recordLocalSongDeletionInLink(songB, songRepository: repo);

      expect(
        (await LinkSongBindings.instance.getBinding(copyA.id.toString()))
            ?.servers[5],
        'pc5-starlight',
      );
      var items =
          (await LinkJournal.instance.libraryAfter(0))['items']
              as List<dynamic>;
      expect(items.last['op'], 'track.deduplicate');
      expect(items.last['fields']['keep_key'], 'muse|starlight|240');

      // Now delete copyA (the last local copy) -> emits track.delete & tombstones it!
      final cursorBeforeDelete =
          (await LinkJournal.instance.libraryAfter(0))['cursor'] as int;
      final songA = repo.songFromEntity(copyA);
      await repo.deleteSong(copyA.id);
      await recordLocalSongDeletionInLink(songA, songRepository: repo);

      expect(
        await LinkSongBindings.instance.getBinding(copyA.id.toString()),
        isNull,
      );
      items =
          (await LinkJournal.instance.libraryAfter(cursorBeforeDelete))['items']
              as List<dynamic>;
      expect(items, hasLength(1));
      expect(items.single['op'], 'track.delete');
      expect(items.single['fields']['track_key'], 'muse|starlight|240');

      // Legacy peer filtering omits lifecycle ops while advancing cursor!
      final legacyFiltered = await LinkJournal.instance.libraryAfter(
        0,
        includeTrackLifecycle: false,
      );
      expect(
        (legacyFiltered['items'] as List).where(
          (op) =>
              op['op'] == 'track.delete' || op['op'] == 'track.deduplicate',
        ),
        isEmpty,
      );
      expect(legacyFiltered['cursor'], greaterThan(0));

      // Tombstone check blocks older/contemporaneous copies, allows fresh re-imports.
      expect(
        await LinkJournal.instance.isTrackTombstoned(
          artist: 'Muse',
          title: 'Starlight',
          duration: const Duration(seconds: 240),
          addedAt: DateTime.now(),
        ),
        isTrue,
      );
      expect(
        await LinkJournal.instance.isTrackTombstoned(
          artist: 'Muse',
          title: 'Starlight',
          duration: const Duration(seconds: 240),
          addedAt: DateTime.now().add(const Duration(minutes: 2)),
        ),
        isFalse,
      );
    },
  );

  test(
    'LokalLinkService capability negotiation sends track_lifecycle and tracks legacy vs modern desktop hello',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      final clientHellos = <Map<String, dynamic>>[];
      var sendCapabilitiesInServerHello = false;

      server.listen((req) async {
        if (req.uri.path != '/api/remote/ws') {
          req.response.statusCode = 404;
          await req.response.close();
          return;
        }
        final ws = await WebSocketTransformer.upgrade(req);
        ws.add(
          LinkMessage.create('hello', {
            'desktopId': 'desk-12345678',
            'proto': 1,
            if (sendCapabilitiesInServerHello)
              'capabilities': ['remote', 'library', 'track_lifecycle'],
          }).encode(),
        );
        ws.listen((raw) {
          final msg = LinkMessage.decode(raw as String);
          if (msg.type == 'hello') {
            clientHellos.add(msg.body);
          }
        });
      });

      final creds = LokalRemoteCredentials(
        origin: Uri.parse('http://127.0.0.1:${server.port}'),
        remoteToken: 'valid-test-token-123456',
        desktopId: 'desk-12345678',
      );
      final link = LokalLinkService();
      addTearDown(link.close);

      // 1. Legacy server hello without capabilities -> supportsTrackLifecycle becomes false.
      await link.connect(creds);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(clientHellos, hasLength(1));
      expect(clientHellos.single['capabilities'], contains('track_lifecycle'));
      expect(link.supportsTrackLifecycle, isFalse);

      // 2. Modern server hello with track_lifecycle -> supportsTrackLifecycle becomes true.
      sendCapabilitiesInServerHello = true;
      await link.connect(creds);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(clientHellos, hasLength(2));
      expect(link.supportsTrackLifecycle, isTrue);
    },
  );

  test(
    'LinkSyncCoordinator applies remote track.deduplicate safely (1 copy kept untouched, >=2 copies merged) and applies remote track.delete',
    () async {
      final repo = SongRepository();
      final favorites = FavoritesService(songRepository: repo);
      final deletedFiles = <String>[];

      // Case A: Only 1 local copy exists (with transfer artifact) -> NEVER deleted, artifact cleaned!
      final soleCopy = await insertSong(
        filePath: '${tempDir.path}/sole.flac',
        title: ' Odyssey - 12345678-1234-4123-8123-123456789abc',
        artist: 'Synth',
        durationMs: 195000,
        fileType: 'flac',
        createFile: true,
      );

      // Case B: 2 local copies exist -> redundant lossy copy deleted, best FLAC kept!
      final dupFlac = await insertSong(
        filePath: '${tempDir.path}/horizon.flac',
        title: 'Horizon',
        artist: 'Daft',
        durationMs: 220000,
        fileType: 'flac',
        bitDepth: 24,
        sampleRate: 48000,
        createFile: true,
      );
      final dupMp3 = await insertSong(
        filePath: '${tempDir.path}/horizon_copy.mp3',
        title: 'Horizon - 99999999-1111-4222-8333-444444444444',
        artist: 'Daft',
        durationMs: 220400,
        fileType: 'mp3',
        bitrate: 192,
        createFile: true,
      );
      await favorites.addFavorite(
        dupMp3.id.toString(),
        song: repo.songFromEntity(dupMp3),
      );

      // Case C: Track targeted by remote track.delete (stream row + older local file deleted, newer local file spared).
      final oldAdded = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final newAdded = DateTime.fromMillisecondsSinceEpoch(1700050000000);
      final doomedStream = await insertSong(
        filePath: 'lokal://1/doomed-remote',
        title: 'Obsolete',
        artist: 'Tester',
        durationMs: 180000,
        sourceType: 'lokal',
        remoteServerId: 1,
        remoteId: 'doomed-remote',
        dateAdded: newAdded,
      );
      final doomedLocal = await insertSong(
        filePath: '${tempDir.path}/obsolete.mp3',
        title: 'Obsolete',
        artist: 'Tester',
        durationMs: 180000,
        fileType: 'mp3',
        dateAdded: oldAdded,
        createFile: true,
      );
      final freshReimport = await insertSong(
        filePath: '${tempDir.path}/fresh_kept.mp3',
        title: 'Reborn',
        artist: 'Tester',
        durationMs: 185000,
        fileType: 'mp3',
        dateAdded: newAdded,
        createFile: true,
      );

      final coordinator = LinkSyncCoordinator(
        socket: _NoopLinkService(),
        credentials: LokalRemoteCredentials(
          origin: Uri.parse('http://127.0.0.1:3421'),
          remoteToken: 'token-1234567890',
          desktopId: 'desktop-peer-1',
        ),
        favorites: favorites,
        deletePhysicalFile: (entity) async {
          deletedFiles.add(entity.filePath);
          final f = File(entity.filePath);
          if (await f.exists()) await f.delete();
        },
      );

      final incomingOps = [
        {
          'op_id': 'op_dedup_sole_01',
          'device_id': 'desktop-peer-1',
          'hlc': '0001700010000000:00000001',
          'entity': 'track',
          'entity_id': 'synth|odyssey|195',
          'op': 'track.deduplicate',
          'fields': {
            'keep_key': 'synth|odyssey|195',
            'title': 'Odyssey',
            'artist': 'Synth',
            'duration': 195,
            'removed_keys': [
              'synth|odyssey - 12345678-1234-4123-8123-123456789abc|195',
            ],
            'removed_hashes': <Map<String, dynamic>>[],
          },
        },
        {
          'op_id': 'op_dedup_pair_02',
          'device_id': 'desktop-peer-1',
          'hlc': '0001700010000000:00000002',
          'entity': 'track',
          'entity_id': 'daft|horizon|220',
          'op': 'track.deduplicate',
          'fields': {
            'keep_key': 'daft|horizon|220',
            'title': 'Horizon',
            'artist': 'Daft',
            'duration': 220,
            'removed_keys': [
              'daft|horizon - 99999999-1111-4222-8333-444444444444|220',
            ],
            'removed_hashes': <Map<String, dynamic>>[],
          },
        },
        {
          'op_id': 'op_del_obsolete_03',
          'device_id': 'desktop-peer-1',
          'hlc': '0001700010000000:00000003',
          'entity': 'track',
          'entity_id': 'tester|obsolete|180',
          'op': 'track.delete',
          'fields': {
            'track_key': 'tester|obsolete|180',
            'title': 'Obsolete',
            'artist': 'Tester',
            'duration': 180,
          },
        },
        {
          'op_id': 'op_del_reborn_old_04',
          'device_id': 'desktop-peer-1',
          'hlc': '0001700010000000:00000004',
          'entity': 'track',
          'entity_id': 'tester|reborn|185',
          'op': 'track.delete',
          'fields': {
            'track_key': 'tester|reborn|185',
            'title': 'Reborn',
            'artist': 'Tester',
            'duration': 185,
          },
        },
      ];

      final beforeOps =
          (await LinkJournal.instance.libraryAfter(0))['items'] as List;
      final merged = await LinkJournal.instance.mergeLibrary(incomingOps);
      await coordinator.materializeLibraryPageForTesting(merged);

      // Sole copy survived AND had its title cleaned!
      final soleAfter = await Database.songs.get(soleCopy.id);
      expect(soleAfter, isNotNull);
      expect(soleAfter!.title, 'Odyssey');
      expect(await File(soleCopy.filePath).exists(), isTrue);

      // Duplicate pair merged into dupFlac, dupMp3 deleted, like transferred, and NO echo ops emitted!
      expect(await Database.songs.get(dupFlac.id), isNotNull);
      expect(await Database.songs.get(dupMp3.id), isNull);
      expect(deletedFiles, contains(dupMp3.filePath));
      expect(await favorites.isFavorite(dupFlac.id.toString()), isTrue);

      // Remote delete removed stream row + older local file, but spared newer re-imported file!
      expect(await Database.songs.get(doomedStream.id), isNull);
      expect(await Database.songs.get(doomedLocal.id), isNull);
      expect(deletedFiles, contains(doomedLocal.filePath));
      expect(await Database.songs.get(freshReimport.id), isNotNull);

      // Ensure applying remote ops did NOT append any new local ops beyond the 4 merged ones.
      final allJournalOps =
          (await LinkJournal.instance.libraryAfter(0))['items'] as List;
      expect(allJournalOps, hasLength(beforeOps.length + 4));
    },
  );

  test(
    'Multi-PC isDesktopTrackAlreadyPresentLocally prevents duplicate download from PC 2 and forgetConfiguration cleans up server/stream/ghost rows while keeping local files',
    () async {
      final server1 = NetworkServerEntity()
        ..protocol = 'lokal'
        ..label = 'PC 1'
        ..baseUrl = 'http://192.168.1.10:3421'
        ..username = 'pc-one:guest';
      final server2 = NetworkServerEntity()
        ..protocol = 'lokal'
        ..label = 'PC 2'
        ..baseUrl = 'http://192.168.1.20:3421'
        ..username = 'pc-two:guest';
      await Database.instance.writeTxn(() async {
        await Database.networkServers.put(server1);
        await Database.networkServers.put(server2);
      });

      final localSong = await insertSong(
        filePath: '${tempDir.path}/shared_hit.flac',
        title: 'Shared Hit',
        artist: 'boards of canada',
        durationMs: 310000,
        fileType: 'flac',
        remoteServerId: server1.id,
        remoteId: 'pc1-id-1',
        createFile: true,
      );
      final streamRow1 = await insertSong(
        filePath: 'lokal://${server1.id}/pc1-stream-only',
        title: 'Stream Only',
        artist: 'Artist',
        durationMs: 150000,
        sourceType: 'lokal',
        remoteServerId: server1.id,
        remoteId: 'pc1-stream-only',
      );
      final ghostRow1 = await insertSong(
        filePath: 'ghost://desktop/${server1.id}/pc1-ghost',
        title: 'Ghost Row',
        artist: 'Artist',
        durationMs: 150000,
        sourceType: 'lokal',
        remoteServerId: server1.id,
        remoteId: 'pc1-ghost',
      );

      // Push from PC 2 with a transfer-artifact title variant of Shared Hit -> detected as already present!
      final presentOnPc2 = await isDesktopTrackAlreadyPresentLocally(
        serverId: server2.id,
        remoteId: 'pc2-id-888',
        track: {
          'id': 'pc2-id-888',
          'title':
              'Boards of Canada - Shared Hit - 12345678-1234-4123-8123-123456789abc',
          'artist': 'unknown',
          'duration': 310.5,
        },
      );
      expect(presentOnPc2, isTrue);

      // Binding for PC 2 was recorded automatically on localSong!
      final bindingAfterPush = await LinkSongBindings.instance.getBinding(
        localSong.id.toString(),
      );
      expect(bindingAfterPush?.servers[server2.id], 'pc2-id-888');

      // Forget PC 1 via LokalRemoteController.forgetConfiguration!
      final creds1 = LokalRemoteCredentials(
        origin: Uri.parse('http://192.168.1.10:3421'),
        remoteToken: 'pc1-token-abcdef123456',
        desktopId: 'pc-one',
        desktopUserId: 'guest',
      );
      final creds2 = LokalRemoteCredentials(
        origin: Uri.parse('http://192.168.1.20:3421'),
        remoteToken: 'pc2-token-abcdef123456',
        desktopId: 'pc-two',
        desktopUserId: 'guest',
      );
      final credStore = _FakeCredStore()..value = creds1;
      final pairedStore = _FakePairedStore();
      await pairedStore.add(creds1);
      await pairedStore.add(creds2);
      await pairedStore.select(LokalPairedDesktopsStore.identity(creds1));

      final container = ProviderContainer(
        overrides: [
          lokalRemoteCredentialsStoreProvider.overrideWithValue(credStore),
          lokalPairedDesktopsStoreProvider.overrideWithValue(pairedStore),
          lokalLinkServiceProvider.overrideWithValue(_NoopLinkService()),
          favoritesServiceProvider.overrideWithValue(FavoritesService()),
        ],
      );
      addTearDown(container.dispose);

      await LinkSongBindings.instance.bind(
        localSong.id.toString(),
        serverId: server1.id,
        remoteId: 'pc1-id-1',
        filePath: localSong.filePath,
      );

      final controller = container.read(lokalRemoteControllerProvider.notifier);
      await controller.forgetConfiguration(expected: creds1);

      // PC 1 server row, stream row, and ghost row are gone!
      expect(await Database.networkServers.get(server1.id), isNull);
      expect(await Database.songs.get(streamRow1.id), isNull);
      expect(await Database.songs.get(ghostRow1.id), isNull);

      // Real local audio file & row are untouched, with stale server1 pointer cleared and server2 binding intact!
      final survivingLocal = await Database.songs.get(localSong.id);
      expect(survivingLocal, isNotNull);
      expect(survivingLocal!.remoteServerId, isNull);
      expect(survivingLocal.remoteId, isNull);
      expect(await File(localSong.filePath).exists(), isTrue);

      final bindingAfterForget = await LinkSongBindings.instance.getBinding(
        localSong.id.toString(),
      );
      expect(bindingAfterForget?.servers.containsKey(server1.id), isFalse);
      expect(bindingAfterForget?.servers[server2.id], 'pc2-id-888');
    },
  );
}
