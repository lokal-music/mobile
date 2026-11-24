import 'dart:async';

import 'artwork_gate.dart';
import 'background_metadata_budget.dart';
import 'library_clear_epoch.dart';
import 'music_folder_service.dart';
import '../data/repositories/song_repository.dart';
import '../data/entities/song_entity.dart';
import 'uac2_preferences_service.dart';

import 'package:flick/core/utils/dev_log.dart';

class BackgroundMetadataService {
  final MusicFolderService _musicFolderService;
  final SongRepository _songRepository;

  bool _isRunning = false;
  Timer? _timer;
  bool _stopped = false;
  final Future<void> Function(Duration) _rest;

  BackgroundMetadataService({
    MusicFolderService? musicFolderService,
    SongRepository? songRepository,
    Future<void> Function(Duration)? rest,
  }) : _musicFolderService = musicFolderService ?? MusicFolderService(),
       _songRepository = songRepository ?? SongRepository(),
       _rest = rest ?? Future<void>.delayed;

  void startPeriodicExtraction({
    Duration interval = const Duration(minutes: 5),
  }) {
    _stopped = false;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => extractPendingMetadata());
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }

  void _logTiming(String label, Duration elapsed) {
    if (!Uac2PreferencesService.isDeveloperModeEnabledSync) return;
    devLog('[BackgroundMetadata] $label: ${elapsed.inMilliseconds}ms');
  }

  Future<int> extractPendingMetadata() async {
    if (_isRunning || _stopped) return 0;
    _isRunning = true;
    final clearEpoch = LibraryClearEpoch.current;
    bool aborted() => _stopped || !LibraryClearEpoch.isCurrent(clearEpoch);

    try {
      final totalStopwatch = Stopwatch()..start();
      final dbStopwatch = Stopwatch()..start();
      final incomplete = await _songRepository.getIncompleteMetadataSongs();
      _logTiming(
        'DB query incomplete (${incomplete.length} songs)',
        dbStopwatch.elapsed,
      );

      if (incomplete.isEmpty || aborted()) return 0;

      const batchSize = 8;
      var totalUpdated = 0;

      for (var i = 0; i < incomplete.length && !aborted(); i += batchSize) {
        while (artworkExtractionPaused && !aborted()) {
          await _rest(const Duration(milliseconds: 150));
        }
        if (aborted()) break;
        final batch = incomplete.sublist(
          i,
          (i + batchSize > incomplete.length)
              ? incomplete.length
              : i + batchSize,
        );

        final contentUris = batch
            .map((s) => s.mediaStoreUri ?? s.filePath)
            .where((uri) => uri.startsWith('content://'))
            .toSet()
            .toList();

        if (contentUris.isEmpty) {
          for (final song in batch) {
            song.metadataComplete = true;
          }
          if (aborted()) break;
          await _songRepository.upsertSongs(batch);
          totalUpdated += batch.length;
          await _rest(backgroundMetadataDelay(Duration.zero));
          continue;
        }

        try {
          final chunkStopwatch = Stopwatch()..start();
          final metadataList = <AudioFileInfo>[];
          for (final uri in contentUris) {
            while (artworkExtractionPaused && !aborted()) {
              await _rest(const Duration(milliseconds: 150));
            }
            if (aborted()) break;
            final probeTime = Stopwatch()..start();
            // The native bulk API creates up to 2 * CPU cores of workers.
            // A single URI takes its serial path; automatic backfill must
            // never occupy that whole pool while the UI is running.
            metadataList.addAll(await _musicFolderService.fetchMetadata([uri]));
            await _rest(backgroundMetadataDelay(probeTime.elapsed));
          }
          // A stopped or cleared partial batch must not write stale rows back.
          if (aborted()) break;
          final metaByUri = <String, AudioFileInfo>{};
          for (final m in metadataList) {
            metaByUri[m.uri] = m;
          }

          final updateBatch = <SongEntity>[];
          for (final song in batch) {
            final lookupUri = song.mediaStoreUri ?? song.filePath;
            final meta = metaByUri[lookupUri];
            if (meta != null) {
              song.sampleRate = meta.sampleRate ?? song.sampleRate;
              song.bitDepth = meta.bitDepth ?? song.bitDepth;
              if (!song.hasLocalEdits) {
                song.discNumber = meta.discNumber ?? song.discNumber;
                song.albumArtist =
                    (meta.albumArtist?.trim().isNotEmpty ?? false)
                    ? meta.albumArtist!.trim()
                    : song.albumArtist;
              }
            }
            song.metadataComplete = true;
            updateBatch.add(song);
          }

          if (aborted()) break;
          await _songRepository.upsertSongs(updateBatch);
          totalUpdated += updateBatch.length;
          _logTiming(
            'batch ${i ~/ batchSize + 1} (${batch.length} songs, '
            '${contentUris.length} URIs, ${updateBatch.length} updated)',
            chunkStopwatch.elapsed,
          );
        } catch (e) {
          devLog('BackgroundMetadataService batch failed: $e');
          await _rest(backgroundMetadataDelay(Duration.zero));
        }
      }

      _logTiming(
        'extract pending metadata total ($totalUpdated updated)',
        totalStopwatch.elapsed,
      );

      return totalUpdated;
    } finally {
      _isRunning = false;
    }
  }
}
