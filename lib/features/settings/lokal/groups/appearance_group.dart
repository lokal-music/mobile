import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/models/progress_bar_style.dart';
import 'package:flick/features/player/widgets/full_player_seek_bar.dart';
import 'package:flick/features/player/widgets/waveform_preview_peaks.dart';
import 'package:flick/core/utils/lokal_layout.dart';
import 'package:flick/features/appearance/lokal_performance_selector.dart';

import 'dart:async';
import 'dart:io';

import 'package:flick/services/motion_art/moving_cover_settings.dart';
import 'package:flick/features/music_videos/video_quality_settings.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/core/utils/app_haptics.dart';
import 'package:flick/features/appearance/lokal_appearance_screen.dart';
import 'package:flick/features/settings/screens/widget_settings_screen.dart';
import 'package:flick/features/settings/screens/ios_widget_settings_screen.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/providers/providers.dart';
import 'package:flick/widgets/lokal/settings/lokal_settings_kit.dart';

void _push(BuildContext context, Widget page) => unawaited(
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
);

/// Theme/accent controls, plus explicit iPhone icon selection. iOS icon changes
/// are user initiated because the system presents its own confirmation alert.
List<LokalSettingsSection> themeAccentSettings(
  BuildContext context,
  WidgetRef ref,
) {
  final appearance = ref.watch(lokalAppearanceProvider);
  final look = ref.read(lokalAppearanceProvider.notifier);
  return [
    LokalSettingsSection(
      title: lokalText('Theme & accent'),
      children: [
        LokalSettingRow(
          label: lokalText('Theme'),
          description: lokalText('Desktop Lokal’s ten themes.'),
          stacked: true,
          trailing: LokalThemeGrid(
            padding: EdgeInsets.zero,
            selected: appearance.theme,
            onSelect: (id) {
              HapticFeedback.selectionClick();
              look.selectTheme(id);
            },
          ),
        ),
        LokalSettingRow(
          label: lokalText('Accent'),
          description: Platform.isIOS
              ? 'Colors inside Lokal. Choose the Home Screen icon separately below.'
              : lokalText(
                  'The app icon follows your accent after you leave Lokal with playback idle. Some launchers restart the app when updating its icon.',
                ),
          stacked: true,
          trailing: LokalAccentRow(
            padding: EdgeInsets.zero,
            selected: appearance.accent,
            onSelect: (accent) {
              HapticFeedback.selectionClick();
              look.setAccent(accent);
            },
          ),
        ),
        if (Platform.isIOS)
          LokalSettingLink(
            label: 'App icon',
            description: 'Choose a Lokal icon for your iPhone Home Screen.',
            onTap: () => unawaited(
              const MethodChannel('lokal/ios')
                  .invokeMethod<bool>('showIconPicker'),
            ),
          ),
      ],
    ),
  ];
}

List<LokalSettingsSection> appearanceSettings(
  BuildContext context,
  WidgetRef ref,
) {
  final appearance = ref.watch(lokalAppearanceProvider);
  final look = ref.read(lokalAppearanceProvider.notifier);
  final prefs = ref.watch(appPreferencesProvider);
  final notifier = ref.read(appPreferencesProvider.notifier);
  final moving = ref.watch(movingCoverSettingsProvider);
  final motion = ref.read(movingCoverSettingsProvider.notifier);
  return [
    LokalSettingsSection(
      title: lokalText('Theme'),
      children: [
        ...themeAccentSettings(context, ref).single.children,
        LokalSettingSlider(
          label: lokalText('Text size'),
          description: lokalText('Bigger or smaller text across Lokal.'),
          value: appearance.textScale,
          min: LokalAppearance.minTextScale,
          max: LokalAppearance.maxTextScale,
          divisions: 16,
          valueLabel: (v) => '${(v * 100).round()}%',
          semanticFormatter: (v) => '${(v * 100).round()} percent',
          onChanged: look.setTextScale,
        ),
        lokalPerformanceSelector(ref),
      ],
    ),
    LokalSettingsSection(
      title: lokalText('Now Playing'),
      children: [
        LokalSettingRow(
          label: lokalText('Full player seekbar'),
          description: lokalText(
            'Line, Wavy or Waveform. Waveforms are prepared from local or downloaded audio. Other streams use a line.',
          ),
          stacked: true,
          trailing: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<ProgressBarStyle>(
                key: ValueKey(ref.watch(progressBarStyleProvider)),
                initialValue: ref.watch(progressBarStyleProvider),
                isExpanded: true,
                items: [
                  for (final style in [
                    ProgressBarStyle.line,
                    ProgressBarStyle.wavy,
                    ProgressBarStyle.waveform,
                  ])
                    DropdownMenuItem(value: style, child: Text(style.label)),
                ],
                onChanged: (style) {
                  if (style != null) {
                    AppHaptics.selection();
                    unawaited(
                      ref
                          .read(progressBarStyleProvider.notifier)
                          .setStyle(style),
                    );
                  }
                },
              ),
              ExcludeSemantics(
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: LokalTokens.resolve(LokalThemeId.dark).surface2,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IgnorePointer(
                    child: FullPlayerSeekBar(
                      style: ref.watch(progressBarStyleProvider),
                      value: .55,
                      // Illustration only; the player reads actual audio peaks.
                      peaks: waveformPreviewPeaks,
                      onChanged: (_) {},
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        LokalSettingRow.toggle(
          label: lokalText('Full resolution tags in full player'),
          description: lokalText(
            'Show the available codec, bit depth, sample rate or bitrate instead of the quality tier. Keep the player badge white.',
          ),
          value: appearance.resolutionTagsInFullPlayer,
          onChanged: look.setResolutionTagsInFullPlayer,
        ),
        LokalSettingRow.toggle(
          label: lokalText('Unboxed player controls'),
          description: lokalText(
            'Remove button backgrounds while keeping the same icons and layout.',
          ),
          value: appearance.unboxedPlayerControls,
          onChanged: look.setUnboxedPlayerControls,
        ),
        LokalSettingRow.toggle(
          label: lokalText('Fullscreen cover'),
          description: lokalText(
            LokalLayout.isTablet(context)
                ? 'A large square cover beside the controls, with artwork blur behind the player.'
                : 'Extend album covers behind the header and fade them into the player. Spotify Canvas fills the screen.',
          ),
          value: appearance.fullscreenCover,
          onChanged: look.setFullscreenCover,
        ),
        if (Platform.isIOS)
          LokalSettingRow(
            label: lokalText('Video quality'),
            description: lokalText(
              'Adjust video quality in the YouTube player.',
            ),
          )
        else
          LokalSettingRow(
            label: lokalText('Video quality'),
            description: lokalText(
              'Maximum resolution for music videos. Higher quality uses more data; the nearest available stream is selected.',
            ),
            stacked: true,
            trailing: DropdownButtonFormField<int>(
              key: ValueKey(ref.watch(videoQualityProvider)),
              initialValue: ref.watch(videoQualityProvider),
              isExpanded: true,
              items: [
                for (final height in videoQualityHeights)
                  DropdownMenuItem(
                    value: height,
                    child: Text(lokalText(videoQualityLabel(height))),
                  ),
              ],
              onChanged: (height) {
                if (height != null) {
                  unawaited(
                    ref.read(videoQualityProvider.notifier).select(height),
                  );
                }
              },
            ),
          ),
        LokalSettingRow.toggle(
          label: lokalText('Moving covers'),
          description: lokalText(
            'Play an animated cover or Canvas in either player, when one is available.',
          ),
          value: prefs.animatedAlbumArt,
          onChanged: notifier.setAnimatedAlbumArt,
        ),
        if (prefs.animatedAlbumArt) ...[
          for (final source in movingCoverSources.entries)
            LokalSettingRow.toggle(
              label: source.value,
              description: source.key == 'spotify'
                  ? lokalText(
                      'Uses your Spotify account in You → Data → Accounts.',
                    )
                  : source.key == 'apple'
                  ? lokalText(
                      'Animated album covers, with Apple lookup fallback.',
                    )
                  : source.key == 'tidal'
                  ? lokalText('Video album covers.')
                  : source.key == 'community'
                  ? lokalText('Clips shared by other listeners.')
                  : lokalText(
                      'Apple animated artwork through artwork.m8tec.top.',
                    ),
              value: moving.sources.contains(source.key),
              onChanged: (value) => motion.setSource(source.key, value),
            ),
          LokalSettingRow.toggle(
            label: lokalText('Prioritize Spotify Canvas'),
            description: lokalText(
              'Ask Spotify before album covers. Tall videos are cropped to fit the cover.',
            ),
            value: moving.spotifyFirst,
            onChanged: motion.prioritizeSpotify,
          ),
        ],
      ],
    ),
    LokalSettingsSection(
      title: lokalText('Interface'),
      children: [
        LokalSettingRow.toggle(
          label: lokalText('Home greeting and subheader'),
          description: lokalText(
            'Show the greeting and listening subtitle on Local, Discovery and Flow. Turn off to free up vertical space.',
          ),
          value: appearance.showHomeGreeting,
          onChanged: look.setShowHomeGreeting,
        ),
        LokalSettingRow.toggle(
          label: lokalText('Full resolution tags in lists'),
          description: lokalText(
            'Show known audio resolution details instead of quality tiers in song lists. Keep the existing quality colors.',
          ),
          value: appearance.resolutionTagsInLists,
          onChanged: look.setResolutionTagsInLists,
        ),
        LokalSettingRow(
          label: lokalText('Language'),
          description: lokalText(
            'The phone’s language, or one Lokal is translated into.',
          ),
          stacked: true,
          trailing: ValueListenableBuilder<Locale?>(
            valueListenable: LocaleController.instance,
            builder: (context, locale, _) => DropdownButtonFormField<String>(
              initialValue: locale == null ? 'system' : locale.languageCode,
              isExpanded: true,
              items: [
                DropdownMenuItem(
                  value: 'system',
                  child: Text(
                    lokalText('Phone'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: 'en',
                  child: Text(lokalText('English')),
                ),
                DropdownMenuItem(
                  value: 'fr',
                  child: Text(lokalText('Français')),
                ),
                DropdownMenuItem(
                  value: 'de',
                  child: Text(lokalText('Deutsch')),
                ),
                DropdownMenuItem(
                  value: 'es',
                  child: Text(lokalText('Español')),
                ),
                DropdownMenuItem(
                  value: 'it',
                  child: Text(lokalText('Italiano')),
                ),
                DropdownMenuItem(
                  value: 'pt',
                  child: Text(lokalText('Português (Brasil)')),
                ),
                DropdownMenuItem(
                  value: 'nl',
                  child: Text(lokalText('Nederlands')),
                ),
                DropdownMenuItem(value: 'pl', child: Text(lokalText('Polski'))),
                DropdownMenuItem(value: 'ru', child: Text('Русский')),
                DropdownMenuItem(
                  value: 'sv',
                  child: Text(lokalText('Svenska')),
                ),
                DropdownMenuItem(value: 'tr', child: Text('Türkçe')),
                DropdownMenuItem(value: 'zh', child: Text('简体中文')),
              ],
              onChanged: (code) =>
                  LocaleController.instance.select(switch (code) {
                    'system' || null => null,
                    'zh' => const Locale('zh', 'CN'),
                    'pt' => const Locale('pt', 'BR'),
                    _ => Locale(code!),
                  }),
            ),
          ),
        ),
        LokalSettingRow.toggle(
          label: lokalText('Haptics'),
          description: lokalText(
            'A light tap under your finger as you use Lokal.',
          ),
          value: prefs.hapticsEnabled,
          onChanged: (value) {
            notifier.setHapticsEnabled(value);
            AppHaptics.setEnabled(value);
          },
        ),
        if (Platform.isAndroid)
          LokalSettingRow(
            label: lokalText('Refresh rate'),
            description: lokalText(
              'Adaptive lets the phone decide. 120 Hz is smoothest and uses more battery.',
            ),
            stacked: true,
            trailing: LokalSegmented<String>(
              expand: true,
              segments: [
                LokalSegment('adaptive', lokalText('Adaptive')),
                LokalSegment('standard', lokalText('60 Hz')),
                LokalSegment('high', lokalText('120 Hz')),
              ],
              value: prefs.refreshRateMode,
              onChanged: notifier.setRefreshRateMode,
            ),
          ),
      ],
    ),
    if (Platform.isIOS)
      LokalSettingsSection(
        title: lokalText('Widgets'),
        children: [
          LokalSettingLink(
            label: lokalText('Home Screen & Lock Screen'),
            description: lokalText('Now Playing, Flow / Radio and Cover Flow.'),
            onTap: () => _push(context, const IosWidgetSettingsScreen()),
          ),
        ],
      ),
    if (Platform.isAndroid)
      LokalSettingsSection(
        title: lokalText('Home-screen widget'),
        children: [
          LokalSettingLink(
            label: lokalText('Home-screen widget'),
            description: lokalText(
              'What the widget on your home screen shows.',
            ),
            onTap: () => _push(context, const WidgetSettingsScreen()),
          ),
        ],
      ),
  ];
}
