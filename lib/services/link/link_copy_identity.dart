import '../../models/song.dart';
import 'link_protocol.dart';
import 'link_song_bindings.dart';
import 'transfer_artifact_cleaner.dart';

/// Candidates only: the desktop must confirm the original file still exists.
/// IDs belong to one paired server and must never match another PC by accident.
class LinkCopyIdentity {
  LinkCopyIdentity({
    required this.serverId,
    required List<Map<String, dynamic>> tracks,
  }) {
    for (final track in tracks) {
      final id = track['id']?.toString();
      if (id == null || id.isEmpty) continue;
      _byId[id] = track;
      final cleaned = cleanTransferMetadata(
        title: track['title']?.toString() ?? '',
        artist: track['artist']?.toString() ?? '',
      );
      _byName
          .putIfAbsent(_key(cleaned.artist, cleaned.title), () => [])
          .add(track);
    }
  }
  final int serverId;
  final _byId = <String, Map<String, dynamic>>{};
  final _byName = <String, List<Map<String, dynamic>>>{};
  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  static String _key(String artist, String title) =>
      '${_normalize(artist)}\u0000${_normalize(title)}';

  String resolverKey(Song song) {
    final boundRemoteId = LinkSongBindings.instance.remoteIdForSong(
      song,
      serverId,
    );
    final original = boundRemoteId != null ? _byId[boundRemoteId] : null;
    final seconds = original?['duration'];
    if (original != null &&
        seconds is num &&
        seconds.isFinite &&
        seconds >= 0) {
      final cleanedOriginal = cleanTransferMetadata(
        title: original['title']?.toString() ?? '',
        artist: original['artist']?.toString() ?? '',
      );
      return linkTrackKey(
        cleanedOriginal.artist,
        cleanedOriginal.title,
        Duration(milliseconds: (seconds * 1000).round()),
      );
    }
    final cleaned = cleanTransferMetadata(
      title: song.title,
      artist: song.artist,
    );
    return linkTrackKey(cleaned.artist, cleaned.title, song.duration);
  }

  List<String> candidates(Song song) {
    final result = <String>{};
    final boundRemoteId = LinkSongBindings.instance.remoteIdForSong(
      song,
      serverId,
    );
    if (boundRemoteId != null && _byId.containsKey(boundRemoteId)) {
      result.add(boundRemoteId);
    }
    // Metadata remains a fallback for independently scanned copies. Never use
    // a title alone, fuzzy substring matching or an unknown/zero duration.
    final cleaned = cleanTransferMetadata(
      title: song.title,
      artist: song.artist,
    );
    if (song.duration > Duration.zero &&
        cleaned.artist.trim().isNotEmpty &&
        cleaned.title.trim().isNotEmpty) {
      for (final track
          in _byName[_key(cleaned.artist, cleaned.title)] ??
              <Map<String, dynamic>>[]) {
        final duration = track['duration'];
        if (duration is num &&
            duration.isFinite &&
            duration > 0 &&
            (duration - song.duration.inMilliseconds / 1000).abs() <= 2) {
          result.add(track['id'].toString());
        }
      }
    }
    return result.toList();
  }
}
