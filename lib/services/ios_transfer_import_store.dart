import 'ios_transfer_song_identity.dart';
import 'link/transfer_artifact_cleaner.dart';

import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;

import '../data/entities/ios_transfer_receipt_entity.dart';
import '../data/entities/network_server_entity.dart';
import '../data/entities/song_entity.dart';
import '../models/ios_transfer_import.dart';
import '../models/ios_transfer_models.dart';
import '../models/ios_transfer_orphan.dart';
import '../src/rust/api/scanner.dart' show extractFileMetadata;

enum IosTransferImportConflict {
  pairingChanged,
  recordingRemoved,
  destinationConflict,
  receiptMismatch,
  retired,
}

class IosTransferImportException implements Exception {
  const IosTransferImportException(this.reason);
  final IosTransferImportConflict reason;
  @override
  String toString() => 'iPhone import ${reason.name}.';
}

class IosTransferImportResult {
  const IosTransferImportResult(this.receipt, this.song);
  final IosTransferReceiptEntity receipt;
  final SongEntity? song;
  bool get committed => receipt.state == 'committed';
  // A previously committed receipt remains historical proof after deletion.
  bool get removedAfterCommit => committed && song == null;
  IosTransferMediaInfo? get validatedMedia {
    final encoded = receipt.validatedMediaJson;
    if (encoded == null) return null;
    if (encoded.length > 1024 || utf8.encode(encoded).length > 1024) {
      throw const FormatException('Invalid saved iPhone media validation.');
    }
    try {
      return IosTransferMediaInfo.fromJson(jsonDecode(encoded));
    } on FormatException {
      throw const FormatException('Invalid saved iPhone media validation.');
    }
  }
}

/// Private bookkeeping only: neither a file ownership proof nor a native lease.
class IosTransferPendingReservation {
  const IosTransferPendingReservation({
    required this.id,
    required this.operationKey,
    required this.songId,
    required this.relativePath,
    required this.retiring,
    required this.scope,
  });
  final int id;
  final String operationKey;
  final int songId;
  final String relativePath;
  final bool retiring;
  final IosTransferScope scope;
}

class IosTransferPendingPage {
  const IosTransferPendingPage(this.entries, this.nextId);
  final List<IosTransferPendingReservation> entries;
  final int? nextId;
}

/// One app-isolate library writer. Native callbacks never open this database.
/// Preparation reserves identity before publication; song and completed receipt
/// commit in one actual Isar transaction. The app adapter/schema are not enabled
/// by constructing this isolated store.
class IosTransferImportStore {
  IosTransferImportStore(
    this.isar, {
    required String musicRoot,
    DateTime Function()? now,
    this.testingBoundary,
  }) : musicRoot = p.normalize(musicRoot),
       _now = now ?? DateTime.now {
    if (!p.isAbsolute(musicRoot) || musicRoot.contains('\u0000')) {
      throw const FormatException('Invalid iPhone library root.');
    }
  }

  final Isar isar;
  final String musicRoot;
  final DateTime Function() _now;
  final Future<void> Function(String stage)? testingBoundary;

  String keyFor(IosTransferJob job) => '${job.id}:${job.revision}';
  Never _fail(IosTransferImportConflict reason) =>
      throw IosTransferImportException(reason);
  void _current(bool Function() check) {
    if (!check()) _fail(IosTransferImportConflict.retired);
  }

  Future<void> _boundary(String stage) async {
    await testingBoundary?.call(stage);
  }

  void _validateJob(IosTransferJob job, IosTransferLibraryTarget target) {
    job.intent.validate(submission: true);
    final localId = job.intent.identity.localSongId;
    if (localId != null) {
      final parsed = int.tryParse(localId);
      if (parsed == null || parsed < 1 || parsed.toString() != localId) {
        _fail(IosTransferImportConflict.receiptMismatch);
      }
    }
    if (job.direction != 'download' ||
        job.receivedBytes == null ||
        job.receivedSha256 == null ||
        !{
          IosTransferPhase.staged,
          IosTransferPhase.validating,
          IosTransferPhase.importing,
          IosTransferPhase.complete,
        }.contains(job.phase)) {
      _fail(IosTransferImportConflict.receiptMismatch);
    }
    target.validateFor(job);
  }

  void _matches(
    IosTransferReceiptEntity receipt,
    IosTransferJob job,
    IosTransferLibraryTarget target,
  ) {
    final identity = job.intent.identity;
    if (receipt.schemaVersion != 1 ||
        !{
          'prepared',
          'retiring',
          'committed',
          'retired',
        }.contains(receipt.state) ||
        receipt.operationKey != keyFor(job) ||
        receipt.jobId != job.id ||
        receipt.revision != job.revision ||
        receipt.localSongId < 1 ||
        (identity.localSongId != null &&
            receipt.localSongId.toString() != identity.localSongId) ||
        receipt.serverId != identity.localServerId ||
        receipt.desktopId != identity.scope.desktopId ||
        receipt.desktopUserId != identity.desktopUserId ||
        receipt.pairingId != identity.scope.pairingId ||
        receipt.origin != identity.scope.origin ||
        receipt.sourceId != identity.sourceId ||
        receipt.relativePath != target.relativePath ||
        receipt.bytes != job.receivedBytes ||
        receipt.sha256 != job.receivedSha256 ||
        (receipt.state == 'committed') != (receipt.committedAt != null)) {
      _fail(IosTransferImportConflict.receiptMismatch);
    }
  }

  Future<void> _server(IosTransferJob job) async {
    final identity = job.intent.identity;
    final server = await isar.networkServerEntitys.get(identity.localServerId!);
    final origin = server == null ? null : Uri.tryParse(server.baseUrl);
    if (server == null ||
        server.protocol != 'lokal' ||
        origin == null ||
        !{'http', 'https'}.contains(origin.scheme) ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/') ||
        origin.origin != Uri.parse(identity.scope.origin).origin ||
        server.username !=
            '${identity.scope.desktopId}:${identity.desktopUserId ?? 'guest'}') {
      _fail(IosTransferImportConflict.pairingChanged);
    }
  }

  void _binding(SongEntity song, IosTransferJob job) {
    if (song.remoteServerId != job.intent.identity.localServerId ||
        song.remoteId != job.intent.identity.sourceId) {
      _fail(IosTransferImportConflict.pairingChanged);
    }
  }

  String absolutePath(IosTransferLibraryTarget target) =>
      p.joinAll([musicRoot, ...target.relativePath.split('/')]);

  /// Find reservations even when the process stopped before native custody
  /// existed. Primary-key pagination survives deletion of a previous page;
  /// historical committed/retired rows do not enter this recovery payload.
  Future<IosTransferPendingPage> pendingReservations({
    int? afterId,
    int limit = 100,
  }) async {
    if ((afterId != null && (afterId < 1 || afterId >= 9223372036854775807)) ||
        limit < 1 ||
        limit > 100) {
      throw const FormatException('Invalid reservation page.');
    }
    return isar.txn(() async {
      final rows = await isar.iosTransferReceiptEntitys
          .where()
          .idGreaterThan(afterId ?? 0)
          .filter()
          .group(
            (q) => q.stateEqualTo('prepared').or().stateEqualTo('retiring'),
          )
          .limit(limit + 1)
          .findAll();
      final entries = <IosTransferPendingReservation>[];
      for (final row in rows.take(limit)) {
        final canonical = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(row.jobId);
        if (row.schemaVersion != 1 ||
            !canonical ||
            row.revision < 1 ||
            row.operationKey != '${row.jobId}:${row.revision}' ||
            row.id < 1 ||
            row.localSongId < 1 ||
            row.committedAt != null) {
          _fail(IosTransferImportConflict.receiptMismatch);
        }
        // Validate the suffix/path without using the bookkeeping as file
        // authority. No absolute path or filesystem operation is returned.
        final path = row.relativePath;
        if (!path.startsWith('Desktop Copies/') ||
            path.split('/').length != 2 ||
            path.contains('\\') ||
            path.contains('\u0000') ||
            !RegExp(' - ${row.jobId}-r${row.revision}\\.[a-z0-9]{1,8}\$')
                .hasMatch(path)) {
          _fail(IosTransferImportConflict.receiptMismatch);
        }
        entries.add(
          IosTransferPendingReservation(
            id: row.id,
            operationKey: row.operationKey,
            songId: row.localSongId,
            relativePath: path,
            retiring: row.state == 'retiring',
            scope: IosTransferScope(
              desktopId: row.desktopId,
              origin: row.origin,
              pairingId: row.pairingId,
            )..validate(),
          ),
        );
      }
      return IosTransferPendingPage(
        List.unmodifiable(entries),
        rows.length > limit ? entries.last.id : null,
      );
    });
  }

  /// Read-only recovery never creates a replacement for a deleted recording.
  Future<IosTransferImportResult?> peek(
    IosTransferJob job,
    IosTransferLibraryTarget target,
  ) async {
    _validateJob(job, target);
    return isar.txn(() async {
      final receipt = await isar.iosTransferReceiptEntitys.getByOperationKey(
        keyFor(job),
      );
      if (receipt == null) return null;
      _matches(receipt, job, target);
      return IosTransferImportResult(
        receipt,
        await isar.songEntitys.get(receipt.localSongId),
      );
    });
  }

  Future<IosTransferImportResult> prepare(
    IosTransferJob job,
    IosTransferLibraryTarget target, {
    required bool Function() isCurrent,
    required Future<void> Function() validateOwnership,
  }) async {
    _validateJob(job, target);
    if (!{
      IosTransferPhase.validating,
      IosTransferPhase.importing,
    }.contains(job.phase)) {
      _fail(IosTransferImportConflict.retired);
    }
    final result = await isar.writeTxn(() async {
      _current(isCurrent);
      final previous = await isar.iosTransferReceiptEntitys.getByOperationKey(
        keyFor(job),
      );
      if (previous != null) {
        _matches(previous, job, target);
        if (!{'prepared', 'committed'}.contains(previous.state)) {
          _fail(IosTransferImportConflict.retired);
        }
        final song = await isar.songEntitys.get(previous.localSongId);
        _current(isCurrent);
        if (song == null && previous.state != 'committed') {
          _fail(IosTransferImportConflict.recordingRemoved);
        }
        return IosTransferImportResult(previous, song);
      }
      await _server(job);
      _current(isCurrent);
      final identity = job.intent.identity;
      SongEntity? song;
      if (identity.localSongId != null) {
        final id = int.tryParse(identity.localSongId!);
        if (id == null || id < 1 || id.toString() != identity.localSongId) {
          _fail(IosTransferImportConflict.receiptMismatch);
        }
        song = await isar.songEntitys.get(id);
        if (song == null) _fail(IosTransferImportConflict.recordingRemoved);
      } else {
        final matching = await isar.songEntitys
            .where()
            .remoteIdEqualTo(identity.sourceId)
            .filter()
            .remoteServerIdEqualTo(identity.localServerId)
            .limit(2)
            .findAll();
        if (matching.length > 1) {
          _fail(IosTransferImportConflict.destinationConflict);
        }
        if (matching.isNotEmpty) song = matching.single;
      }
      _current(isCurrent);
      if (song != null) {
        _binding(song, job);
        if (song.sourceType != 'lokal') {
          _fail(IosTransferImportConflict.destinationConflict);
        }
      }
      final slot = await isar.songEntitys.getByFilePathStartOffsetMs(
        absolutePath(target),
        song?.startOffsetMs,
      );
      if (slot != null && slot.id != song?.id) {
        _fail(IosTransferImportConflict.destinationConflict);
      }
      // This native lease check runs while holding Isar's writer. A clear or
      // unpair barrier revokes old leases before taking that same writer, so a
      // delayed old engine cannot reserve a new row after the barrier commits.
      await validateOwnership();
      _current(isCurrent);
      final createSong = song == null;
      if (song == null) {
        final metadata = job.intent.metadata;
        song = SongEntity()
          ..filePath =
              'lokal://${identity.localServerId}/${Uri.encodeComponent(identity.sourceId)}'
          ..sourceType = 'lokal'
          ..albumArtPath = 'lokal-cover://${identity.sourceId}'
          ..remoteId = identity.sourceId
          ..remoteServerId = identity.localServerId
          ..title = metadata.title
          ..artist = metadata.artist
          ..album = metadata.album
          ..albumArtist = metadata.albumArtist
          ..genre = metadata.genre
          ..durationMs = metadata.durationMs
          ..trackNumber = metadata.trackNumber
          ..discNumber = metadata.discNumber
          ..year = metadata.year
          ..fileType = metadata.fileExtension
          ..dateAdded = _now();
      }
      await retainIosImportSongIdentitiesInTransaction(isar, [song]);
      if (createSong) await isar.songEntitys.put(song);
      await _boundary('prepare:afterSong');
      _current(isCurrent);
      final receipt = IosTransferReceiptEntity()
        ..operationKey = keyFor(job)
        ..jobId = job.id
        ..revision = job.revision
        ..localSongId = song.id
        ..serverId = identity.localServerId!
        ..desktopId = identity.scope.desktopId
        ..desktopUserId = identity.desktopUserId
        ..pairingId = identity.scope.pairingId!
        ..origin = identity.scope.origin
        ..sourceId = identity.sourceId
        ..relativePath = target.relativePath
        ..bytes = job.receivedBytes!
        ..sha256 = job.receivedSha256!
        ..preparedAt = _now();
      await isar.iosTransferReceiptEntitys.put(receipt);
      await _boundary('prepare:beforeCommit');
      await validateOwnership();
      _current(isCurrent);
      return IosTransferImportResult(receipt, song);
    });
    await _boundary('prepare:afterCommit');
    return result;
  }

  /// Save the real reader result before native publication. Its receipt already
  /// binds the immutable byte count/hash, so a later engine can finish without
  /// requiring staging or inventing quality from the desktop/filename.
  Future<IosTransferImportResult> recordMediaValidation(
    IosTransferJob job,
    IosTransferLibraryTarget target,
    IosTransferMediaInfo media, {
    required bool Function() isCurrent,
    required Future<void> Function() validateOwnership,
  }) async {
    _validateJob(job, target);
    media.validate();
    if (!{
      IosTransferPhase.validating,
      IosTransferPhase.importing,
    }.contains(job.phase)) {
      _fail(IosTransferImportConflict.retired);
    }
    final encoded = jsonEncode(media.toJson());
    if (utf8.encode(encoded).length > 1024) {
      _fail(IosTransferImportConflict.receiptMismatch);
    }
    final result = await isar.writeTxn(() async {
      _current(isCurrent);
      final receipt = await isar.iosTransferReceiptEntitys.getByOperationKey(
        keyFor(job),
      );
      if (receipt == null) _fail(IosTransferImportConflict.receiptMismatch);
      _matches(receipt, job, target);
      if (!{'prepared', 'committed'}.contains(receipt.state)) {
        _fail(IosTransferImportConflict.retired);
      }
      final song = await isar.songEntitys.get(receipt.localSongId);
      final previous = IosTransferImportResult(receipt, song);
      if (previous.validatedMedia != null) {
        if (jsonEncode(previous.validatedMedia!.toJson()) != encoded) {
          _fail(IosTransferImportConflict.receiptMismatch);
        }
        return previous;
      }
      if (receipt.state != 'prepared' || song == null) {
        _fail(IosTransferImportConflict.recordingRemoved);
      }
      await _server(job);
      _binding(song, job);
      await validateOwnership();
      _current(isCurrent);
      receipt.validatedMediaJson = encoded;
      await isar.iosTransferReceiptEntitys.put(receipt);
      await _boundary('media:beforeCommit');
      await validateOwnership();
      _current(isCurrent);
      return IosTransferImportResult(receipt, song);
    });
    await _boundary('media:afterCommit');
    return result;
  }

  Future<IosTransferImportResult> commit(
    IosTransferJob job,
    IosTransferLibraryReceipt copy,
    IosTransferMediaInfo media, {
    required bool Function() isCurrent,
    required Future<void> Function() validateOwnership,
  }) async {
    _validateJob(job, copy);
    if (job.phase != IosTransferPhase.importing) {
      _fail(IosTransferImportConflict.retired);
    }
    final targetPath = absolutePath(copy);
    var isUntagged = true;
    try {
      final probed = await extractFileMetadata(path: targetPath);
      if (probed != null &&
          (probed.title?.trim().isNotEmpty ?? false) &&
          !hasTransferArtifact(probed.title!) &&
          (probed.artist?.trim().isNotEmpty ?? false) &&
          !isPlaceholderTransferArtist(probed.artist)) {
        isUntagged = false;
      }
    } catch (_) {
      isUntagged = true;
    }
    final result = await isar.writeTxn(() async {
      _current(isCurrent);
      final receipt = await isar.iosTransferReceiptEntitys.getByOperationKey(
        keyFor(job),
      );
      if (receipt == null) _fail(IosTransferImportConflict.receiptMismatch);
      _matches(receipt, job, copy);
      if (!{'prepared', 'committed'}.contains(receipt.state)) {
        _fail(IosTransferImportConflict.retired);
      }
      final song = await isar.songEntitys.get(receipt.localSongId);
      if (receipt.state == 'committed') {
        return IosTransferImportResult(receipt, song);
      }
      if (song == null) _fail(IosTransferImportConflict.recordingRemoved);
      await _server(job);
      _binding(song, job);
      media.validate();
      final savedMedia = IosTransferImportResult(receipt, song).validatedMedia;
      if (savedMedia == null ||
          jsonEncode(savedMedia.toJson()) != jsonEncode(media.toJson())) {
        _fail(IosTransferImportConflict.receiptMismatch);
      }
      _current(isCurrent);
      if (song.sourceType != 'lokal') {
        _fail(IosTransferImportConflict.destinationConflict);
      }
      final path = targetPath;
      final slot = await isar.songEntitys.getByFilePathStartOffsetMs(
        path,
        song.startOffsetMs,
      );
      if (slot != null && slot.id != song.id) {
        _fail(IosTransferImportConflict.destinationConflict);
      }
      await validateOwnership();
      _current(isCurrent);
      FileStat? stat;
      try {
        final s = File(path).statSync();
        if (s.type != FileSystemEntityType.notFound && s.size >= 0) {
          stat = s;
        }
      } on FileSystemException {
        stat = null;
      }
      final cleaned = cleanTransferMetadata(
        title: song.title,
        artist: song.artist,
      );
      if (hasTransferArtifact(song.title) ||
          (isPlaceholderTransferArtist(song.artist) && cleaned.changed)) {
        song
          ..title = cleaned.title
          ..artist = cleaned.artist;
      }
      song
        ..filePath = path
        ..folderUri = musicRoot
        ..relativeFolderPath = 'Desktop Copies'
        ..mediaStoreUri = null
        ..sourceType = null
        ..fileSize = stat != null ? stat.size : copy.bytes
        ..fileType =
            media.format ??
            media.codec ??
            job.intent.metadata.fileExtension.toUpperCase()
        ..sampleRate = media.sampleRate
        ..bitDepth = media.bitDepth
        ..bitrate = media.bitrate
        ..channels = media.channels
        ..metadataComplete = true
        ..lastModified = stat?.modified ?? _now();
      if (isUntagged) {
        song.hasLocalEdits = true;
      }
      // Existing CUE ranges and current descriptive/user metadata retain their identity.
      if (song.startOffsetMs == null) {
        song.durationMs = media.durationMs ?? song.durationMs;
      }
      await isar.songEntitys.put(song);
      await _boundary('commit:afterSong');
      _current(isCurrent);
      receipt
        ..state = 'committed'
        ..committedAt = _now();
      await isar.iosTransferReceiptEntitys.put(receipt);
      await _boundary('commit:beforeCommit');
      await validateOwnership();
      _current(isCurrent);
      return IosTransferImportResult(receipt, song);
    });
    await _boundary('commit:afterCommit');
    return result;
  }

  /// The scanner must call this inside its write transaction before indexing
  /// an owned target, rather than caching the answer before file enumeration.
  Future<bool> isReservedPathInTransaction(String path) async {
    if (!p.isWithin(musicRoot, path)) return false;
    final relative = p
        .relative(path, from: musicRoot)
        .split(p.separator)
        .join('/');
    if (!relative.startsWith('Desktop Copies/')) return false;
    return await isar.iosTransferReceiptEntitys
            .where()
            .relativePathEqualTo(relative)
            .filter()
            .group(
              (q) => q.stateEqualTo('prepared').or().stateEqualTo('retiring'),
            )
            .findFirst() !=
        null;
  }

  /// Caller must revoke import writers and drain native file work first. Its
  /// separate current-client cleanup authority is checked inside this writer;
  /// a revoked publication lease cannot authorize abandonment. No public file
  /// is touched here. Retiring is durable and blocks late prepare/commit/scan.
  Future<IosTransferImportResult?> beginRetirement(
    IosTransferJob job,
    IosTransferLibraryTarget target, {
    required bool Function() isCurrent,
    required Future<void> Function() validateCleanupAuthority,
  }) async {
    _validateJob(job, target);
    final result = await isar.writeTxn(() async {
      _current(isCurrent);
      final receipt = await isar.iosTransferReceiptEntitys.getByOperationKey(
        keyFor(job),
      );
      if (receipt == null) return null;
      _matches(receipt, job, target);
      final song = await isar.songEntitys.get(receipt.localSongId);
      if (receipt.state == 'prepared') {
        await validateCleanupAuthority();
        _current(isCurrent);
        receipt.state = 'retiring';
        await isar.iosTransferReceiptEntitys.put(receipt);
        await _boundary('retiring:beforeCommit');
        await validateCleanupAuthority();
        _current(isCurrent);
      }
      return IosTransferImportResult(receipt, song);
    });
    await _boundary('retiring:afterCommit');
    return result;
  }

  /// Native has fenced publication, drained its file worker and proved that
  /// this older revision has no custody. Retire only the exact private row;
  /// never infer file ownership, remove a file, or change a Song here.
  Future<void> retireOrphanReservation(
    IosTransferPendingReservation pending,
    IosTransferOrphanLease lease, {
    required bool Function() isCurrent,
    required Future<void> Function() validateBookkeepingAuthority,
  }) async {
    final job = lease.currentJob, identity = lease.currentJob.intent.identity;
    job.intent.validate(submission: true);
    if (pending.operationKey != lease.key.value ||
        pending.songId != lease.songId) {
      _fail(IosTransferImportConflict.receiptMismatch);
    }
    await isar.writeTxn(() async {
      _current(isCurrent);
      await validateBookkeepingAuthority();
      final row = await isar.iosTransferReceiptEntitys.get(pending.id);
      final path = pending.relativePath;
      if (row == null ||
          row.schemaVersion != 1 ||
          row.operationKey != pending.operationKey ||
          row.jobId != lease.key.jobId ||
          row.revision != lease.key.revision ||
          row.localSongId != pending.songId ||
          row.relativePath != path ||
          row.committedAt != null ||
          !{'prepared', 'retiring', 'retired'}.contains(row.state) ||
          (pending.retiring && row.state == 'prepared') ||
          row.serverId != identity.localServerId ||
          row.desktopId != identity.scope.desktopId ||
          row.desktopUserId != identity.desktopUserId ||
          row.pairingId != identity.scope.pairingId ||
          row.origin != identity.scope.origin ||
          row.sourceId != identity.sourceId ||
          row.bytes < 1 ||
          row.bytes >= 9223372036854775807 ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(row.sha256) ||
          (job.intent.expectedBytes != null &&
              row.bytes != job.intent.expectedBytes) ||
          (job.intent.expectedSha256 != null &&
              row.sha256 != job.intent.expectedSha256) ||
          utf8.encode(path).length > 512 ||
          path.split('/').length != 2 ||
          !path.startsWith('Desktop Copies/') ||
          path.split('/').last.startsWith('.') ||
          path.contains('\\') ||
          RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(path) ||
          !path.endsWith(
            ' - ${row.jobId}-r${row.revision}.${job.intent.metadata.fileExtension}',
          )) {
        _fail(IosTransferImportConflict.receiptMismatch);
      }
      _current(isCurrent);
      if (row.state != 'retired') {
        row.state = 'retired';
        await isar.iosTransferReceiptEntitys.put(row);
      }
      await _boundary('orphan:beforeCommit');
      await validateBookkeepingAuthority();
      _current(isCurrent);
    });
    await _boundary('orphan:afterCommit');
  }

  /// Call after native cancellation/owned-file cleanup has drained. A committed
  /// receipt remains historical proof; this never removes or recreates a song.
  Future<IosTransferImportResult?> retireReservation(
    IosTransferJob job,
    IosTransferLibraryTarget target, {
    required bool Function() isCurrent,
    required Future<void> Function() validateOwnership,
  }) async {
    _validateJob(job, target);
    final result = await isar.writeTxn(() async {
      _current(isCurrent);
      final receipt = await isar.iosTransferReceiptEntitys.getByOperationKey(
        keyFor(job),
      );
      if (receipt == null) return null;
      _matches(receipt, job, target);
      final song = await isar.songEntitys.get(receipt.localSongId);
      if (receipt.state != 'committed') {
        if (!{'retiring', 'retired'}.contains(receipt.state)) {
          _fail(IosTransferImportConflict.retired);
        }
        await validateOwnership();
        _current(isCurrent);
        receipt.state = 'retired';
        await isar.iosTransferReceiptEntitys.put(receipt);
        await _boundary('retired:beforeCommit');
        await validateOwnership();
        _current(isCurrent);
      }
      return IosTransferImportResult(receipt, song);
    });
    await _boundary('retired:afterCommit');
    return result;
  }
}
