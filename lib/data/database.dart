import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'entities/artist_entity.dart';
import 'entities/link_event_entities.dart';
import 'entities/folder_entity.dart';
import 'entities/ios_transfer_receipt_entity.dart';
import 'entities/ios_song_identity_entity.dart';
import 'entities/network_server_entity.dart';
import 'entities/recently_played_entity.dart';
import 'entities/song_audio_cache_entity.dart';
import 'entities/song_entity.dart';
import '../services/ios_transfer_song_identity.dart';

export 'entities/artist_entity.dart';
export 'entities/link_event_entities.dart';
export 'entities/folder_entity.dart';
export 'entities/network_server_entity.dart';
export 'entities/recently_played_entity.dart';
export 'entities/song_audio_cache_entity.dart';
export 'entities/song_entity.dart';

/// Database singleton for Isar operations.
class Database {
  static const String _databaseName = 'flick_player';

  static Isar? _instance;
  static bool get isInitialized => _instance != null;

  static Isar get instance {
    if (_instance == null) {
      throw StateError('Database not initialized. Call Database.init() first.');
    }
    return _instance!;
  }

  /// Initialize the database. Should be called once at app startup.
  static Future<void> init() async {
    if (_instance != null) return;

    // Music is exposed through Files on iPhone. Keep database internals in
    // Application Support so file sharing cannot accidentally edit the store.
    final dir = Platform.isIOS
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();
    File? migratedLegacy;
    if (Platform.isIOS) {
      final documents = await getApplicationDocumentsDirectory();
      final legacy = File('${documents.path}/$_databaseName.isar');
      final current = File('${dir.path}/$_databaseName.isar');
      if (!await current.exists() && await legacy.exists()) {
        await dir.create(recursive: true);
        final staging = File('${current.path}.migrating');
        await legacy.copy(staging.path);
        await staging.rename(current.path);
        migratedLegacy = legacy;
        // Keep the original until the migrated database opens successfully.
      }
    }
    final schemas = [
      SongEntitySchema,
      FolderEntitySchema,
      RecentlyPlayedEntitySchema,
      ArtistEntitySchema,
      SongAudioCacheEntitySchema,
      NetworkServerEntitySchema,
      PlayEventEntitySchema,
      LibraryOpEntitySchema,
      // Private import recovery state; never exported through the peer journal.
      if (Platform.isIOS) IosTransferReceiptEntitySchema,
      if (Platform.isIOS) IosSongIdentityEntitySchema,
    ];

    try {
      final opened = await Isar.open(
        schemas,
        directory: dir.path,
        name: _databaseName,
        // A native import may acknowledge its receipt only after Isar commits
        // durable truth. Other platforms retain their existing default mode.
        relaxedDurability: !Platform.isIOS,
      );
      try {
        if (Platform.isIOS) {
          await opened.writeTxn(() async {
            if (await opened.iosSongIdentityEntitys.count() == 0) {
              await retainIosImportSongIdentitiesInTransaction(opened, []);
            }
          });
        }
        // Publish only after the old library's identity floor is durable.
        _instance = opened;
      } catch (_) {
        await opened.close();
        rethrow;
      }
    } on IsarError catch (e) {
      if (Platform.isIOS) rethrow;
      if (e.message.contains('MDBX_INCOMPATIBLE')) {
        await _deleteDatabaseFiles(dir.path);
        await _clearFingerprintCache(dir.path);
        _instance = await Isar.open(
          schemas,
          directory: dir.path,
          name: _databaseName,
        );
      } else {
        rethrow;
      }
    }
    if (migratedLegacy != null) {
      final backup = File(
        '${dir.path}/$_databaseName.pre-storage-migration.isar',
      );
      try {
        if (!await backup.exists()) await migratedLegacy.rename(backup.path);
      } on FileSystemException {
        // Retain the original backup if moving it fails; never delete it.
      }
    }
  }

  static Future<void> _deleteDatabaseFiles(String directory) async {
    final paths = [
      '$directory/$_databaseName.isar',
      '$directory/$_databaseName.isar.lock',
    ];

    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }

    // Defensive cleanup for older recovery code that treated the database file
    // path as a directory.
    final legacyDirectory = Directory('$directory/$_databaseName.isar');
    if (await legacyDirectory.exists()) {
      await legacyDirectory.delete(recursive: true);
    }
  }

  static const String _fingerprintCacheDirName = 'flick_fingerprints';

  static Future<void> _clearFingerprintCache(String directory) async {
    final cacheDir = Directory('$directory/$_fingerprintCacheDirName');
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
    }
  }

  /// Close the database connection.
  static Future<void> close() async {
    await _instance?.close();
    _instance = null;
  }

  /// Get the songs collection.
  static IsarCollection<SongEntity> get songs => instance.songEntitys;

  /// Get the folders collection.
  static IsarCollection<FolderEntity> get folders => instance.folderEntitys;

  /// Get the recently played collection.
  static IsarCollection<RecentlyPlayedEntity> get recentlyPlayed =>
      _instance!.recentlyPlayedEntitys;

  /// Get the artists collection.
  static IsarCollection<ArtistEntity> get artists => _instance!.artistEntitys;

  /// Get the song audio cache collection.
  static IsarCollection<SongAudioCacheEntity> get songAudioCache =>
      _instance!.songAudioCacheEntitys;

  /// Get the network server collection.
  static IsarCollection<NetworkServerEntity> get networkServers =>
      _instance!.networkServerEntitys;
}
