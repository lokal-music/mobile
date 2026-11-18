import 'package:flick/services/motion_art/animated_artwork_service.dart';
import 'package:flick/services/motion_art/moving_cover_availability.dart';
import 'package:flick/services/motion_art/moving_cover_settings.dart';
import 'package:flutter_test/flutter_test.dart';

const _song = (
  title: 'Track A',
  artist: 'Artist',
  album: 'Album',
  duration: Duration(minutes: 3),
  sourceRevision: 0,
  spotifySessionRevision: 0,
  artworkRevision: 0,
  networkRevision: 0,
);

MotionArtLookup _motion(String source) => MotionArtLookup(
  artwork: AnimatedArtwork(
    name: 'Album',
    artist: 'Artist',
    albumId: '$source:track-a',
    animatedUrl: 'https://example.test/motion.m3u8',
  ),
);

void main() {
  test('no enabled artwork sources: no footer Cover button and no lookup', () async {
    var called = 0;
    final result = await hasAvailableMovingCover(
      song: _song,
      settings: const MovingCoverSettings(sources: <String>{}),
      lookup: ({required title, required artist, album, duration, settings}) async {
        called++;
        return _motion('apple');
      },
    );
    expect(result, isFalse);
    expect(called, 0);
  });

  test('static album art never qualifies as a moving cover', () async {
    final result = await hasAvailableMovingCover(
      song: _song,
      settings: const MovingCoverSettings(sources: {'apple'}),
      lookup: ({required title, required artist, album, duration, settings}) async {
        return const MotionArtLookup(
          artwork: AnimatedArtwork(
            name: 'Album',
            artist: 'Artist',
            albumId: 'apple:track-a',
            staticUrl: 'https://example.test/cover.jpg',
          ),
        );
      },
    );
    expect(result, isFalse);
  });

  test('Apple Music motion art makes the Cover action available', () async {
    final result = await hasAvailableMovingCover(
      song: _song,
      settings: const MovingCoverSettings(sources: {'apple'}),
      lookup: ({required title, required artist, album, duration, settings}) async {
        expect(title, 'Track A');
        expect(artist, 'Artist');
        expect(settings!.order, ['apple']);
        return _motion('apple');
      },
    );
    expect(result, isTrue);
  });

  test('Spotify Canvas qualifies even with per-song playback disabled', () async {
    final result = await hasAvailableMovingCover(
      song: _song,
      settings: const MovingCoverSettings(
        sources: {'spotify'},
        disabledSongs: {'artist|track a'},
      ),
      lookup: ({required title, required artist, album, duration, settings}) async {
        expect(settings!.order, ['spotify']);
        expect(settings.disabledSongs, isNotEmpty);
        return _motion('spotify');
      },
    );
    expect(result, isTrue,
        reason: 'An existing Canvas must remain toggleable after disabling it');
  });

  test('availability is per song, without inheriting previous motion art', () async {
    Future<MotionArtLookup> lookup({
      required String title,
      required String artist,
      String? album,
      Duration? duration,
      MovingCoverSettings? settings,
    }) async => title == 'Track A'
        ? _motion('spotify')
        : const MotionArtLookup();
    const settings = MovingCoverSettings(sources: {'spotify'});
    expect(
      await hasAvailableMovingCover(song: _song, settings: settings, lookup: lookup),
      isTrue,
    );
    expect(
      await hasAvailableMovingCover(
        song: (
          title: 'Track B',
          artist: 'Artist',
          album: 'Album',
          duration: Duration(minutes: 3),
          sourceRevision: 0,
          spotifySessionRevision: 0,
          artworkRevision: 0,
  networkRevision: 0,
        ),
        settings: settings,
        lookup: lookup,
      ),
      isFalse,
    );
  });

  test('unavailable artwork provider does not interrupt player', () async {
    expect(
      await hasAvailableMovingCover(
        song: _song,
        settings: const MovingCoverSettings(sources: {'spotify'}),
        lookup: ({required title, required artist, album, duration, settings}) =>
            Future<MotionArtLookup>.error(StateError('Spotify session expired')),
      ),
      isFalse,
    );
  });
}
