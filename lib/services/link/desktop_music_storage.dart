import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/entities/song_entity.dart';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../music_folder_service.dart';
import '../music_library_path.dart';
import 'transfer_artifact_cleaner.dart';

class DesktopMusicFolder {
  const DesktopMusicFolder(this.uri, {this.path});
  final String uri;
  final String? path;
}

class DesktopMusicFile {
  const DesktopMusicFile({
    required this.path,
    required this.folderUri,
    this.documentUri,
    this.relativeFolderPath = '',
  });
  final String path, folderUri;
  final String? documentUri;
  final String relativeFolderPath;
}

/// Permanent copies use a selected library folder. Private files are staging or
/// recovery inputs; an unavailable folder must never silently change the target.
class DesktopMusicStorage {
  static const destinationKey = 'lokal.link.desktop_copy_folder_uri';
  DesktopMusicStorage({
    Future<List<DesktopMusicFolder>> Function()? folders,
    MethodChannel channel = const MethodChannel('com.mossapps.flick/storage'),
    Future<void> Function(List<String>)? indexMedia,
  }) : _folders = folders ?? _savedFolders,
       _channel = channel,
       _indexMedia = indexMedia ?? MusicFolderService().indexMediaFiles;
  final Future<List<DesktopMusicFolder>> Function() _folders;
  final MethodChannel _channel;
  final Future<void> Function(List<String>) _indexMedia;
  static Future<List<DesktopMusicFolder>> _savedFolders() async {
    final service = MusicFolderService();
    final selected = (await SharedPreferences.getInstance())
        .getString(destinationKey);
    final available = await service.getSavedFolders();
    // An explicit destination is strict: never silently write elsewhere if
    // SAF access is revoked or the selected folder has been removed.
    final folders = selected == null
        ? available
        : available.where((f) => f.uri == selected).toList();
    return [
      for (final folder in folders)
        DesktopMusicFolder(
          folder.uri,
          path: (await service.resolveStorageInfo(folder.uri)).fsPath,
        ),
    ];
  }

  Future<void> requireFolder() async {
    if ((await _folders()).isEmpty)
      throw StateError(
        'Choose a music folder in Library settings before copying desktop songs.',
      );
  }

  static String cleanBaseStem(String artist, String title) {
    final cleaned = cleanTransferMetadata(title: title, artist: artist);
    final cleanArtist = isPlaceholderTransferArtist(cleaned.artist)
        ? ''
        : cleaned.artist.trim();
    final cleanTitle = cleaned.title.trim();
    final combined = cleanArtist.isEmpty
        ? cleanTitle
        : cleanTitle.isEmpty
        ? cleanArtist
        : '$cleanArtist - $cleanTitle';
    var base = combined
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
    if (base.isEmpty ||
        !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(base)) {
      base = 'Song';
    }
    base = String.fromCharCodes(
      base.runes.take(120),
    ).trim().replaceAll(RegExp(r'[. ]+$'), '');
    return base.isEmpty ? 'Song' : base;
  }

  Future<DesktopMusicFile> save(
    File source, {
    required String title,
    required String artist,
    String? album,
    String? albumArtist,
    required String extension,
  }) async {
    if (!RegExp(r'^[a-zA-Z0-9]{1,8}$').hasMatch(extension))
      throw const FormatException('Invalid audio format.');
    final folders = await _folders();
    if (folders.isEmpty)
      throw StateError(
        'Choose a music folder in Library settings before copying desktop songs.',
      );
    final length = await source.length();
    if (length == 0) throw StateError('The desktop song file is empty.');
    final cleaned = cleanTransferMetadata(title: title, artist: artist);
    final effectiveArtist = isPlaceholderTransferArtist(cleaned.artist)
        ? artist
        : cleaned.artist;
    final directories = MusicLibraryPath.directories(
      artist: effectiveArtist,
      album: album,
      albumArtist: albumArtist,
    );
    final relative = directories.join('/');
    final ext = extension.toLowerCase();
    final stem = cleanBaseStem(artist, title);
    final defaultName = '$stem.$ext';
    for (final folder in folders) {
      final root = folder.path;
      if (root != null && p.isAbsolute(root)) {
        final targetDir = Directory(p.joinAll([root, ...directories]));
        File? part;
        try {
          await targetDir.create(recursive: true);
          File? target;
          for (var i = 1; i <= 10000; i++) {
            final candidateName = i == 1 ? '$stem.$ext' : '$stem ($i).$ext';
            final candidate = File(p.join(targetDir.path, candidateName));
            if (!await candidate.exists()) {
              target = candidate;
              break;
            }
          }
          if (target == null) {
            throw const FileSystemException(
              'Too many duplicate song files in target folder',
            );
          }
          part = File('${target.path}.part');
          await source.copy(part.path);
          if (await part.length() != length)
            throw const FileSystemException('Incomplete copy');
          if (await target.exists()) {
            throw const FileSystemException('Target file already exists');
          }
          await part.rename(target.path);
          return DesktopMusicFile(
            path: target.path,
            folderUri: folder.uri,
            relativeFolderPath: relative,
          );
        } on FileSystemException {
          try {
            if (part != null && await part.exists()) await part.delete();
          } on FileSystemException {
            /* Keep the failure actionable below. */
          }
        }
      }
      if (Uri.tryParse(folder.uri)?.scheme == 'content') {
        try {
          final result = await _channel.invokeMapMethod<String, dynamic>(
            'copyMusicToFolder',
            {
              'folderTreeUri': folder.uri,
              'sourcePath': source.path,
              'directorySegments': directories,
              'fileName': defaultName,
            },
          );
          final uri = result?['uri'] as String?;
          if (uri == null || !uri.startsWith('content://')) continue;
          final resolved = result?['path'] as String?;
          return DesktopMusicFile(
            path: resolved ?? uri,
            folderUri: folder.uri,
            documentUri: uri,
            relativeFolderPath: relative,
          );
        } on PlatformException {
          /* Try another selected folder, never private storage. */
        }
      }
    }
    throw StateError(
      'Cannot write to your selected music folder. Re-select it in Library settings to restore access, then retry.',
    );
  }

  /// Keep the row's identity, likes, history, artwork and synced lyric key.
  /// The private input is retained as recovery data for already queued playback.
  Future<void> saveEntity(
    SongEntity entity, {
    required Future<void> Function(SongEntity) persist,
  }) async {
    final oldPath = entity.filePath, oldFolder = entity.folderUri;
    final oldDocument = entity.mediaStoreUri,
        oldRelative = entity.relativeFolderPath;
    final oldLastModified = entity.lastModified, oldFileSize = entity.fileSize;
    final output = await save(
      File(oldPath),
      title: entity.title,
      artist: entity.artist,
      album: entity.album,
      albumArtist: entity.albumArtist,
      extension: entity.fileType ?? p.extension(oldPath).replaceFirst('.', ''),
    );
    try {
      entity.filePath = output.path;
      entity.folderUri = output.folderUri;
      entity.mediaStoreUri = output.documentUri;
      entity.relativeFolderPath = output.relativeFolderPath;
      if (!output.path.startsWith('content://')) {
        try {
          final stat = await File(output.path).stat();
          if (stat.type != FileSystemEntityType.notFound) {
            entity.lastModified = stat.modified;
            entity.fileSize = stat.size;
          }
        } on FileSystemException {
          /* Retain prior metadata if stat fails. */
        }
      }
      await persist(entity);
    } catch (_) {
      entity.filePath = oldPath;
      entity.folderUri = oldFolder;
      entity.mediaStoreUri = oldDocument;
      entity.relativeFolderPath = oldRelative;
      entity.lastModified = oldLastModified;
      entity.fileSize = oldFileSize;
      try {
        await remove(output);
      } catch (_) {
        /* Never remove the recovery input. */
      }
      rethrow;
    }
    try {
      await index(output);
    } catch (_) {
      /* A later library scan can index it. */
    }
  }

  Future<void> index(DesktopMusicFile file) => _indexMedia([file.path]);
  Future<void> remove(DesktopMusicFile file) async {
    if (file.documentUri != null) {
      await _channel.invokeMethod<bool>('removeCopiedMusicDocument', {
        'uri': file.documentUri,
      });
    } else if (await File(file.path).exists()) {
      await File(file.path).delete();
    }
  }
}
