import 'package:flick/core/utils/app_haptics.dart';
import 'package:flutter/material.dart';
import 'package:flick/widgets/lokal/lokal_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/widgets/lokal/lokal_glass.dart';
import 'package:flick/core/constants/app_constants.dart';
import 'package:flick/core/utils/audio_metadata_utils.dart';
import 'package:flick/core/utils/responsive.dart';
import 'package:flick/providers/providers.dart';
import 'package:flick/services/duplicate_cleaner_service.dart';
import 'package:flick/widgets/common/ios_transfer_root.dart';
import 'package:flick/l10n/l10n.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _formatFileSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '—';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return l10n.kb((bytes / 1024).toStringAsFixed(1));
  if (bytes < 1024 * 1024 * 1024) {
    return l10n.mb((bytes / (1024 * 1024)).toStringAsFixed(1));
  }
  return l10n.gb((bytes / (1024 * 1024 * 1024)).toStringAsFixed(2));
}

String _fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/');
  return parts.isNotEmpty ? parts.last : path;
}

String _folderName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/');
  if (parts.length >= 2) return parts[parts.length - 2];
  return '';
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final t = context.lokal;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: t.surface,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: destructive ? t.red : t.accent,
            foregroundColor: destructive ? Colors.white : t.onAccent,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class DuplicateCleanerScreen extends ConsumerStatefulWidget {
  const DuplicateCleanerScreen({super.key});

  @override
  ConsumerState<DuplicateCleanerScreen> createState() =>
      _DuplicateCleanerScreenState();
}

class _DuplicateCleanerScreenState
    extends ConsumerState<DuplicateCleanerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(duplicateScanProvider.notifier).scanForDuplicates();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(duplicateScanProvider);

    return Scaffold(
      backgroundColor: context.lokal.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              scanState: scanState,
              onBack: () => Navigator.of(context).pop(),
              onRefresh: () =>
                  ref.read(duplicateScanProvider.notifier).scanForDuplicates(),
            ),
            Expanded(child: _buildBody(context, scanState)),
            if (scanState.result != null &&
                scanState.result!.totalDuplicates > 0)
              _BottomActionBar(scanState: scanState),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, DuplicateScanState scanState) {
    if (scanState.isScanning) {
      return _buildScanningView(context);
    }
    if (scanState.error != null) {
      return _buildErrorView(context, scanState.error!);
    }
    if (scanState.result == null) {
      return _buildEmptyView(context);
    }
    if (scanState.result!.totalDuplicates == 0) {
      return _buildNoDuplicatesView(context);
    }
    return _buildDuplicatesView(context, scanState);
  }

  Widget _buildScanningView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.lokal.surface.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                border: Border.all(color: context.lokal.border),
              ),
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: context.lokal.text,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacingLg),
            Text(
              l10n.scanningForDuplicates,
              style: TextStyle(
                fontFamily: LokalTheme.sans,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: context.lokal.text,
              ),
            ),
            const SizedBox(height: AppConstants.spacingSm),
            Text(
              l10n.groupingByTitleArtistThisIs,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: LokalTheme.sans,
                fontSize: 13,
                height: 1.4,
                color: context.lokal.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(BuildContext context, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.lokal.red.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                border: Border.all(
                  color: context.lokal.red.withValues(alpha: .4),
                ),
              ),
              child: Icon(
                LucideIcons.triangleAlert,
                size: 32,
                color: context.lokal.red,
              ),
            ),
            const SizedBox(height: AppConstants.spacingLg),
            Text(
              l10n.somethingWentWrong,
              style: TextStyle(
                fontFamily: LokalTheme.sans,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: context.lokal.text,
              ),
            ),
            const SizedBox(height: AppConstants.spacingSm),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: LokalTheme.sans,
                fontSize: 13,
                height: 1.4,
                color: context.lokal.muted,
              ),
            ),
            const SizedBox(height: AppConstants.spacingLg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: context.lokal.accent,
                  foregroundColor: context.lokal.onAccent,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => ref
                    .read(duplicateScanProvider.notifier)
                    .scanForDuplicates(),
                child: Text(l10n.tryAgain),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView(BuildContext context) {
    return Center(
      child: Text(
        l10n.noScanResultsYet,
        style: TextStyle(
          fontFamily: LokalTheme.sans,
          fontSize: 15,
          color: context.lokal.muted,
        ),
      ),
    );
  }

  Widget _buildNoDuplicatesView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: context.lokal.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                border: Border.all(
                  color: context.lokal.accent.withValues(alpha: 0.28),
                ),
              ),
              child: Icon(
                LucideIcons.sparkles,
                size: 40,
                color: context.lokal.accent,
              ),
            ),
            const SizedBox(height: AppConstants.spacingLg),
            Text(
              l10n.allClearNoDuplicates,
              style: TextStyle(
                fontFamily: LokalTheme.sans,
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: context.lokal.text,
              ),
            ),
            const SizedBox(height: AppConstants.spacingSm),
            Text(
              l10n.yourLibraryIsTidyWeLl,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: LokalTheme.sans,
                fontSize: 13,
                height: 1.45,
                color: context.lokal.muted,
              ),
            ),
            const SizedBox(height: AppConstants.spacingLg),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: context.lokal.text,
                side: BorderSide(color: context.lokal.border2),
                shape: const StadiumBorder(),
              ),
              onPressed: () =>
                  ref.read(duplicateScanProvider.notifier).scanForDuplicates(),
              child: Text(l10n.scanAgain),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDuplicatesView(
    BuildContext context,
    DuplicateScanState scanState,
  ) {
    final result = scanState.result!;

    return Column(
      children: [
        _SummaryCard(scanState: scanState, result: result),
        const SizedBox(height: AppConstants.spacingSm),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingMd,
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.mousePointerClick,
                size: 14,
                color: context.lokal.muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.checkVersionsToKeepUncheckedWill,
                  style: TextStyle(
                    fontFamily: LokalTheme.sans,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.lokal.text,
                  ),
                ),
              ),
              if (scanState.hasCustomSelection)
                GestureDetector(
                  onTap: () {
                    AppHaptics.tap();
                    ref
                        .read(duplicateScanProvider.notifier)
                        .resetAllToRecommended();
                  },
                  child: Text(
                    l10n.reset,
                    style: TextStyle(
                      fontFamily: LokalTheme.sans,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.lokal.text,
                      decoration: TextDecoration.underline,
                      decorationColor: context.lokal.text,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacingSm),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingMd,
            ).copyWith(bottom: AppConstants.spacingMd),
            itemCount: result.duplicateGroups.length,
            itemBuilder: (context, index) {
              final group = result.duplicateGroups[index];
              return _DuplicateGroupCard(group: group);
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.scanState,
    required this.onBack,
    required this.onRefresh,
  });

  final DuplicateScanState scanState;
  final VoidCallback onBack;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final hasResult = scanState.result != null;
    final subtitle = scanState.isScanning
        ? l10n.scanningYourLibrary
        : hasResult
        ? (scanState.result!.totalDuplicates == 0
              ? l10n.noDuplicatesFound
              : l10n.groupsToRemove(
                  scanState.result!.totalGroups,
                  scanState.result!.totalDuplicates,
                ))
        : l10n.findAndCleanUpDuplicateSongs;

    final t = context.lokal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LokalGlassButton(
                semanticLabel: 'Back',
                size: 40,
                onPressed: onBack,
                child: Icon(Icons.chevron_left_rounded, color: t.text),
              ),
              const Spacer(),
              if (hasResult && !scanState.isScanning)
                LokalGlassButton(
                  semanticLabel: l10n.scanAgain,
                  size: 40,
                  onPressed: onRefresh,
                  child: Icon(Icons.refresh_rounded, color: t.text, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              l10n.duplicateCleaner,
              style: TextStyle(
                fontFamily: LokalTheme.sans,
                fontSize: 30,
                height: 1.1,
                letterSpacing: -1.2,
                fontWeight: FontWeight.w800,
                color: t.text,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 0, 0),
            child: Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: t.muted, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary card
// ---------------------------------------------------------------------------

class _SummaryCard extends ConsumerStatefulWidget {
  const _SummaryCard({required this.scanState, required this.result});

  final DuplicateScanState scanState;
  final DuplicateScanResult result;

  @override
  ConsumerState<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends ConsumerState<_SummaryCard> {
  // Keep the results list visible on first open; expand the explanation on demand.
  bool _collapsed = true;

  @override
  Widget build(BuildContext context) {
    final scanState = widget.scanState;
    final result = widget.result;
    final toRemove = scanState.selectedRemoveCount;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppConstants.spacingMd)
          .copyWith(top: AppConstants.spacingSm),
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: context.lokal.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: context.lokal.border2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.lokal.surface3,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(color: context.lokal.border2),
                ),
                child: Icon(
                  LucideIcons.copy,
                  size: 20,
                  color: context.lokal.text,
                ),
              ),
              const SizedBox(width: AppConstants.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.reviewBeforeYouClean,
                      style: TextStyle(
                        fontFamily: LokalTheme.sans,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: context.lokal.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _collapsed
                          ? l10n.groupsToRemove2(result.totalGroups, toRemove)
                          : lokalText(
                              'Duplicate files are deleted from storage while likes, playlists, and play counts are merged into the kept copy.',
                            ),
                      style: TextStyle(
                        fontFamily: LokalTheme.sans,
                        fontSize: 12,
                        height: 1.35,
                        color: context.lokal.muted.withValues(alpha: 0.92),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppConstants.spacingSm),
              GestureDetector(
                onTap: () {
                  AppHaptics.tap();
                  setState(() => _collapsed = !_collapsed);
                },
                child: AnimatedRotation(
                  turns: _collapsed ? 0.0 : 0.5,
                  duration: AppConstants.animationNormal,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: context.lokal.surface3,
                      shape: BoxShape.circle,
                      border: Border.all(color: context.lokal.border),
                    ),
                    child: Icon(
                      LucideIcons.chevronDown,
                      color: context.lokal.muted,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: AppConstants.animationNormal,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedOpacity(
              duration: AppConstants.animationNormal,
              opacity: _collapsed ? 0.0 : 1.0,
              child: _collapsed
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: AppConstants.spacingMd),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppConstants.spacingMd,
                            vertical: AppConstants.spacingSm,
                          ),
                          decoration: BoxDecoration(
                            color: context.lokal.surface3.withValues(
                              alpha: 0.9,
                            ),
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusMd,
                            ),
                            border: Border.all(color: context.lokal.border2),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _SummaryStat(
                                label: l10n.groups,
                                value: result.totalGroups.toString(),
                                icon: LucideIcons.layers,
                              ),
                              Container(
                                width: 1,
                                height: 36,
                                color: context.lokal.border,
                              ),
                              _SummaryStat(
                                label: l10n.toRemove,
                                value: toRemove.toString(),
                                icon: LucideIcons.trash2,
                                highlight: true,
                              ),
                              Container(
                                width: 1,
                                height: 36,
                                color: context.lokal.border,
                              ),
                              _SummaryStat(
                                label: l10n.willKeep,
                                value: scanState.selectedKeepCount.toString(),
                                icon: LucideIcons.shieldCheck,
                              ),
                            ],
                          ),
                        ),
                        if (scanState.hasCustomSelection) ...[
                          const SizedBox(height: AppConstants.spacingSm),
                          Row(
                            children: [
                              Icon(
                                LucideIcons.info,
                                size: 13,
                                color: context.lokal.muted,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  l10n.youCustomizedWhichVersionsToKeep,
                                  style: TextStyle(
                                    fontFamily: LokalTheme.sans,
                                    fontSize: 11.5,
                                    color: context.lokal.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.label,
    required this.value,
    required this.icon,
    this.highlight = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          icon,
          size: 18,
          color: highlight ? context.lokal.text : context.lokal.muted,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontFamily: LokalTheme.sans,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: context.lokal.text,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontFamily: LokalTheme.sans,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: context.lokal.muted,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom action bar
// ---------------------------------------------------------------------------

class _BottomActionBar extends ConsumerWidget {
  const _BottomActionBar({required this.scanState});

  final DuplicateScanState scanState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toRemove = scanState.selectedRemoveCount;
    final isRemoving = scanState.isRemoving;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppConstants.spacingMd,
        AppConstants.spacingMd,
        AppConstants.spacingMd,
        MediaQuery.paddingOf(context).bottom + AppConstants.spacingMd,
      ),
      decoration: BoxDecoration(
        color: context.lokal.surface.withValues(alpha: 0.86),
        border: Border(top: BorderSide(color: context.lokal.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(LucideIcons.info, size: 14, color: context.lokal.muted2),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isRemoving
                      ? l10n.removingDuplicates
                      : l10n.readyToRemoveSongKeepingIn(
                          toRemove,
                          scanState.selectedKeepCount,
                        ),
                  style: TextStyle(
                    fontFamily: LokalTheme.sans,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: context.lokal.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingSm),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isRemoving || toRemove == 0
                  ? null
                  : () => _confirmRemoveSelected(context, ref, toRemove),
              icon: isRemoving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(LucideIcons.trash2, size: 18),
              label: Text(
                isRemoving ? l10n.removing : l10n.removeDuplicates3(toRemove),
                style: const TextStyle(
                  fontFamily: LokalTheme.sans,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.lokal.red.withValues(alpha: 0.92),
                foregroundColor: Colors.white,
                disabledBackgroundColor: context.lokal.surface3.withValues(
                  alpha: 0.5,
                ),
                disabledForegroundColor: context.lokal.muted2,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingXs),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: isRemoving
                  ? null
                  : () => _confirmRemoveAll(context, ref, toRemove),
              style: TextButton.styleFrom(
                foregroundColor: context.lokal.muted,
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
              child: Text(
                l10n.orRemoveAllUsingRecommendedPicks,
                style: TextStyle(
                  fontFamily: LokalTheme.sans,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: context.lokal.muted,
                  decoration: TextDecoration.underline,
                  decorationColor: context.lokal.muted2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemoveSelected(
    BuildContext context,
    WidgetRef ref,
    int toRemove,
  ) async {
    final kept = ref.read(duplicateScanProvider).selectedKeepCount;
    final confirmed = await _confirm(
      context,
      title: l10n.removeDuplicates2(toRemove),
      message: lokalText(
        'We’ll keep your {kept} checked {keptLabel}, merge likes, playlists, and play counts into {keptTarget}, and delete the other {removed} duplicate {removedLabel} from device storage.',
        args: {
          'kept': kept,
          'keptLabel': kept == 1 ? 'version' : 'versions',
          'keptTarget': kept == 1 ? 'it' : 'them',
          'removed': toRemove,
          'removedLabel': toRemove == 1 ? 'file' : 'files',
        },
      ),
      confirmLabel: l10n.remove,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    DuplicateRemovalResult? result;
    try {
      result = await IosTransferRoot.withMutationBarrier(
        context,
        () => ref.read(duplicateScanProvider.notifier).removeSelected(),
      );
    } catch (_) {
      if (context.mounted) {
        LokalToast.show(
          context,
          'Could not remove duplicates. Check transfer recovery and retry.',
        );
      }
      return;
    }
    if (!context.mounted) return;
    if (result != null) {
      LokalToast.show(
        context,
        l10n.removedDuplicatesKept(result.removedCount, result.keptCount),
        duration: const Duration(seconds: 4),
        leading: Icon(LucideIcons.check, size: 18, color: context.lokal.accent),
      );
    }
  }

  Future<void> _confirmRemoveAll(
    BuildContext context,
    WidgetRef ref,
    int toRemove,
  ) async {
    final confirmed = await _confirm(
      context,
      title: l10n.removeAllWithBestPicks,
      message: lokalText(
        'We’ll keep the highest-quality copy in each group, merge likes, playlists, and play counts into it, and delete {removed} duplicate {removedLabel} from device storage.',
        args: {
          'removed': toRemove,
          'removedLabel': toRemove == 1 ? 'file' : 'files',
        },
      ),
      confirmLabel: l10n.removeAll,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await IosTransferRoot.withMutationBarrier(
        context,
        () => ref.read(duplicateScanProvider.notifier).removeAllDuplicates(),
      );
    } catch (_) {
      if (context.mounted) {
        LokalToast.show(
          context,
          'Could not remove duplicates. Check transfer recovery and retry.',
        );
      }
      return;
    }
    if (!context.mounted || ref.read(duplicateScanProvider).error != null) {
      return;
    }
    LokalToast.show(
      context,
      l10n.duplicatesRemovedUsingRecommendedPicks,
      duration: const Duration(seconds: 4),
      leading: Icon(LucideIcons.check, size: 18, color: context.lokal.accent),
    );
  }
}

// ---------------------------------------------------------------------------
// Group card — multi-keep selection (check any versions to keep)
// ---------------------------------------------------------------------------

class _DuplicateGroupCard extends ConsumerStatefulWidget {
  const _DuplicateGroupCard({required this.group});

  final DuplicateGroup group;

  @override
  ConsumerState<_DuplicateGroupCard> createState() =>
      _DuplicateGroupCardState();
}

class _DuplicateGroupCardState extends ConsumerState<_DuplicateGroupCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(duplicateScanProvider);
    final keepSet =
        scanState.keepSelection[widget.group.key] ??
        {widget.group.recommendedKeep.id};
    final keptCount = keepSet.length;
    final removeCount = widget.group.songs.length - keptCount;
    final isRemoving = scanState.isRemoving;

    // Sort so kept + recommended appear first for quicker scanning.
    final songs = List.of(widget.group.songs);
    songs.sort((a, b) {
      final aKept = keepSet.contains(a.id);
      final bKept = keepSet.contains(b.id);
      if (aKept && !bKept) return -1;
      if (!aKept && bKept) return 1;
      final aRec = a.id == widget.group.recommendedKeep.id;
      final bRec = b.id == widget.group.recommendedKeep.id;
      if (aRec && !bRec) return -1;
      if (!aRec && bRec) return 1;
      return 0;
    });

    final String keepingBadgeText;
    if (keptCount == 1) {
      final kept = widget.group.songs.firstWhere(
        (s) => keepSet.contains(s.id),
        orElse: () => widget.group.recommendedKeep,
      );
      final type = kept.fileType?.toUpperCase() ?? '—';
      final br =
          AudioMetadataUtils.formatBitrateLabel(
            kept.bitrate,
            sampleRate: kept.sampleRate,
            bitDepth: kept.bitDepth,
          ) ??
          l10n.unknownBitrate;
      keepingBadgeText = l10n.keeping(type, br);
    } else {
      keepingBadgeText = l10n.keepingOfToRemove(
        keptCount,
        widget.group.songs.length,
        removeCount,
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
      decoration: BoxDecoration(
        color: context.lokal.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: context.lokal.border2),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              onTap: isRemoving
                  ? null
                  : () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.spacingMd),
                child: Row(
                  children: [
                    Container(
                      width: context.scaleSize(AppConstants.containerSizeSm),
                      height: context.scaleSize(AppConstants.containerSizeSm),
                      decoration: BoxDecoration(
                        color: context.lokal.surface3,
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusSm,
                        ),
                        border: Border.all(color: context.lokal.border),
                      ),
                      child: Icon(
                        LucideIcons.copy,
                        color: context.lokal.muted,
                        size: context.responsiveIcon(AppConstants.iconSizeMd),
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.group.songs.first.title,
                            style: TextStyle(
                              fontFamily: LokalTheme.sans,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: context.lokal.text,
                              letterSpacing: -0.15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            l10n.copies(
                              widget.group.songs.first.artist,
                              widget.group.songs.length,
                            ),
                            style: TextStyle(
                              fontFamily: LokalTheme.sans,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.lokal.muted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: context.lokal.accent.withValues(
                                    alpha: 0.14,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppConstants.radiusRound,
                                  ),
                                  border: Border.all(
                                    color: context.lokal.accent.withValues(
                                      alpha: 0.28,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      LucideIcons.shieldCheck,
                                      size: 11,
                                      color: context.lokal.accent,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      keepingBadgeText,
                                      style: TextStyle(
                                        fontFamily: LokalTheme.sans,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: context.lokal.accent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingSm),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: AppConstants.animationNormal,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: context.lokal.surface3,
                          shape: BoxShape.circle,
                          border: Border.all(color: context.lokal.border),
                        ),
                        child: Icon(
                          LucideIcons.chevronDown,
                          color: context.lokal.muted,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: AppConstants.animationNormal,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedOpacity(
              duration: AppConstants.animationNormal,
              opacity: _expanded ? 1.0 : 0.0,
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.only(
                        left: AppConstants.spacingMd,
                        right: AppConstants.spacingMd,
                        bottom: AppConstants.spacingMd,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(height: 1, color: context.lokal.border),
                          const SizedBox(height: AppConstants.spacingSm),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              Text(
                                l10n.chooseWhichToKeep,
                                style: TextStyle(
                                  fontFamily: LokalTheme.sans,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: context.lokal.text,
                                ),
                              ),
                              if (keptCount != 1 ||
                                  !keepSet.contains(
                                    widget.group.recommendedKeep.id,
                                  ))
                                GestureDetector(
                                  onTap: isRemoving
                                      ? null
                                      : () {
                                          AppHaptics.tap();
                                          ref
                                              .read(
                                                duplicateScanProvider.notifier,
                                              )
                                              .resetKeepToRecommended(
                                                widget.group.key,
                                              );
                                        },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: context.lokal.surface3.withValues(
                                        alpha: 0.9,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        AppConstants.radiusRound,
                                      ),
                                      border: Border.all(
                                        color: context.lokal.border2,
                                      ),
                                    ),
                                    child: Text(
                                      l10n.recommendedOnly,
                                      style: TextStyle(
                                        fontFamily: LokalTheme.sans,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: context.lokal.muted,
                                      ),
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: isRemoving
                                    ? null
                                    : () {
                                        AppHaptics.tap();
                                        ref
                                            .read(
                                              duplicateScanProvider.notifier,
                                            )
                                            .setKeepSet(
                                              widget.group.key,
                                              widget.group.songs
                                                  .map((s) => s.id)
                                                  .toSet(),
                                            );
                                      },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: context.lokal.surface3.withValues(
                                      alpha: 0.9,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      AppConstants.radiusRound,
                                    ),
                                    border: Border.all(
                                      color: context.lokal.border2,
                                    ),
                                  ),
                                  child: Text(
                                    l10n.keepAll,
                                    style: TextStyle(
                                      fontFamily: LokalTheme.sans,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: context.lokal.muted,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppConstants.spacingXs),
                          Text(
                            l10n.checkTheVersionsYouWantTo,
                            style: TextStyle(
                              fontFamily: LokalTheme.sans,
                              fontSize: 11.5,
                              height: 1.35,
                              color: context.lokal.muted.withValues(alpha: 0.9),
                            ),
                          ),
                          if (keepSet.length > 1) ...[
                            const SizedBox(height: 6),
                            Text(
                              l10n.keptWillBeRemoved(keptCount, removeCount),
                              style: TextStyle(
                                fontFamily: LokalTheme.sans,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: context.lokal.accent,
                              ),
                            ),
                          ],
                          const SizedBox(height: AppConstants.spacingSm),
                          ...songs.map((song) {
                            final isKept = keepSet.contains(song.id);
                            final canToggleOff = keepSet.length > 1;
                            return _SongSelectRow(
                              song: song,
                              group: widget.group,
                              selected: isKept,
                              isRecommended:
                                  song.id == widget.group.recommendedKeep.id,
                              enabled: !isRemoving,
                              canToggleOff: canToggleOff,
                              onTap: () {
                                AppHaptics.selection();
                                final ok = ref
                                    .read(duplicateScanProvider.notifier)
                                    .toggleKeep(widget.group.key, song.id);
                                if (!ok && context.mounted) {
                                  LokalToast.show(
                                    context,
                                    l10n.atLeastOneVersionMustStay,
                                    duration: const Duration(seconds: 2),
                                    leading: Icon(
                                      LucideIcons.info,
                                      size: 16,
                                      color: context.lokal.orange,
                                    ),
                                  );
                                }
                              },
                            );
                          }),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SongSelectRow extends StatelessWidget {
  const _SongSelectRow({
    required this.song,
    required this.group,
    required this.selected,
    required this.isRecommended,
    required this.enabled,
    required this.onTap,
    this.canToggleOff = true,
  });

  final dynamic song;
  final DuplicateGroup group;
  final bool selected;
  final bool isRecommended;
  final bool enabled;
  final bool canToggleOff;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bitrateLabel =
        AudioMetadataUtils.formatBitrateLabel(
          song.bitrate,
          sampleRate: song.sampleRate,
          bitDepth: song.bitDepth,
        ) ??
        l10n.unknownBitrate;
    final typeLabel = (song.fileType as String?)?.toUpperCase() ?? l10n.unknown;
    final sizeLabel = _formatFileSize(song.fileSize as int?);
    final file = _fileName(song.filePath as String);
    final folder = _folderName(song.filePath as String);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacingXs),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          child: Ink(
            padding: const EdgeInsets.all(AppConstants.spacingSm),
            decoration: BoxDecoration(
              color: selected
                  ? Color.alphaBlend(
                      context.lokal.accent.withValues(alpha: .18),
                      context.lokal.surface2,
                    )
                  : context.lokal.surface2.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(
                color: selected
                    ? context.lokal.accent.withValues(alpha: 0.45)
                    : context.lokal.border2.withValues(alpha: 0.9),
                width: selected ? 1.3 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Checkbox
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: selected ? context.lokal.accent : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? context.lokal.accent
                          : context.lokal.muted.withValues(alpha: 0.65),
                      width: 1.4,
                    ),
                  ),
                  child: selected
                      ? const Icon(
                          LucideIcons.check,
                          size: 13,
                          color: Colors.white,
                        )
                      : null,
                ),
                const SizedBox(width: AppConstants.spacingSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? context.lokal.accent.withValues(alpha: 0.22)
                                  : context.lokal.surface3.withValues(
                                      alpha: 0.95,
                                    ),
                              borderRadius: BorderRadius.circular(
                                AppConstants.radiusXs,
                              ),
                              border: Border.all(
                                color: selected
                                    ? context.lokal.accent.withValues(
                                        alpha: 0.38,
                                      )
                                    : context.lokal.border2,
                              ),
                            ),
                            child: Text(
                              typeLabel,
                              style: TextStyle(
                                fontFamily: LokalTheme.sans,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                                color: selected
                                    ? context.lokal.accent
                                    : context.lokal.text,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$bitrateLabel • $sizeLabel',
                            style: TextStyle(
                              fontFamily: LokalTheme.sans,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? context.lokal.accent
                                  : context.lokal.text,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (isRecommended) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: context.lokal.orange.withValues(
                                  alpha: 0.14,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppConstants.radiusRound,
                                ),
                                border: Border.all(
                                  color: context.lokal.orange.withValues(
                                    alpha: 0.32,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    LucideIcons.star,
                                    size: 10,
                                    color: context.lokal.orange,
                                  ),
                                  SizedBox(width: 3),
                                  Text(
                                    l10n.recommended,
                                    style: TextStyle(
                                      fontFamily: LokalTheme.sans,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: context.lokal.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        selected ? l10n.keepingThisVersion : l10n.willBeRemoved,
                        style: TextStyle(
                          fontFamily: LokalTheme.sans,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? context.lokal.accent
                              : context.lokal.muted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        file,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: LokalTheme.sans,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: context.lokal.text,
                        ),
                      ),
                      if (folder.isNotEmpty)
                        Text(
                          l10n.inLabel(folder),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: LokalTheme.sans,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: context.lokal.muted.withValues(alpha: 0.95),
                          ),
                        ),
                      if ((song.albumArtPath as String?) != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.image,
                                size: 11,
                                color: context.lokal.muted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                l10n.hasArtwork,
                                style: TextStyle(
                                  fontFamily: LokalTheme.sans,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                  color: context.lokal.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
