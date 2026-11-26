import 'package:flick/l10n/l10n.dart';
import 'package:flick/l10n/generated/app_localizations.dart';

// Earlier library rows stored localized placeholders. Recognize every shipped
// locale so changing the UI language cannot prevent later metadata enrichment.
final _unknownArtists = {
  for (final locale in kSupportedLocales)
    lookupAppLocalizations(locale).unknownArtist,
};
final _unknownAlbums = {
  for (final locale in kSupportedLocales)
    lookupAppLocalizations(locale).unknownAlbum,
};
const _extraUnknownArtists = {
  '<unknown>',
  'unknown artist',
  'unknown',
  'lokal phone',
  'lokal mobile',
  'phone-downloads',
};

bool isUnknownLibraryArtist(String? value) {
  if (value == null) return false;
  if (_unknownArtists.contains(value)) return true;
  final normalized = value.trim().toLowerCase();
  if (_extraUnknownArtists.contains(normalized)) return true;
  return _unknownArtists.any(
    (entry) => entry.trim().toLowerCase() == normalized,
  );
}

bool isUnknownLibraryAlbum(String? value) => _unknownAlbums.contains(value);
