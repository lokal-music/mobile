import 'dart:io';

const maxDesktopTracksToCopy = 100;

List<String> validateDesktopTrackCopyIds(Object? raw) {
  if (raw is! List || raw.isEmpty || raw.length > maxDesktopTracksToCopy) {
    throw const FormatException(
      'Choose between 1 and 100 desktop songs to copy.',
    );
  }
  final ids = <String>[];
  final seen = <String>{};
  for (final value in raw) {
    if (value is! String ||
        value.trim().isEmpty ||
        value != value.trim() ||
        value.length > 512 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value) ||
        !seen.add(value)) {
      throw const FormatException('The desktop song list is invalid.');
    }
    ids.add(value);
  }
  return List.unmodifiable(ids);
}

class DesktopTrackCopyResult {
  const DesktopTrackCopyResult({
    required this.requested,
    required this.copied,
    required this.alreadyPresent,
    required this.failures,
  });

  final int requested;
  final int copied;
  final int alreadyPresent;
  final List<String> failures;
}

class DesktopTrackCopyProgress {
  const DesktopTrackCopyProgress({
    required this.processed,
    required this.copied,
    required this.alreadyPresent,
    required this.total,
    required this.currentTitle,
  });

  final int processed;
  final int copied;
  final int alreadyPresent;
  final int total;
  final String currentTitle;
}

Future<DesktopTrackCopyResult> copyDesktopCatalogueTracks({
  required Object? requestedIds,
  required Future<List<Map<String, dynamic>>> Function() loadCatalogue,
  required Future<bool> Function(String id) isAlreadyPresent,
  required Future<void> Function(Map<String, dynamic> track) copyTrack,
  void Function(DesktopTrackCopyProgress progress)? onProgress,
}) async {
  final ids = validateDesktopTrackCopyIds(requestedIds);
  final catalogue = await loadCatalogue();
  final tracksById = <String, Map<String, dynamic>>{};
  for (final track in catalogue) {
    final id = track['id']?.toString();
    if (id != null && id.isNotEmpty) tracksById.putIfAbsent(id, () => track);
  }

  var copied = 0, alreadyPresent = 0;
  final failures = <String>[];
  var processed = 0;
  for (final id in ids) {
    final track = tracksById[id];
    if (track == null) {
      failures.add('Unavailable desktop song');
      processed++;
      onProgress?.call(
        DesktopTrackCopyProgress(
          processed: processed,
          copied: copied,
          alreadyPresent: alreadyPresent,
          total: ids.length,
          currentTitle: 'Unavailable desktop song',
        ),
      );
      continue;
    }
    final rawTitle = track['title'];
    final title = rawTitle is String && rawTitle.trim().isNotEmpty
        ? _safeText(rawTitle, 80)
        : 'Desktop song';
    try {
      if (await isAlreadyPresent(id)) {
        alreadyPresent++;
      } else {
        await copyTrack(track);
        copied++;
      }
    } on Object catch (error) {
      final reason = switch (error) {
        StateError(:final message) => message.toString(),
        FormatException(:final message) => message.toString(),
        HttpException(:final message) => message,
        _ => 'Transfer failed.',
      };
      final safeReason = _safeText(reason, 120);
      failures.add(
        '$title: ${safeReason.isEmpty ? "Transfer failed." : safeReason}',
      );
    } finally {
      processed++;
      onProgress?.call(
        DesktopTrackCopyProgress(
          processed: processed,
          copied: copied,
          alreadyPresent: alreadyPresent,
          total: ids.length,
          currentTitle: title,
        ),
      );
    }
  }
  return DesktopTrackCopyResult(
    requested: ids.length,
    copied: copied,
    alreadyPresent: alreadyPresent,
    failures: List.unmodifiable(failures),
  );
}

String _safeText(String value, int limit) {
  final sanitized = value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
  return sanitized.substring(0, sanitized.length.clamp(0, limit).toInt());
}
