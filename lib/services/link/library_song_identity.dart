import 'package:flick/features/discovery/recommendation_match.dart'
    show leadArtist, recommendationKey, titleKey;
import 'package:flick/models/song.dart';
import 'package:flick/core/utils/artist_credits.dart' show splitArtistCredits;

import 'transfer_artifact_cleaner.dart';

class _KeptDesktopGroup {
  _KeptDesktopGroup({required this.visibleIndex, required this.kept});

  final int visibleIndex;
  Song kept;
  final List<String> memberIds = [];
}

int _parsedBitrateKbps(Song song) {
  final res = song.resolution;
  if (res == null || res.isEmpty) return 0;
  final match = RegExp(r'(\d+)\s*kbps', caseSensitive: false).firstMatch(res);
  return match == null ? 0 : (int.tryParse(match.group(1)!) ?? 0);
}

bool _isHigherDesktopQuality(Song candidate, Song current) {
  final candBits = candidate.bitDepth ?? 0;
  final currBits = current.bitDepth ?? 0;
  if (candBits != currBits) return candBits > currBits;

  final candRate = candidate.sampleRate ?? 0;
  final currRate = current.sampleRate ?? 0;
  if (candRate != currRate) return candRate > currRate;

  final candBitrate = _parsedBitrateKbps(candidate);
  final currBitrate = _parsedBitrateKbps(current);
  if (candBitrate != currBitrate) return candBitrate > currBitrate;

  return false;
}

/// The desktop keeps the complete track credits. Where the album artist
/// actually appears among a multi-artist credit, it identifies the release's
/// lead without discarding Kendrick/SZA-style featured credits.
String creditedLeadArtist(Song song) {
  final cleaned = cleanTransferMetadata(title: song.title, artist: song.artist);
  final artist = cleaned.artist.trim();
  final owner = song.albumArtist?.trim() ?? '';
  // Album ownership is the display lead, even if Android exposes only the
  // second repeated Vorbis ARTIST value (e.g. Kendrick instead of SZA).
  // Compilations and absent/placeholder album artists keep track credits.
  final generic = owner.toLowerCase();
  if (owner.isNotEmpty &&
      generic != 'unknown artist' &&
      generic != 'various artists' &&
      generic != 'va') {
    return leadArtist(owner);
  }
  return leadArtist(artist);
}

/// Visible library rows and a lookup for existing playlist IDs. An imported
/// desktop song may be hidden in the library in favour of an equivalent local
/// recording, but that must never make a saved playlist entry disappear.
class PreferredLibrarySongIndex {
  const PreferredLibrarySongIndex({
    required this.visible,
    required this.byId,
    this.desktopCopiesByPhoneId = const {},
  });

  final List<Song> visible;

  /// Includes aliases from suppressed desktop track IDs to their phone copies
  /// (and from duplicate multi-PC desktop rows to the kept desktop row).
  /// Ghost-only history tracks are intentionally absent.
  final Map<String, Song> byId;

  /// The original desktop IDs suppressed by the same verified library
  /// deduplication decision. Remote control uses these IDs to play the PC
  /// copy; it must not try a title-only handoff for a local recording.
  final Map<String, List<Song>> desktopCopiesByPhoneId;
}

/// Recording-level matching, not fuzzy artwork matching: require a lead
/// artist, normalized title, duration within two seconds, and compatible
/// known album tags. Do not conflate different edits/masters.
/// [recordingReferences] are temporary metadata-only selections for remote
/// lookup; callers displaying the library should leave them empty.
PreferredLibrarySongIndex preferredLibrarySongIndex(
  List<Song> songs, {
  List<Song> recordingReferences = const [],
}) {
  // Most phone libraries have no desktop stream rows to reconcile. Avoid
  // normalizing every title/artist on every artwork or metadata update.
  if (!songs.any(
    (song) =>
        song.sourceType == 'lokal' &&
        !(song.filePath?.startsWith('ghost://') ?? false),
  )) {
    final visible = [
      for (final song in songs)
        if (!(song.filePath?.startsWith('ghost://') ?? false)) song,
    ];
    return PreferredLibrarySongIndex(
      visible: visible,
      byId: {for (final song in visible) song.id: song},
    );
  }

  final cleanedCache = <Song, ({String title, String artist})>{};
  ({String title, String artist}) cleanedFor(Song song) =>
      cleanedCache.putIfAbsent(song, () {
        final c = cleanTransferMetadata(title: song.title, artist: song.artist);
        return (title: c.title, artist: c.artist);
      });

  // Display ownership and recording identity are different. Do not make
  // inferred album ownership merge two unrelated artists in playlists.
  String? recordingKey(Song song) {
    if (song.duration <= Duration.zero) return null;
    final cleaned = cleanedFor(song);
    final rawArtist = cleaned.artist.trim();
    final owner = song.albumArtist?.trim() ?? '';
    final matchingOwner = owner.isNotEmpty &&
        splitArtistCredits(rawArtist).any(
          (credit) => recommendationKey(credit) == recommendationKey(owner),
        );
    final artist = recommendationKey(
      matchingOwner ? leadArtist(owner) : leadArtist(rawArtist),
    );
    final title = titleKey(cleaned.title);
    if (artist.isEmpty || title.isEmpty) return null;
    return '$artist\u0000$title';
  }

  final locallyAvailable = <String, List<Song>>{};
  // A multi-value Vorbis ARTIST tag may be reduced to the featured singer by
  // Android while desktop retains the album's lead artist. Index by title as
  // well so the unusually strong credit/album match below can reconcile them.
  final localByTitle = <String, List<Song>>{};
  // Saved playlist entries can outlive their scanned ID or carry only
  // catalogue metadata. Remote selection may compare those references to
  // desktop recordings without treating them as locally playable files.
  final referenceIds = recordingReferences.map((song) => song.id).toSet();
  for (final song in recordingReferences.followedBy(songs)) {
    if (song.isNetworkSource ||
        (!referenceIds.contains(song.id) &&
            (song.isPending || song.filePath?.isNotEmpty != true)) ||
        song.filePath?.startsWith('ghost://') == true) {
      continue;
    }
    final key = recordingKey(song);
    if (key != null) {
      (locallyAvailable[key] ??= []).add(song);
      (localByTitle[titleKey(cleanedFor(song).title)] ??= []).add(song);
    }
  }

  // Require an explicit featured credit IN THE TRACK TITLE before accepting
  // different lead artists. Equal titles and durations alone are not evidence
  // that two unrelated recordings are identical.
  bool matchesSplitCredit(Song desktop, Song phone) {
    final owner = recommendationKey(desktop.albumArtist);
    final phoneArtist = recommendationKey(creditedLeadArtist(phone));
    final pcArtist = recommendationKey(creditedLeadArtist(desktop));
    if (owner.isEmpty || owner != pcArtist || phoneArtist == pcArtist) {
      return false;
    }
    final localAlbum = recommendationKey(phone.album);
    final pcAlbum = recommendationKey(desktop.album);
    if (localAlbum.isEmpty || pcAlbum.isEmpty || localAlbum != pcAlbum) {
      return false;
    }
    if ((phone.duration - desktop.duration).abs() >
        const Duration(seconds: 1)) {
      return false;
    }
    if (phone.trackNumber != null &&
        desktop.trackNumber != null &&
        phone.trackNumber != desktop.trackNumber) {
      return false;
    }
    if (phone.discNumber != null &&
        desktop.discNumber != null &&
        phone.discNumber != desktop.discNumber) {
      return false;
    }
    // e.g. "30 For 30 (with Kendrick Lamar)": Android exposes the second
    // ARTIST value as the local lead, desktop exposes the album owner SZA.
    final title = cleanedFor(desktop).title.toLowerCase();
    final featured = RegExp(
      r'\b(?:with|feat\.?|ft\.?|featuring)\s+([^)]*)',
      caseSensitive: false,
    ).firstMatch(title)?.group(1);
    if (featured == null || featured.trim().isEmpty) return false;
    final featuredCredits = splitArtistCredits(featured);
    return featuredCredits.any(
      (credit) => recommendationKey(credit) == phoneArtist,
    );
  }

  Song? matchingPhoneCopy(Song desktop) {
    if (desktop.sourceType != 'lokal') return null;
    final key = recordingKey(desktop);
    if (key == null) return null;
    for (final phone in locallyAvailable[key] ?? const <Song>[]) {
      if ((phone.duration - desktop.duration).abs() >
          const Duration(seconds: 2)) {
        continue;
      }

      final localAlbum = recommendationKey(phone.album);
      final desktopAlbum = recommendationKey(desktop.album);
      if (localAlbum.isEmpty ||
          desktopAlbum.isEmpty ||
          localAlbum == desktopAlbum) {
        return phone;
      }
    }
    // Avoid this secondary scan on the normal matching path. Only songs with
    // matching normalized titles are checked, not the entire phone library.
    for (final phone
        in localByTitle[titleKey(cleanedFor(desktop).title)] ??
            const <Song>[]) {
      if (matchesSplitCredit(desktop, phone)) return phone;
    }
    return null;
  }

  final visible = <Song>[];
  final byId = <String, Song>{};
  final desktopCopiesByPhoneId = <String, List<Song>>{};
  final keptDesktopGroups = <String, List<_KeptDesktopGroup>>{};

  for (final song in songs) {
    if (song.filePath?.startsWith('ghost://') ?? false) continue;
    final replacement = matchingPhoneCopy(song);
    if (replacement != null) {
      if (song.remoteId?.isNotEmpty == true &&
          song.remoteServerId != null &&
          song.filePath?.startsWith('lokal://') == true) {
        (desktopCopiesByPhoneId[replacement.id] ??= []).add(song);
      }
      // Retain original IDs as aliases for playlists and other references.
      byId[song.id] = replacement;
      continue;
    }

    if (song.sourceType == 'lokal') {
      final rKey = recordingKey(song);
      if (rKey != null) {
        _KeptDesktopGroup? matchedGroup;
        for (final group in keptDesktopGroups[rKey] ?? const <_KeptDesktopGroup>[]) {
          if ((song.duration - group.kept.duration).abs() <=
              const Duration(seconds: 2)) {
            matchedGroup = group;
            break;
          }
        }
        if (matchedGroup != null) {
          if (_isHigherDesktopQuality(song, matchedGroup.kept)) {
            matchedGroup.kept = song;
            visible[matchedGroup.visibleIndex] = song;
            for (final memberId in matchedGroup.memberIds) {
              byId[memberId] = song;
            }
          }
          matchedGroup.memberIds.add(song.id);
          byId[song.id] = matchedGroup.kept;
          continue;
        }
        final group = _KeptDesktopGroup(
          visibleIndex: visible.length,
          kept: song,
        )..memberIds.add(song.id);
        (keptDesktopGroups[rKey] ??= []).add(group);
      }
    }

    visible.add(song);
    byId[song.id] = song;
  }
  return PreferredLibrarySongIndex(
    visible: visible,
    byId: byId,
    desktopCopiesByPhoneId: desktopCopiesByPhoneId,
  );
}

/// In the library, prefer phone copies to equivalent desktop records.
/// The desktop records remain in the database; saved playlists can resolve
/// their original IDs through [preferredLibrarySongIndex].
List<Song> preferLocalLibrarySongs(List<Song> songs) =>
    preferredLibrarySongIndex(songs).visible;
