import '../providers/recent_search_tracks.dart';
import '../widgets/online_catalogue_search_section.dart';
import '../widgets/lyrics_search_section.dart';
import '../widgets/artist_search_portrait.dart';
import 'package:flick/features/library_jobs/artist_metadata.dart';
import '../widgets/global_catalogue_search_section.dart';
import '../widgets/recent_search_grid.dart';
import '../widgets/soulseek_search_section.dart';

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flick/core/constants/app_constants.dart';
import 'package:flick/core/theme/app_colors.dart';
import 'package:flick/core/theme/adaptive_color_provider.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/models/nav_bar_config.dart';
import 'package:flick/models/playlist.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/providers.dart';
import 'package:flick/widgets/common/cached_image_widget.dart';
import 'package:flick/widgets/common/flick_artwork_placeholder.dart';
import 'package:flick/widgets/common/glass_search_bar.dart';
import 'package:flick/features/songs/widgets/song_actions_bottom_sheet.dart';
import 'package:flick/features/search/models/search_category.dart';
import 'package:flick/features/search/models/global_search_results.dart';
import 'package:flick/features/search/providers/global_search_provider.dart';
import 'package:flick/features/search/providers/search_filter_provider.dart';
import 'package:flick/features/search/widgets/online_search_section.dart';
import 'package:flick/features/search/widgets/search_filter_chips.dart';
import 'package:flick/features/konnekted/library/lokal_albums_artists.dart';
import 'package:flick/features/konnekted/library/lokal_genres.dart';
import 'package:flick/features/konnekted/library/lokal_library_kit.dart';
import 'package:flick/features/konnekted/library/lokal_navigation.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/widgets/lokal/lokal_swipe_to_queue.dart';
import 'package:flick/services/catalogue_quality.dart';
import 'package:flick/widgets/lokal/lokal_quality.dart';
import 'package:flick/services/link/library_song_identity.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.footerFocusRequests, this.initialQuery});

  /// Supplied only by the bottom-bar Search destination. An explicit tap
  /// requests the keyboard even if the optional generic auto-focus preference
  /// is disabled. Other Search entry points keep their existing behavior.
  final ValueListenable<int>? footerFocusRequests;
  /// Optional prefilled search opened from a live radio song or artist.
  final String? initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final _controller = TextEditingController(text: widget.initialQuery);
  final _focusNode = FocusNode();
  SongRepository get _songRepository => ref.read(songRepositoryProvider);
  Timer? _debounce;
  late String _debouncedQuery = widget.initialQuery?.trim() ?? '';
  final Map<SearchCategory, bool> _expanded = {};

  static const int _previewLimit = 4;

  @override
  void initState() {
    super.initState();
    widget.footerFocusRequests?.addListener(_onFooterSearchTap);
    if (widget.initialQuery?.trim().isNotEmpty == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.unfocus();
      });
    }
    // The footer may have been tapped before this lazily mounted screen
    // exists. Focus after the TextField attaches to the element tree.
    if (widget.footerFocusRequests != null) _focusAfterNavigation();
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.footerFocusRequests != widget.footerFocusRequests) {
      oldWidget.footerFocusRequests?.removeListener(_onFooterSearchTap);
      widget.footerFocusRequests?.addListener(_onFooterSearchTap);
      if (widget.footerFocusRequests != null) _focusAfterNavigation();
    }
  }

  void _onFooterSearchTap() => _focusAfterNavigation();

  void _selectAllQuery() {
    final text = _controller.text;
    if (text.isEmpty) return;
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: text.length,
    );
  }

  void _focusAfterNavigation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.footerFocusRequests == null) return;
      _focusNode.requestFocus();
      _selectAllQuery();
      // Android may hide its IME on Back while leaving the field focused.
      // requestKeyboard() also reopens it on a repeated dock Search tap.
      _focusNode.context
          ?.findAncestorStateOfType<EditableTextState>()
          ?.requestKeyboard();
    });
  }

  @override
  void dispose() {
    widget.footerFocusRequests?.removeListener(_onFooterSearchTap);
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    // Trigger rebuild for hasInput (clear button) immediately.
    setState(() {});
    if (value.trim().isEmpty) {
      if (_debouncedQuery.isNotEmpty) {
        setState(() => _debouncedQuery = '');
      }
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final q = value.trim();
      if (mounted && q != _debouncedQuery) {
        setState(() => _debouncedQuery = q);
      }
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _controller.clear();
    setState(() => _debouncedQuery = '');
  }

  bool _isExpanded(SearchCategory cat) => _expanded[cat] ?? false;
  void _toggleExpanded(SearchCategory cat) {
    setState(() => _expanded[cat] = !_isExpanded(cat));
  }

  @override
  Widget build(BuildContext context) {
    final autoFocus = ref.watch(appPreferencesProvider).autoFocusSearch;

    ref.listen(navigationIndexProvider, (prev, next) {
      if (next == NavBarButton.search.pageIndex && autoFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _focusNode.requestFocus();
          _selectAllQuery();
        });
      } else if (prev == NavBarButton.search.pageIndex) {
        _focusNode.unfocus();
      }
    });

    final enabled = ref.watch(searchFilterProvider);
    final scope = ref.watch(searchScopeProvider);
    final repoQuery = _debouncedQuery;
    final hasInput = _controller.text.trim().isNotEmpty;
    final hasQuery = repoQuery.isNotEmpty;
    final resultsAsync = hasQuery && scope != SearchScope.online && scope != SearchScope.soulseek &&
        enabled.singleOrNull != SearchCategory.lyrics
        ? ref.watch(globalSearchResultsProvider(repoQuery))
        : null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Glass search bar inside gradient container (songs/artists parity).
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.surfaceLight.withValues(alpha: .75),
                      AppColors.surface.withValues(alpha: .85),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                  border: Border.all(color: AppColors.glassBorder),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: GlassSearchBar(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: autoFocus,
                  textInputAction: TextInputAction.search,
                  hintText: l10n.searchSongsArtistsAlbums,
                  showBackground: false,
                  onChanged: _onSearchChanged,
                  onClear: _clearSearch,
                ),
              ),
            ),
            // Poweramp-style horizontal chip shelf.
            Builder(
              builder: (context) {
                final counts = resultsAsync?.value?.counts;
                return SearchFilterChips(
                  enabled: enabled,
                  scope: scope,
                  onScopeChanged: (value) =>
                      ref.read(searchScopeProvider.notifier).select(value),
                  onToggle: (cat) =>
                      ref.read(searchFilterProvider.notifier).toggle(cat),
                  counts: counts,
                  query: repoQuery,
                );
              },
            ),
            Expanded(
              child: scope == SearchScope.soulseek
                  ? SoulseekSearchSection(query: repoQuery)
                  : !hasInput
                  ? _buildEmptyState(context)
                  : scope != SearchScope.online &&
                          enabled.singleOrNull == SearchCategory.lyrics && hasQuery
                  ? scope == SearchScope.library
                      ? LyricsSearchSection(
                          key: ValueKey('library-lyrics:$repoQuery'),
                          query: repoQuery, online: false,
                          onPlayLocal: _playSong,
                        )
                      : NestedScrollView(
                          // Local lyrics owns a scroll view. A plain sliver
                          // wrapper would give it unbounded height on Android.
                          headerSliverBuilder: (context, innerBoxIsScrolled) => [
                            if (_onlineSection(repoQuery) case final online?) online,
                          ],
                          body: LyricsSearchSection(
                            key: ValueKey('library-lyrics:$repoQuery'),
                            query: repoQuery, online: false,
                            onPlayLocal: _playSong,
                          ),
                        )
                  : scope == SearchScope.online && hasQuery
                  ? CustomScrollView(
                      slivers: [
                        if (_onlineSection(repoQuery) case final online?)
                          online,
                        const SliverToBoxAdapter(child: SizedBox(height: 140)),
                      ],
                    )
                  : _buildResultsArea(
                      context,
                      hasQuery: hasQuery,
                      resultsAsync: resultsAsync,
                      enabled: enabled,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsArea(
    BuildContext context, {
    required bool hasQuery,
    required AsyncValue<GlobalSearchResults>? resultsAsync,
    required Set<SearchCategory> enabled,
  }) {
    if (!hasQuery) {
      // Debounce in-flight – show spinner if user typed but not yet committed.
      return Center(
        child: CircularProgressIndicator(
          color: AppColors.textTertiary,
          strokeWidth: 2,
        ),
      );
    }
    final async = resultsAsync!;
    return async.when(
      data: (results) {
        if (enabled.isEmpty) {
          return _buildFilteredEmpty(context);
        }
        // Check if no enabled category has results.
        final anyEnabledHasResults = SearchCategory.values.any(
          (c) => enabled.contains(c) && results.hasResultsFor(c),
        );
        if (!anyEnabledHasResults) {
          // Nothing in the library: what's online still shows under it.
          return CustomScrollView(
            key: _resultsScrollKey(enabled),
            slivers: [
              // In All, online results may still be present. Do not claim
              // the entire search has no results just because local is empty.
              if (ref.read(searchScopeProvider) == SearchScope.library)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: _buildNoResults(context, results.query),
                  ),
                ),
              if (_onlineSection(results.query) case final online?) online,
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          );
        }
        return _buildGroupedResults(context, results, enabled);
      },
      loading: () => ref.read(searchScopeProvider) == SearchScope.all
          ? CustomScrollView(
              key: _resultsScrollKey(enabled),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator(
                      color: AppColors.textTertiary, strokeWidth: 2,
                    )),
                  ),
                ),
                // Online searches should not wait on the local database.
                if (_onlineSection(_debouncedQuery) case final online?) online,
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            )
          : Center(
              child: CircularProgressIndicator(
                color: AppColors.textTertiary,
                strokeWidth: 2,
              ),
            ),
      error: (e, st) => CustomScrollView(
        key: _resultsScrollKey(enabled),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spacingLg),
              child: Text(
                l10n.searchFailed2(e),
                style: TextStyle(color: context.adaptiveTextTertiary),
              ),
            ),
          ),
          if (_onlineSection(_debouncedQuery) case final online?) online,
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    // Idle Search is a browsing destination, not an empty dead end.
    // The preview stays deliberately short; all categories remain available
    // on the dedicated Library > Genres destination.
    final summary = ref.watch(lokalGenreSummaryProvider).value;
    final scope = ref.watch(searchScopeProvider);
    final previewGenres =
        summary?.genres.take(6).toList() ?? const <LokalGenre>[];
    final previewUnclassified = previewGenres.length < 6
        ? (summary?.noGenre ?? const <Song>[])
        : const <Song>[];
    final browseGenres = scope != SearchScope.online &&
        (previewGenres.isNotEmpty || previewUnclassified.isNotEmpty);
    final genreSlivers = <Widget>[
      if (browseGenres)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    lokalText('Browse by genre'),
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => pushLokal(context, const LokalGenresPage()),
                  child: Text(lokalText('See all')),
                ),
              ],
            ),
          ),
        ),
      if (browseGenres)
        LokalGenreGrid(
          genres: previewGenres,
          noGenreSongs: previewUnclassified,
        ),
    ];
    if (ref.watch(recentSearchTracksProvider).isNotEmpty) {
      return RecentSearchGrid(
        headerSlivers: genreSlivers,
        onSelected: (track) {
          final song = (ref.read(songsProvider).value?.songs ?? const <Song>[])
              .where((song) => song.id == track.songId)
              .firstOrNull;
          if (song != null) {
            unawaited(_playSong(song, [song]));
          } else {
            _controller.text = track.title;
            _onSearchChanged(track.title);
          }
        },
      );
    }
    if (browseGenres) {
      return CustomScrollView(
        slivers: [
          ...genreSlivers,
          const SliverToBoxAdapter(child: SizedBox(height: 160)),
        ],
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.search,
            size: 48,
            color: context.adaptiveTextTertiary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            ref.watch(searchScopeProvider) == SearchScope.online
                ? l10n.searchOnline2 : l10n.searchYourLibrary,
            style: TextStyle(
              fontFamily: 'GoogleSansFlex',
              fontSize: 15,
              color: context.adaptiveTextTertiary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ref.watch(searchScopeProvider) == SearchScope.online
                ? l10n.searchAcrossSongsArtistsAndAlbums : l10n.findSongsArtistsAlbumsFolders,
            style: TextStyle(
              fontFamily: 'GoogleSansFlex',
              fontSize: 13,
              color: context.adaptiveTextTertiary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.tapChipsToFilterCategories,
            style: TextStyle(
              fontFamily: 'GoogleSansFlex',
              fontSize: 11,
              color: context.adaptiveTextTertiary.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults(BuildContext context, String query) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.search,
            size: 48,
            color: context.adaptiveTextTertiary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.noResultsFor(query),
            style: TextStyle(
              fontFamily: 'GoogleSansFlex',
              fontSize: 15,
              color: context.adaptiveTextTertiary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            lokalText('Try another keyword'),
            style: TextStyle(
              fontFamily: 'GoogleSansFlex',
              fontSize: 12,
              color: context.adaptiveTextTertiary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilteredEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.slidersHorizontal,
            size: 48,
            color: context.adaptiveTextTertiary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.noCategoriesSelected,
            style: TextStyle(
              fontFamily: 'GoogleSansFlex',
              fontSize: 15,
              color: context.adaptiveTextTertiary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.tapAllOrEnableAChip,
            style: TextStyle(
              fontFamily: 'GoogleSansFlex',
              fontSize: 12,
              color: context.adaptiveTextTertiary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedResults(
    BuildContext context,
    GlobalSearchResults results,
    Set<SearchCategory> enabled,
  ) {
    final slivers = <Widget>[];
    void addSection({
      required SearchCategory cat,
      required int count,
      required List<Widget> Function() buildItems,
    }) {
      if (!enabled.contains(cat) || count == 0) return;
      final expanded = _isExpanded(cat);
      final showSeeAll = enabled.length != 1 && count > _previewLimit;
      slivers.add(
        _SectionHeader(
          category: cat,
          count: count,
          showSeeAll: showSeeAll,
          expanded: expanded,
          onToggle: () => _toggleExpanded(cat),
        ),
      );
      slivers.addAll(buildItems());
      if (showSeeAll && !expanded) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacingLg,
                2,
                AppConstants.spacingLg,
                AppConstants.spacingSm,
              ),
              child: GestureDetector(
                onTap: () => _toggleExpanded(cat),
                child: Text(
                  l10n.seeAll2(count),
                  style: TextStyle(
                    fontFamily: 'GoogleSansFlex',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 8)));
    }

    addSection(
      cat: SearchCategory.songs,
      count: results.songs.length,
      buildItems: () {
        final expanded =
            enabled.length == 1 || _isExpanded(SearchCategory.songs);
        final visible = expanded
            ? results.songs
            : results.songs.take(_previewLimit).toList();
        return [
          SliverList.builder(
            itemCount: visible.length,
            itemBuilder: (c, i) => _SongTile(
              song: visible[i],
              playlistForMode: results.songs,
              repository: _songRepository,
              onPlay: _playSong,
            ),
          ),
        ];
      },
    );

    addSection(
      cat: SearchCategory.artists,
      count: results.artists.length,
      buildItems: () {
        final expanded =
            enabled.length == 1 || _isExpanded(SearchCategory.artists);
        final visible = expanded
            ? results.artists
            : results.artists.take(_previewLimit).toList();
        return [
          SliverList.builder(
            itemCount: visible.length,
            itemBuilder: (c, i) {
              final entry = visible[i];
              return _ArtistTile(
                name: entry.key,
                songs: entry.value,
                onTap: () => _openArtist(context, entry.key, entry.value),
              );
            },
          ),
        ];
      },
    );

    addSection(
      cat: SearchCategory.albums,
      count: results.albums.length,
      buildItems: () {
        final expanded =
            enabled.length == 1 || _isExpanded(SearchCategory.albums);
        final visible = expanded
            ? results.albums
            : results.albums.take(_previewLimit).toList();
        return [
          SliverList.builder(
            itemCount: visible.length,
            itemBuilder: (c, i) {
              final album = visible[i];
              return _AlbumTile(
                album: album,
                onTap: () => _openAlbum(context, album),
              );
            },
          ),
        ];
      },
    );

    addSection(
      cat: SearchCategory.albumArtists,
      count: results.albumArtists.length,
      buildItems: () {
        final expanded =
            enabled.length == 1 || _isExpanded(SearchCategory.albumArtists);
        final visible = expanded
            ? results.albumArtists
            : results.albumArtists.take(_previewLimit).toList();
        return [
          SliverList.builder(
            itemCount: visible.length,
            itemBuilder: (c, i) {
              final entry = visible[i];
              return _ArtistTile(
                name: entry.key,
                songs: entry.value,
                icon: LucideIcons.users,
                onTap: () => _openArtist(context, entry.key, entry.value),
              );
            },
          ),
        ];
      },
    );

    addSection(
      cat: SearchCategory.folders,
      count: results.folders.length,
      buildItems: () {
        final expanded =
            enabled.length == 1 || _isExpanded(SearchCategory.folders);
        final visible = expanded
            ? results.folders
            : results.folders.take(_previewLimit).toList();
        return [
          SliverList.builder(
            itemCount: visible.length,
            itemBuilder: (c, i) {
              final folder = visible[i];
              return _FolderTile(
                folder: folder,
                onTap: () => _playSong(folder.songs.first, folder.songs),
              );
            },
          ),
        ];
      },
    );

    addSection(
      cat: SearchCategory.year,
      count: results.yearMatches.length,
      buildItems: () {
        final expanded =
            enabled.length == 1 || _isExpanded(SearchCategory.year);
        final visible = expanded
            ? results.yearMatches
            : results.yearMatches.take(_previewLimit).toList();
        return [
          SliverList.builder(
            itemCount: visible.length,
            itemBuilder: (c, i) => _SongTile(
              song: visible[i],
              playlistForMode: results.yearMatches,
              repository: _songRepository,
              onPlay: _playSong,
              subtitleSuffix: visible[i].year?.toString(),
            ),
          ),
        ];
      },
    );

    addSection(
      cat: SearchCategory.playlists,
      count: results.playlists.length,
      buildItems: () {
        final expanded =
            enabled.length == 1 || _isExpanded(SearchCategory.playlists);
        final visible = expanded
            ? results.playlists
            : results.playlists.take(_previewLimit).toList();
        return [
          SliverList.builder(
            itemCount: visible.length,
            itemBuilder: (c, i) => _PlaylistTile(
              playlist: visible[i],
              onTap: () => _openPlaylist(context, visible[i]),
            ),
          ),
        ];
      },
    );

    return CustomScrollView(
      key: _resultsScrollKey(enabled),
      slivers: [
        ...slivers,
        if (_onlineSection(results.query) case final online?) online,
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  Key _resultsScrollKey(Set<SearchCategory> enabled) =>
      ValueKey('${enabled.singleOrNull}:${ref.read(searchScopeProvider)}');

  Widget? _onlineSection(String query) {
    if (ref.read(searchScopeProvider) == SearchScope.library) return null;
    final category = ref.read(searchFilterProvider).singleOrNull;
    if (!supportsOnlineCategory(category)) return null;
    if (category == SearchCategory.lyrics) {
      return SliverToBoxAdapter(
        key: ValueKey('online-lyrics-sliver:$query'),
        child: LyricsSearchSection(
          key: ValueKey('online-lyrics:$query'),
          query: query, online: true,
          onPlayLocal: _playSong,
        ),
      );
    }
    if (category == SearchCategory.artists ||
        category == SearchCategory.albums) {
      return SliverToBoxAdapter(
        key: ValueKey('catalogue-sliver:$category:$query'),
        child: OnlineCatalogueSearchSection(
          key: ValueKey('catalogue:$category:$query'),
          query: query,
          category: category!,
        ),
      );
    }
    // Global catalogue is metadata-only; playback uses source priority.
    // Preserve per-provider searches as a secondary mobile feature.
    final global = SliverToBoxAdapter(
      child: GlobalCatalogueSearchSection(
        key: ValueKey('global:$query'),
        query: query,
        songsOnly: true,
      ),
    );
    final songs = OnlineSearchSection(
      key: ValueKey('songs:$query'),
      query: query,
    );
    return SliverMainAxisGroup(key: ValueKey('online-sliver:$query'), slivers: [global, songs]);
  }

  Future<void> _playSong(Song song, List<Song> playlist) async {
    unawaited(
      ref
          .read(recentSearchTracksProvider.notifier)
          .add(
            RecentSearchTrack(
              title: song.title,
              artist: song.artist,
              songId: song.id,
              artwork: song.albumArt,
            ),
          ),
    );
    final notifier = ref.read(playerProvider.notifier);
    final mode = ref.read(appPreferencesProvider).searchPlaybackMode;
    if (mode == 'queue' && ref.read(playerProvider).currentSong != null) {
      final queueIndex = await notifier.addToQueue(song);
      await notifier.playFromQueueIndex(queueIndex);
    } else if (mode == 'library') {
      final library = await _songRepository.getAllSongs();
      if (!mounted) return;
      await notifier.play(song, playlist: library);
    } else {
      await notifier.play(song, playlist: playlist);
    }
  }

  void _openArtist(BuildContext context, String name, List<Song> songs) =>
      unawaited(
        songs.isEmpty
            ? openLokalArtist(context, name: name)
            : pushLokal(context, LokalArtistPage(name: name, songs: songs)),
      );

  void _openAlbum(BuildContext context, AlbumGroup album) =>
      unawaited(pushLokal(context, LokalAlbumPage(album: album)));

  void _openPlaylist(BuildContext context, Playlist playlist) =>
      unawaited(openLokalPlaylist(context, playlist.id));
}

class _SectionHeader extends StatelessWidget {
  final SearchCategory category;
  final int count;
  final bool showSeeAll;
  final bool expanded;
  final VoidCallback onToggle;

  const _SectionHeader({
    required this.category,
    required this.count,
    required this.showSeeAll,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingLg,
          AppConstants.spacingMd,
          AppConstants.spacingLg,
          AppConstants.spacingSm,
        ),
        child: Row(
          children: [
            Icon(category.icon, size: 14, color: context.adaptiveTextTertiary),
            const SizedBox(width: 6),
            Text(
              category.label,
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: context.adaptiveTextSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.glassBackgroundStrong,
                borderRadius: BorderRadius.circular(AppConstants.radiusRound),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontFamily: 'GoogleSansFlex',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: context.adaptiveTextTertiary,
                ),
              ),
            ),
            const Spacer(),
            if (showSeeAll)
              GestureDetector(
                onTap: onToggle,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    expanded ? l10n.showLess : l10n.seeAll,
                    style: TextStyle(
                      fontFamily: 'GoogleSansFlex',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SongTile extends ConsumerWidget {
  final Song song;
  final List<Song> playlistForMode;
  final SongRepository repository;
  final Future<void> Function(Song, List<Song>) onPlay;
  final String? subtitleSuffix;

  const _SongTile({
    required this.song,
    required this.playlistForMode,
    required this.repository,
    required this.onPlay,
    this.subtitleSuffix,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final album = song.album;
    final suffix = subtitleSuffix;
    final artistLabel = creditedLeadArtist(song);
    return LokalSwipeToQueue(
      song: song,
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 48,
            height: 48,
            child: CachedImageWidget(
              imagePath: song.albumArt,
              audioSourcePath: song.filePath,
              fit: BoxFit.cover,
              useThumbnail: true,
              thumbnailWidth: 96,
              thumbnailHeight: 96,
              placeholder: ColoredBox(
                color: AppColors.surface,
                child: FlickArtworkPlaceholder(size: 22, opacity: 0.9),
              ),
              errorWidget: ColoredBox(
                color: AppColors.surface,
                child: FlickArtworkPlaceholder(size: 22, opacity: 0.9),
              ),
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(child: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: context.adaptiveTextPrimary,
              ),
            )),
            if (song.sourceType == 'lokal') ...[
              const SizedBox(width: 7),
              Tooltip(
                message: 'Desktop file · Lokal Link',
                child: Semantics(
                  label: 'Desktop file',
                  child: Icon(Icons.computer_rounded,
                    color: context.adaptiveTextTertiary, size: 16),
                ),
              ),
            ],
          ],
        ),
        // Desktop badge lives beside the search result name.
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              suffix != null && suffix.isNotEmpty
                  ? '${artistLabel}${album != null && album.isNotEmpty ? ' · $album' : ''} · $suffix'
                  : '${artistLabel}${album != null && album.isNotEmpty ? ' · $album' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
                fontSize: 12,
                color: context.adaptiveTextTertiary,
              ),
            ),
            if (catalogueAudioDetails(
                  quality: song.resolution,
                  bitDepth: song.bitDepth,
                  sampleRate: song.sampleRate,
                  codec: song.fileType,
                )
                case final info when info.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  info,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'GoogleSansFlex',
                    fontSize: 10.5,
                    color: context.adaptiveTextTertiary,
                  ),
                ),
              ),
            if (song.atmosAvailable || song.atmosEncoded)
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: LokalAtmosPill(),
                ),
              ),
          ],
        ),
        onTap: () => onPlay(song, playlistForMode),
        onLongPress: () => SongActionsBottomSheet.show(
          context,
          song,
          queueActions: false,
          hideMediaActions: true,
        ),
      ),
    );
  }
}

class _ArtistTile extends ConsumerWidget {
  final String name;
  final List<Song> songs;
  final IconData icon;
  final VoidCallback onTap;

  const _ArtistTile({
    required this.name,
    required this.songs,
    this.icon = LucideIcons.mic,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portrait = ref.watch(artistMetadataProvider.select(
      (paths) => paths[ArtistMetadata.key(name)],
    ));
    final albumCount = songs.map((s) => s.album ?? '').toSet().length;
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surfaceLight,
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: ArtistSearchPortrait(name: name, localPath: portrait),
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'GoogleSansFlex',
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: context.adaptiveTextPrimary,
        ),
      ),
      subtitle: Text(
        l10n.songsAlbums2(songs.length, albumCount),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'GoogleSansFlex',
          fontSize: 12,
          color: context.adaptiveTextTertiary,
        ),
      ),
      trailing: Icon(
        LucideIcons.chevronRight,
        size: 16,
        color: context.adaptiveTextTertiary.withValues(alpha: 0.6),
      ),
      onTap: onTap,
    );
  }
}

class _AlbumTile extends StatelessWidget {
  final AlbumGroup album;
  final VoidCallback onTap;

  const _AlbumTile({required this.album, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final art = album.songs.firstOrNull?.albumArt;
    final path = album.songs.firstOrNull?.filePath;
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 48,
          height: 48,
          child: CachedImageWidget(
            imagePath: art,
            audioSourcePath: path,
            fit: BoxFit.cover,
            useThumbnail: true,
            thumbnailWidth: 96,
            thumbnailHeight: 96,
            placeholder: ColoredBox(
              color: AppColors.surface,
              child: FlickArtworkPlaceholder(size: 22, opacity: 0.9),
            ),
            errorWidget: ColoredBox(
              color: AppColors.surface,
              child: FlickArtworkPlaceholder(size: 22, opacity: 0.9),
            ),
          ),
        ),
      ),
      title: Text(
        album.albumName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'GoogleSansFlex',
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: context.adaptiveTextPrimary,
        ),
      ),
      subtitle: Text(
        l10n.tracks5(album.albumArtist, album.songs.length),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'GoogleSansFlex',
          fontSize: 12,
          color: context.adaptiveTextTertiary,
        ),
      ),
      trailing: Icon(
        LucideIcons.chevronRight,
        size: 16,
        color: context.adaptiveTextTertiary.withValues(alpha: 0.6),
      ),
      onTap: onTap,
    );
  }
}

class _FolderTile extends StatelessWidget {
  final dynamic folder; // FolderGroup
  final VoidCallback onTap;

  const _FolderTile({required this.folder, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = folder.name as String;
    final songs = folder.songs as List<Song>;
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Icon(
          LucideIcons.folder,
          size: 22,
          color: AppColors.accent.withValues(alpha: 0.9),
        ),
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'GoogleSansFlex',
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: context.adaptiveTextPrimary,
        ),
      ),
      subtitle: Text(
        l10n.songs12(songs.length),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'GoogleSansFlex',
          fontSize: 12,
          color: context.adaptiveTextTertiary,
        ),
      ),
      trailing: Icon(
        LucideIcons.play,
        size: 16,
        color: context.adaptiveTextTertiary.withValues(alpha: 0.6),
      ),
      onTap: onTap,
    );
  }
}

class _PlaylistTile extends ConsumerWidget {
  final dynamic playlist; // Playlist
  final VoidCallback onTap;

  const _PlaylistTile({required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = playlist.name as String;
    final count = (playlist.songIds as List).length;
    final songsState = ref.watch(songsProvider).value;
    Widget leading;
    if (songsState != null) {
      final ids = (playlist.songIds as List).cast<String>().toSet();
      final playlistSongs = songsState.songs
          .where((s) => ids.contains(s.id))
          .toList();
      final arts = playlistSongs
          .map((s) => s.albumArt)
          .where((a) => a != null && a.isNotEmpty)
          .cast<String>()
          .take(4)
          .toList();
      if (arts.isEmpty) {
        leading = Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: const FlickArtworkPlaceholder(size: 22, opacity: 0.9),
        );
      } else if (arts.length == 1) {
        leading = ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 48,
            height: 48,
            child: CachedImageWidget(
              imagePath: arts[0],
              fit: BoxFit.cover,
              placeholder: Container(color: AppColors.surfaceLight),
              errorWidget: Container(color: AppColors.surfaceLight),
            ),
          ),
        );
      } else {
        leading = ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 48,
            height: 48,
            child: GridView.count(
              crossAxisCount: 2,
              physics: const NeverScrollableScrollPhysics(),
              children: arts.take(4).map((path) {
                return CachedImageWidget(
                  imagePath: path,
                  fit: BoxFit.cover,
                  placeholder: Container(color: AppColors.surfaceLight),
                  errorWidget: Container(color: AppColors.surfaceLight),
                );
              }).toList(),
            ),
          ),
        );
      }
    } else {
      leading = Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: const FlickArtworkPlaceholder(size: 22, opacity: 0.9),
      );
    }
    return ListTile(
      leading: leading,
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'GoogleSansFlex',
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: context.adaptiveTextPrimary,
        ),
      ),
      subtitle: Text(
        l10n.songs13(count),
        style: TextStyle(
          fontFamily: 'GoogleSansFlex',
          fontSize: 12,
          color: context.adaptiveTextTertiary,
        ),
      ),
      trailing: Icon(
        LucideIcons.chevronRight,
        size: 16,
        color: context.adaptiveTextTertiary.withValues(alpha: 0.6),
      ),
      onTap: onTap,
    );
  }
}
