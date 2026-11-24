import 'dart:async';
import 'dart:io';

import 'package:flick/widgets/lokal/lokal_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/music_folder_service.dart';
import '../../services/link/desktop_music_storage.dart';

import '../../core/theme/lokal_tokens.dart';
import '../../l10n/l10n.dart';
import '../../models/lokal_remote_state.dart';
import '../../providers/lokal_remote_provider.dart';
import '../../providers/ios_transfer_provider.dart';
import '../../services/link/lokal_link_service.dart';
import '../../services/lokal_remote_service.dart';
import '../../widgets/lokal/settings/lokal_settings_kit.dart';
import '../../widgets/common/ios_transfer_root.dart';
import '../settings/screens/lokal_remote_settings_screen.dart';
import 'ios_transfer_queue_screen.dart';

class LokalDesktopLinkScreen extends ConsumerStatefulWidget {
  const LokalDesktopLinkScreen({super.key});
  @override
  ConsumerState<LokalDesktopLinkScreen> createState() =>
      _LokalDesktopLinkScreenState();
}

class _LokalDesktopLinkScreenState
    extends ConsumerState<LokalDesktopLinkScreen> {
  final _address = TextEditingController(), _code = TextEditingController();
  List<LokalDiscoveredDesktop> _desktops = [];
  List<LokalPairedDesktop> _pairedDesktops = [];
  bool _busy = false,
      _discovering = false,
      _theme = false,
      _sendDownloads = false;
  String? _error;
  int? _preparingTotal;
  int _queuedFiles = 0;
  String? _copyFolderUri;
  List<MusicFolder> _copyFolders = const [];
  @override
  void initState() {
    super.initState();
    unawaited(_loadOptions());
  }

  Future<void> _loadOptions() async {
    final prefs = await SharedPreferences.getInstance();
    final activeCredentials =
        await ref.read(lokalRemoteCredentialsStoreProvider).read();
    final id = activeCredentials?.desktopId;
    final paired = await ref.read(lokalRemoteControllerProvider.notifier)
        .pairedDesktops();
    final folders = await MusicFolderService().getSavedFolders();
    if (mounted)
      setState(() {
        _copyFolders = folders;
        _pairedDesktops = paired;
        _copyFolderUri = prefs.getString(DesktopMusicStorage.destinationKey);
        _theme = prefs.getBool('lokal.link.$id.theme') ?? false;
        _sendDownloads =
            prefs.getBool('lokal.link.$id.send_downloads') ?? false;
      });
  }

  @override
  void dispose() {
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error is LokalRemoteException
              ? error.message
              : error is StateError
              ? error.message.toString()
              : l10n.linkActionFailed,
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discover() async {
    setState(() => _discovering = true);
    try {
      final desktops = await ref
          .read(lokalRemoteControllerProvider.notifier)
          .discoverDesktops();
      if (mounted) setState(() => _desktops = desktops);
    } catch (_) {
      if (mounted) setState(() => _error = l10n.linkNoDesktopFound);
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
  }

  Future<void> _merge() => _run(() async {
    await ref.read(lokalRemoteControllerProvider.notifier).approveMerge();
    if (mounted) {
      LokalToast.show(context, lokalText('Libraries are up to date.'));
    }
  });

  Future<void> _syncNow() => _run(() async {
    await ref.read(lokalRemoteControllerProvider.notifier).syncNow();
    if (mounted) {
      LokalToast.show(context, lokalText('Libraries are up to date.'));
    }
  });

  Future<void> _copyFiles() => _run(() async {
    final controller = ref.read(lokalRemoteControllerProvider.notifier);
    try {
      final plan = await controller.prepareFileCopy();
      if (!mounted) return;
      final adapter = Platform.isIOS
          ? ref.read(iosTransferCopyAdapterProvider)
          : null;
      final credentials = adapter == null
          ? null
          : await ref.read(lokalRemoteCredentialsStoreProvider).read();
      final nativePlan = adapter == null || credentials == null
          ? null
          : await adapter.prepare(plan, credentials);
      if (!mounted) return;
      final confirmed = await showLokalConfirmSheet(
        context: context,
        title: lokalText('Copy missing songs both ways?'),
        message: nativePlan != null
            ? lokalText(
                '{count} song files will be prepared and queued. Keep Lokal open until preparation finishes, and keep the desktop awake on Wi-Fi. Originals stay on their source device. Follow progress and recovery in File transfers.',
                args: {'count': nativePlan.total},
              )
            : lokalText(
                '{send} songs to your PC, {receive} new songs to this phone, and {recover} existing private copies to your selected music folder under Lokal Desktop. Recovery uses files already on your phone; no re-download. Existing files are kept. Keep both apps open on Wi-Fi; check again to retry unfinished copies.',
                args: {
                  'send': plan.toDesktop.length,
                  'receive': plan.toPhone.length,
                  'recover': plan.toMusicFolder.length,
                },
              ),
        confirmLabel: lokalText('Copy files'),
      );
      if (!confirmed || !mounted) return;
      if (nativePlan != null) {
        setState(() {
          _preparingTotal = nativePlan.total;
          _queuedFiles = 0;
        });
        try {
          await nativePlan.submit(
            onProgress: (queued, _) {
              if (mounted) setState(() => _queuedFiles = queued);
            },
          );
        } catch (_) {
          if (mounted) {
            LokalToast.show(
              context,
              lokalText(
                'Some files could not be queued. Review File transfers before trying again. Submitted transfers are kept.',
              ),
            );
          }
        }
        if (mounted) {
          setState(() => _preparingTotal = null);
          final session = ref.read(iosTransferSessionProvider);
          if (session != null) await showIosTransferQueue(context, session);
        }
      } else {
        await controller.copyMissingFiles(plan);
      }
    } finally {
      if (mounted && _preparingTotal != null)
        setState(() => _preparingTotal = null);
      controller.cancelFileCopyPlan();
    }
  });

  Widget _fileCopyStatus(LokalRemoteControllerState link) {
    final progress = link.fileCopyProgress;
    final t = context.lokal;
    if (_preparingTotal case final total?) {
      return LokalSettingsBlock(
        child: LokalSettingsCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lokalText('Preparing file transfers'),
                style: TextStyle(color: t.text, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                lokalText(
                  '{queued} of {total} files queued. Keep Lokal open until preparation finishes.',
                  args: {'queued': _queuedFiles, 'total': total},
                ),
                style: TextStyle(color: t.muted),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: total > 0 ? _queuedFiles / total : null,
              ),
            ],
          ),
        ),
      );
    }

    final title = switch (progress.phase) {
      LinkCopyPhase.idle => lokalText('Keep song files on both devices'),
      LinkCopyPhase.checking => lokalText('Checking for missing song files…'),
      LinkCopyPhase.copying => lokalText('Copying missing song files…'),
      LinkCopyPhase.complete =>
        progress.failures.isEmpty
            ? lokalText('Song files are up to date')
            : lokalText('Some song files could not be copied'),
      LinkCopyPhase.paused => lokalText('File copying paused'),
    };
    return LokalSettingsBlock(
      child: LokalSettingsCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(color: t.text, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (progress.busy) ...[
              LinearProgressIndicator(
                value: progress.total > 0
                    ? progress.processed / progress.total
                    : null,
              ),
              const SizedBox(height: 8),
              if (progress.currentTitle case final name?)
                Text(
                  progress.phase == LinkCopyPhase.checking
                      ? name
                      : lokalText(
                          progress.toDesktop
                              ? 'Sending to PC: {song}'
                              : 'Saving on phone: {song}',
                          args: {'song': name},
                        ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
            if (progress.phase == LinkCopyPhase.copying ||
                progress.phase == LinkCopyPhase.complete ||
                progress.phase == LinkCopyPhase.paused)
              Text(
                lokalText(
                  '{send} sent · {receive} saved · {failed} failed',
                  args: {
                    'send': progress.sent,
                    'receive': progress.received,
                    'failed': progress.failures.length,
                  },
                ),
                style: TextStyle(color: t.muted),
              ),
            for (final title in progress.failures.take(5))
              Text(title, style: TextStyle(color: t.muted)),
            Text(
              lokalText(
                'Saves original song files under Lokal Desktop in your selected music folder. Existing private copies can be recovered here too. Nothing is deleted or replaced. Check again to retry unfinished files.',
              ),
              style: TextStyle(color: t.muted),
            ),
            if (Platform.isIOS) ...[
              const SizedBox(height: 8),
              Text(
                lokalText(
                  'Keep Lokal open and your iPhone unlocked, with your desktop awake, while copying over Wi-Fi. If copying stops, check again to retry unfinished files.',
                ),
                style: TextStyle(color: t.muted),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(_copyFolderUri),
              initialValue: _copyFolderUri ?? '',
              decoration: InputDecoration(
                labelText: lokalText('Save PC files to'),
                helperText:
                    _copyFolderUri != null &&
                        !_copyFolders.any((f) => f.uri == _copyFolderUri)
                    ? lokalText(
                        'Selected folder is no longer available. Choose another.',
                      )
                    : lokalText('Choose a folder in Library settings first.'),
              ),
              isExpanded: true,
              items: [
                DropdownMenuItem<String>(
                  value: '',
                  child: Text(lokalText('First available music folder')),
                ),
                if (_copyFolderUri != null &&
                    !_copyFolders.any((f) => f.uri == _copyFolderUri))
                  DropdownMenuItem<String>(
                    value: _copyFolderUri!,
                    child: Text(
                      lokalText(
                        'Previously selected folder unavailable — choose another',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                for (final folder in _copyFolders)
                  DropdownMenuItem<String>(
                    value: folder.uri,
                    child: Text(
                      folder.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: progress.busy
                  ? null
                  : (uri) async {
                      final prefs = await SharedPreferences.getInstance();
                      if (uri == null || uri.isEmpty) {
                        await prefs.remove(DesktopMusicStorage.destinationKey);
                      } else {
                        await prefs.setString(
                          DesktopMusicStorage.destinationKey,
                          uri,
                        );
                      }
                      if (mounted)
                        setState(
                          () => _copyFolderUri = uri?.isEmpty == true
                              ? null
                              : uri,
                        );
                    },
            ),
            const SizedBox(height: 12),
            if (progress.phase == LinkCopyPhase.checking)
              TextButton.icon(
                onPressed: () => ref
                    .read(lokalRemoteControllerProvider.notifier)
                    .cancelFileCopyPlan(),
                icon: const Icon(Icons.close_rounded),
                label: Text(lokalText('Cancel check')),
              ),
            FilledButton.tonal(
              onPressed:
                  _busy ||
                      progress.busy ||
                      link.syncProgress.busy ||
                      !link.socketConnected
                  ? null
                  : _copyFiles,
              child: Text(lokalText('Copy missing song files')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mergeStatus(LokalRemoteControllerState link) {
    final progress = link.syncProgress;
    final t = context.lokal;
    final title = !link.socketConnected
        ? lokalText('Waiting for your desktop')
        : switch (progress.phase) {
            LinkSyncPhase.idle => lokalText('Library merge enabled'),
            LinkSyncPhase.preparing => lokalText('Preparing your libraries…'),
            LinkSyncPhase.catalog => lokalText('Adding desktop songs…'),
            LinkSyncPhase.history => lokalText('Syncing listening history…'),
            LinkSyncPhase.library => lokalText(
              'Syncing likes, playlists and metadata…',
            ),
            LinkSyncPhase.metadata => lokalText(
              'Checking copied audio details…',
            ),
            LinkSyncPhase.lyrics => lokalText('Syncing saved lyrics…'),
            LinkSyncPhase.finalizing => lokalText('Updating your profile…'),
            LinkSyncPhase.complete => lokalText('Libraries are up to date'),
            LinkSyncPhase.paused => lokalText('Library sync paused'),
          };
    final completed = progress.completedAt;
    return LokalSettingsBlock(
      child: LokalSettingsCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(color: t.text, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (progress.busy && link.socketConnected) ...[
              LinearProgressIndicator(value: progress.fraction),
              const SizedBox(height: 8),
              if (progress.total case final total?)
                Text(
                  lokalText(
                    '{done} of {total} songs',
                    args: {'done': progress.processed, 'total': total},
                  ),
                  style: TextStyle(color: t.muted),
                )
              else if (progress.processed > 0)
                Text(
                  lokalText(
                    '{count} entries processed',
                    args: {'count': progress.processed},
                  ),
                  style: TextStyle(color: t.muted),
                ),
            ],
            if (progress.catalogSongs case final count?)
              Text(
                lokalText(
                  'Desktop library: {count} songs',
                  args: {'count': count},
                ),
                style: TextStyle(color: t.muted),
              ),
            if (completed != null)
              Text(
                lokalText(
                  'Last completed: {time}',
                  args: {
                    'time':
                        '${MaterialLocalizations.of(context).formatShortDate(completed.toLocal())} ${TimeOfDay.fromDateTime(completed.toLocal()).format(context)}',
                  },
                ),
                style: TextStyle(color: t.muted),
              ),
            const SizedBox(height: 8),
            Text(
              lokalText(
                'Listening history, minutes and play counts sync automatically in small batches while your desktop is linked. Full desktop-library, metadata, likes and playlist sync is manual: tap Sync now. No full library scan runs on startup or reconnection. Optional phone-download transfers stay queued until Sync now.',
              ),
              style: TextStyle(color: t.muted),
            ),
            if (progress.phase == LinkSyncPhase.paused ||
                !link.socketConnected) ...[
              const SizedBox(height: 8),
              Text(
                lokalText(
                  'Keep both devices connected. Completed work is saved; reconnect or retry to continue.',
                ),
                style: TextStyle(color: t.muted),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed:
                  _busy ||
                      progress.busy ||
                      link.fileCopyProgress.busy ||
                      !link.socketConnected
                  ? null
                  : _syncNow,
              child: Text(l10n.syncNow),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pair({LokalPairingLink? qr}) => _run(() async {
    final address = _address.text.trim();
    final origin =
        qr?.origin.toString() ??
        (address.contains('://') ? address : 'http://$address');
    final expected = await ref.read(lokalRemoteCredentialsStoreProvider).read();
    if (!mounted) return;
    await IosTransferRoot.withPairingRetirement(
      context,
      expected: expected,
      mutation: () => ref
          .read(lokalRemoteControllerProvider.notifier)
          .pairDesktop(
            origin: origin,
            code: qr?.code ?? _code.text,
            expectedDesktopId: qr?.desktopId,
            syncTheme: _theme,
          ),
    );
    _code.clear();
    await _saveOption('send_downloads', _sendDownloads);
    final paired = await ref.read(lokalRemoteControllerProvider.notifier)
        .pairedDesktops();
    if (mounted) setState(() => _pairedDesktops = paired);
  });
  Future<void> _scan() async {
    final value = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const _PairingScanner()));
    if (value == null || !mounted) return;
    try {
      final qr = LokalPairingLink.parse(value);
      _address.text = qr.origin.toString();
      await _pair(qr: qr);
    } on FormatException {
      if (mounted) setState(() => _error = l10n.linkInvalidQr);
    }
  }

  Future<void> _saveOption(String key, bool value) async {
    final credentials = await ref
        .read(lokalRemoteCredentialsStoreProvider)
        .read();
    if (credentials?.desktopId == null) return;
    await (await SharedPreferences.getInstance()).setBool(
      'lokal.link.${credentials!.desktopId}.$key',
      value,
    );
  }

  @override
  Widget build(BuildContext context) {
    final link = ref.watch(lokalRemoteControllerProvider),
        controller = ref.read(lokalRemoteControllerProvider.notifier),
        t = context.lokal;
    return LokalSettingsScaffold(
      title: l10n.linkDesktop,
      subtitle: l10n.linkPairingHint,
      children: [
        if (_error != null)
          LokalSettingsBlock(
            child: Text(_error!, style: TextStyle(color: t.accent)),
          ),
        if (link.error != null)
          LokalSettingsBlock(
            child: Text(link.error!, style: TextStyle(color: t.muted)),
          ),
        if (link.transferMessage != null)
          LokalSettingsBlock(
            child: Text(
              link.transferMessage!,
              style: TextStyle(
                color: link.transferHasError ? t.accent : t.muted,
              ),
            ),
          ),
        if (_pairedDesktops.length > 1)
          LokalSettingsBlock(
            child: LokalSettingsCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      lokalText('Paired desktops'),
                      style: TextStyle(
                        color: t.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final desktop in _pairedDesktops)
                    Builder(builder: (context) {
                      final active = link.config?.origin ==
                          desktop.credentials.origin;
                      return ListTile(
                        leading: Icon(
                          Icons.desktop_windows_rounded,
                          color: active ? t.accent : t.muted,
                        ),
                        title: Text(desktop.name),
                        subtitle: Text(desktop.credentials.origin.authority),
                        trailing: active
                            ? Text(lokalText('Active'))
                            : const Icon(Icons.swap_horiz_rounded),
                        onTap: active || _busy
                            ? null
                            : () => _run(() async {
                                await controller.switchDesktop(desktop.id);
                                final paired = await controller.pairedDesktops();
                                if (mounted) setState(() => _pairedDesktops = paired);
                                await _loadOptions();
                              }),
                      );
                    }),
                ],
              ),
            ),
          ),
        if (link.configured) ...[
          LokalSettingsBlock(
            child: LokalSettingsCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.desktop_windows_rounded, color: t.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              link.desktopName,
                              style: TextStyle(
                                color: t.text,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              link.reachable
                                  ? l10n.linkConnected
                                  : l10n.linkOffline,
                              style: TextStyle(color: t.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Keep connection management in one row on small phones.
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            minimumSize: const Size(0, 44),
                          ),
                          onPressed: _busy
                              ? null
                              : () => _run(controller.connect),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(l10n.linkReconnect, maxLines: 1),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            minimumSize: const Size(0, 44),
                          ),
                          onPressed: _busy ? null : controller.disconnect,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(l10n.linkDisconnect, maxLines: 1),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                final confirmed = await showLokalConfirmSheet(
                                  context: context,
                                  title: l10n.linkForget,
                                  message: l10n.linkForgetDescription,
                                  confirmLabel: l10n.linkForget,
                                  destructive: true,
                                );
                                if (confirmed && mounted) {
                                  final expected = await ref
                                      .read(lokalRemoteCredentialsStoreProvider)
                                      .read();
                                  if (!mounted) return;
                                  await IosTransferRoot.withPairingRetirement(
                                    context,
                                    expected: expected,
                                    mutation: () =>
                                        controller.forgetConfiguration(
                                          expected: expected,
                                        ),
                                  );
                                  final paired = await controller.pairedDesktops();
                                  if (mounted) setState(() => _pairedDesktops = paired);
                                }
                              }),
                        child: Text(l10n.linkForget),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _scan,
                      icon: const Icon(Icons.add_link_rounded),
                      label: Text(lokalText('Pair another desktop')),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (link.mergeApproved ||
              link.syncProgress.phase != LinkSyncPhase.idle)
            _mergeStatus(link),
          if (link.mergeApproved) _fileCopyStatus(link),
          if (Platform.isIOS) const IosTransferQueueEntry(),
          if (link.socketConnected && !link.mergeApproved)
            LokalSettingsBlock(
              child: LokalSettingsCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.linkMergeLibraries,
                      style: TextStyle(
                        color: t.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.linkMergePreview,
                      style: TextStyle(color: t.muted),
                    ),
                    if (link.syncPreview?['history'] case final int count)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          l10n.linkHistoryCount(count),
                          style: TextStyle(color: t.muted),
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy ? null : _merge,
                      child: Text(l10n.linkMerge),
                    ),
                  ],
                ),
              ),
            ),
          if (link.socketConnected)
            LokalSettingsBlock(
              child: LokalSettingsCard(
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      title: Text(l10n.linkMatchTheme),
                      value: _theme,
                      onChanged: (value) {
                        setState(() => _theme = value);
                        unawaited(_saveOption('theme', value));
                      },
                    ),
                    SwitchListTile.adaptive(
                      title: Text(l10n.linkSendDownloads),
                      subtitle: Text(l10n.linkSendDownloadsDescription),
                      value: _sendDownloads,
                      onChanged: (value) {
                        setState(() => _sendDownloads = value);
                        unawaited(_saveOption('send_downloads', value));
                      },
                    ),
                  ],
                ),
              ),
            ),
        ] else ...[
          LokalSettingsBlock(
            child: LokalSettingsCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _scan,
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: Text(l10n.linkScanQr),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _discovering ? null : _discover,
                    icon: const Icon(Icons.wifi_find_rounded),
                    label: Text(
                      _discovering
                          ? l10n.linkSearching
                          : l10n.linkSearchDesktops,
                    ),
                  ),
                  for (final desktop in _desktops)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.desktop_windows_rounded),
                      title: Text(desktop.name),
                      subtitle: Text(desktop.origin.toString()),
                      onTap: () {
                        _address.text = desktop.origin.toString();
                      },
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _address,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: l10n.linkDesktopAddress,
                      hintText: '192.168.1.20:3421',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: InputDecoration(
                      labelText: l10n.linkPairingCode,
                    ),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.linkMatchTheme),
                    value: _theme,
                    onChanged: (value) => setState(() => _theme = value),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : () => _pair(),
                    child: Text(_busy ? l10n.linkConnecting : l10n.linkPair),
                  ),
                ],
              ),
            ),
          ),
        ],
        LokalSettingsBlock(
          child: TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => const LokalRemoteSettingsScreen(),
              ),
            ),
            child: Text(l10n.linkLegacyRemote),
          ),
        ),
      ],
    );
  }
}

class _PairingScanner extends StatefulWidget {
  const _PairingScanner();
  @override
  State<_PairingScanner> createState() => _PairingScannerState();
}

class _PairingScannerState extends State<_PairingScanner> {
  bool _done = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(l10n.linkScanQr)),
    body: MobileScanner(
      onDetect: (capture) {
        if (_done) return;
        for (final barcode in capture.barcodes) {
          final raw = barcode.rawValue;
          if (raw != null && raw.startsWith('lokal://pair?')) {
            _done = true;
            Navigator.of(context).pop(raw);
            break;
          }
        }
      },
      errorBuilder: (_, error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.linkCameraUnavailable, textAlign: TextAlign.center),
        ),
      ),
    ),
  );
}
