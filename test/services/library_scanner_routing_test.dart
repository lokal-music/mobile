import 'package:flick/services/library_scanner_service.dart';
import 'package:flick/data/entities/song_entity.dart';
import 'package:test/test.dart';

void main() {
  test('ordinary iPhone scans repair old sparse album rows despite cached timestamps', () {
    final song = SongEntity()..metadataComplete = true;
    expect(
      LibraryScannerService.canReuseAlbumScanFingerprint(song, isIOS: true),
      isFalse,
    );
    expect(
      LibraryScannerService.canReuseAlbumScanFingerprint(song, isIOS: false),
      isTrue,
      reason: 'Android scan policy stays unchanged',
    );
    song.albumArtist = ' ';
    expect(
      LibraryScannerService.canReuseAlbumScanFingerprint(song, isIOS: true),
      isFalse,
    );
    song.albumArtist = 'Album owner';
    expect(
      LibraryScannerService.canReuseAlbumScanFingerprint(song, isIOS: true),
      isTrue,
      reason: 'completed repair is not rescanned forever',
    );
    song.albumArtist = null;
    song.hasLocalEdits = true;
    expect(
      LibraryScannerService.canReuseAlbumScanFingerprint(song, isIOS: true),
      isTrue,
      reason: 'never replace user-edited tags automatically',
    );
  });
  group('chooseAndroidScanEngine', () {
    test('all-files access with readable path routes to Rust walk', () {
      expect(
        LibraryScannerService.chooseAndroidScanEngine(
          allFilesAccess: true,
          hasReadableFsPath: true,
          useDeepScan: false,
          isRemovable: false,
        ),
        'rust',
      );
    });

    test('all-files access covers removable volumes too', () {
      expect(
        LibraryScannerService.chooseAndroidScanEngine(
          allFilesAccess: true,
          hasReadableFsPath: true,
          useDeepScan: false,
          isRemovable: true,
        ),
        'rust',
      );
    });

    test('all-files access collapses the deep-scan flag', () {
      expect(
        LibraryScannerService.chooseAndroidScanEngine(
          allFilesAccess: true,
          hasReadableFsPath: true,
          useDeepScan: true,
          isRemovable: true,
        ),
        'rust',
      );
    });

    test('all-files access without readable path falls back to SAF', () {
      expect(
        LibraryScannerService.chooseAndroidScanEngine(
          allFilesAccess: true,
          hasReadableFsPath: false,
          useDeepScan: false,
          isRemovable: true,
        ),
        'saf',
      );
    });

    test('scoped normal scan with path uses MediaStore', () {
      expect(
        LibraryScannerService.chooseAndroidScanEngine(
          allFilesAccess: false,
          hasReadableFsPath: true,
          useDeepScan: false,
          isRemovable: false,
        ),
        'mediaStore',
      );
    });

    test('scoped deep scan on primary uses Rust', () {
      expect(
        LibraryScannerService.chooseAndroidScanEngine(
          allFilesAccess: false,
          hasReadableFsPath: true,
          useDeepScan: true,
          isRemovable: false,
        ),
        'rust',
      );
    });

    test('scoped deep scan on removable prefers MediaStore', () {
      expect(
        LibraryScannerService.chooseAndroidScanEngine(
          allFilesAccess: false,
          hasReadableFsPath: true,
          useDeepScan: true,
          isRemovable: true,
        ),
        'mediaStore',
      );
    });

    test('scoped scan without path uses SAF', () {
      expect(
        LibraryScannerService.chooseAndroidScanEngine(
          allFilesAccess: false,
          hasReadableFsPath: false,
          useDeepScan: false,
          isRemovable: false,
        ),
        'saf',
      );
    });

    test('SAF folder without all-files or media-audio permission routes directly to SAF', () {
      for (final useDeepScan in [false, true]) {
        for (final isRemovable in [false, true]) {
          expect(
            LibraryScannerService.chooseAndroidScanEngine(
              allFilesAccess: false,
              hasReadableFsPath: true,
              useDeepScan: useDeepScan,
              isRemovable: isRemovable,
              hasMediaAudioPermission: false,
              isSafUri: true,
            ),
            'saf',
            reason: 'useDeepScan=$useDeepScan isRemovable=$isRemovable',
          );
        }
      }
    });

    test('SAF folder with all-files access still prefers Rust walk', () {
      expect(
        LibraryScannerService.chooseAndroidScanEngine(
          allFilesAccess: true,
          hasReadableFsPath: true,
          useDeepScan: false,
          isRemovable: false,
          hasMediaAudioPermission: true,
          isSafUri: true,
        ),
        'rust',
      );
    });
  });

  group('shouldRustRetryMetadata', () {
    test('wavpack and dsd always retry through the rust parsers', () {
      for (final ext in ['wv', 'dsf', 'dff']) {
        expect(
          LibraryScannerService.shouldRustRetryMetadata(
            extension: ext,
            hasMetadata: true,
            hasSampleRate: true,
            hasDuration: true,
          ),
          isTrue,
          reason: ext,
        );
      }
    });

    test('flac without a sample rate retries (hi-res retriever failure)', () {
      expect(
        LibraryScannerService.shouldRustRetryMetadata(
          extension: 'flac',
          hasMetadata: true,
          hasSampleRate: false,
          hasDuration: true,
        ),
        isTrue,
      );
    });

    test('flac without a duration retries', () {
      expect(
        LibraryScannerService.shouldRustRetryMetadata(
          extension: 'flac',
          hasMetadata: true,
          hasSampleRate: true,
          hasDuration: false,
        ),
        isTrue,
      );
    });

    test('missing retriever row retries for any extension', () {
      expect(
        LibraryScannerService.shouldRustRetryMetadata(
          extension: 'm4a',
          hasMetadata: false,
          hasSampleRate: false,
          hasDuration: false,
        ),
        isTrue,
      );
    });

    test('solved stream layout does not retry', () {
      expect(
        LibraryScannerService.shouldRustRetryMetadata(
          extension: 'flac',
          hasMetadata: true,
          hasSampleRate: true,
          hasDuration: true,
        ),
        isFalse,
      );
    });

    test('missing bit depth alone does not retry (lossy codecs)', () {
      expect(
        LibraryScannerService.shouldRustRetryMetadata(
          extension: 'mp3',
          hasMetadata: true,
          hasSampleRate: true,
          hasDuration: true,
        ),
        isFalse,
      );
    });

    test('extension-less content uris still retry when unsolved', () {
      expect(
        LibraryScannerService.shouldRustRetryMetadata(
          extension: '',
          hasMetadata: true,
          hasSampleRate: false,
          hasDuration: true,
        ),
        isTrue,
      );
    });
  });
}
