// Localization entry point for Flick.
//
// Two accessors are provided, on purpose:
//
//   * `l10n.<key>`     -- a global accessor, usable anywhere, including the
//                         service layer. A large share of this app's
//                         user-visible strings live in services that have no
//                         BuildContext (player_service.dart alone holds ~170),
//                         so a context-only API would not be practical.
//   * `context.l10n`   -- the idiomatic widget-layer accessor.
//
// The global is kept in sync by [LocaleController.bind], which is called from
// MaterialApp.builder on every build, and once from main() before the first
// frame so that strings produced during startup already use the right locale.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import 'package:flick/l10n/generated/app_localizations.dart';

import 'lokal_ui_translations.dart';

import 'package:flick/services/app_preferences_service.dart';

export 'package:flick/l10n/generated/app_localizations.dart';

// 模型层的展示扩展（label / description / menuLabel …）。
//
// 它们放在 lib/l10n/ 而不是 lib/models/，是为了让模型保持与语言无关 —— 上游
// review 明确要求 models 不得依赖 l10n（会破坏分层与可测试性）。这里 re-export，
// 调用方只要 import 本文件就能拿到，无需额外 import。
export 'package:flick/l10n/model_labels.dart';

/// Locales the app ships translations for.
///
/// English is listed first so that a device locale we do not translate falls
/// back to English rather than to Chinese. Chinese devices still resolve to
/// `zh` through the language-code match below.
const List<Locale> kSupportedLocales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('fr'),
  Locale('de'),
  Locale('es'),
  Locale('it'),
  Locale('pt', 'BR'),
  Locale('nl'),
  Locale('pl'),
  Locale('ru'),
  Locale('sv'),
  Locale('tr'),
];

/// Used when nothing else matches.
const Locale kFallbackLocale = Locale('en');

/// The current localizations. Initialized to English so that reads before the
/// first frame cannot throw.
AppLocalizations _current = lookupAppLocalizations(kFallbackLocale);

/// Global accessor. Prefer `context.l10n` inside widgets.
AppLocalizations get l10n => _current;

/// Localizes fixed Lokal presentation phrases without changing navigation
/// identifiers or translating song, artist, album, and file metadata.
String lokalText(String message, {Map<String, Object?> args = const {}}) {
  const autonyms = {
    'English',
    'Français',
    'Deutsch',
    'Español',
    'Italiano',
    'Português (Brasil)',
    'Nederlands',
    'Polski',
    'Русский',
    'Svenska',
    'Türkçe',
    '简体中文',
    'Lokal',
    'Flick',
    'YouTube Music',
    'Spotify',
    'Last.fm',
    'ListenBrainz',
  };
  final locale = l10n.localeName.replaceAll('-', '_');
  var value = autonyms.contains(message)
      ? message
      : (lokalUiTranslations[locale]?[message] ??
            lokalUiTranslations[locale.split('_').first]?[message] ??
            message);
  for (final entry in args.entries)
    value = value.replaceAll('{${entry.key}}', entry.value?.toString() ?? '');
  return value;
}

/// Idiomatic widget-layer accessor.
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Maps [requested] onto the closest locale we actually support.
Locale resolveSupportedLocale(Locale requested) {
  for (final supported in kSupportedLocales) {
    if (supported.languageCode == requested.languageCode) {
      return supported;
    }
  }
  return kFallbackLocale;
}

/// Holds the user's language choice and keeps the global [l10n] in sync.
///
/// A `null` [value] means "follow the device locale".
class LocaleController extends ValueNotifier<Locale?> {
  LocaleController._() : super(null);

  static final LocaleController instance = LocaleController._();

  /// Persisted marker for "follow the system locale".
  static const String systemValue = 'system';

  /// True when the app follows the device locale.
  bool get followsSystem => value == null;

  /// The locale to hand to MaterialApp. Never null.
  Locale get effectiveLocale => value ?? _deviceLocale();

  /// Restores the persisted choice. Await this before the first frame.
  Future<void> load() async {
    final stored = await AppPreferencesService().getAppLocale();
    value = _localeFromStored(stored);
  }

  /// Selects [locale], or `null` to follow the device locale.
  Future<void> select(Locale? locale) async {
    if (locale == value) return;
    value = locale;
    await AppPreferencesService().setAppLocale(_storedFromLocale(locale));
    if (!Platform.isAndroid) return;
    // Android home-screen widgets use native resources, not Flutter's
    // Localizations delegate. Mirror the choice and refresh the widget views
    // so manually chosen Türkçe takes effect without requiring an OS switch.
    try {
      await HomeWidget.saveWidgetData<String>(
        'flick_widget_locale',
        locale?.languageCode ?? systemValue,
      );
      for (final provider in <String>[
        'com.mossapps.flick.widgets.MiniPlayerWidgetProvider',
        'com.mossapps.flick.widgets.FlowRadioWidgetProvider',
        'com.mossapps.flick.widgets.CoverFlowRecommendationWidgetProvider',
        'com.mossapps.flick.widgets.FlagshipWidgetProvider',
        'com.mossapps.flick.widgets.CompactWidgetProvider',
      ]) {
        await HomeWidget.updateWidget(qualifiedAndroidName: provider);
      }
    } catch (_) {
      // A widget host may not exist. Language selection still succeeds.
    }
  }

  /// Points the global accessor at [localizations]. Called from the app builder.
  void bind(AppLocalizations localizations) {
    _current = localizations;
  }

  /// Points the global accessor at [locale] without a BuildContext. Used during
  /// startup, before any Localizations widget exists.
  void bindLocale(Locale locale) {
    _current = lookupAppLocalizations(resolveSupportedLocale(locale));
  }

  Locale _deviceLocale() {
    final binding = WidgetsBinding.instance;
    final locales = binding.platformDispatcher.locales;
    if (locales.isEmpty) return kFallbackLocale;
    return resolveSupportedLocale(locales.first);
  }

  Locale? _localeFromStored(String? stored) {
    if (stored == null || stored.isEmpty || stored == systemValue) return null;
    final parts = stored.split('_');
    final language = parts.first;
    if (language.isEmpty) return null;
    final country = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
    return resolveSupportedLocale(
      country == null ? Locale(language) : Locale(language, country),
    );
  }

  String _storedFromLocale(Locale? locale) {
    if (locale == null) return systemValue;
    final country = locale.countryCode;
    return country == null || country.isEmpty
        ? locale.languageCode
        : '${locale.languageCode}_$country';
  }
}
