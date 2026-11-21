import 'package:flutter_test/flutter_test.dart';
import 'package:flick/features/songs/widgets/song_actions_bottom_sheet.dart';
import 'package:flick/models/song.dart';

Song _song(String id) => Song(
  id: id,
  title: 'Song $id',
  artist: 'Artist',
  duration: const Duration(minutes: 3),
  fileType: 'FLAC',
);

void main() {
  group('full-player overflow visibility', () {
    test('motion cover and Watch video do not duplicate player footer', () {
      expect(showMovingCoverMenuAction(nowPlaying: true), isFalse);
      expect(
        showWatchVideoMenuAction(nowPlaying: true, videosEnabled: true),
        isFalse,
      );
      // The library/queue song menu retains its separate capabilities.
      expect(showMovingCoverMenuAction(nowPlaying: false), isTrue);
      expect(
        showWatchVideoMenuAction(nowPlaying: false, videosEnabled: true),
        isTrue,
      );
      expect(
        showWatchVideoMenuAction(nowPlaying: false, videosEnabled: false),
        isFalse,
      );
      // Classic player retains browsing actions while suppressing duplicates.
      expect(
        showMovingCoverMenuAction(nowPlaying: false, hideMediaActions: true),
        isFalse,
      );
      expect(
        showWatchVideoMenuAction(
          nowPlaying: false,
          videosEnabled: true,
          hideMediaActions: true,
        ),
        isFalse,
      );
    });

    test('Send to desktop is only available for local files when paired', () {
      expect(
        showSendToDesktopMenuAction(localFile: true, connected: true),
        isTrue,
      );
      expect(
        showSendToDesktopMenuAction(localFile: false, connected: true),
        isFalse,
      );
      expect(
        showSendToDesktopMenuAction(localFile: true, connected: false),
        isFalse,
      );
    });

    test('Now Playing menu follows a new track while it is open', () {
      final original = _song('original');
      final next = _song('next');
      expect(
        songForOpenMenu(
          nowPlaying: true,
          openedSong: original,
          currentSong: next,
        ),
        same(next),
      );
      expect(
        songForOpenMenu(
          nowPlaying: false,
          openedSong: original,
          currentSong: next,
        ),
        same(original),
      );
      expect(
        songForOpenMenu(
          nowPlaying: true,
          openedSong: original,
          currentSong: null,
        ),
        isNull,
      );
    });
  });
}
