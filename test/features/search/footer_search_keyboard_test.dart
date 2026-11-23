import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/library/lokal_library_kit.dart';
import 'package:flick/features/search/screens/search_screen.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _search({ValueListenable<int>? footerTaps, String? initialQuery}) =>
    ProviderScope(
      child: MaterialApp(
        theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
        home: SearchScreen(
          footerFocusRequests: footerTaps,
          initialQuery: initialQuery,
        ),
      ),
    );

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'app_auto_focus_search': false,
    }),
  );

  testWidgets('footer Search opens the keyboard even when auto-focus is off', (
    tester,
  ) async {
    final taps = ValueNotifier<int>(1);
    addTearDown(taps.dispose);
    await tester.pumpWidget(_search(footerTaps: taps));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(
      field.autofocus,
      isFalse,
      reason: 'The optional generic auto-focus preference remains off',
    );
    expect(
      field.focusNode?.hasFocus,
      isTrue,
      reason: 'An explicit footer Search tap focuses the search field',
    );
    expect(
      tester.testTextInput.isVisible,
      isTrue,
      reason: 'Focus should open the Android software keyboard',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reselecting footer Search refocuses and selects existing query without erasing it',
    (tester) async {
      final taps = ValueNotifier<int>(1);
      addTearDown(taps.dispose);
      await tester.pumpWidget(_search(footerTaps: taps));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'Miles');
      // Simulate a user closing the keyboard, then tapping Search again while
      // already on the Search tab (which does not remount the Search screen).
      final field = tester.widget<TextField>(find.byType(TextField).first);
      tester.testTextInput.hide();
      await tester.pump();
      expect(field.focusNode?.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.byType(SearchScreen), findsOneWidget);

      taps.value++;
      await tester.pump();
      await tester.pump();
      expect(field.focusNode?.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(field.controller!.text, 'Miles');
      expect(
        field.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tapping unfocused Search bar selects previous query, second tap allows cursor edit',
    (tester) async {
      await tester.pumpWidget(_search(initialQuery: 'Daft Punk'));
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.focusNode?.hasFocus, isFalse);

      // First tap focuses the bar and selects all existing query text.
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      expect(field.focusNode?.hasFocus, isTrue);
      expect(
        field.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 9),
      );

      // A second tap while already focused collapses selection so the user can edit.
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      expect(field.controller!.selection.isCollapsed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'LokalSearchField selects existing query on focus gain',
    (tester) async {
      final controller = TextEditingController(text: 'Coltrane');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: LokalTheme.build(LokalTokens.resolve(LokalThemeId.dark)),
          home: Scaffold(
            body: LokalSearchField(
              controller: controller,
              hint: 'Search',
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 8),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ordinary Search entry does not force a keyboard with auto-focus off',
    (tester) async {
      await tester.pumpWidget(_search());
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.autofocus, isFalse);
      expect(field.focusNode?.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching away from footer Search removes its focus listener', (
    tester,
  ) async {
    final taps = ValueNotifier<int>(1);
    addTearDown(taps.dispose);
    await tester.pumpWidget(_search(footerTaps: taps));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    taps.value++;
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
