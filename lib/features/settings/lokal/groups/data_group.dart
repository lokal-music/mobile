import 'package:flutter/foundation.dart';
import 'package:flick/features/settings/widgets/battery_optimization_setting.dart';
import 'package:flick/features/settings/widgets/eco_data_mode_toggle.dart';
import 'package:flick/features/settings/widgets/automatic_backup_settings_tile.dart';
import 'package:flick/features/settings/library_scan/library_scan_flow.dart';
import 'package:flick/providers/library_scan_preferences_provider.dart';
import 'package:flick/services/scan_session_controller.dart';

import 'package:flick/l10n/l10n.dart';

import '../lokal_settings_group.dart';

import 'package:flick/features/settings/widgets/discord_presence_settings_tile.dart';
import 'package:flick/features/settings/widgets/youtube_music_settings_tile.dart';
import 'package:flick/features/settings/widgets/spotify_account_settings_tile.dart';
import 'package:flick/features/settings/widgets/soulseek_account_settings_tile.dart';
import 'package:flick/features/settings/widgets/lastfm_settings_tile.dart';
import 'package:flick/features/settings/widgets/listenbrainz_settings_tile.dart';

import 'dart:async';
import 'dart:io';

import '../../../link/lokal_desktop_link_screen.dart';

import 'package:flutter/material.dart';
import 'package:flick/widgets/lokal/lokal_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/data/repositories/folder_repository.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/providers/library_scanner_provider.dart';
import 'package:flick/providers/songs_provider.dart';
import 'package:flick/services/alac_converter_service.dart';
import 'package:flick/services/album_art_service.dart';
import 'package:flick/services/fingerprint_cache_service.dart';
import 'package:flick/services/playback_cache_preferences_service.dart';
import 'package:flick/widgets/lokal/settings/lokal_settings_kit.dart';
import 'package:flick/widgets/common/ios_transfer_root.dart';

/// Bumped after a cache changes, so the sizes shown measure again.
final _cacheChanged = ValueNotifier<int>(0);

String _bytes(int bytes) {
  if (bytes <= 0) return '0 MB';
  const units = ['B', 'KB', 'MB', 'GB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(size >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
}

void _say(BuildContext context, String message) {
  if (context.mounted) LokalToast.show(context, message);
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool destructive = false,
}) async {
  return showLokalConfirmSheet(
    context: context,
    title: title,
    message: message,
    confirmLabel: action,
    destructive: destructive,
  );
}

Future<void> _clear(
  BuildContext context, {
  required String what,
  required Future<void> Function() clear,
}) async {
  final ok = await _confirm(
    context,
    title: lokalText("Clear {arg0}?", args: {'arg0': what}),
    message: lokalText('It fills up again as you listen.'),
    action: 'Clear',
  );
  if (!ok || !context.mounted) return;
  try {
    await clear();
    if (context.mounted) _say(context, 'Cleared.');
  } catch (error) {
    if (context.mounted) _say(context, 'Couldn’t clear it ($error).');
  } finally {
    _cacheChanged.value++;
  }
}

/// Data: accounts and connected devices, caches, and clearing the library.
List<LokalSettingsSection> dataSettings(
  BuildContext context,
  WidgetRef ref,
) => [
  LokalSettingsSection(
    title: LokalDataSections.accounts,
    children: [
      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)
        LokalSettingCustom(
          label: lokalText('Soulseek'),
          description: lokalText(
            defaultTargetPlatform == TargetPlatform.iOS
                ? 'Search, download and optionally share your main music folder while Lokal is open.'
                : 'Search, download and optionally share your main music folder.',
          ),
          child: const SoulseekAccountSettingsTile(),
        ),
      // Keep Spotify sign-in and likes sync together.
      LokalSettingCustom(
        label: lokalText('Spotify'),
        description: lokalText(
          'Connect Spotify for Discovery, Canvas artwork and liked-song syncing.',
        ),
        child: const SpotifyAccountSettingsTile(),
      ),
      LokalSettingCustom(
        label: lokalText('YouTube'),
        description: lokalText('Sign in to load your mixes, likes and history'),
        child: YoutubeMusicSettingsTile(),
      ),
      LokalSettingCustom(
        label: lokalText('Discord Rich Presence'),
        description: lokalText(
          'Show your music on Discord using the Discord app on your phone. Off by default; local cover files stay on your device.',
        ),
        child: const DiscordPresenceSettingsTile(),
      ),
      LokalSettingLink(
        label: lokalText('Desktop link'),
        description: lokalText(
          'Pair, merge libraries and copy music files over Wi-Fi.',
        ),
        onTap: () => unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const LokalDesktopLinkScreen(),
            ),
          ),
        ),
      ),
      LokalSettingCustom(
        label: lokalText('Last.fm'),
        description: lokalText('Scrobble what you play and power Discovery'),
        child: LastFmSettingsTile(),
      ),
      LokalSettingCustom(
        label: lokalText('ListenBrainz'),
        description: lokalText('Send your listens to ListenBrainz'),
        child: ListenBrainzSettingsTile(),
      ),
    ],
  ),
  LokalSettingsSection(
    title: lokalText('Mobile data'),
    children: const [EcoDataModeToggle()],
  ),
  if (Platform.isAndroid)
    LokalSettingsSection(
      title: lokalText('Background'),
      children: const [
        LokalSettingCustom(
          label: 'Battery optimization',
          description: 'Allow background playback, scans and file transfers.',
          child: BatteryOptimizationSetting(),
        ),
      ],
    ),
  LokalSettingsSection(
    title: lokalText('Library tools'),
    children: [
      LokalSettingRow.toggle(
        label: lokalText('Prepare audio after scanning'),
        description: lokalText(
          'Analyze new songs for waveforms, loudness and cover art. Optional; not required for playback.',
        ),
        value: ref.watch(libraryScanPreferencesProvider).preloadAudioData,
        onChanged: ref
            .read(libraryScanPreferencesProvider.notifier)
            .setPreloadAudioData,
      ),
      LokalSettingCustom(
        label: 'Prepare audio · ReplayGain scan',
        description: 'Analyze waveforms and loudness; write ReplayGain tags.',
        child: ValueListenableBuilder<ScanSessionStatus>(
          valueListenable: ScanSessionController.instance.status,
          builder: (context, status, _) {
            final busy = status == ScanSessionStatus.running;
            return Column(
              children: [
                LokalSettingRow(
                  icon: Icons.graphic_eq_rounded,
                  label: lokalText('Prepare audio'),
                  description: lokalText(
                    'Analyze audio for waveforms and loudness. Not required for playback.',
                  ),
                  trailing: LokalSettingButton(
                    label: 'Run',
                    onPressed: busy
                        ? null
                        : () => LibraryScanFlow.preloadAudio(context),
                  ),
                ),
                LokalSettingRow(
                  icon: Icons.speed_rounded,
                  label: lokalText('ReplayGain scan'),
                  description: lokalText(
                    'Measure loudness and write ReplayGain tags.',
                  ),
                  trailing: LokalSettingButton(
                    label: 'Run',
                    onPressed: busy
                        ? null
                        : () => LibraryScanFlow.scanReplayGain(context),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ],
  ),
  LokalSettingsSection(
    title: lokalText('Cache'),
    children: [
      LokalSettingRow(
        label: lokalText('Artwork cache'),
        description: lokalText(
          'Album covers kept on the phone so they open at once.',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CacheSize(AlbumArtService.instance.getCacheSize),
            const SizedBox(width: 10),
            LokalSettingButton(
              label: lokalText('Clear'),
              onPressed: () => _clear(
                context,
                what: 'the artwork cache',
                clear: AlbumArtService.instance.clearCache,
              ),
            ),
          ],
        ),
      ),
      LokalSettingRow(
        label: lokalText('Converted songs'),
        description: lokalText(
          'Playable copies of songs the phone can’t play as they are, like Apple Lossless.',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _CacheSize(AlacConverterService.getCacheSize),
            const SizedBox(width: 10),
            LokalSettingButton(
              label: lokalText('Clear'),
              onPressed: () => _clear(
                context,
                what: 'converted songs',
                clear: AlacConverterService.clearCache,
              ),
            ),
          ],
        ),
      ),
      const _CacheLimit(),
    ],
  ),
  LokalSettingsSection(
    title: lokalText('Backup'),
    children: const [
      LokalSettingCustom(
        label: 'Automatic backup',
        description: 'Daily or weekly settings, playlists and listening-history backups. Music files are not included.',
        child: AutomaticBackupSettingsTile(),
      ),
    ],
  ),
  LokalSettingsSection(
    title: lokalText('Danger zone'),
    children: [
      LokalSettingRow(
        label: lokalText('Clear library'),
        description: lokalText(
          'Remove every song from Lokal. Your music files aren’t touched; rescan to bring them back.',
        ),
        trailing: LokalSettingButton(
          label: lokalText('Clear'),
          destructive: true,
          onPressed: () async {
            final ok = await _confirm(
              context,
              title: lokalText('Clear your library?'),
              message: lokalText(
                'Every song is removed from Lokal. Files on your phone stay where they are.',
              ),
              action: 'Clear library',
              destructive: true,
            );
            if (!ok || !context.mounted) return;
            try {
              LibraryScanFlow.cancelActiveScan();
              await IosTransferRoot.withLibraryClearBarrier(context, () async {
                await SongRepository().deleteAllSongs();
                await FolderRepository().resetAllFolderScanStats();
                await FileFingerprintCache().clearAll();
              });
              ref.invalidate(songsProvider);
              ref.invalidate(songsByAlbumProvider);
              ref.invalidate(songsByArtistProvider);
              ref.invalidate(musicFoldersProvider);
              if (context.mounted) _say(context, 'Library cleared.');
            } catch (error) {
              if (context.mounted) {
                _say(context, 'Couldn’t clear the library ($error).');
              }
            }
          },
        ),
      ),
    ],
  ),
];

/// A cache's size in DM Mono, measured again after a clear.
class _CacheSize extends StatefulWidget {
  const _CacheSize(this.measure);

  final Future<int> Function() measure;

  @override
  State<_CacheSize> createState() => _CacheSizeState();
}

class _CacheSizeState extends State<_CacheSize> {
  int? _size;

  @override
  void initState() {
    super.initState();
    _cacheChanged.addListener(_measure);
    _measure();
  }

  @override
  void dispose() {
    _cacheChanged.removeListener(_measure);
    super.dispose();
  }

  void _measure() {
    unawaited(
      widget.measure().then(
        (bytes) {
          if (mounted) setState(() => _size = bytes);
        },
        onError: (Object _) {
          if (mounted) setState(() => _size = 0);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = _size;
    return Text(
      size == null || size < 0 ? '…' : _bytes(size),
      style: LokalTheme.label(context.lokal, size: 12),
    );
  }
}

/// How big the converted-songs cache may grow.
class _CacheLimit extends StatefulWidget implements LokalSearchable {
  const _CacheLimit();

  static const _label = 'Cache size limit';
  static const _description =
      'Past this size, the oldest converted songs are removed.';

  @override
  String get searchText => '$_label $_description';

  @override
  State<_CacheLimit> createState() => _CacheLimitState();
}

class _CacheLimitState extends State<_CacheLimit> {
  final _service = PlaybackCachePreferencesService();
  int? _cap;

  @override
  void initState() {
    super.initState();
    unawaited(
      _service.getMaxCacheBytes().then((cap) {
        if (mounted) setState(() => _cap = cap);
      }),
    );
  }

  Future<void> _set(int bytes) async {
    setState(() => _cap = bytes);
    await _service.setMaxCacheBytes(bytes);
    // A smaller limit removes the oldest copies straight away.
    await AlacConverterService.enforceCacheCap(bytes);
    _cacheChanged.value++;
  }

  @override
  Widget build(BuildContext context) {
    final options = [
      for (final (label, bytes) in kPlaybackCacheCapPresets)
        LokalSegment(bytes, label),
    ];
    final cap = _cap;
    return LokalSettingChoice<int>(
      label: _CacheLimit._label,
      description: _CacheLimit._description,
      options: [
        ...options,
        if (cap != null && !options.any((o) => o.value == cap))
          LokalSegment(cap, _bytes(cap)),
      ],
      value: cap ?? kPlaybackCacheDefaultMaxBytes,
      enabled: cap != null,
      onChanged: _set,
    );
  }
}
