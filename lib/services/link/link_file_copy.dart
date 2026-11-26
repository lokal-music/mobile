import 'dart:io';

import 'copy_check_guard.dart';

import '../../data/database.dart';
import '../../data/repositories/song_repository.dart';
import '../../features/discovery/recommendation_match.dart';
import '../../models/lokal_remote_state.dart';
import '../../models/song.dart';
import 'link_journal.dart';
import 'link_copy_identity.dart';
import 'link_song_bindings.dart';
import 'lokal_desktop_source.dart';
import 'lokal_link_service.dart';
import 'transfer_artifact_cleaner.dart';

class LinkCopyPlan {
  const LinkCopyPlan({
    required this.server,
    required this.toDesktop,
    required this.toPhone,
    this.toMusicFolder = const [],
  });
  final NetworkServerEntity server;
  final List<Song> toDesktop;
  final List<({Map<String, dynamic> track, Song? existing})> toPhone;
  final List<Song> toMusicFolder;
  int get total => toDesktop.length + toPhone.length + toMusicFolder.length;
}

/// Explicit, non-destructive copies. Rechecking both catalogues on each attempt
/// makes retries skip completed files without a second transfer queue/database.
class LinkFileCopy {
  LinkFileCopy({
    required this.credentials,
    required this.socket,
    required this.connected,
    required this.onProgress,
  }) : _libraryEpoch = LokalDesktopSource.instance.libraryTransferEpoch;
  final int _libraryEpoch;
  bool get _currentLibrary =>
      _libraryEpoch == LokalDesktopSource.instance.libraryTransferEpoch;
  final LokalRemoteCredentials credentials;
  final LokalLinkService socket;
  final bool Function() connected;
  final void Function(LinkCopyProgress) onProgress;

  final _preview = CopyCheckGuard();
  bool get cancelled => _preview.stopped;
  void cancel() => _preview.cancel();
  void _checking(String stage, {int processed = 0, int total = 0}) {
    _check();
    _preview.pulse();
    onProgress(
      LinkCopyProgress(
        phase: LinkCopyPhase.checking,
        currentTitle: stage,
        processed: processed,
        total: total,
      ),
    );
  }

  void _check() {
    _preview.check();
    if (!_currentLibrary)
      throw StateError('The library changed. Retry the copy preview.');
    if (!connected())
      throw StateError('Reconnect to your desktop to continue copying.');
  }

  Future<LinkCopyPlan> plan() => _preview.run(_buildPlan);

  Future<LinkCopyPlan> _buildPlan() async {
    _check();
    await LinkSongBindings.instance.ensureLoaded();
    _checking('Connecting to desktop…');
    final source = LokalDesktopSource.instance;
    final contentMatching = await source.requireOriginalFileSupport(
      credentials,
    );
    _check();
    final server = await source.ensureServer(credentials);
    _checking('Reading desktop library…');
    final catalogue = await source.readCatalogue(
      credentials,
      onPage: (count) => _checking('Reading desktop library: $count songs…'),
    );
    final identity = LinkCopyIdentity(serverId: server.id, tracks: catalogue);
    final originalChecks = <String, Future<bool>>{};
    final confirmedDesktopIds = <String>{};
    Future<bool> alreadyOnDesktop(Song song) async {
      final candidateIds = <String>{
        if (LinkSongBindings.instance.remoteIdForSong(song, server.id)
            case final boundId?)
          boundId,
        ...identity.candidates(song),
      };
      for (final id in candidateIds) {
        _check();
        if (await originalChecks.putIfAbsent(
          id,
          () => source.hasOriginalFile(credentials, id),
        )) {
          confirmedDesktopIds.add(id);
          await LinkSongBindings.instance.bind(
            song.id,
            serverId: server.id,
            remoteId: id,
            filePath: song.filePath,
          );
          await source.rememberDesktopOriginal(
            song,
            server.id,
            id,
            stillCurrent: () => _currentLibrary && !cancelled && connected(),
          );
          return true;
        }
      }
      return false;
    }

    final songs = await SongRepository().getAllSongs();
    final entities = await Database.songs.getAll([
      for (final song in songs)
        if (int.tryParse(song.id) case final id?) id,
    ]);
    final mediaUris = {
      for (final row in entities)
        if (row?.mediaStoreUri case final uri?) row!.id.toString(): uri,
    };
    final local = <Song>[];
    var checked = 0;
    _checking('Checking files on this phone…', total: songs.length);
    for (final song in songs) {
      _check();
      if (++checked % 25 == 0)
        _checking(
          'Checking files on this phone…',
          processed: checked,
          total: songs.length,
        );
      if (song.isNetworkSource || song.filePath == null) continue;
      final uri = Uri.tryParse(song.filePath!);
      if (uri?.scheme == 'content') {
        local.add(song);
        continue;
      }
      var exists = false;
      try {
        exists = await File(
          uri?.scheme == 'file' ? uri!.toFilePath() : song.filePath!,
        ).exists();
      } on FileSystemException {
        /* The media URI may still be accessible. */
      }
      final mediaUri = mediaUris[song.id];
      if (exists) {
        local.add(song);
      } else if (mediaUri != null && mediaUri.startsWith('content://')) {
        local.add(song.copyWith(filePath: mediaUri));
      }
    }
    final recover = <Song>[];
    for (final song in local) {
      if (await source.isPrivateDesktopCopy(song)) recover.add(song);
    }
    final missing = <Song>[];
    for (var offset = 0; offset < local.length; offset += 250) {
      _check();
      _checking(
        'Comparing song identities…',
        processed: offset,
        total: local.length,
      );
      final batch = local.skip(offset).take(250).toList();
      final reply = await socket.request('command', {
        'action': 'resolveTracks',
        'value': {
          'queue': [
            for (final song in batch)
              {
                ...LinkJournal.instance.songWire(song),
                // Retain the original PC identity for copied files; use
                // current metadata rather than stale aliases for other songs.
                'track_key': identity.resolverKey(song),
              },
          ],
        },
      });
      if (reply.body['missing'] is! List)
        throw const FormatException(
          'Update Lokal on your PC to compare song files.',
        );
      for (final index in reply.body['missing'] as List) {
        if (index is! int || index < 0 || index >= batch.length)
          throw const FormatException('Invalid missing-song response.');
        // The resolver can miss a downloaded copy after its local tags or
        // duration changed. Confirm its preserved desktop identity/fresh
        // catalogue candidates without transferring the audio back to the PC.
        if (!await alreadyOnDesktop(batch[index])) missing.add(batch[index]);
      }
    }
    // Name/duration misses are not proof a file is absent: independent scans,
    // tag edits and organizer moves can lose the original association. Compare
    // exact bytes before putting such songs into the upload preview.
    if (contentMatching && missing.isNotEmpty) {
      var unresolved = List<Song>.of(missing);
      missing.clear();
      if (source.supportsSizeMatching) {
        final mayExist = <Song>[];
        for (var offset = 0; offset < unresolved.length; offset += 2048) {
          _checking(
            'Comparing file sizes…',
            processed: offset,
            total: unresolved.length,
          );
          final batch = unresolved.skip(offset).take(2048).toList();
          final sizes = <String, int>{};
          for (final song in batch) {
            _check();
            final size = await source.originalFileSize(song);
            if (size != null) sizes[song.id] = size;
          }
          final existingSizes = sizes.isEmpty
              ? <int>{}
              : await source.matchOriginalSizes(
                  credentials,
                  sizes.values.toSet().toList(),
                );
          _check();
          for (final song in batch) {
            final size = sizes[song.id];
            if (size == null || existingSizes.contains(size)) {
              mayExist.add(song);
            } else {
              missing.add(song);
            }
          }
        }
        unresolved = mayExist;
      }
      for (var offset = 0; offset < unresolved.length; offset += 32) {
        _check();
        final batch = unresolved.skip(offset).take(32).toList();
        final candidates = <Song>[];
        final fingerprints = <Map<String, dynamic>>[];
        for (final song in batch) {
          _check();
          _checking(
            'Comparing audio contents: ${song.title}',
            processed: offset + candidates.length,
            total: unresolved.length,
          );
          final fingerprint = await source.originalFingerprint(
            song,
            check: () {
              _check();
              _preview.pulse();
            },
          );
          if (fingerprint == null) {
            missing.add(song);
          } else {
            candidates.add(song);
            fingerprints.add(fingerprint);
          }
        }
        if (fingerprints.isEmpty) continue;
        final matches = await source.matchOriginalFingerprints(
          credentials,
          fingerprints,
        );
        _check();
        for (var index = 0; index < candidates.length; index++) {
          _check();
          final remoteId = matches[index];
          if (remoteId == null) {
            missing.add(candidates[index]);
          } else {
            confirmedDesktopIds.add(remoteId);
            await LinkSongBindings.instance.bind(
              candidates[index].id,
              serverId: server.id,
              remoteId: remoteId,
              filePath: candidates[index].filePath,
            );
            await source.rememberDesktopOriginal(
              candidates[index],
              server.id,
              remoteId,
              stillCurrent: () => _currentLibrary && !cancelled && connected(),
            );
          }
        }
      }
    }

    // Filter out tombstoned local songs from toDesktop.
    final filteredToDesktop = <Song>[];
    for (final song in missing) {
      _check();
      if (await LinkJournal.instance.isTrackTombstoned(
        artist: song.artist,
        title: song.title,
        duration: song.duration,
        addedAt: song.dateAdded,
      )) {
        continue;
      }
      filteredToDesktop.add(song);
    }

    String name(String value) =>
        value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    String cleanPairKey(String artist, String title) {
      final cleaned = cleanTransferMetadata(title: title, artist: artist);
      final aKey = recommendationKey(leadArtist(cleaned.artist));
      final tKey = titleKey(cleaned.title);
      final normA = aKey.isNotEmpty ? aKey : name(cleaned.artist);
      final normT = tKey.isNotEmpty ? tKey : name(cleaned.title);
      return '$normA\u0000$normT';
    }
    String rawPairKey(String artist, String title) =>
        '${name(artist)}\u0000${name(title)}';

    final localByName = <String, List<Song>>{};
    for (final song in local) {
      localByName
          .putIfAbsent(cleanPairKey(song.artist, song.title), () => [])
          .add(song);
      localByName
          .putIfAbsent(rawPairKey(song.artist, song.title), () => [])
          .add(song);
    }

    final allowedSongIds = {for (final song in local) song.id};
    final allowedPaths = {
      for (final song in local)
        if (song.filePath != null && song.filePath!.isNotEmpty) song.filePath!,
    };
    final boundRemoteIds = await LinkSongBindings.instance.remoteIdsForServer(
      server.id,
      allowedSongIds: allowedSongIds,
      allowedPaths: allowedPaths,
    );

    final downloads = <({Map<String, dynamic> track, Song? existing})>[];
    final seen = <String>{};
    final localDesktopIds = {
      ...confirmedDesktopIds,
      ...boundRemoteIds,
      for (final song in local)
        if (song.remoteServerId == server.id && song.remoteId != null)
          song.remoteId!,
    };
    final remoteById = {
      for (final song in songs)
        if (song.sourceType == 'lokal' && song.remoteServerId == server.id)
          song.remoteId: song,
    };
    _checking('Preparing copy preview…');
    for (final track in catalogue) {
      _check();
      final id = track['id'].toString();
      if (!seen.add(id) || localDesktopIds.contains(id)) continue;
      final title = track['title'] as String? ?? '',
          artist = track['artist'] as String? ?? '';
      final seconds = (track['duration'] as num? ?? 0).toDouble();
      final matchedByClean =
          localByName[cleanPairKey(artist, title)] ?? const <Song>[];
      final matchedByRaw =
          localByName[rawPairKey(artist, title)] ?? const <Song>[];
      if ([...matchedByClean, ...matchedByRaw].any(
        (song) => (song.duration.inMilliseconds / 1000 - seconds).abs() <= 2,
      )) {
        continue;
      }
      final addedAtRaw = track['added_at'] ?? track['addedAt'];
      DateTime? addedAt;
      if (addedAtRaw is num && addedAtRaw > 0) {
        // Desktop added_at is unix seconds (or ms if > 1e11).
        final ms = addedAtRaw > 100000000000
            ? addedAtRaw.round()
            : (addedAtRaw * 1000).round();
        addedAt = DateTime.fromMillisecondsSinceEpoch(ms);
      }
      if (await LinkJournal.instance.isTrackTombstoned(
        artist: artist,
        title: title,
        duration: Duration(milliseconds: (seconds * 1000).round()),
        addedAt: addedAt,
      )) {
        continue;
      }
      final existing = remoteById[id];
      downloads.add((track: track, existing: existing));
    }
    _check();
    // Keep the operation reserved while the user reviews the copy preview.
    _checking('Ready to review files');
    return LinkCopyPlan(
      server: server,
      toDesktop: filteredToDesktop,
      toPhone: downloads,
      toMusicFolder: recover,
    );
  }

  Future<void> copy(LinkCopyPlan plan) async {
    var processed = 0, sent = 0, received = 0;
    final failures = <String>[];
    void report(LinkCopyPhase phase, {String? title, bool toDesktop = false}) =>
        onProgress(
          LinkCopyProgress(
            phase: phase,
            total: plan.total,
            processed: processed,
            sent: sent,
            received: received,
            failures: List.unmodifiable(failures),
            currentTitle: title,
            toDesktop: toDesktop,
          ),
        );
    try {
      report(LinkCopyPhase.copying);
      for (final song in plan.toDesktop) {
        _check();
        report(LinkCopyPhase.copying, title: song.title, toDesktop: true);
        try {
          await LokalDesktopSource.instance.uploadToDesktop(song, credentials);
          sent++;
        } catch (error) {
          final reason = error is StateError
              ? error.message
              : error is HttpException
              ? error.message
              : 'Could not read or send the audio file. Reconnect and retry.';
          failures.add('${song.title} — $reason');
        }
        processed++;
        report(LinkCopyPhase.copying);
      }
      for (final song in plan.toMusicFolder) {
        _check();
        report(LinkCopyPhase.copying, title: song.title);
        try {
          await LokalDesktopSource.instance.recoverPrivateCopy(song);
          received++;
        } catch (error) {
          failures.add(
            '${song.title} — ${error is StateError ? error.message : "Could not save to the selected music folder. Retry."}',
          );
        }
        processed++;
        report(LinkCopyPhase.copying);
      }
      for (final entry in plan.toPhone) {
        _check();
        final title = entry.track['title'] as String? ?? 'Song';
        report(LinkCopyPhase.copying, title: title);
        try {
          await LokalDesktopSource.instance.copyOriginalToPhone(
            plan.server,
            entry.track,
            existing: entry.existing,
          );
          received++;
        } catch (error) {
          failures.add(
            '$title — ${error is StateError ? error.message : "Could not copy this file. Reconnect and retry."}',
          );
        }
        processed++;
        report(LinkCopyPhase.copying);
      }
      _check();
      report(LinkCopyPhase.complete);
    } catch (_) {
      report(LinkCopyPhase.paused);
      rethrow;
    }
  }
}
