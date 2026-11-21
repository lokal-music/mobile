// Switching the language at runtime has to reach the strings.
//
// `l10n` is a global accessor (see lib/l10n/l10n.dart) because a large share of
// this app's user-visible text lives in services with no BuildContext.
// `LocaleController.bind` re-points it from `MaterialApp.builder` on every
// build. Anything that reads `l10n` while building therefore follows a language
// switch -- but anything that *captures* it (a field initialised with
// `l10n.something`, a top-level `final`) keeps the first locale forever. That is
// exactly what shipped once: protocol, crossfade and crossfeed labels were built
// at startup, so changing the language left them in the old one
// (fixed upstream in 1fe3af48).
//
// This test pins the contract: flip the controller, and both the global accessor
// and the rendered text must change.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flick/l10n/l10n.dart';

/// The same wiring `lib/app/app.dart` uses: the controller drives `locale`, and
/// the builder keeps the global accessor pointed at the active localizations.
Widget _app() {
  return ValueListenableBuilder<Locale?>(
    valueListenable: LocaleController.instance,
    builder: (context, selectedLocale, _) {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: kSupportedLocales,
        locale: selectedLocale,
        home: Builder(
          builder: (context) {
            LocaleController.instance.bind(AppLocalizations.of(context));
            // Read through the global accessor on purpose: this is what the
            // service layer and the enumerated labels do.
            return Text(l10n.flickReplay, textDirection: TextDirection.ltr);
          },
        ),
      );
    },
  );
}

void main() {
  setUp(() {
    // `LocaleController.select` persists the choice, so the platform channel has
    // to answer; without this the first await never completes.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    // Singleton: leave it following the device locale for the next test.
    LocaleController.instance.value = null;
  });

  testWidgets('a language switch reaches the global l10n accessor', (
    tester,
  ) async {
    await LocaleController.instance.select(const Locale('en'));
    await tester.pumpWidget(_app());
    expect(l10n.flickReplay, 'Lokal Replay');
    expect(find.text('Lokal Replay'), findsOneWidget);

    await LocaleController.instance.select(const Locale('zh', 'CN'));
    await tester.pumpAndSettle();

    expect(
      l10n.flickReplay,
      'Lokal 回顾',
      reason:
          'The global accessor still points at the previous locale, so every '
          'string the service layer produces is stale.',
    );
    expect(find.text('Lokal 回顾'), findsOneWidget);
    expect(find.text('Lokal Replay'), findsNothing);
  });

  testWidgets('Turkish follows a live locale switch without stale text', (
    tester,
  ) async {
    await LocaleController.instance.select(const Locale('en'));
    await tester.pumpWidget(_app());
    expect(l10n.flickReplay, 'Lokal Replay');

    await LocaleController.instance.select(const Locale('tr'));
    await tester.pumpAndSettle();

    expect(l10n.flickReplay, 'Lokal Yıl Özeti');
    expect(l10n.settings, 'Ayarlar');
    expect(lokalText('Queue'), 'Sıra');
    expect(
      lokalText('The phone’s language, or one Lokal is translated into.'),
      'Telefonun dili veya Lokal\'in desteklediği dillerden biri.',
    );
    expect(find.text('Lokal Yıl Özeti'), findsOneWidget);
    expect(find.text('Lokal Replay'), findsNothing);

    await LocaleController.instance.select(const Locale('en'));
    await tester.pumpAndSettle();
    expect(l10n.flickReplay, 'Lokal Replay');
    expect(lokalText('Queue'), 'Queue');
  });

  testWidgets('incoming desktop transfer messages localize dynamic values', (
    tester,
  ) async {
    await LocaleController.instance.select(const Locale('tr'));
    await tester.pumpWidget(_app());
    expect(
      lokalText(
        'Copying {arg0} of {arg1} songs from desktop…',
        args: {'arg0': 2, 'arg1': 5},
      ),
      'Masaüstünden 5 şarkının 2 tanesi kopyalanıyor…',
    );

    await LocaleController.instance.select(const Locale('en'));
    await tester.pumpAndSettle();
    expect(
      lokalText(
        'Copied {arg0} songs from desktop.{arg1}',
        args: {'arg0': 3, 'arg1': ' 2 already on this phone.'},
      ),
      'Copied 3 songs from desktop. 2 already on this phone.',
    );
  });

  testWidgets('incoming desktop progress is translated for every UI locale', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    for (final locale in kSupportedLocales.where(
      (locale) => locale.languageCode != 'en',
    )) {
      await LocaleController.instance.select(locale);
      await tester.pumpAndSettle();
      final message = lokalText(
        'Copying {arg0} of {arg1} songs from desktop…',
        args: {'arg0': 2, 'arg1': 5},
      );
      expect(
        message,
        isNot('Copying {arg0} of {arg1} songs from desktop…'),
        reason: '$locale should have a transfer translation',
      );
      expect(message, contains('2'));
      expect(message, contains('5'));
    }
  });

  test('Turkish is supported and resolves from regional variants', () {
    expect(kSupportedLocales, contains(const Locale('tr')));
    expect(
      resolveSupportedLocale(const Locale('tr', 'TR')),
      const Locale('tr'),
    );
    final translations = lookupAppLocalizations(const Locale('tr'));
    expect(translations.addedSongsToQueue(1), 'Sıraya eklendi');
    expect(translations.addedSongsToQueue(4), '4 şarkı sıraya eklendi');
    expect(translations.songsIn(3, 2), '2 klasörde 3 şarkı');
  });

  testWidgets('a widget reading l10n during build follows the switch', (
    tester,
  ) async {
    // Two switches in a row: a cached value would freeze at the first one.
    await LocaleController.instance.select(const Locale('zh', 'CN'));
    await tester.pumpWidget(_app());
    expect(l10n.flickReplay, 'Lokal 回顾');

    await LocaleController.instance.select(const Locale('en'));
    await tester.pumpAndSettle();
    expect(l10n.flickReplay, 'Lokal Replay');
    expect(find.text('Lokal Replay'), findsOneWidget);
  });
}
