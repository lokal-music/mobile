import 'collection_download_dialog.dart';

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flick/l10n/l10n.dart';
import 'package:flick/widgets/lokal/lokal_choice_sheet.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/models/song.dart';
import 'package:flick/services/link/library_song_identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lokal_library_kit.dart';
import 'lokal_song_filter.dart';

import 'package:flick/widgets/lokal/lokal_quality.dart';

final DateTime _epochDate = DateTime.fromMillisecondsSinceEpoch(0);

/// Use heart-tap chronology on Likes; ordinary library pages still use the
/// actual file import date. A zero rank means a legacy/untracked entry and
/// never outranks a newly liked track.
int compareSongAddedOrder(
  Song a,
  Song b, {
  required bool descending,
  Map<String, int>? likedRanks,
}) {
  final direction = descending ? -1 : 1;
  final comparison = likedRanks == null
      ? (a.dateAdded ?? _epochDate).compareTo(b.dateAdded ?? _epochDate)
      : (likedRanks[a.id] ?? 0).compareTo(likedRanks[b.id] ?? 0);
  return comparison != 0
      ? comparison * direction
      : a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

/// Validates persisted view settings without changing any non-Likes browser.
class LokalSongBrowserViewSettings {
  const LokalSongBrowserViewSettings({
    required this.sort,
    required this.descending,
    required this.location,
    required this.audioFilter,
    required this.query,
  });

  final LokalSongSort sort;
  final bool descending;
  final LokalSongLocation location;
  final String audioFilter;
  final String query;

  Map<String, Object?> toJson() => {
    'sort': sort.name,
    'descending': descending,
    'location': location.name,
    'audioFilter': audioFilter,
    'query': query,
  };

  static LokalSongBrowserViewSettings? decode(
    String? json, {
    LokalSongSort fallbackSort = LokalSongSort.recentlyAdded,
    bool allowOriginal = false,
  }) {
    if (json == null) return null;
    try {
      final raw = jsonDecode(json);
      if (raw is! Map) return null;
      final sort =
          LokalSongSort.values
              .where((s) => s.name == raw['sort'])
              .firstOrNull ??
          fallbackSort;
      final location =
          LokalSongLocation.values
              .where((s) => s.name == raw['location'])
              .firstOrNull ??
          LokalSongLocation.all;
      final filter = raw['audioFilter'];
      final isQuality =
          filter is String &&
          filter.startsWith('quality:') &&
          LokalQualityTier.values.any(
            (tier) => tier.name == filter.substring(8),
          );
      final isFormat =
          filter is String && RegExp(r'^format:\d+:\d+$').hasMatch(filter);
      return LokalSongBrowserViewSettings(
        sort: sort == LokalSongSort.original && !allowOriginal
            ? fallbackSort
            : sort,
        descending: raw['descending'] is bool
            ? raw['descending'] as bool
            : (sort == LokalSongSort.recentlyAdded ||
                  sort == LokalSongSort.mostPlayed ||
                  sort == LokalSongSort.longest),
        location: location,
        audioFilter: filter == 'all' || isQuality || isFormat
            ? filter as String
            : 'all',
        query: raw['query'] is String
            ? ((raw['query'] as String).length > 200
                  ? (raw['query'] as String).substring(0, 200)
                  : raw['query'] as String)
            : '',
      );
    } catch (_) {
      return null;
    }
  }
}

/// Desktop's Simple view sorts.
enum LokalSongSort {
  /// The list's own order (a playlist, or history newest first).
  original('Default order'),
  recentlyAdded('Recently added'),
  title('Title'),
  artist('Artist'),
  mostPlayed('Most played'),
  longest('Longest');

  const LokalSongSort(this.label);

  final String label;
}

/// A song list as slivers: a search field and sort that stay pinned while
/// the list scrolls, the Play and Shuffle pills, and the songs.
class LokalSongBrowser extends ConsumerStatefulWidget {
  const LokalSongBrowser({
    super.key,
    required this.songs,
    this.initialSort = LokalSongSort.recentlyAdded,
    this.originalLabel,
    this.searchHint = 'Search songs',
    this.onRemove,
    this.subtitleOf,
    this.recentlyAddedRanks,
    this.preferencesKey,
    this.onDownload,
  });

  final List<Song> songs;
  final LokalSongSort initialSort;

  /// Supplied only by Likes: hearts sort chronologically, not by import date.
  final Map<String, int>? recentlyAddedRanks;

  /// Optional stable persistence key, scoped per list (Likes, Library,
  /// Downloads, recently played/added, genre, or individual playlist).
  final String? preferencesKey;

  /// Offers [LokalSongSort.original] under this name, e.g. "Playlist order".
  final String? originalLabel;
  final String searchHint;

  /// Downloads the full collection, independently of the browser's filters.
  final VoidCallback? onDownload;

  /// Offered in each song's actions, e.g. remove from this playlist.
  final void Function(Song song)? onRemove;
  final String Function(Song song)? subtitleOf;

  @override
  ConsumerState<LokalSongBrowser> createState() => _LokalSongBrowserState();
}

class _LokalSongBrowserState extends ConsumerState<LokalSongBrowser> {
  final _search = TextEditingController();
  late LokalSongSort _sort = widget.initialSort;
  late bool _descending = _defaultDescending(widget.initialSort);
  Timer? _queryTimer;
  String _query = '';
  bool _viewModified = false;
  Future<void> _writeTail = Future<void>.value();

  @override
  void initState() {
    super.initState();
    if (widget.preferencesKey != null) unawaited(_restoreView());
  }

  @override
  void didUpdateWidget(covariant LokalSongBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferencesKey == widget.preferencesKey) return;
    // Navigator can reuse a browser element while switching list contexts.
    // Never leak a previous playlist's active filters into the new one.
    _viewModified = false;
    _sort = widget.initialSort;
    _descending = _defaultDescending(widget.initialSort);
    _location = LokalSongLocation.all;
    _audioFilter = 'all';
    _query = '';
    _search.clear();
    _visibleCache = null;
    if (widget.preferencesKey != null) unawaited(_restoreView());
  }

  Future<void> _restoreView() async {
    final key = widget.preferencesKey;
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = LokalSongBrowserViewSettings.decode(
        prefs.getString(key),
        fallbackSort: widget.initialSort,
        allowOriginal: widget.originalLabel != null,
      );
      if (!mounted ||
          widget.preferencesKey != key ||
          _viewModified ||
          saved == null)
        return;
      setState(() {
        _sort = saved.sort;
        _descending = saved.descending;
        _location = saved.location;
        _audioFilter = saved.audioFilter;
        _query = saved.query;
        _search.text = saved.query;
      });
    } catch (_) {
      // Storage issues must not break song browsing.
    }
  }

  void _persistView() {
    final key = widget.preferencesKey;
    if (key == null) return;
    final encoded = jsonEncode(
      LokalSongBrowserViewSettings(
        sort: _sort,
        descending: _descending,
        location: _location,
        audioFilter: _audioFilter,
        query: _query,
      ).toJson(),
    );
    // Serialize rapid filter changes to prevent older async writes winning.
    _writeTail = _writeTail
        .then((_) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(key, encoded);
        })
        .catchError((Object _) {});
  }

  void _updateView(VoidCallback update) {
    _viewModified = true;
    setState(update);
    _persistView();
  }

  static bool _defaultDescending(LokalSongSort sort) =>
      sort == LokalSongSort.recentlyAdded ||
      sort == LokalSongSort.mostPlayed ||
      sort == LokalSongSort.longest;

  void _onSearchChanged(String value) {
    _queryTimer?.cancel();
    _viewModified = true;
    if (value.isEmpty) {
      _updateView(() => _query = '');
      return;
    }
    // Typing should stay responsive with tens of thousands of entries.
    _queryTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted) _updateView(() => _query = value);
    });
  }

  LokalSongLocation _location = LokalSongLocation.all;
  String _audioFilter = 'all';
  LokalSongLocation? _inputLocation;
  String? _inputAudioFilter;
  List<Song>? _visibleCache;
  List<Song>? _inputSongs;
  Map<String, int>? _inputCounts;
  String? _inputQuery;
  LokalSongSort? _inputSort;
  bool? _inputDescending;
  Map<String, int>? _inputLikedRanks;
  List<Song>? _formatInput;
  List<String> _cachedFormats = const [];

  List<String> _formats() {
    if (!identical(_formatInput, widget.songs)) {
      _formatInput = widget.songs;
      _cachedFormats = libraryAudioFormats(widget.songs);
    }
    return _cachedFormats;
  }

  @override
  void dispose() {
    _queryTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  List<Song> _visible(Map<String, int> counts) {
    final query = _query.trim().toLowerCase();
    if (identical(_inputSongs, widget.songs) &&
        identical(_inputCounts, counts) &&
        _inputQuery == query &&
        _inputSort == _sort &&
        _inputDescending == _descending &&
        identical(_inputLikedRanks, widget.recentlyAddedRanks) &&
        _inputLocation == _location &&
        _inputAudioFilter == _audioFilter &&
        _visibleCache != null) {
      return _visibleCache!;
    }
    final songs = [
      for (final song in widget.songs)
        if (matchesLibraryFilters(song, _location, _audioFilter) &&
            (query.isEmpty ||
                '${song.title}\n${song.artist}\n${song.album ?? ''}'
                    .toLowerCase()
                    .contains(query)))
          song,
    ];
    // Lowercasing inside the sort comparator repeatedly allocates strings.
    // Precompute the sort keys once per filter/sort change.
    final titleKeys = <String, String>{
      for (final song in songs) song.id: song.title.toLowerCase(),
    };
    int byTitle(Song a, Song b) => titleKeys[a.id]!.compareTo(titleKeys[b.id]!);
    final direction = _descending ? -1 : 1;
    switch (_sort) {
      case LokalSongSort.original:
        // This is the one case with no sort key. Reversing the visible list
        // must never mutate the persisted playlist order.
        if (_descending) {
          songs.setAll(0, songs.reversed.toList(growable: false));
        }
      case LokalSongSort.recentlyAdded:
        songs.sort(
          (a, b) => compareSongAddedOrder(
            a,
            b,
            descending: _descending,
            likedRanks: widget.recentlyAddedRanks,
          ),
        );
      case LokalSongSort.title:
        songs.sort((a, b) => byTitle(a, b) * direction);
      case LokalSongSort.artist:
        final artistKeys = <String, String>{
          for (final song in songs)
            song.id: creditedLeadArtist(song).toLowerCase(),
        };
        songs.sort((a, b) {
          final c = artistKeys[a.id]!.compareTo(artistKeys[b.id]!);
          return c != 0 ? c * direction : byTitle(a, b);
        });
      case LokalSongSort.mostPlayed:
        songs.sort((a, b) {
          final c = (counts[a.id] ?? 0).compareTo(counts[b.id] ?? 0);
          return c != 0 ? c * direction : byTitle(a, b);
        });
      case LokalSongSort.longest:
        songs.sort((a, b) {
          final c = a.duration.compareTo(b.duration);
          return c != 0 ? c * direction : byTitle(a, b);
        });
    }
    _inputSongs = widget.songs;
    _inputCounts = counts;
    _inputQuery = query;
    _inputSort = _sort;
    _inputDescending = _descending;
    _inputLikedRanks = widget.recentlyAddedRanks;
    _inputLocation = _location;
    _inputAudioFilter = _audioFilter;
    return _visibleCache = songs;
  }

  Future<void> _chooseSort(
    List<LokalSongSort> options,
    String Function(LokalSongSort) label,
  ) async {
    final selected = await showLokalChoiceSheet<LokalSongSort>(
      context: context,
      title: 'Sort by',
      selected: _sort,
      choices: [
        for (final sort in options)
          LokalChoice(
            value: sort,
            label: label(sort),
            icon: switch (sort) {
              LokalSongSort.original => Icons.format_list_numbered_rounded,
              LokalSongSort.recentlyAdded => Icons.history_rounded,
              LokalSongSort.title => Icons.sort_by_alpha_rounded,
              LokalSongSort.artist => Icons.person_outline_rounded,
              LokalSongSort.mostPlayed => Icons.bar_chart_rounded,
              LokalSongSort.longest => Icons.timer_outlined,
            },
          ),
      ],
    );
    if (selected == null || !mounted) return;
    // Changing the sort criterion must not silently reset the user's
    // chosen ascending/descending direction or any active filters.
    _updateView(() => _sort = selected);
  }

  Future<void> _chooseLocation() async {
    final selected = await showLokalChoiceSheet<LokalSongLocation>(
      context: context,
      title: 'Filter by location',
      selected: _location,
      choices: [
        for (final location in LokalSongLocation.values)
          LokalChoice(
            value: location,
            label: lokalText(location.label),
            icon: switch (location) {
              LokalSongLocation.all => Icons.library_music_outlined,
              LokalSongLocation.phone => Icons.smartphone_rounded,
              LokalSongLocation.pc => Icons.computer_rounded,
              LokalSongLocation.other => Icons.cloud_outlined,
            },
          ),
      ],
    );
    if (selected != null && mounted) {
      _updateView(() => _location = selected);
    }
  }

  Future<void> _chooseQuality(List<String> formats) async {
    final selected = await showLokalChoiceSheet<String>(
      context: context,
      title: 'Filter by format and quality',
      selected: _audioFilter,
      choices: [
        const LokalChoice(
          value: 'all',
          label: 'All formats and qualities',
          icon: Icons.tune_rounded,
        ),
        for (final tier in LokalQualityTier.values)
          LokalChoice(
            value: 'quality:${tier.name}',
            label: lokalText(tier.label),
            icon: Icons.high_quality_rounded,
          ),
        for (final format in formats)
          LokalChoice(
            value: format,
            label: libraryAudioFilterLabel(format),
            icon: Icons.graphic_eq_rounded,
          ),
      ],
    );
    if (selected != null && mounted) {
      _updateView(() => _audioFilter = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final counts = _sort == LokalSongSort.mostPlayed
        ? ref.watch(lokalPlayCountsProvider).value ?? const <String, int>{}
        : const <String, int>{};
    final songs = _visible(counts);
    final formats = _formats();
    final sorts = [
      if (widget.originalLabel != null) LokalSongSort.original,
      for (final sort in LokalSongSort.values)
        if (sort != LokalSongSort.original) sort,
    ];
    String label(LokalSongSort sort) => sort == LokalSongSort.original
        ? widget.originalLabel ?? sort.label
        : sort.label;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    return SliverMainAxisGroup(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: LokalPinnedHeader(
            height: 60 * scale,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: LokalSearchField(
                      controller: _search,
                      hint: widget.searchHint,
                      onChanged: _onSearchChanged,
                    ),
                  ),
                  IconButton(
                    tooltip: lokalText(
                      "Sort: {arg0}",
                      args: {'arg0': label(_sort)},
                    ),
                    icon: Icon(Icons.sort_rounded, color: t.accent),
                    onPressed: () => unawaited(_chooseSort(sorts, label)),
                  ),
                  IconButton(
                    tooltip: lokalText(
                      _descending
                          ? 'Descending · switch to ascending'
                          : 'Ascending · switch to descending',
                    ),
                    icon: Icon(
                      _descending
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded,
                      color: t.accent,
                    ),
                    onPressed: () =>
                        _updateView(() => _descending = !_descending),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ActionChip(
                  tooltip: lokalText('Filter by location'),
                  onPressed: () => unawaited(_chooseLocation()),
                  avatar: Icon(
                    Icons.folder_outlined,
                    size: 18,
                    color: t.accent,
                  ),
                  label: Text(lokalText(_location.label)),
                ),
                ActionChip(
                  tooltip: lokalText('Filter by format and quality'),
                  onPressed: () => unawaited(_chooseQuality(formats)),
                  avatar: Icon(
                    Icons.equalizer_rounded,
                    size: 18,
                    color: t.accent,
                  ),
                  label: Text(lokalText(libraryAudioFilterLabel(_audioFilter))),
                ),
                if (_location != LokalSongLocation.all ||
                    _audioFilter != 'all') ...[
                  Text(
                    lokalSongCount(songs.length),
                    style: TextStyle(color: t.muted, fontSize: 12),
                  ),
                  TextButton(
                    onPressed: () => _updateView(() {
                      _location = LokalSongLocation.all;
                      _audioFilter = 'all';
                    }),
                    child: Text(lokalText('Clear filters')),
                  ),
                ],
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: LokalPlayShufflePills(songs: songs)),
        if (widget.onDownload != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: LokalPill(
                icon: Icons.download_rounded,
                label: lokalText('Download missing songs'),
                onTap: widget.onDownload,
              ),
            ),
          ),
        if (songs.isEmpty)
          SliverToBoxAdapter(
            child: LokalEmptyState(
              icon: Icons.search_off_rounded,
              title: lokalText('No matching songs'),
              message: lokalText(
                'Try another search, location or audio filter.',
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return LokalTrackRow(
                song: song,
                subtitle: widget.subtitleOf?.call(song),
                onTap: () => lokalPlay(
                  context,
                  ref,
                  songs,
                  start: song,
                  startIndex: index,
                ),
                onRemove: widget.onRemove == null
                    ? null
                    : () => widget.onRemove!(song),
              );
            },
          ),
      ],
    );
  }
}

/// A page with a song list: Songs, Liked, Downloads, a genre.
class LokalSongListPage extends ConsumerWidget {
  const LokalSongListPage({
    super.key,
    required this.title,
    required this.source,
    this.initialSort = LokalSongSort.recentlyAdded,
    this.originalLabel,
    this.emptyIcon = Icons.music_note_rounded,
    this.emptyTitle = 'No songs yet',
    this.emptyMessage = 'Songs show up here once they’re in your library.',
    this.subtitleOf,
    this.recentlyAddedRanks,
    this.preferencesKey,
    this.showTotalDuration = false,
    this.downloadMissing = false,
  });

  final String title;
  final AsyncValue<List<Song>> Function(WidgetRef ref) source;
  final LokalSongSort initialSort;
  final String? originalLabel;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final String Function(Song song)? subtitleOf;
  final Map<String, int> Function(WidgetRef ref)? recentlyAddedRanks;
  final String? preferencesKey;
  final bool showTotalDuration;
  final bool downloadMissing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = source(ref);
    final list = songs.value;
    final metadata = list == null
        ? null
        : '${lokalSongCount(list.length)} · ${lokalRunningTime(list)}';
    final pendingMetadata = songs.hasError
        ? lokalText('Couldn’t load these songs')
        : (title == lokalText('Library')
              ? lokalText('Opening your collection')
              : lokalText('Loading history…'));
    return LokalLibraryPage(
      title: title,
      // Recently Played uses a full-size metadata row: never hide its
      // running time in the small uppercase section-label treatment.
      subtitle: showTotalDuration
          ? null
          : (list == null ? null : lokalSongCount(list.length)),
      header: showTotalDuration
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LokalLargeTitle(title: title),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: Text(
                    metadata ?? pendingMetadata,
                    style: TextStyle(
                      color: context.lokal.muted,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            )
          : null,
      slivers: [
        if (list != null && list.isNotEmpty)
          LokalSongBrowser(
            songs: list,
            initialSort: initialSort,
            originalLabel: originalLabel,
            subtitleOf: subtitleOf,
            recentlyAddedRanks: recentlyAddedRanks?.call(ref),
            preferencesKey: preferencesKey,
            onDownload: downloadMissing
                ? () => unawaited(
                    downloadMissingCollectionSongs(context, ref, list),
                  )
                : null,
          )
        else
          SliverToBoxAdapter(
            child: songs.hasError
                ? LokalEmptyState(
                    icon: Icons.error_outline_rounded,
                    title: lokalText('Couldn’t load these songs'),
                    message: lokalText('Try again in a moment.'),
                    actionLabel: 'Try again',
                    onAction: () => ref.invalidate(konnektedLibraryProvider),
                  )
                : list == null
                ? const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : LokalEmptyState(
                    icon: emptyIcon,
                    title: emptyTitle,
                    message: emptyMessage,
                  ),
          ),
      ],
    );
  }
}
