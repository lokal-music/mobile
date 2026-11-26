import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;

import '../../data/database.dart';
import '../ios_transfer_scan_guard.dart';
import '../music_folder_service.dart';
import 'desktop_music_storage.dart';
import 'link_song_bindings.dart';
import 'transfer_artifact_cleaner.dart';

/// Repairs legacy transfer UUID / addon-hash suffixes in local song metadata
/// and on-disk filenames without changing Isar recording IDs.
class TransferArtifactRepairService {
  TransferArtifactRepairService({
    Isar? isar,
    Future<void> Function(List<String>)? indexMedia,
  }) : _isarOverride = isar,
       _indexMedia = indexMedia ?? MusicFolderService().indexMediaFiles;

  static final TransferArtifactRepairService instance =
      TransferArtifactRepairService();

  final Isar? _isarOverride;
  final Future<void> Function(List<String>) _indexMedia;

  Isar? _completedIsar;
  Future<void>? _inFlight;

  @visibleForTesting
  void resetForTesting() {
    _completedIsar = null;
    _inFlight = null;
  }

  Future<void> repairIfNeeded() {
    final targetIsar =
        _isarOverride ?? (Database.isInitialized ? Database.instance : null);
    if (targetIsar == null || !targetIsar.isOpen) {
      return Future<void>.value();
    }
    if (identical(_completedIsar, targetIsar)) {
      return Future<void>.value();
    }
    final pending = _inFlight;
    if (pending != null) return pending;

    late final Future<void> run;
    run = _repair(targetIsar).then(
      (_) {
        _completedIsar = targetIsar;
      },
      onError: (Object _) {
        // Allow a retry on next launch if an unexpected I/O error aborted.
      },
    ).whenComplete(() {
      if (identical(_inFlight, run)) {
        _inFlight = null;
      }
    });
    _inFlight = run;
    return run;
  }

  Future<void> _repair(Isar isar) async {
    final rows = await isar.songEntitys
        .filter()
        .sourceTypeIsNull()
        .findAll();
    if (rows.isEmpty) return;

    final renamedOnDisk = <String, String>{};
    final mediaPathsToIndex = <String>{};

    for (final row in rows) {
      if (row.filePath.isEmpty ||
          row.filePath.startsWith('ghost://') ||
          row.filePath.startsWith('lokal://')) {
        continue;
      }

      var metadataChanged = false;
      if (hasTransferArtifact(row.title) ||
          (isPlaceholderTransferArtist(row.artist) &&
              row.title.contains(' - '))) {
        final cleaned = cleanTransferMetadata(
          title: row.title,
          artist: row.artist,
        );
        if (cleaned.changed) {
          row
            ..title = cleaned.title
            ..artist = cleaned.artist
            ..hasLocalEdits = true;
          metadataChanged = true;
        } else if (hasTransferArtifact(row.title)) {
          row.hasLocalEdits = true;
          metadataChanged = true;
        }
      }

      final isContentUri = row.filePath.startsWith('content://');
      final rawPath = isContentUri
          ? null
          : (row.filePath.startsWith('file://')
                ? Uri.tryParse(row.filePath)?.toFilePath()
                : row.filePath);

      if (metadataChanged &&
          rawPath != null &&
          (row.lastModified == null || row.fileSize == null)) {
        try {
          final stat = await File(rawPath).stat();
          if (stat.type != FileSystemEntityType.notFound && stat.size >= 0) {
            row.lastModified ??= stat.modified;
            row.fileSize ??= stat.size;
          }
        } on FileSystemException {
          /* Keep metadata repair even when stat fails. */
        }
      }

      var pathRenamed = false;
      String? oldPath;
      String? newPath;

      if (!isContentUri &&
          rawPath != null &&
          iosTransferOperationKeyForPath(rawPath) == null) {
        final stem = p.basenameWithoutExtension(rawPath);
        if (hasTransferArtifact(stem)) {
          if (isPlaceholderTransferArtist(row.artist)) {
            final fromStem = cleanTransferMetadata(
              title: stem,
              artist: row.artist,
            );
            if (fromStem.changed) {
              row
                ..title = fromStem.title
                ..artist = fromStem.artist
                ..hasLocalEdits = true;
              metadataChanged = true;
            }
          }

          final alreadyRenamedTarget = renamedOnDisk[rawPath];
          if (alreadyRenamedTarget != null) {
            oldPath = row.filePath;
            newPath = alreadyRenamedTarget;
            pathRenamed = true;
          } else if (await File(rawPath).exists()) {
            final dir = p.dirname(rawPath);
            final rawExt = p.extension(rawPath).replaceFirst('.', '');
            final ext =
                (rawExt.isNotEmpty ? rawExt : (row.fileType ?? 'flac'))
                    .toLowerCase();
            final baseStem = DesktopMusicStorage.cleanBaseStem(
              row.artist,
              row.title,
            );

            String? chosenPath;
            for (var i = 1; i <= 10000; i++) {
              final candidateName = i == 1
                  ? '$baseStem.$ext'
                  : '$baseStem ($i).$ext';
              final candidatePath = p.join(dir, candidateName);
              if (candidatePath == rawPath) {
                chosenPath = rawPath;
                break;
              }
              final existsOnDisk = await File(candidatePath).exists();
              final occupiedInDb = await isar.songEntitys
                      .getByFilePathStartOffsetMs(
                        candidatePath,
                        row.startOffsetMs,
                      ) !=
                  null;
              if (!existsOnDisk && !occupiedInDb) {
                chosenPath = candidatePath;
                break;
              }
            }

            if (chosenPath != null && chosenPath != rawPath) {
              try {
                await File(rawPath).rename(chosenPath);
                renamedOnDisk[rawPath] = chosenPath;
                oldPath = row.filePath;
                newPath = chosenPath;
                pathRenamed = true;
              } on FileSystemException {
                /* Leave original path intact if filesystem denies rename. */
              }
            }
          }
        }
      }

      if (!metadataChanged && !pathRenamed) continue;

      FileStat? updatedStat;
      if (pathRenamed && newPath != null) {
        try {
          final s = await File(newPath).stat();
          if (s.type != FileSystemEntityType.notFound && s.size >= 0) {
            updatedStat = s;
          }
        } on FileSystemException {
          updatedStat = null;
        }
      }

      final resolvedNewPath = newPath;
      final resolvedOldPath = oldPath;
      var committed = false;
      try {
        await isar.writeTxn(() async {
          final current = await isar.songEntitys.get(row.id);
          if (current == null || current.sourceType != null) return;
          if (pathRenamed && resolvedNewPath != null) {
            final conflict = await isar.songEntitys.getByFilePathStartOffsetMs(
              resolvedNewPath,
              current.startOffsetMs,
            );
            if (conflict != null && conflict.id != current.id) {
              return;
            }
            current.filePath = resolvedNewPath;
            if (updatedStat != null) {
              current.lastModified = updatedStat.modified;
              current.fileSize = updatedStat.size;
            }
          } else {
            current.lastModified ??= row.lastModified;
            current.fileSize ??= row.fileSize;
          }
          if (metadataChanged) {
            current
              ..title = row.title
              ..artist = row.artist
              ..hasLocalEdits = true;
          }
          await isar.songEntitys.put(current);
          committed = true;
        });
      } catch (_) {
        if (pathRenamed &&
            resolvedNewPath != null &&
            resolvedOldPath != null &&
            renamedOnDisk[rawPath] == resolvedNewPath) {
          try {
            if (await File(resolvedNewPath).exists() &&
                !await File(resolvedOldPath).exists()) {
              await File(resolvedNewPath).rename(resolvedOldPath);
              renamedOnDisk.remove(rawPath);
            }
          } on FileSystemException {
            /* Best-effort rollback. */
          }
        }
        rethrow;
      }

      if (committed &&
          pathRenamed &&
          resolvedNewPath != null &&
          resolvedOldPath != null) {
        mediaPathsToIndex
          ..add(resolvedOldPath)
          ..add(resolvedNewPath);
        try {
          await LinkSongBindings.instance.updateFilePath(
            row.id.toString(),
            resolvedNewPath,
            oldFilePath: resolvedOldPath,
          );
        } on MissingPluginException {
          /* Unit tests without SharedPreferences mock. */
        }
      }
    }

    if (mediaPathsToIndex.isNotEmpty) {
      try {
        await _indexMedia(mediaPathsToIndex.toList());
      } catch (_) {
        /* Best-effort MediaStore refresh. */
      }
    }
  }
}
