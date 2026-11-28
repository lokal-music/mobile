import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/features/konnekted/library/lokal_genres.dart';
import 'package:flick/features/search/providers/search_filter_provider.dart';
import 'package:flick/features/search/screens/search_screen.dart';
import 'package:flick/models/song.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FixedScopeNotifier extends SearchScopeNotifier {
  _FixedScopeNotifier(this._initialScope);

  final SearchScope _initialScope;

  @override
  SearchScope build() => _initialScope;
}

const _library = <Song>[
  Song(
    id: '1',
    title: 'Blue in Green',
    artist: 'Miles Davis',
    album: 'Kind of Blue',
    genre: 'Jazz',
    duration: Duration(minutes: 5),
    fileType: 'FLAC',
  ),
  Song(
    id: '2',
    title: 'So What',
    artist: 'Miles Davis',
    album: 'Kind of Blue',
    genre: 'Jazz',
    duration: Duration(minutes: 9),
    fileType: 'FLAC',
  ),
  Song(
    id: '3',
    title: 'Paranoid Android',
    artist: 'Radiohead',
    album: 'OK Computer',
    genre: 'Rock',
    duration: Duration(minutes: 6),
    fileType: 'FLAC',
  ),
];

Widget _buildSearch(SearchScope scope) => ProviderScope(
  overrides: [
    konnektedLibraryProvider.overrideWithValue(const AsyncData(_library)),
    searchScopeProvider.overrideWith(() => _FixedScopeNotifier(scope)),
  ],
  child: MaterialApp(
    theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
    home: const SearchScreen(),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'app_auto_focus_search': false,
    });
  });

  testWidgets('Search does not show Browse by genre in All scope', (
    tester,
  ) async {
    await tester.pumpWidget(_buildSearch(SearchScope.all));
    await tester.pump();

    expect(find.text('Browse by genre'), findsNothing);
    expect(find.byType(LokalGenreGrid), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Search does not show Browse by genre in Local scope', (
    tester,
  ) async {
    await tester.pumpWidget(_buildSearch(SearchScope.library));
    await tester.pump();

    expect(find.text('Browse by genre'), findsNothing);
    expect(find.byType(LokalGenreGrid), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
