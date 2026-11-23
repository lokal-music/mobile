import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flick/l10n/lokal_ui_translations.dart';

Map<String, String> _strings(String path) {
  final contents = jsonDecode(File(path).readAsStringSync())
      as Map<String, dynamic>;
  return {
    for (final entry in contents.entries)
      if (!entry.key.startsWith('@') && entry.value is String)
        entry.key: entry.value as String,
  };
}

/// Recognizes both simple placeholders and ICU plural/select argument names.
Set<String> _arguments(String message) => RegExp(
  r'\{([A-Za-z_]\w*)\s*(?:,|\})',
).allMatches(message).map((match) => match.group(1)!).toSet();

bool _balancedBraces(String message) {
  var depth = 0;
  for (final codeUnit in message.codeUnits) {
    if (codeUnit == 123) depth++;
    if (codeUnit == 125) depth--;
    if (depth < 0) return false;
  }
  return depth == 0;
}

void main() {
  final english = _strings('lib/l10n/app_en.arb');
  final russian = _strings('lib/l10n/app_ru.arb');
  final sourceWithMetadata = jsonDecode(
    File('lib/l10n/app_en.arb').readAsStringSync(),
  ) as Map<String, dynamic>;

  test('Russian ARB covers every source key, without extra keys', () {
    expect(russian.keys.toSet(), english.keys.toSet());
    expect(
      jsonDecode(File('lib/l10n/app_ru.arb').readAsStringSync())['@@locale'],
      'ru',
    );
  });

  test('Russian strings preserve ICU syntax and argument names', () {
    final errors = <String>[];
    for (final entry in english.entries) {
      final translated = russian[entry.key]!;
      if (translated.trim().isEmpty) {
        errors.add('${entry.key}: empty translation');
      }
      if (!_balancedBraces(translated)) {
        errors.add('${entry.key}: unbalanced braces');
      }
      if (entry.value.contains(', plural,')) {
        final metadata = sourceWithMetadata['@${entry.key}']
            as Map<String, dynamic>? ?? const <String, dynamic>{};
        final declared =
            (metadata['placeholders'] as Map<String, dynamic>? ??
                const <String, dynamic>{}).keys.toSet();
        for (final argument in declared) {
          if (!translated.contains('{$argument}') &&
              !translated.contains('{$argument, plural,')) {
            errors.add('${entry.key}: missing argument $argument');
          }
        }
      } else if (!_setEquals(_arguments(entry.value), _arguments(translated))) {
        errors.add('${entry.key}: source ${_arguments(entry.value)} vs '
            'Russian ${_arguments(translated)}');
      }
      if (entry.value.contains(', plural,') &&
          (!translated.contains(', plural,') ||
              !translated.contains('other{'))) {
        errors.add('${entry.key}: missing ICU plural branch');
      }
    }
    expect(errors, isEmpty, reason: errors.join('\n'));
  });

  test('all Lokal presentation phrases have Russian strings and matching arguments', () {
    final source = lokalUiTranslations['fr']!;
    final localized = lokalUiTranslations['ru']!;
    expect(localized.keys.toSet(), containsAll(source.keys.toSet()));

    final errors = <String>[];
    for (final entry in localized.entries) {
      if (entry.value.trim().isEmpty) {
        errors.add('${entry.key}: empty UI translation');
      }
      if (!_setEquals(_arguments(entry.key), _arguments(entry.value))) {
        errors.add('${entry.key}: placeholder mismatch');
      }
    }
    expect(errors, isEmpty, reason: errors.join('\n'));
  });

  test('legal attribution stays unchanged in Russian locale', () {
    const key = 'mitLicenseCopyrightC2026Flick';
    expect(russian[key], english[key]);
  });
}

bool _setEquals(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);
