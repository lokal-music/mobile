import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flick/widgets/lokal/lokal_toast.dart';

import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/services/audio_preload_service.dart';
import 'package:flick/services/library_scanner_service.dart';
import 'package:flick/services/music_folder_service.dart';
import 'package:flick/services/replaygain_scan_service.dart';
import 'package:flick/services/scan_session_controller.dart';

import 'library_scan_sheet.dart';

/// Drives one user-visible session from [stream] to its end state on
/// [controller]: `running` until the stream's completion event (or its end),
/// then `complete` with a [ScanSessionResult], `unavailable` for unplugged
/// storage, or `failed` when the stream throws. A Stop that ended the session
/// early leaves it `cancelled`.
///
/// Nothing that runs after the scan's completion event (covers, audio
/// preload, background metadata) is awaited: the scan is done when the scanner
/// says so, and that work carries on silently.
///
/// UI-free so the state machine can be tested on its own.
Future<ScanSessionStatus> driveScanSession({
  required ScanSessionController controller,
  required int generation,
  required Stream<ScanProgress> stream,
  required String title,
  required ScanSessionKind kind,
  Future<int> Function()? countSongs,
  Stopwatch? stopwatch,
}) async {
  final watch = stopwatch ?? (Stopwatch()..start());
  ScanProgress? last;
  try {
    await for (final progress in stream) {
      if (!controller.isCurrent(generation)) break;
      last = progress;
      controller.update(generation, progress);
      if (progress.isComplete) break;
    }
  } catch (error, stackTrace) {
    debugPrint('Scan session "$title" failed: $error\n$stackTrace');
    if (!controller.isCurrent(generation)) return ScanSessionStatus.cancelled;
    controller.fail(generation);
    return ScanSessionStatus.failed;
  }

  if (!controller.isCurrent(generation)) return ScanSessionStatus.cancelled;
  if (last?.unavailable == true) {
    controller.markUnavailable(generation);
    return ScanSessionStatus.unavailable;
  }

  var total = last?.songsFound ?? 0;
  if (countSongs != null) {
    try {
      total = await countSongs();
    } catch (error) {
      debugPrint('Scan session "$title": song count failed: $error');
    }
  }
  if (!controller.isCurrent(generation)) return ScanSessionStatus.cancelled;

  watch.stop();
  controller.finish(
    generation,
    ScanSessionResult(
      kind: kind,
      title: title,
      newSongs: last?.newSongs ?? 0,
      modifiedSongs: last?.modifiedSongs ?? 0,
      deletedSongs: last?.deletedSongs ?? 0,
      totalSongs: total,
      processed: last?.filesProcessed ?? 0,
      elapsed: watch.elapsed,
    ),
  );
  return ScanSessionStatus.complete;
}

/// One line saying what a finished session did, e.g. "12 songs added".
String scanResultHeadline(ScanSessionResult result) {
  final songs = l10n.songsCount;
  return switch (result.kind) {
    ScanSessionKind.scan => '${songs(result.newSongs)} added',
    ScanSessionKind.preload => '${songs(result.processed)} prepared',
    ScanSessionKind.replayGain => '${songs(result.processed)} analysed',
  };
}

/// Adding folders and scanning them, from anywhere in the app: the Library's
/// empty state, Settings › Library and the Folders page all start here.
///
/// Each run owns the single [ScanSessionController] session and shows it in
/// a [LibraryScanSheet] on the root navigator. The run does not depend on the
/// widget that started it, so leaving the page never strands a session.
abstract final class LibraryScanFlow {
  static LibraryScannerService? _scannerInstance;
  static LibraryScannerService get _scanner =>
      _scannerInstance ??= LibraryScannerService();

  static final MusicFolderService _folders = MusicFolderService();

  /// Cancels any active scan session or detached post-scan enrichment task.
  ///
  /// Drops the cached scanner instance after cancelling it so a subsequent
  /// rescan starts with a clean `_currentlyScanning` set even if the cancelled
  /// scan is still unwinding an async native call.
  static void cancelActiveScan() {
    if (ScanSessionController.instance.isActive) {
      ScanSessionController.instance.stop();
    }
    final previous = _scannerInstance;
    _scannerInstance = null;
    previous?.cancelScan();
  }

  /// Opens the system folder picker, saves the folder and scans it.
  ///
  /// Returns the folder that was added, or `null` when nothing was.
  static Future<MusicFolder?> addFolder(BuildContext context) async {
    void say(String message) {
      if (context.mounted) LokalToast.show(context, message);
    }

    if (ScanSessionController.instance.isActive) {
      say('Wait for the current scan to finish.');
      return null;
    }
    try {
      // SAF grants access to the chosen tree itself on every supported Android
      // version. Broad media/storage permissions are not prerequisites and
      // introduce another first-run system dialog before the picker.
      final folder = await _folders.addFolder();
      if (folder == null) return null;
      if (!context.mounted) {
        unawaited(_scanDetached(folder));
        return folder;
      }
      unawaited(scanFolder(context, folder));
      return folder;
    } on FolderAlreadyExistsException catch (e) {
      say(e.message);
    } catch (e) {
      say('Couldn’t add the folder ($e).');
    }
    return null;
  }

  /// Scans one saved folder.
  static Future<void> scanFolder(BuildContext context, MusicFolder folder) {
    final scanner = _scanner;
    return _run(
      context,
      title: folder.displayName,
      kind: ScanSessionKind.scan,
      onCancel: scanner.cancelScan,
      run: () => scanner.scanFolder(folder.uri, folder.displayName),
    );
  }

  /// Rescans every folder: [ScanMode.quick] rereads changed files only,
  /// [ScanMode.full] rereads all of them, and [deep] also reads every folder
  /// straight from storage instead of Android's media index.
  static Future<void> rescanAll(
    BuildContext context, {
    ScanMode mode = ScanMode.quick,
    bool deep = false,
  }) {
    final scanner = _scanner;
    return _run(
      context,
      title: 'All folders',
      kind: ScanSessionKind.scan,
      onCancel: scanner.cancelScan,
      run: () => scanner.scanAllFolders(mode: mode, forceDeepScan: deep),
    );
  }

  /// Decodes every song once so waveforms and loudness are ready.
  static Future<void> preloadAudio(BuildContext context) async {
    final songs = await SongRepository().getAllSongEntities();
    if (songs.isEmpty || !context.mounted) return;
    final service = AudioPreloadService.instance;
    await _run(
      context,
      title: 'Preparing audio',
      kind: ScanSessionKind.preload,
      onCancel: service.cancel,
      countSongs: false,
      run: () => service
          .preloadSongs(songs, forceAll: false)
          .map(
            (p) => ScanProgress(
              songsFound: p.completed,
              totalFiles: p.total,
              filesProcessed: p.completed,
              currentFile: p.currentFile,
              phase: 'Analysing audio',
              isComplete: p.isComplete,
            ),
          ),
    );
  }

  /// Measures every song's loudness and writes ReplayGain tags.
  static Future<void> scanReplayGain(BuildContext context) async {
    final songs = await SongRepository().getAllSongEntities();
    if (songs.isEmpty || !context.mounted) return;
    final service = ReplayGainScanService();
    await _run(
      context,
      title: 'ReplayGain scan',
      kind: ScanSessionKind.replayGain,
      onCancel: service.cancel,
      countSongs: false,
      run: () => service
          .scanLibrary(songs)
          .map(
            (p) => ScanProgress(
              songsFound: p.completed,
              totalFiles: p.total,
              filesProcessed: p.completed,
              currentFile: p.currentFile,
              phase: 'Analysing loudness',
              isComplete: p.isComplete,
            ),
          ),
    );
  }

  /// A folder picked after its page went away still gets scanned, reported
  /// by the floating pill alone.
  static Future<void> _scanDetached(MusicFolder folder) async {
    final controller = ScanSessionController.instance;
    final scanner = _scanner;
    final generation = controller.begin(
      title: folder.displayName,
      kind: ScanSessionKind.scan,
      onCancel: scanner.cancelScan,
    );
    controller.overlayDismissed(generation);
    await driveScanSession(
      controller: controller,
      generation: generation,
      stream: scanner.scanFolder(folder.uri, folder.displayName),
      title: folder.displayName,
      kind: ScanSessionKind.scan,
      countSongs: SongRepository().getSongCount,
    );
    controller.dismiss();
  }

  static Future<void> _run(
    BuildContext context, {
    required String title,
    required ScanSessionKind kind,
    required VoidCallback onCancel,
    required Stream<ScanProgress> Function() run,
    bool countSongs = true,
  }) async {
    final controller = ScanSessionController.instance;
    if (controller.isActive) {
      LokalToast.fromSnackBar(context, 
        const SnackBar(
          content: Text('Wait for the current scan to finish.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final generation = controller.begin(
      title: title,
      kind: kind,
      onCancel: onCancel,
    );
    var sheetOpen = true;
    unawaited(
      LibraryScanSheet.show(
        context,
        generation: generation,
      ).whenComplete(() => sheetOpen = false),
    );

    final status = await driveScanSession(
      controller: controller,
      generation: generation,
      stream: run(),
      title: title,
      kind: kind,
      countSongs: countSongs ? SongRepository().getSongCount : null,
    );

    // The sheet shows the outcome itself, with Done. Hidden, the pill plays
    // its check and a snackbar says what happened.
    if (sheetOpen) return;
    final result = controller.result.value;
    if (status == ScanSessionStatus.complete &&
        result != null &&
        context.mounted) {
      LokalToast.fromSnackBar(context, 
        SnackBar(
          content: Text('${result.title}: ${scanResultHeadline(result)}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    controller.dismiss();
  }
}
