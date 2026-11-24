import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:flick/l10n/l10n.dart';
import 'package:flick/providers/cast_provider.dart';
import 'package:flick/services/android_audio_device_service.dart';
import 'package:flick/services/casting/cast_device.dart';
import 'package:flick/services/casting/casting_service.dart';
import 'package:flick/services/casting/chromecast_backend.dart';
import 'package:flick/widgets/lokal/lokal_toast.dart';

/// The full-player output pill's single entry point for Cast, DLNA, and
/// local audio. Do not use Android's system media-output picker as the only
/// selector: it cannot enumerate app-specific Cast receiver routes.
class PlaybackOutputPicker extends ConsumerStatefulWidget {
  const PlaybackOutputPicker({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    enableDrag: false,
    showDragHandle: false,
    builder: (context) => const PlaybackOutputPicker(),
  );

  @override
  ConsumerState<PlaybackOutputPicker> createState() =>
      _PlaybackOutputPickerState();
}

class _PlaybackOutputPickerState extends ConsumerState<PlaybackOutputPicker> {
  bool _refreshing = false;
  bool _switching = false;
  String? _error;
  List<Map<String, dynamic>> _localRoutes = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (_refreshing || _switching) return;
    setState(() { _refreshing = true; _error = null; });
    // Local routes must never wait for network discovery (which can take
    // seconds on Wi-Fi or when an SSDP receiver is unreachable).
    final tasks = <Future<void>>[
      () async {
        try {
          await ref.read(castProvider.notifier).discover();
        } catch (error) {
          if (mounted) setState(() => _error = _message(error));
        }
      }(),
      if (Platform.isAndroid)
        () async {
          // Query the actual USAGE_MEDIA output independently of MediaRouter.
          unawaited(AndroidAudioDeviceService.instance.refreshMediaOutput());
          try {
            final routes = await ChromecastBackend().getOutputRoutes()
                .timeout(const Duration(seconds: 3));
            if (mounted) setState(() => _localRoutes = routes);
          } catch (_) {
            // Keep the already known output and Cast devices visible.
          }
        }(),
    ];
    await Future.wait(tasks);
    if (mounted) setState(() => _refreshing = false);
  }

  String _message(Object error) =>
      error is PlatformException ? error.message ?? error.code : error.toString();

  Future<void> _run(Future<void> Function() action) async {
    if (_switching) return;
    setState(() { _switching = true; _error = null; });
    try {
      final castWarning = ref.read(castServiceProvider).errorNotifier;
      // Never display a warning left over from a previous output change.
      castWarning.value = null;
      await action();
      if (mounted) {
        final warning = castWarning.value;
        if (warning != null && warning.isNotEmpty) {
          LokalToast.show(context, warning);
        }
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _returnToPhone() => _run(() async {
    if (Platform.isAndroid) {
      // The default local route is the speaker, not every output connected
      // to the handset. A Bluetooth route must not be treated as 'phone'.
      final selected = await CastingService.instance
          .selectLocalOutputRoute('__phone__');
      if (!selected) {
        throw StateError(lokalText('Could not switch to the phone speaker.'));
      }
      unawaited(AndroidAudioDeviceService.instance.refreshMediaOutput());
    } else if (ref.read(castProvider).isActive) {
      await ref.read(castProvider.notifier).disconnect();
    }
  });

  Future<void> _abandonReceiver() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(lokalText('Return to this device?')),
        content: Text(lokalText(
          'The receiver may still be playing. Lokal will detach from it and '
          'return to this phone paused to avoid playing on both devices.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(lokalText('Return to phone')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _run(() => ref.read(castProvider.notifier).disconnect(
      leaveReceiver: true,
      resumeLocal: false,
    ));
  }

  Future<void> _systemOutputs() => _run(() async {
    if (ref.read(castProvider).isActive) {
      await ref.read(castProvider.notifier).disconnect();
    }
    if (Platform.isAndroid) {
      final shown = await AndroidAudioDeviceService.instance.showOutputSwitcher();
      if (!shown) {
        throw StateError(lokalText(
          'Android could not open its audio outputs. Start local playback and try again.',
        ));
      }
    } else if (Platform.isIOS) {
      final shown = await const MethodChannel('lokal/ios')
          .invokeMethod<bool>('showRoutePicker');
      if (shown == false) {
        throw StateError(lokalText('The audio output picker could not open.'));
      }
    }
  });

  Future<void> _selectLocal(Map<String, dynamic> route) => _run(() async {
    final id = route['id'] as String?;
    if (id == null) return;
    final changed = await CastingService.instance.selectLocalOutputRoute(id);
    if (!changed) {
      throw StateError(lokalText('This audio output is no longer available.'));
    }
  });

  @override
  Widget build(BuildContext context) {
    final cast = ref.watch(castProvider);
    final active = cast.activeDevice;
    final busy = _switching || cast.isChangingOutput;
    final devices = <CastDevice>[
      if (active != null) active,
      ...cast.devices.where(
        (item) => active == null ||
            item.id != active.id || item.backend != active.backend,
      ),
    ];
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .76,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.outputDevice,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (_refreshing)
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: l10n.scanForDevices,
                      onPressed: busy ? null : _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ),
            ValueListenableBuilder<AndroidPlaybackDeviceInfo>(
              valueListenable: AndroidAudioDeviceService
                  .instance.mediaOutputInfoNotifier,
              builder: (context, media, _) {
                final knownMedia =
                    Platform.isAndroid && media.routeType != null;
                final phoneSelected = active == null &&
                    (Platform.isIOS ||
                        (knownMedia && media.isInternalRoute));
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      key: const ValueKey('output-picker-phone'),
                      leading: const Icon(Icons.smartphone_rounded),
                      title: Text(l10n.thisDevice),
                      subtitle: Text(lokalText('Play on this phone')),
                      selected: phoneSelected,
                      trailing: phoneSelected
                          ? const Icon(Icons.check_rounded)
                          : null,
                      enabled: !busy,
                      onTap: _returnToPhone,
                    ),
                    if (Platform.isIOS)
                      ListTile(
                        key: const ValueKey('output-picker-system'),
                        leading: const Icon(Icons.headphones_rounded),
                        title: Text(lokalText('AirPlay and headphones')),
                        subtitle: Text(
                          lokalText('Choose a local audio output'),
                        ),
                        enabled: !busy,
                        onTap: _systemOutputs,
                        trailing: const Icon(Icons.chevron_right_rounded),
                      ),
                    if (Platform.isAndroid)
                      for (final route in _localRoutes)
                        Builder(
                          builder: (context) {
                            final type = route['type'] as String? ?? '';
                            final selected = active == null &&
                                route['selected'] == true &&
                                (!knownMedia ||
                                    (media.isBluetoothRoute &&
                                        type == 'Bluetooth') ||
                                    (media.isUsbRoute && type == 'USB') ||
                                    (media.isWiredRoute && type == 'Wired') ||
                                    (media.isDockRoute && type == 'Dock') ||
                                    (media.isInternalRoute &&
                                        type == 'Speaker'));
                            return ListTile(
                              key: ValueKey(
                                'output-picker-local-${route['id']}',
                              ),
                              leading: Icon(type == 'Bluetooth'
                                  ? Icons.headphones_rounded
                                  : Icons.speaker_rounded),
                              title: Text(
                                route['name'] as String? ?? l10n.output,
                              ),
                              subtitle: Text(type),
                              selected: selected,
                              trailing: selected
                                  ? const Icon(Icons.check_rounded)
                                  : null,
                              enabled: !busy,
                              onTap: () => _selectLocal(route),
                            );
                          },
                        ),
                  ],
                );
              },
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Text(
                l10n.availableDevices,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  if (devices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                      child: Text(
                        _refreshing
                            ? l10n.searchingTheLocalNetwork
                            : l10n.noCastingDevicesFoundMakeSure,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  else
                    for (final device in devices)
                      ListTile(
                        key: ValueKey(
                          'output-picker-cast-${device.backend.name}-${device.id}',
                        ),
                        leading: Icon(
                          device.backend == CastBackend.chromecast
                              ? LucideIcons.cast
                              : LucideIcons.radio,
                        ),
                        title: Text(device.name),
                        subtitle: Text(
                          device.backend == CastBackend.chromecast
                              ? l10n.chromecast
                              : l10n.dlnaUpnp,
                        ),
                        selected: active?.id == device.id &&
                            active?.backend == device.backend,
                        trailing: active?.id == device.id &&
                                active?.backend == device.backend
                            ? const Icon(Icons.check_rounded)
                            : null,
                        enabled: !busy,
                        onTap: () => _run(
                          () => ref
                              .read(castProvider.notifier)
                              .connect(device),
                        ),
                      ),
                  if (active != null)
                    ListTile(
                      key: const ValueKey('output-picker-abandon'),
                      leading: const Icon(Icons.phonelink_off_rounded),
                      title: Text(
                        lokalText(
                          'Return to phone if receiver is unreachable',
                        ),
                      ),
                      subtitle: Text(
                        lokalText('Keep phone playback paused'),
                      ),
                      enabled: !busy,
                      onTap: _abandonReceiver,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
