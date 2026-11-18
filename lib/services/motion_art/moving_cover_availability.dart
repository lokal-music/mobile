import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'animated_artwork_service.dart';
import 'moving_cover_service.dart';
import 'moving_cover_settings.dart';

/// Identity of the currently displayed recording and revisions of the
/// configured art sources. Per-song enable/disable is deliberately NOT part
/// of this key: a disabled song with real motion must still offer "Cover" so
/// the user can turn it back on.
typedef MovingCoverAvailabilityKey = ({
  String title,
  String artist,
  String? album,
  Duration duration,
  int sourceRevision,
  int spotifySessionRevision,
  int artworkRevision,
  int networkRevision,
});

typedef MovingCoverLookup = Future<MotionArtLookup> Function({
  required String title,
  required String artist,
  String? album,
  Duration? duration,
  MovingCoverSettings? settings,
});

/// Same coalesced/cached lookup that MotionArtView uses to load video.
/// Spotify Canvas is one of these sources when enabled in settings.
final movingCoverLookupProvider = Provider<MovingCoverLookup>(
  (ref) => MovingCoverService.instance.lookup,
);

Future<bool> hasAvailableMovingCover({
  required MovingCoverAvailabilityKey song,
  required MovingCoverSettings settings,
  required MovingCoverLookup lookup,
}) async {
  if (settings.order.isEmpty) return false;
  try {
    final result = await lookup(
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: song.duration,
      settings: settings,
    );
    // A static image is not a moving cover. This also accepts Spotify Canvas
    // when it is the source of the returned motion clip.
    return result.artwork?.hasMotion == true;
  } catch (_) {
    // An unavailable art service must never interrupt the full player.
    return false;
  }
}

/// Async availability is keyed by song, not by the whole player. A new song
/// cannot inherit the preceding song's Cover button while lookup is pending.
final movingCoverAvailabilityProvider =
    FutureProvider.autoDispose.family<bool, MovingCoverAvailabilityKey>(
  (ref, song) {
    // A per-track Cover toggle only changes disabledSongs; it must not
    // invalidate availability and briefly make its own button disappear.
    // Source changes (including enabling Spotify Canvas) do trigger a probe.
    ref.watch(movingCoverSettingsProvider.select((s) => s.order.join(',')));
    return hasAvailableMovingCover(
      song: song,
      settings: ref.read(movingCoverSettingsProvider),
      lookup: ref.watch(movingCoverLookupProvider),
    );
  },
);
