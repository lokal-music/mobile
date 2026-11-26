import '../../core/utils/library_metadata_placeholders.dart';

/// Machine-generated transfer UUID suffix (with optional iOS `-r<N>` revision).
final RegExp transferUuidSuffixPattern = RegExp(
  r'\s+-\s+[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?:-r[1-9][0-9]*)?$',
  caseSensitive: false,
);

/// Machine-generated 16-hex addon hash suffix (` [0123456789abcdef]`).
final RegExp transferAddonHashSuffixPattern = RegExp(
  r'\s+\[[0-9a-f]{16}\]$',
  caseSensitive: false,
);

/// Trailing copy collision suffix (` (2)` .. ` (9999)`).
final RegExp _copyCollisionSuffixPattern = RegExp(
  r'\s+\((?:[2-9]|[1-9][0-9]{1,3})\)$',
);

const Set<String> _placeholderArtists = {
  '',
  '<unknown>',
  'unknown artist',
  'unknown',
  'lokal phone',
  'lokal mobile',
  'phone-downloads',
};

/// Returns true if [artist] is empty, a corrupted transfer placeholder, or a
/// localized unknown-artist sentinel.
bool isPlaceholderTransferArtist(String? artist) {
  if (artist == null) return true;
  final trimmed = artist.trim().toLowerCase();
  if (_placeholderArtists.contains(trimmed)) return true;
  return isUnknownLibraryArtist(artist);
}

/// Returns true when [value] ends with a legacy transfer UUID or 16-hex addon
/// hash suffix.
bool hasTransferArtifact(String value) {
  final trimmed = value.trimRight();
  return transferUuidSuffixPattern.hasMatch(trimmed) ||
      transferAddonHashSuffixPattern.hasMatch(trimmed);
}

({String value, bool strippedMachineSuffix}) _stripMachineSuffixes(
  String input,
) {
  var current = input.trim();
  var stripped = false;
  while (true) {
    final withoutUuid = current.replaceFirst(transferUuidSuffixPattern, '');
    if (withoutUuid != current) {
      current = withoutUuid.trimRight();
      stripped = true;
      continue;
    }
    final withoutHash = current.replaceFirst(
      transferAddonHashSuffixPattern,
      '',
    );
    if (withoutHash != current) {
      current = withoutHash.trimRight();
      stripped = true;
      continue;
    }
    if (stripped) {
      final withoutCollision = current.replaceFirst(
        _copyCollisionSuffixPattern,
        '',
      );
      if (withoutCollision != current) {
        current = withoutCollision.trimRight();
        continue;
      }
    }
    break;
  }
  return (
    value: current.trim().isEmpty ? input.trim() : current.trim(),
    strippedMachineSuffix: stripped,
  );
}

/// Strips machine-generated transfer UUID / `-r<N>` / `[16-hex]` suffixes (and
/// any exposed copy-collision suffix) from a filename stem.
String cleanTransferStem(String stem) => _stripMachineSuffixes(stem).value;

/// Shared Desktop/Mobile metadata cleaner:
/// 1. Iteratively strips `- <uuid>`, `- <uuid>-r<N>`, and `[16-hex]` suffixes
///    from [title] (plus a trailing ` (N)` collision suffix if a machine suffix
///    was stripped).
/// 2. Recovers `artist` and `title` from `'Artist - Title'` when [artist] is a
///    placeholder/corrupted string.
/// 3. Strips a redundant `'${artist} - '` prefix from [title] when [artist] is
///    already known.
({String title, String artist, bool changed}) cleanTransferMetadata({
  required String title,
  required String artist,
}) {
  final stripped = _stripMachineSuffixes(title);
  var nextTitle = stripped.value;
  var nextArtist = artist.trim();

  if (isPlaceholderTransferArtist(nextArtist)) {
    final sepIndex = nextTitle.indexOf(' - ');
    if (sepIndex > 0) {
      final left = nextTitle.substring(0, sepIndex).trim();
      final right = nextTitle.substring(sepIndex + 3).trim();
      if (left.isNotEmpty && right.isNotEmpty) {
        if (!isPlaceholderTransferArtist(left)) {
          nextArtist = left;
        }
        nextTitle = right;
      }
    }
  } else {
    final normalizedArtist = nextArtist.replaceAll(RegExp(r'\s+'), ' ');
    final escapedArtist = RegExp.escape(
      normalizedArtist,
    ).replaceAll(r'\ ', r'\s+');
    final prefixPattern = RegExp(
      '^$escapedArtist\\s+-\\s+(.+)\$',
      caseSensitive: false,
    );
    final match = prefixPattern.firstMatch(nextTitle);
    if (match != null) {
      final remainder = match.group(1)!.trim();
      if (remainder.isNotEmpty) {
        nextTitle = remainder;
      }
    }
  }

  final effectiveArtist = nextArtist.isEmpty ? artist : nextArtist;
  final changed = nextTitle != title || effectiveArtist != artist;
  return (title: nextTitle, artist: effectiveArtist, changed: changed);
}
