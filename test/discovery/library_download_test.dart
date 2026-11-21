import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flick/data/entities/song_entity.dart';
import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/search/library_download.dart';
import 'package:flick/models/song.dart';
import 'package:flick/src/rust/api/metadata_editor.dart' as rust_metadata;
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/features/konnekted/lokal_mixes.dart';
import 'package:flick/services/lyrics_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late File cached;
  final upserts = <SongEntity>[];
  final registered = <String>[];
  final indexed = <String>[];
  final covers = <String>[];
  final tags = <String>[];
  final savedLyrics = <String?>[];
  final probed = <String>[];
  rust_metadata.TagReadResult embedded = const rust_metadata.TagReadResult();
  LyricsData? downloadLyrics;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('library_download_test');
    cached = File(p.join(root.path, 'cache', 'abc.m4a'));
    await cached.create(recursive: true);
    await cached.writeAsBytes(List.filled(64, 7));
    upserts.clear();
    registered.clear();
    indexed.clear();
    covers.clear();
    tags.clear();
    savedLyrics.clear();
    probed.clear();
    embedded = const rust_metadata.TagReadResult();
    downloadLyrics = null;
  });

  tearDown(() => root.delete(recursive: true));

  Song prepared() => Song(
    id: 'discovery:abc',
    title: 'Song: One?',
    artist: 'The Artist',
    album: 'Album',
    duration: const Duration(seconds: 200),
    fileType: 'M4A',
    sampleRate: 44100,
    filePath: cached.path,
    isExternal: true,
  );

  LibraryDownloader downloader(
    List<LibraryDownloadFolder> folders, {
    bool tagged = true,
  }) => LibraryDownloader(
    folders: () async => folders,
    fallbackRoot: p.join(root.path, 'Music'),
    registerFolder: (path, name) async => registered.add(path),
    upsert: (entity) async => upserts.add(entity),
    tag: (path, song, lyrics) async {
      tags.add(path);
      if (lyrics != null)
        savedLyrics.add(LibraryDownloader.portableLyrics(lyrics));
      return tagged;
    },
    readTags: (path) async {
      probed.add(path);
      return embedded;
    },
    lyricsLookup: (_) async => downloadLyrics,
    cover: (path, song, url) async => covers.add(url),
    indexMedia: (paths) async => indexed.addAll(paths),
    now: () => DateTime(2026, 10, 20),
  );

  test('iPhone imports embedded album grouping and track order without changing carousel behavior', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final music = Directory(p.join(root.path, 'Library'))..createSync();
    final folders = [
      LibraryDownloadFolder(uri: 'library', name: 'Music', path: music.path),
    ];
    for (final number in [2, 1]) {
      embedded = rust_metadata.TagReadResult(
        album: 'Apple Music Album',
        albumArtist: 'Album Owner',
        trackNumber: number,
        discNumber: 1,
        genre: 'Rock',
        year: 2026,
      );
      await downloader(folders).save(
        Song(
          id: 'track-$number',
          title: 'Track $number',
          artist: 'Performer $number',
          album: number == 2 ? 'Unknown Album' : null,
          filePath: cached.path,
          duration: const Duration(seconds: 200),
          fileType: 'M4A',
        ),
      );
    }
    expect(probed, hasLength(2));
    expect(
      probed.every(
        (path) =>
            File(path).existsSync() &&
            !p.isWithin(p.dirname(cached.path), path),
      ),
      isTrue,
    );
    expect(upserts.map((s) => s.album), [
      'Apple Music Album',
      'Apple Music Album',
    ]);
    expect(upserts.map((s) => s.albumArtist), ['Album Owner', 'Album Owner']);
    expect(
      upserts.every(
        (s) => s.discNumber == 1 && s.genre == 'Rock' && s.year == 2026,
      ),
      isTrue,
    );
    final songs = [
      for (final row in upserts)
        Song(
          id: row.title,
          title: row.title,
          artist: row.artist,
          album: row.album,
          albumArtist: row.albumArtist,
          trackNumber: row.trackNumber,
          discNumber: row.discNumber,
          duration: const Duration(seconds: 200),
          fileType: 'M4A',
        ),
    ];
    const mix = LokalMix(
      id: 'mix',
      name: 'Daily Mix',
      type: LokalMixType.daily,
      tracks: [],
    );
    final covers = konnektedCoversWithLocalAlbums([
      for (final song in songs) LokalMadeForYouPick(song: song, mix: mix),
    ], songs);
    expect(
      covers,
      hasLength(2),
      reason: 'keep Android recommendation cards and front-face behavior',
    );
    for (final cover in covers) {
      expect(cover.coverSong, isNotNull);
      expect(cover.songs.map((s) => s.trackNumber), [
        1,
        2,
      ], reason: 'long-press opens the whole album');
    }
  });

  test('Android retains its existing MediaStore indexing path', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await downloader([]).save(prepared());
    expect(probed, isEmpty);
    expect(indexed, hasLength(1));
    expect(upserts.single.metadataComplete, isTrue);
  });

  test('iPhone tag writes preserve existing values when catalogue fields are placeholders', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fields = LibraryDownloader.tagFieldsForDownload(
      const Song(
        id: 'song',
        title: 'Title',
        artist: 'Artist',
        album: ' Unknown Album ',
        albumArtist: ' ',
        trackNumber: 0,
        discNumber: 0,
        year: 0,
        duration: Duration.zero,
        fileType: 'FLAC',
      ),
      null,
    );
    expect(fields.album, isNull);
    expect(fields.albumArtist, isNull);
    expect(fields.trackNumber, isNull);
    expect(fields.discNumber, isNull);
    expect(fields.year, isNull);
    final tagged = LibraryDownloader.tagFieldsForDownload(
      const Song(
        id: 'song',
        title: 'Title',
        artist: 'Guest Artist',
        album: 'Album',
        albumArtist: 'Album Owner',
        trackNumber: 3,
        discNumber: 2,
        year: 2026,
        duration: Duration.zero,
        fileType: 'FLAC',
      ),
      null,
    );
    expect(tagged.albumArtist, 'Album Owner');
    expect(tagged.trackNumber, 3);
    expect(tagged.discNumber, 2);
  });

  test('iPhone tag-read failure retains the download and leaves metadata eligible for retry', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final saved = await LibraryDownloader(
      folders: () async => [],
      fallbackRoot: p.join(root.path, 'Music'),
      registerFolder: (_, _) async {},
      upsert: (song) async => upserts.add(song),
      tag: (_, _, _) async => true,
      readTags: (_) async => throw const FileSystemException('Read failed'),
      lyricsLookup: (_) async => null,
      indexMedia: (_) async {},
    ).save(prepared());
    expect(File(saved.path).readAsBytesSync(), cached.readAsBytesSync());
    expect(upserts.single.album, 'Album');
    expect(upserts.single.metadataComplete, isFalse);
  });

  test('iPhone download fallback uses persistent app-owned Music', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getApplicationDocumentsDirectory');
      return p.join(root.path, 'Documents');
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });
    final saved = await LibraryDownloader(
      folders: () async => [],
      registerFolder: (path, _) async => registered.add(path),
      upsert: (entity) async => upserts.add(entity),
      tag: (_, _, _) async => false,
      lyricsLookup: (_) async => null,
      indexMedia: (_) async {},
    ).save(prepared());
    final expectedRoot = p.join(
      root.path,
      'Documents',
      'Music',
      'Lokal Downloads',
    );
    expect(p.isWithin(expectedRoot, saved.path), true);
    expect(registered, [expectedRoot]);
    expect(File(saved.path).readAsBytesSync(), cached.readAsBytesSync());
    expect(upserts.single.folderUri, expectedRoot);
  });

  test('iOS saves verified codec and measured download bitrate', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await downloader(const []).save(
      prepared().copyWith(fileType: 'AAC', resolution: '256 kbps'),
    );
    expect(upserts.single.fileType, 'AAC');
    expect(upserts.single.bitrate, 256);

    await downloader(const []).save(
      prepared().copyWith(fileType: 'ALAC', resolution: 'Lossless'),
    );
    expect(upserts.last.fileType, 'ALAC');
    expect(upserts.last.bitrate, isNull);
  });

  test(
    'download embeds portable line lyrics without fabricating word stamps',
    () async {
      downloadLyrics = const LyricsData(
        lines: [
          LyricsLine(timestamp: Duration(seconds: 8), text: 'First verse'),
          LyricsLine(timestamp: Duration(seconds: 12), text: 'Second verse'),
        ],
        isSynchronized: true,
        source: 'LyricsPlus',
        rawContent: '',
      );
      final music = Directory(p.join(root.path, 'Library'))..createSync();
      await downloader([
        LibraryDownloadFolder(uri: 'u', name: 'Music', path: music.path),
      ]).save(prepared());
      expect(savedLyrics.single, contains('[00:08.00]First verse'));
      expect(savedLyrics.single, contains('[00:12.00]Second verse'));
      expect(savedLyrics.single, isNot(contains('<00:08.00>')));
    },
  );

  test(
    'a syllable-timed download keeps enhanced timing beside portable tags',
    () async {
      downloadLyrics = const LyricsData(
        lines: [
          LyricsLine(
            timestamp: Duration(seconds: 10),
            text: 'Hello world',
            words: [
              LyricsWord(
                start: Duration(seconds: 10),
                end: Duration(milliseconds: 10500),
                text: 'Hello ',
              ),
              LyricsWord(
                start: Duration(milliseconds: 10500),
                end: Duration(seconds: 11),
                text: 'world',
              ),
            ],
          ),
        ],
        isSynchronized: true,
        rawContent: '',
      );
      final music = Directory(p.join(root.path, 'Library'))..createSync();
      final result = await downloader([
        LibraryDownloadFolder(uri: 'u', name: 'Music', path: music.path),
      ]).save(prepared());
      expect(savedLyrics.single, contains('[00:10.00]Hello world'));
      expect(savedLyrics.single, isNot(contains('<00:10.00>')));
      final enhanced = File(p.setExtension(result.path, '.elrc'));
      expect(await enhanced.exists(), isTrue);
      expect(await enhanced.readAsString(), contains('<00:10.00>Hello '));
      expect(await enhanced.readAsString(), contains('<00:10.50>world'));
    },
  );

  test(
    'plain lyrics are embedded without fake synchronization timestamps',
    () async {
      downloadLyrics = const LyricsData(
        lines: [
          LyricsLine(timestamp: Duration.zero, text: 'Verse'),
          LyricsLine(timestamp: Duration.zero, text: 'Chorus'),
        ],
        isSynchronized: false,
        rawContent: '',
      );
      final music = Directory(p.join(root.path, 'Library'))..createSync();
      await downloader([
        LibraryDownloadFolder(uri: 'u', name: 'Music', path: music.path),
      ]).save(prepared());
      expect(savedLyrics.single, 'Verse\nChorus');
    },
  );

  test(
    'a lyrics lookup miss does not prevent downloaded audio from being saved',
    () async {
      final music = Directory(p.join(root.path, 'Library'))..createSync();
      final result = await downloader([
        LibraryDownloadFolder(uri: 'u', name: 'Music', path: music.path),
      ]).save(prepared());
      expect(File(result.path).existsSync(), isTrue);
      expect(savedLyrics, isEmpty);
    },
  );

  test(
    'Atmos download remains byte-identical and retains codec identity',
    () async {
      final music = Directory(p.join(root.path, 'Library'))..createSync();
      final original = await cached.readAsBytes();
      final joc = prepared().copyWith(
        fileType: 'E-AC-3 JOC',
        atmosAvailable: true,
        atmosEncoded: true,
      );
      final saved = await downloader([
        LibraryDownloadFolder(
          uri: 'content://music',
          name: 'Music',
          path: music.path,
        ),
      ]).save(joc, artwork: 'https://example.com/cover.jpg');
      expect(saved.path, endsWith('.atmos.m4a'));
      expect(await File(saved.path).readAsBytes(), original);
      expect(upserts.single.fileType, 'E-AC-3 JOC');
      expect(upserts.single.hasLocalEdits, isTrue);
      expect(tags, isEmpty, reason: 'Tagging must not rewrite JOC MP4 boxes');
      expect(
        covers,
        isEmpty,
        reason: 'Do not embed artwork into the Atmos container',
      );
    },
  );

  test('AC-4 saves preserve bytes and a rescan-safe codec suffix', () async {
    cached = await cached.rename(p.setExtension(cached.path, '.mp4'));
    final original = await cached.readAsBytes();
    final music = Directory(p.join(root.path, 'Library'))..createSync();
    final ac4 = prepared().copyWith(fileType: 'AC-4', atmosEncoded: true);
    final folders = [
      LibraryDownloadFolder(uri: 'u', name: 'Music', path: music.path),
    ];
    await downloader(folders).save(ac4);
    final saved = await downloader(folders).save(ac4);
    expect(saved.path, endsWith(' (2).ac4.atmos.mp4'));
    expect(await File(saved.path).readAsBytes(), original);
    expect(upserts.last.fileType, 'AC-4');
    expect(tags, isEmpty);
    expect(covers, isEmpty);
  });

  test('copies into the first writable library folder and adds it', () async {
    final music = Directory(p.join(root.path, 'Library'))..createSync();
    final saved = await downloader([
      const LibraryDownloadFolder(uri: 'content://saf-only', name: 'SD'),
      LibraryDownloadFolder(
        uri: 'content://tree/music',
        name: 'Music',
        path: music.path,
      ),
    ]).save(prepared(), artwork: 'https://example.com/cover.jpg');

    expect(saved.fallback, isFalse);
    expect(saved.folderName, 'Music');
    expect(
      saved.path,
      p.join(music.path, 'The Artist', 'Album', 'The Artist - Song One.m4a'),
    );
    expect(File(saved.path).readAsBytesSync(), hasLength(64));
    expect(cached.existsSync(), isTrue, reason: 'the cache keeps its copy');

    final entity = upserts.single;
    expect(entity.filePath, saved.path);
    expect(entity.title, 'Song: One?');
    expect(entity.artist, 'The Artist');
    expect(entity.album, 'Album');
    expect(entity.durationMs, 200000);
    expect(entity.fileType, 'M4A');
    expect(entity.folderUri, 'content://tree/music');
    expect(entity.relativeFolderPath, 'The Artist/Album');
    expect(entity.hasLocalEdits, isFalse);
    expect(indexed, [saved.path]);
    expect(covers, ['https://example.com/cover.jpg']);
    expect(registered, isEmpty);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('$platform download falls back to prepared cached artwork before indexing', () async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final image = File(p.join(root.path, 'cache', 'cover.jpg'));
      await image.writeAsBytes([1, 2, 3]);
      final events = <String>[];
      final seen = <String>[];
      final song = prepared().copyWith(albumArt: image.path);
      final saver = LibraryDownloader(
        folders: () async => [], fallbackRoot: p.join(root.path, 'Music'),
        registerFolder: (_, _) async {},
        upsert: (_) async => events.add('upsert'),
        tag: (_, _, _) async => true,
        readTags: (_) async => const rust_metadata.TagReadResult(),
        lyricsLookup: (_) async => null,
        cover: (path, target, location) async {
          expect(target.filePath, path);
          expect(target.isExternal, isFalse, reason: 'embed into the library copy, not the online cache');
          expect(target.folderUri, isNotNull);
          seen.add(location);
          if (location.startsWith('https:')) throw const FileSystemException('CDN unavailable');
          events.add('cover');
        },
        indexMedia: (_) async => events.add('index'),
      );
      final saved = await saver.save(song, artwork: 'https://covers.example/broken.jpg');
      expect(seen, ['https://covers.example/broken.jpg', image.path]);
      expect(events, ['upsert', 'cover', 'index']);
      expect(await File(saved.path).readAsBytes(), await cached.readAsBytes());
      seen.clear();
      await saver.save(song);
      expect(seen, [image.path], reason: 'an explicit artwork argument is optional');
    });
  }

  test(
    'a second copy gets a numbered name; untagged keeps its names',
    () async {
      final music = Directory(p.join(root.path, 'Library'))..createSync();
      final folders = [
        LibraryDownloadFolder(uri: 'u', name: 'Music', path: music.path),
      ];
      await downloader(folders).save(prepared());
      final second = await downloader(folders, tagged: false).save(prepared());
      expect(p.basename(second.path), 'The Artist - Song One (2).m4a');
      expect(upserts.last.hasLocalEdits, isTrue);
    },
  );

  test(
    'falls back to Lokal Downloads in Music and adds it to the library',
    () async {
      // A library folder that can't hold a new folder (it's a file here).
      final blocked = File(p.join(root.path, 'blocked'))..createSync();
      final saved = await downloader([
        LibraryDownloadFolder(uri: 'u', name: 'Locked', path: blocked.path),
      ]).save(prepared());

      final fallback = p.join(root.path, 'Music', 'Lokal Downloads');
      expect(saved.fallback, isTrue);
      expect(saved.folderName, 'Lokal Downloads');
      expect(p.dirname(saved.path), p.join(fallback, 'The Artist', 'Album'));
      expect(registered, [fallback]);
      expect(upserts.single.folderUri, fallback);
      expect(upserts.single.relativeFolderPath, 'The Artist/Album');
    },
  );

  test('fails with a message when nothing can be written', () async {
    File(p.join(root.path, 'Music')).createSync(); // Music is a file.
    await expectLater(
      downloader(const []).save(prepared()),
      throwsA(isA<DiscoveryException>()),
    );
    expect(upserts, isEmpty);
  });

  test('a missing download is an error', () async {
    cached.deleteSync();
    await expectLater(
      downloader(const []).save(prepared()),
      throwsA(isA<DiscoveryException>()),
    );
  });

  test('file names drop characters file systems refuse', () {
    final song = prepared();
    expect(
      LibraryDownloader.fileName(song, '.mp3'),
      'The Artist - Song One.mp3',
    );
    expect(
      LibraryDownloader.fileName(
        Song(
          id: 'x',
          title: '..',
          artist: '/',
          duration: Duration.zero,
          fileType: 'MP3',
        ),
        '.mp3',
      ),
      'Song.mp3',
    );
  });

  test(
    'a Monochrome FLAC download keeps catalogue title, artist, album and cover',
    () async {
      final flac = File(p.join(root.path, 'cache', '155142501534011392.flac'));
      await flac.writeAsBytes(List.filled(64, 7));
      final song = Song(
        id: 'discovery:mono',
        title: 'Get Lucky',
        artist: 'Daft Punk',
        album: 'Random Access Memories',
        duration: const Duration(seconds: 370),
        fileType: 'FLAC',
        filePath: flac.path,
        sourceDisplayName: 'Monochrome',
        isExternal: true,
      );
      final music = Directory(p.join(root.path, 'Library'))..createSync();
      final saved = await downloader([
        LibraryDownloadFolder(
          uri: 'test-library',
          name: 'Music',
          path: music.path,
        ),
      ]).save(song, artwork: 'https://tracks.monochrome.st/cover.jpg');

      expect(p.basename(saved.path), 'Daft Punk - Get Lucky.flac');
      expect(upserts.single.title, 'Get Lucky');
      expect(upserts.single.artist, 'Daft Punk');
      expect(upserts.single.album, 'Random Access Memories');
      expect(upserts.single.fileType, 'FLAC');
      expect(upserts.single.hasLocalEdits, isFalse);
      expect(tags, [
        saved.path,
      ], reason: 'FLAC tags must be written into the file');
      expect(covers, ['https://tracks.monochrome.st/cover.jpg']);
    },
  );
}
