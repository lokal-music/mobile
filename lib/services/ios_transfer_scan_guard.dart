import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../data/entities/ios_transfer_receipt_entity.dart';
import '../data/entities/song_entity.dart';
import 'ios_library_scan_epoch.dart';

bool _matchesReceiptRelativePath(String filePath, String relativePath) {
  if (!p.posix.isAbsolute(filePath) || filePath.contains('\u0000')) {
    return false;
  }
  final normalizedFile = unorm.nfc(p.posix.normalize(filePath)).toLowerCase();
  final normalizedRelative = unorm
      .nfc(p.posix.normalize(relativePath))
      .toLowerCase();
  return normalizedFile.endsWith('/$normalizedRelative');
}

/// Match the native ASCII operation suffix rather than the display title.
/// This also handles APFS case/Unicode spelling and /var parent aliases without
/// filesystem calls inside the Isar writer. A matching UUID in any Desktop
/// Copies directory is conservatively protected until its reservation settles.
String? iosTransferOperationKeyForPath(String path) {
  if (!p.posix.isAbsolute(path) || path.contains('\u0000')) return null;
  final normalized = p.posix.normalize(path);
  if (p.posix.basename(p.posix.dirname(normalized)).toLowerCase() !=
      'desktop copies') {
    return null;
  }
  final match = RegExp(
    r' - ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})-r([1-9][0-9]*)\.[a-z0-9]{1,8}$',
    caseSensitive: false,
  ).firstMatch(p.posix.basename(normalized));
  if (match == null) return null;
  final revision = int.tryParse(match[2]!);
  if (revision == null || revision < 1) return null;
  return '${match[1]!.toLowerCase()}:$revision';
}

/// Scanner-only policy. Every call runs inside the caller's Isar write txn;
/// explicit user mutations and the import writer do not use this policy.
class IosTransferScanGuard {
  IosTransferScanGuard(this.isar);
  final Isar isar;

  Future<bool> allowsUpsertInTransaction(SongEntity incoming) async {
    final key = iosTransferOperationKeyForPath(incoming.filePath);
    if (key == null) return true;
    final receipt = await isar.iosTransferReceiptEntitys.getByOperationKey(key);
    if (receipt == null) return true;
    if (receipt.schemaVersion != 1 ||
        receipt.operationKey != '${receipt.jobId}:${receipt.revision}' ||
        receipt.localSongId < 1) {
      return false;
    }
    if (receipt.state == 'retired') return true;
    if (receipt.state != 'committed') return false;
    // A scan started before import completion has no current local ID. It must
    // not create a duplicate via an alias or overwrite the newly committed row.
    final current = await isar.songEntitys.get(receipt.localSongId);
    if (current == null) {
      // A new user scan may index retained public bytes after explicit removal.
      // It gets a different ID via the receipt-aware allocator; the historical
      // import anchor and its completed transfer are never recreated.
      if (!IosLibraryScanEpoch.current ||
          !_matchesReceiptRelativePath(
            incoming.filePath,
            receipt.relativePath,
          ) ||
          incoming.id == receipt.localSongId) {
        return false;
      }
      if (incoming.id == Isar.autoIncrement) return true;
      final rescanned = await isar.songEntitys.get(incoming.id);
      return rescanned != null && rescanned.filePath == incoming.filePath;
    }
    return incoming.id == receipt.localSongId &&
        current.filePath == incoming.filePath;
  }

  Future<bool> allowsRemovalInTransaction(int songId) async {
    final row = await isar.songEntitys.get(songId);
    final key = row == null
        ? null
        : iosTransferOperationKeyForPath(row.filePath);
    if (key != null) {
      final owner = await isar.iosTransferReceiptEntitys.getByOperationKey(key);
      // Every derived CUE range shares the protected file. Only the atomic
      // range mapper may remove it while a live import receipt owns the path.
      if (owner != null &&
          (owner.schemaVersion != 1 || owner.state != 'retired')) {
        return false;
      }
    }
    final receipts = await isar.iosTransferReceiptEntitys
        .where()
        .localSongIdEqualTo(songId)
        .findAll();
    // Keep the import anchor until explicit removal has crossed the native
    // cancellation/writer barrier. In particular a CUE rewrite must not delete
    // it before its replacement rows have an accepted identity mapping.
    return receipts.every(
      (receipt) => receipt.schemaVersion == 1 && receipt.state == 'retired',
    );
  }
}
