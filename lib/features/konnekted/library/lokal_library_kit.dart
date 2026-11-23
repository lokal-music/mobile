import 'package:flick/core/utils/lokal_layout.dart';
import 'package:flick/widgets/lokal/lokal_quality.dart';
import 'package:flick/widgets/lokal/lokal_page_geometry.dart';

import '../../link/lokal_ghost_availability.dart';

import 'package:flick/services/link/library_song_identity.dart';

import 'dart:async';

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/navigation/lokal_page_motion.dart';
import 'package:flick/core/theme/lokal_interaction.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/features/konnekted/konnekted_home.dart';
import 'package:flick/features/songs/widgets/song_actions_bottom_sheet.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flick/services/player_service.dart' show PlayerService;
import 'package:flick/widgets/lokal/lokal_glass.dart';
import 'package:flick/widgets/lokal/lokal_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flick/widgets/lokal/lokal_swipe_to_queue.dart';

import 'replayable_stream_songs.dart';
import 'playlist_hero_header.dart';

/// Shared pieces of Lokal's Library screens: Apple Music's iOS layout on the
/// theme's own solid background, glass only for the small round buttons.

/// Prefer an on-device recording; if there are none, use a cached or
/// reachable desktop recording. A missing desktop must never block Play All
/// when all remaining audio is already cached from that desktop.
@visibleForTesting
Future<Song?> firstAvailableLibraryFallback(
  List<Song> queue,
  Future<bool> Function(Song song) desktopAvailable, {
  bool Function()? stillCurrent,
}) async {
  for (final song in queue) {
    if (stillCurrent?.call() == false) return null;
    if (!song.isNetworkSource &&
        !song.isPending &&
        song.filePath?.isNotEmpty == true) {
      return song;
    }
  }
  for (final song in queue) {
    if (stillCurrent?.call() == false) return null;
    if (song.sourceType == 'lokal') {
      final available = await desktopAvailable(song);
      if (stillCurrent?.call() == false) return null;
      if (available) return song;
    }
  }
  return null;
}

final _libraryPlayRequests = Expando<int>('library play preflight');

/// Plays [queue] from [start] (or its first song); [shuffle] plays it in a
/// random order. [startIndex] identifies repeated occurrences in the visible
/// list, including when two entries refer to the same Song object.
/// A failure shows a short message instead of throwing.
Future<void> lokalPlay(
  BuildContext context,
  WidgetRef ref,
  List<Song> queue, {
  Song? start,
  int? startIndex,
  bool shuffle = false,
}) async {
  if (queue.isEmpty) return;
  final player = ref.read(playerProvider.notifier);
  final request = (_libraryPlayRequests[player] ?? 0) + 1;
  _libraryPlayRequests[player] = request;
  final list = replayableStreamQueue(
    shuffle
        ? ref.read(playerServiceProvider).shuffleForPlayback(queue, (song) => song.id)
        : queue,
  );
  // Playback must use the same reconstructed entry as the queue, not a
  // stale favorite object from before the provider refreshed.
  final requested =
      start ??
      (startIndex != null && startIndex >= 0 && startIndex < queue.length
          ? queue[startIndex]
          : queue.first);
  final index = shuffle
      ? 0
      : PlayerService.selectedPlaylistIndex(
          queue,
          requested,
          indexHint: startIndex,
        );
  var selectedIndex = index < 0 ? 0 : index;
  var selected = list[selectedIndex];
  try {
    if (selected.sourceType == 'lokal') {
      final service = ref.read(playerServiceProvider);
      final revision = service.playbackRequestRevision;
      bool current() =>
          context.mounted &&
          _libraryPlayRequests[player] == request &&
          service.playbackRequestRevision == revision;
      // A mounted row may still hold an earlier offline result after the PC
      // wakes. An explicit user action refreshes one shared server probe.
      final server = selected.remoteServerId;
      if (server != null) {
        ref.invalidate(lokalDesktopStreamingAvailableProvider(server));
      }
      final available = await ref.read(
        lokalSongAvailableProvider(selected).future,
      );
      if (!current()) return;
      if (!available) {
        final fallback = start == null && startIndex == null
            ? await firstAvailableLibraryFallback(
                list,
                (candidate) =>
                    ref.read(lokalSongAvailableProvider(candidate).future),
                stillCurrent: current,
              )
            : null;
        if (!current()) return;
        if (fallback == null) {
          LokalToast.show(
            context,
            lokalText(
              'Reconnect to this Lokal desktop to stream its songs, or download them for offline playback.',
            ),
          );
          return;
        }
        selectedIndex = list.indexWhere((song) => identical(song, fallback));
        selected = list[selectedIndex];
      }
    }
    if (!context.mounted || _libraryPlayRequests[player] != request) return;
    await player.play(selected, playlist: list, playlistIndex: selectedIndex);
  } catch (_) {
    if (!context.mounted) return;
    LokalToast.show(
      context,
      lokalText(
        'Couldn’t play this song. Check that its file or server is available.',
      ),
    );
  }
}

/// Adds [songs] to the end of the queue.
Future<void> lokalQueueAll(
  BuildContext context,
  WidgetRef ref,
  List<Song> songs,
) async {
  final player = ref.read(playerProvider.notifier);
  for (final song in songs) {
    await player.addToQueue(replayableStreamSong(song));
  }
  if (!context.mounted) return;
  LokalToast.show(context, l10n.addedSongsToQueue(songs.length));
}

/// Pushes a Library page on the navigator the caller lives in.
Future<void> pushLokal(BuildContext context, Widget page) =>
    Navigator.of(context).push<void>(LokalPageRoute(builder: (_) => page));

/// Total running time, "1 hr 12 min" or "42 min".
String lokalRunningTime(Iterable<Song> songs) {
  final minutes = songs
      .fold<Duration>(Duration.zero, (sum, s) => sum + s.duration)
      .inMinutes;
  if (minutes >= 60) return '${minutes ~/ 60} hr ${minutes % 60} min';
  return '$minutes min';
}

String lokalSongCount(int count) => l10n.songsCount(count);

/// A Library page: the round glass back button, a large title and [slivers],
/// on the theme's background.
class LokalLibraryPage extends StatelessWidget {
  const LokalLibraryPage({
    super.key,
    required this.title,
    required this.slivers,
    this.subtitle,
    this.actions = const [],
    this.header,
    this.showBack = true,
    this.edgeToEdgeHeader = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> slivers;

  /// Replaces the large title, e.g. an album's cover and name.
  final Widget? header;
  final bool showBack;

  /// Place playlist artwork behind the status bar and keep navigation pinned
  /// inside the safe area. Default library pages retain their SafeArea.
  final bool edgeToEdgeHeader;

  @override
  Widget build(BuildContext context) {
    if (edgeToEdgeHeader && header != null) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: context.lokal.bg,
          body: CustomScrollView(
            slivers: [
              PlaylistSliverHeader(
                hero: header!,
                navigation: LokalPageBar(showBack: showBack, actions: actions),
              ),
              ...slivers,
              SliverToBoxAdapter(
                child: SizedBox(
                  height:
                      (LokalLayout.isTablet(context) ? 32 : 150) +
                      MediaQuery.paddingOf(context).bottom,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: context.lokal.bg,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: LokalPageBar(showBack: showBack, actions: actions),
            ),
            SliverToBoxAdapter(
              child:
                  header ?? LokalLargeTitle(title: title, subtitle: subtitle),
            ),
            ...slivers,
            SliverToBoxAdapter(
              child: SizedBox(
                height:
                    (LokalLayout.isTablet(context) ? 32 : 150) +
                    MediaQuery.paddingOf(context).bottom,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The row of round glass buttons at the top of a page.
class LokalPageBar extends StatelessWidget {
  const LokalPageBar({
    super.key,
    this.showBack = true,
    this.leading,
    this.actions = const [],
    this.padding = LokalPageGeometry.barPadding,
  });

  final EdgeInsetsGeometry padding;
  final bool showBack;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final canPop = showBack && Navigator.of(context).canPop();
    return Padding(
      padding: padding,
      child: SizedBox(
        height: LokalPageGeometry.barHeight,
        child: Row(
          children: [
            if (leading != null)
              leading!
            else if (canPop)
              LokalGlassButton(
                semanticLabel: lokalText('Back'),
                onPressed: () => Navigator.of(context).maybePop(),
                child: Icon(
                  Icons.chevron_left_rounded,
                  size: 28,
                  color: context.lokal.text,
                ),
              ),
            const Spacer(),
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              actions[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// A round glass header button with an icon.
class LokalRoundAction extends StatelessWidget {
  const LokalRoundAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconSize = 22,
  });

  final double iconSize;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    excludeFromSemantics: true,
    child: LokalGlassButton(
      semanticLabel: label,
      onPressed: onPressed,
      child: Icon(icon, color: context.lokal.text, size: iconSize),
    ),
  );
}

class LokalLargeTitle extends StatelessWidget {
  const LokalLargeTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.onLongPress,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPress: onLongPress,
    child: Padding(
      padding: LokalPageGeometry.titlePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 34,
                height: 1.1,
                letterSpacing: -1,
                fontWeight: FontWeight.w800,
                color: context.lokal.text,
              ),
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subtitle!.toUpperCase(),
                style: LokalTheme.label(context.lokal),
              ),
            ),
        ],
      ),
    ),
  );
}

/// A section title inside a page, with an optional "See all".
class LokalSectionTitle extends StatelessWidget {
  const LokalSectionTitle({
    super.key,
    required this.title,
    this.onSeeAll,
    this.actionLabel,
  });

  final String title;
  final VoidCallback? onSeeAll;

  /// Optional action text for expandable sections (e.g. See all / Hide).
  final String? actionLabel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 12, 8),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                letterSpacing: -.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            child: Text(
              actionLabel ?? lokalText('See all'),
              semanticsLabel: '${actionLabel ?? lokalText('See all')} $title',
            ),
          ),
      ],
    ),
  );
}

/// Apple Music's Play and Shuffle pills.
class LokalPlayShufflePills extends ConsumerWidget {
  const LokalPlayShufflePills({super.key, required this.songs, this.extra});

  final List<Song> songs;

  /// A third pill after Shuffle, e.g. Start radio.
  final Widget? extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = songs.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: Row(
        children: [
          Expanded(
            child: LokalPill(
              icon: Icons.play_arrow_rounded,
              label: lokalText('Play'),
              onTap: enabled ? () => lokalPlay(context, ref, songs) : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LokalPill(
              icon: Icons.shuffle_rounded,
              label: lokalText('Shuffle'),
              onTap: enabled
                  ? () => lokalPlay(context, ref, songs, shuffle: true)
                  : null,
            ),
          ),
          if (extra != null) ...[const SizedBox(width: 12), extra!],
        ],
      ),
    );
  }
}

class LokalPill extends StatelessWidget {
  const LokalPill({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// Icon only, square.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final color = onTap == null ? t.muted2 : t.accent;
    return Semantics(
      button: true,
      label: compact ? label : null,
      child: Material(
        color: t.surface2,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 48,
            width: compact ? 52 : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 22),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One song: cover (or track number), title, a second line and the more
/// button. A long press opens the same actions.
class LokalTrackRow extends ConsumerWidget {
  const LokalTrackRow({
    super.key,
    required this.song,
    required this.onTap,
    this.number,
    this.subtitle,
    this.onRemove,
    this.trailing,
  });

  final Song song;
  final VoidCallback onTap;

  /// Shows this number instead of the cover (an album's track list).
  final int? number;
  final String? subtitle;
  final VoidCallback? onRemove;
  final Widget? trailing;

  void _actions(BuildContext context) => unawaited(
    SongActionsBottomSheet.show(
      context,
      song,
      onRemoveFromPlaylist: onRemove,
      queueActions: false,
      hideMediaActions: true,
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.lokal;
    final second = subtitle ?? creditedLeadArtist(song);
    final available =
        song.sourceType != 'lokal' ||
        (ref.watch(lokalSongAvailableProvider(song)).value ?? false);
    return LokalSwipeToQueue(
      song: song,
      enabled: available,
      onNext: needsStreamReResolution(song)
          ? () async {
              final player = ref.read(playerProvider.notifier);
              final index = await player.addToQueue(replayableStreamSong(song));
              if (index > 0) await player.moveQueueItemToNext(index);
              if (context.mounted) {
                LokalToast.show(
                  context,
                  lokalText('“{arg0}” plays next', args: {'arg0': song.title}),
                );
              }
            }
          : null,
      onQueue: needsStreamReResolution(song)
          ? () async {
              await ref
                  .read(playerProvider.notifier)
                  .addToQueue(replayableStreamSong(song));
              if (context.mounted) {
                LokalToast.show(
                  context,
                  lokalText(
                    'Added “{arg0}” to the queue',
                    args: {'arg0': song.title},
                  ),
                );
              }
            }
          : null,
      child: InkWell(
        onTap: available ? onTap : null,
        onLongPress: () => _actions(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 4, 6),
          child: Row(
            children: [
              if (number != null)
                SizedBox(
                  width: 30,
                  child: Text(
                    lokalText("{arg0}", args: {'arg0': number}),
                    style: LokalTheme.label(t, size: 13),
                  ),
                )
              else
                KonnektedArtwork(song: song, size: 48, radius: 8),
              SizedBox(width: number != null ? 4 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: available ? t.text : t.muted2,
                      ),
                    ),
                    Row(
                      children: [
                        if (second.isNotEmpty)
                          Expanded(
                            child: Text(
                              second,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: t.muted),
                            ),
                          ),
                        if (LokalQualityTier.of(song) case final tier?) ...[
                          const SizedBox(width: 8),
                          LokalQualityPill(tier: tier, song: song),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (song.sourceType == 'lokal')
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    lokalText('PC'),
                    style: TextStyle(
                      color: available ? t.accent : t.muted2,
                      fontSize: 10,
                      fontFamily: 'DMMono',
                    ),
                  ),
                ),
              ?trailing,
              IconButton(
                tooltip: lokalText('More'),
                onPressed: () => _actions(context),
                icon: Icon(Icons.more_horiz_rounded, color: t.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A square cover with a tactile press/release and predictable focus.
class LokalCoverCard extends StatelessWidget {
  const LokalCoverCard({
    super.key,
    required this.art,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.round = false,
    this.heroTag,
  });

  final Widget art;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool round;
  final String? heroTag;

  @override
  Widget build(BuildContext context) => LokalPressable(
    radius: round ? 100 : 14,
    semanticLabel: lokalText(
      "{arg0}, {arg1}",
      args: {'arg0': title, 'arg1': subtitle},
    ),
    onTap: onTap,
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: round
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(round ? 999 : 14),
              child: heroTag == null ? art : Hero(tag: heroTag!, child: art),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: round ? TextAlign.center : TextAlign.start,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: round ? TextAlign.center : TextAlign.start,
            style: TextStyle(fontSize: 12, color: context.lokal.muted),
          ),
        ],
      ),
    ),
  );
}

/// The cover of a set of songs: one cover, or four in a grid.
class LokalCollage extends StatelessWidget {
  const LokalCollage({super.key, required this.songs});

  final List<Song> songs;

  @override
  Widget build(BuildContext context) => songs.isEmpty
      ? Container(
          color: context.lokal.surface3,
          alignment: Alignment.center,
          child: Icon(Icons.music_note_rounded, color: context.lokal.accent),
        )
      : KonnektedMixArt(songs: songs);
}

/// A sliver grid of cards, two columns on a phone.
class LokalCardGrid extends StatelessWidget {
  const LokalCardGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.extraHeight = 46,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double extraHeight;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    sliver: SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final columns = LokalLayout.isTablet(context)
            ? LokalLayout.columns(
                width,
                target:
                    180 *
                    MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
              )
            : width > 420
            ? 3
            : 2;
        final cell = (width - 16 * (columns - 1)) / columns;
        final scale = MediaQuery.textScalerOf(context).scale(1);
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 18,
            mainAxisExtent: cell + extraHeight * scale,
          ),
          delegate: SliverChildBuilderDelegate(
            itemBuilder,
            childCount: itemCount,
          ),
        );
      },
    ),
  );
}

/// The search field under a page title.
class LokalSearchField extends StatefulWidget {
  const LokalSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<LokalSearchField> createState() => _LokalSearchFieldState();
}

class _LokalSearchFieldState extends State<LokalSearchField> {
  final FocusNode _focusNode = FocusNode();
  bool _hadFocus = false;
  bool _pendingSelectAllOnTap = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _selectAll() {
    final text = widget.controller.text;
    if (text.isEmpty) return;
    widget.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: text.length,
    );
  }

  void _onFocusChanged() {
    final hasFocus = _focusNode.hasFocus;
    if (hasFocus && !_hadFocus) {
      if (widget.controller.text.isNotEmpty) {
        _selectAll();
        _pendingSelectAllOnTap = true;
      }
    } else if (!hasFocus) {
      _pendingSelectAllOnTap = false;
    }
    _hadFocus = hasFocus;
  }

  void _onTap() {
    if (!_pendingSelectAllOnTap) return;
    _pendingSelectAllOnTap = false;
    _selectAll();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      onTap: _onTap,
      onChanged: (value) {
        _pendingSelectAllOnTap = false;
        widget.onChanged(value);
      },
      textInputAction: TextInputAction.search,
      style: TextStyle(color: t.text, fontSize: 16),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: t.surface2,
        hintText: widget.hint,
        hintStyle: TextStyle(color: t.muted),
        prefixIcon: Icon(Icons.search_rounded, color: t.muted),
        suffixIcon: widget.controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: lokalText('Clear'),
                icon: Icon(Icons.cancel_rounded, color: t.muted, size: 18),
                onPressed: () {
                  _pendingSelectAllOnTap = false;
                  widget.controller.clear();
                  widget.onChanged('');
                },
              ),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// A header that stays at the top while its group scrolls under it.
class LokalPinnedHeader extends SliverPersistentHeaderDelegate {
  LokalPinnedHeader({required this.child, required this.height});

  final Widget child;
  final double height;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      ColoredBox(
        color: context.lokal.bg,
        child: SizedBox.expand(
          child: SafeArea(top: false, bottom: false, child: child),
        ),
      );

  @override
  bool shouldRebuild(LokalPinnedHeader old) =>
      old.child != child || old.height != height;
}

/// One compact navigation row: accent icon, label, optional count, chevron.
class LokalNavRow extends StatelessWidget {
  const LokalNavRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border)),
          ),
          child: Row(
            children: [
              Icon(icon, color: t.accent, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 17, color: t.text),
                ),
              ),
              if (detail != null)
                Text(detail!, style: TextStyle(fontSize: 15, color: t.muted)),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: t.muted2, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// A short empty or error state inside a page.
class LokalEmptyState extends StatelessWidget {
  const LokalEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 24),
      child: Column(
        children: [
          Icon(icon, size: 48, color: t.muted2),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: t.muted, height: 1.45),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

/// Play counts per song id, for "Most played".
final lokalPlayCountsProvider = FutureProvider.autoDispose<Map<String, int>>(
  (ref) => ref.watch(konnektedHistoryRepositoryProvider).getPlayCounts(),
);
