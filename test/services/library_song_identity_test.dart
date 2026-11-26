import 'package:flick/models/song.dart';
import 'package:flick/services/link/library_song_identity.dart';
import 'package:flutter_test/flutter_test.dart';

Song song(
  String id,
  String title,
  String path, {
  String artist = 'Artist',
  String? albumArtist,
  String? album = 'Album',
  String? source,
  Duration duration = const Duration(minutes: 3),
}) => Song(
  id: id,
  title: title,
  artist: artist,
  albumArtist: albumArtist,
  album: album,
  duration: duration,
  fileType: 'FLAC',
  filePath: path,
  sourceType: source,
);

void main() {
  test('Mornye FLAC split ARTIST values do not duplicate linked song', () {
    // Uploaded FLAC: ARTIST=SZA, ARTIST=Kendrick Lamar,
    // ALBUMARTIST=SZA, DISPLAY ARTIST=SZA; Kendrick Lamar.
    // Android can expose the second ARTIST value while desktop uses SZA.
    final phone = song(
      'phone-30', '30 For 30 (with Kendrick Lamar)',
      '/storage/Music/SZA - 30 For 30 (with Kendrick Lamar).flac',
      artist: 'Kendrick Lamar', album: 'SOS Deluxe: LANA',
      duration: const Duration(milliseconds: 278277),
    );
    final desktop = song(
      'pc-30', '30 For 30 (with Kendrick Lamar)',
      'lokal://desktop/30', artist: 'SZA', albumArtist: 'SZA',
      album: 'SOS Deluxe: LANA', source: 'lokal',
      duration: const Duration(milliseconds: 278000),
    );
    for (final entries in [[desktop, phone], [phone, desktop]]) {
      final index = preferredLibrarySongIndex(entries);
      expect(index.visible.map((s) => s.id).toList(), ['phone-30']);
      expect(index.byId['pc-30'], same(phone));
      expect(index.byId['phone-30'], same(phone));
    }
  });

  test('different artists without named featured credit remain independent', () {
    final phone = song('phone', 'Duet', '/music/duet.flac',
        artist: 'Kendrick Lamar', album: 'SOS Deluxe: LANA');
    final pc = song('pc', 'Duet', 'lokal://desktop/duet',
        artist: 'SZA', albumArtist: 'SZA', album: 'SOS Deluxe: LANA',
        source: 'lokal');
    expect(preferLocalLibrarySongs([phone, pc]), [phone, pc]);
    final otherAlbum = song('pc2', 'Duet (with Kendrick Lamar)',
        'lokal://desktop/duet2', artist: 'SZA', albumArtist: 'SZA',
        album: 'Different Album', source: 'lokal');
    final phoneWithTitle = song('phone2', 'Duet (with Kendrick Lamar)',
        '/music/other.flac', artist: 'Kendrick Lamar',
        album: 'SOS Deluxe: LANA');
    expect(preferLocalLibrarySongs([phoneWithTitle, otherAlbum]),
        [phoneWithTitle, otherAlbum]);
  });

  test('album artist wins display when Android exposes only a featured artist', () {
    final phone = song('phone', '30 For 30 (with Kendrick Lamar)',
      '/music/sza.flac', artist: 'Kendrick Lamar',
      albumArtist: 'SZA', album: 'SOS Deluxe: LANA');
    expect(creditedLeadArtist(phone), 'SZA');
    // Track credits remain intact; only the presentation changes.
    expect(phone.artist, 'Kendrick Lamar');
  });

  test('album owner remains the lead when the full credit lists multiple artists', () {
    final phone = song('phone', 'All the Stars', '/music/stars.flac',
      artist: 'SZA', albumArtist: 'SZA');
    final pc = song('pc', 'All the Stars', 'lokal://1/stars',
      artist: 'Kendrick Lamar, SZA', albumArtist: 'SZA', source: 'lokal');
    expect(creditedLeadArtist(pc), 'SZA');
    final index = preferredLibrarySongIndex([pc, phone]);
    expect(index.visible.map((s) => s.id), ['phone']);
    expect(index.byId['pc']?.id, 'phone');
  });

  test(
    '5500 phone songs retain order, identity and lookups without desktop rows',
    () {
      final library = [
        for (var i = 0; i < 5500; i++)
          song('$i', 'Song $i (2011 Remaster)', '/music/$i.flac'),
      ];
      final remote = song(
        'remote',
        'Remote',
        'webdav://1/song',
        source: 'webdav',
      );
      final ghost = song('ghost', 'Ghost', 'ghost://1/song', source: 'lokal');
      final index = preferredLibrarySongIndex([...library, remote, ghost]);
      expect(index.visible, [...library, remote]);
      expect(index.byId.length, 5501);
      for (final original in library) {
        expect(identical(index.byId[original.id], original), true);
      }
      expect(index.byId['ghost'], isNull);
    },
  );


  test('album owner is the display lead for local and linked featured credits', () {
    final mobile = song(
      'local', 'SZA song', '/music/sza.flac',
      artist: 'Kendrick Lamar, SZA', albumArtist: 'SZA',
    );
    final desktop = song(
      'desktop', 'Seedhe Maut song', 'lokal://1/sm',
      artist: 'Badshah, Seedhe Maut', albumArtist: 'Seedhe Maut',
      source: 'lokal',
    );
    expect(creditedLeadArtist(mobile), 'SZA');
    expect(creditedLeadArtist(desktop), 'Seedhe Maut');
    // The underlying credits are intentionally not rewritten.
    expect(mobile.artist, 'Kendrick Lamar, SZA');
    expect(desktop.artist, 'Badshah, Seedhe Maut');
  });

  test('album owner must be a whole credited name, not a substring', () {
    final pc = song('pc', 'Track', 'lokal://1/track',
      artist: 'Annabelle, Bob', albumArtist: 'Anna', source: 'lokal');
    expect(creditedLeadArtist(pc), 'Anna'); // ALBUMARTIST is the display lead.
    final phone = song('phone', 'Track', '/music/track.flac',
      artist: 'Anna', albumArtist: 'Anna');
    final index = preferredLibrarySongIndex([pc, phone]);
    expect(index.visible.map((s) => s.id), ['pc', 'phone']);
  });

  test('history ghosts stay hidden, desktop-only songs stay available', () {
    final local = song('1', 'Local', '/music/local.flac');
    final duplicate = song('2', 'Local', 'lokal://1/2', source: 'lokal');
    final ghost = song(
      '3',
      'Streamed once',
      'ghost://desktop/1/3',
      source: 'lokal',
    );
    final owned = song('4', 'PC file', 'lokal://1/4', source: 'lokal');
    expect(
      preferLocalLibrarySongs([local, duplicate, ghost, owned])
          .map((s) => s.id),
      ['1', '4'],
    );
  });

  test('mobile version wins over desktop featured-credit variant', () {
    final phone = song(
      'phone',
      'Sun Is Rising',
      '/storage/emulated/0/Music/sun.flac',
      artist: 'Ships of the Pharaohs, Last Nubian',
      duration: const Duration(minutes: 4, seconds: 3),
    );
    final desktop = song(
      'pc',
      'Sun Is Rising',
      'lokal://1/track',
      artist: 'Ships of the Pharaohs',
      source: 'lokal',
      duration: const Duration(minutes: 4, seconds: 2),
    );
    expect(preferLocalLibrarySongs([desktop, phone]).map((s) => s.id),
        ['phone']);
    // Deduplication must work independently of incoming sort order.
    expect(preferLocalLibrarySongs([phone, desktop]).map((s) => s.id),
        ['phone']);
  });

  test('credits and recording title normalize without fuzzy lookalikes', () {
    final local = song('phone', 'Halo (2011 Remaster)',
        '/storage/Music/halo.flac', artist: 'Beyoncé feat. Jay-Z');
    final pc = song('pc', 'Halo', 'lokal://1/2',
        artist: 'Beyonce', source: 'lokal');
    // A punctuation-normalized, version-labeled track is not a second copy.
    expect(preferLocalLibrarySongs([local, pc]).map((s) => s.id),
        ['phone']);
  });

  test('different versions, masters and artists remain separate', () {
    final local = song('phone', 'Sun Is Rising',
        '/storage/Music/sun.flac', artist: 'Ships of the Pharaohs',
        duration: const Duration(minutes: 4, seconds: 3));
    final wrongArtist = song('otherArtist', 'Sun Is Rising',
        'lokal://1/other', artist: 'Another Artist', source: 'lokal',
        duration: const Duration(minutes: 4, seconds: 3));
    final remix = song('remix', 'Sun Is Rising (Remix)',
        'lokal://1/remix', artist: 'Ships of the Pharaohs',
        source: 'lokal', duration: const Duration(minutes: 4, seconds: 3));
    final differentLength = song('long', 'Sun Is Rising',
        'lokal://1/long', artist: 'Ships of the Pharaohs',
        source: 'lokal', duration: const Duration(minutes: 4, seconds: 8));
    final differentAlbum = song('otherAlbum', 'Sun Is Rising',
        'lokal://1/album', artist: 'Ships of the Pharaohs',
        album: 'Different Release', source: 'lokal',
        duration: const Duration(minutes: 4, seconds: 3));
    expect(
      preferLocalLibrarySongs([
        local, wrongArtist, remix, differentLength, differentAlbum
      ]).map((s) => s.id),
      ['phone', 'otherArtist', 'remix', 'long', 'otherAlbum'],
    );
  });

  test('no local copy: keep a remotely synced recording', () {
    final remote = song('remote', 'PC only', 'lokal://1/remote',
        source: 'lokal');
    final server = song('navidrome', 'Server only', 'subsonic://7/remote',
        source: 'subsonic');
    expect(preferLocalLibrarySongs([remote, server]).map((s) => s.id),
        ['remote', 'navidrome']);
  });

  test('unknown durations, ghosts and pending local sources cannot hide PCs',
      () {
    final pc = song('pc', 'Track', 'lokal://1/track', source: 'lokal');
    final emptyLength = song('empty', 'Track', '/music/unknown.flac',
        duration: Duration.zero);
    final noPath = song('noPath', 'Track', '',
        duration: const Duration(minutes: 3));
    final ghost = song('ghost', 'Track', 'ghost://desktop/track',
        source: 'lokal');
    expect(
      preferLocalLibrarySongs([pc, emptyLength, noPath, ghost])
          .map((s) => s.id),
      ['pc', 'empty', 'noPath'],
    );
  });

  test('missing album on one side still resolves a strong recording match', () {
    final phone = song('phone', 'Sun Is Rising', '/music/sun.flac',
        album: '', artist: 'Ships of the Pharaohs');
    final pc = song('pc', 'Sun Is Rising', 'lokal://1/a',
        album: 'Greatest Hits', artist: 'Ships of the Pharaohs',
        source: 'lokal');
    expect(preferLocalLibrarySongs([pc, phone]).map((s) => s.id),
        ['phone']);
  });
  test('playlist lookup retains IDs hidden by deduplication', () {
    final phone = song('phone', 'Same song', '/music/song.flac');
    final desktop = song('desktop', 'Same song', 'lokal://1/song',
        source: 'lokal');
    final ghost = song('ghost', 'History', 'ghost://1/history',
        source: 'lokal');
    final index = preferredLibrarySongIndex([desktop, phone, ghost]);

    expect(index.visible.map((s) => s.id), ['phone']);
    expect(index.byId['desktop'], same(phone));
    expect(index.byId['phone'], same(phone));
    expect(index.byId.containsKey('ghost'), isFalse);
  });

  test('a nonmatching desktop version keeps its own playlist identity', () {
    final phone = song('phone', 'Same song', '/music/song.flac');
    final remix = song('remix', 'Same song (Live)', 'lokal://1/live',
        source: 'lokal');
    final index = preferredLibrarySongIndex([phone, remix]);
    expect(index.byId['remix'], same(remix));
    expect(index.visible, [phone, remix]);
  });

  test('transfer artifacts in local or desktop titles still deduplicate cleanly', () {
    final phone = song(
      'phone-corrupt',
      'Daft Punk - Digital Love - 11111111-2222-3333-4444-555555555555-r1',
      '/music/Digital Love.flac',
      artist: '<unknown>',
      album: 'Discovery',
    );
    final pc = song(
      'pc-clean',
      'Digital Love [0123456789abcdef]',
      'lokal://1/dl',
      artist: 'Daft Punk',
      album: 'Discovery',
      source: 'lokal',
    );
    final index = preferredLibrarySongIndex([pc, phone]);
    expect(index.visible.map((s) => s.id), ['phone-corrupt']);
    expect(index.byId['pc-clean'], same(phone));
  });

  test('multi-PC lokal:// rows deduplicate to highest quality and alias byId', () {
    final pc1 = Song(
      id: 'pc1-cd',
      title: 'Midnight City',
      artist: 'M83',
      album: 'Hurry Up, We\'re Dreaming',
      duration: const Duration(seconds: 243),
      fileType: 'FLAC',
      filePath: 'lokal://1/mc',
      sourceType: 'lokal',
      remoteServerId: 1,
      remoteId: 'mc-1',
      bitDepth: 16,
      sampleRate: 44100,
      resolution: '16-bit / 44.1kHz / 900 kbps',
    );
    final pc2 = Song(
      id: 'pc2-hires',
      title: 'Midnight City - 99999999-8888-7777-6666-555555555555',
      artist: 'M83',
      album: 'Hurry Up, We\'re Dreaming',
      duration: const Duration(seconds: 244),
      fileType: 'FLAC',
      filePath: 'lokal://2/mc',
      sourceType: 'lokal',
      remoteServerId: 2,
      remoteId: 'mc-2',
      bitDepth: 24,
      sampleRate: 96000,
      resolution: '24-bit / 96kHz / 3100 kbps',
    );
    final pc3 = Song(
      id: 'pc3-mp3',
      title: 'Midnight City',
      artist: 'M83',
      album: 'Unknown Album',
      duration: const Duration(seconds: 243),
      fileType: 'MP3',
      filePath: 'lokal://3/mc',
      sourceType: 'lokal',
      remoteServerId: 3,
      remoteId: 'mc-3',
      resolution: '320 kbps',
    );

    final index = preferredLibrarySongIndex([pc1, pc2, pc3]);
    expect(index.visible.map((s) => s.id), ['pc2-hires']);
    expect(index.byId['pc1-cd'], same(pc2));
    expect(index.byId['pc2-hires'], same(pc2));
    expect(index.byId['pc3-mp3'], same(pc2));

    // Equal quality keeps first and still aliases duplicates.
    final equalA = song('pcA', 'Equal Track', 'lokal://1/eq', source: 'lokal');
    final equalB = song('pcB', 'Equal Track', 'lokal://2/eq', source: 'lokal');
    final equalIndex = preferredLibrarySongIndex([equalA, equalB]);
    expect(equalIndex.visible.map((s) => s.id), ['pcA']);
    expect(equalIndex.byId['pcB'], same(equalA));
  });
}
