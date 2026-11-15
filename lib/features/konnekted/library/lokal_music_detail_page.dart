import 'package:flick/features/songs/widgets/song_actions_bottom_sheet.dart';
import 'package:flick/features/library_jobs/artist_metadata.dart';

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flick/features/appearance/lokal_performance_advisor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/core/theme/lokal_appearance.dart';
import 'package:flick/core/theme/lokal_interaction.dart';
import 'package:flick/data/database.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/features/albums/widgets/identify_album_sheet.dart';
import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/discovery/lastfm_discovery.dart';
import 'package:flick/features/discovery/recommendation_match.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/features/konnekted/konnekted_discovery.dart';
import 'package:flick/features/player/widgets/add_to_playlist_sheet.dart';
import 'package:flick/features/player/widgets/artist_credit_links.dart';
import 'package:flick/features/search/library_download.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/favorites_provider.dart';
import 'package:flick/providers/player_provider.dart';
import 'package:flick/providers/app_preferences_provider.dart';
import 'package:flick/services/apple_music/apple_artist_visuals_service.dart';
import 'package:flick/services/apple_music/apple_artist_logo_cache.dart';
import 'package:flick/providers/songs_provider.dart';
import 'package:flick/widgets/common/cached_image_widget.dart';
import 'package:flick/widgets/lokal/lokal_glass.dart';
import 'package:flick/widgets/lokal/lokal_choice_sheet.dart';
import 'package:flick/widgets/lokal/lokal_status_snack.dart';
import 'package:flick/features/link/lokal_ghost_availability.dart';

import 'artist_follow_store.dart';
import 'online_album_store.dart';
import 'lokal_artwork_reveal.dart';
import 'lokal_artist_motion_backdrop.dart';
import 'lokal_detail_header.dart';
import 'lokal_detail_fixed_backdrop.dart';
import 'lokal_detail_scroll_chrome.dart';
import 'lokal_library_groups.dart';
import 'lokal_library_kit.dart';
import 'lokal_online_catalogue.dart';
import 'lokal_online_page_mode.dart';
import 'package:flick/core/utils/album_match.dart';
import 'package:flick/features/discovery/discovery_artwork.dart';
import 'lokal_radio.dart';
import 'package:flick/widgets/lokal/lokal_swipe_to_queue.dart';

class LokalMusicDetailPage extends ConsumerStatefulWidget {
  const LokalMusicDetailPage.artist({
    super.key,
    required String name,
    required this.localSongs,
    this.initialOnline = false,
    this.catalogue,
  }) : title = name,
       artist = name,
       isArtist = true,
       release = null,
       artworkHeroTag = null;
  const LokalMusicDetailPage.album({
    super.key,
    required this.title,
    required this.artist,
    required this.localSongs,
    this.initialOnline = false,
    this.catalogue,
    this.release,
    this.artworkHeroTag,
  }) : isArtist = false;

  final String title, artist;
  final List<Song> localSongs;
  final bool isArtist, initialOnline;
  final LokalCatalogueAlbum? release;
  final LokalOnlineCatalogue? catalogue;
  final String? artworkHeroTag;

  @override
  ConsumerState<LokalMusicDetailPage> createState() =>
      _LokalMusicDetailPageState();
}

class _Entry {
  const _Entry(this.track, this.owned);
  final LokalCatalogueTrack track;
  final Song? owned;
}

/// A partial online album has no reliable total duration.
@visibleForTesting
String? lokalAlbumRunningTime(List<Song?> rowSongs) {
  if (rowSongs.isEmpty || rowSongs.any((song) => song == null)) return null;
  return lokalRunningTime(rowSongs.cast<Song>());
}

class _LokalMusicDetailPageState extends ConsumerState<LokalMusicDetailPage> {
  LokalOnlineCatalogue get _catalogue => widget.catalogue ?? LokalOnlineCatalogue.instance;
  // Detail routes must open at pixel zero, even after an overscroll bounce or
  // reopening the same artist/album. Never restore a previous scroll offset.
  final _scrollController = ScrollController(keepScrollOffset: false);
  final _client = http.Client();
  final _cancel = Completer<void>();
  late final _progress = LokalStatusSnack(
    () => mounted ? context : null,
  );
  LokalCataloguePage? _page;
  Future<void>? _catalogueLoad;
  bool _online = false,
      _loading = false,
      _busy = false,
      _followed = false,
      _savedAlbum = false,
      _albumSaving = false,
      _allSongs = false;
  // Playback already reports its own progress in the player. Keep this out of
  // setState: toggling the shared download/action busy state redraws the page's
  // Play button as a spinner when any Top Songs row is tapped.
  bool _playPending = false;
  String? _portrait, _error;
  AppleArtistVisuals? _artistVisuals;
  String? _visualEvidenceKey;
  int _visualRequest = 0;
  bool _heroInView = true;
  int _request = 0;
  // Heavy library grouping and reconciliation must not run during the first
  // 320ms of an incoming page's route animation. Build the lightweight
  // header and known tracks first, then populate related releases at rest.
  bool _relatedReady = false;
  Animation<double>? _entryAnimation;
  List<Song>? _cachedLibrary;
  List<Song>? _cachedLocal;
  List<AlbumGroup>? _cachedRelated;
  List<Song>? _relatedSource;
  List<_Entry>? _entryCache;
  List<Song>? _entryCacheLocal, _entryCacheLibrary;
  Object? _entryCacheCounts;
  LokalCataloguePage? _entryCachePage;
  bool? _entryCacheOnline, _entryCacheReady;
  String get _identity =>
      '${widget.isArtist ? 'artist' : 'album'}:${recommendationKey(widget.artist)}:${recommendationKey(widget.title)}';
  String get _consentKey => 'lokal.catalogue.online.$_identity';

  @override
  void initState() {
    super.initState();
    LokalPerformanceAdvisor.noteNavigation(surface: 'detail');
    _scrollController.addListener(_updateHeroVisibility);
    OnlineAlbumStore.instance.addListener(_onSavedAlbumsChanged);
    _restore();
  }

  void _onSavedAlbumsChanged() {
    if (mounted && !widget.isArtist) {
      final saved = OnlineAlbumStore.instance.isSaved(widget.title, widget.artist);
      if (saved != _savedAlbum) setState(() => _savedAlbum = saved);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final routeAnimation = ModalRoute.of(context)?.animation;
    if (identical(routeAnimation, _entryAnimation) &&
        (routeAnimation != null || _relatedReady)) return;
    _entryAnimation?.removeStatusListener(_onEntryStatus);
    _entryAnimation = routeAnimation;
    if (routeAnimation == null ||
        routeAnimation.status == AnimationStatus.completed) {
      // Do not call setState during a build.
      WidgetsBinding.instance.addPostFrameCallback((_) => _completeEntry());
    } else {
      routeAnimation.addStatusListener(_onEntryStatus);
    }
  }

  void _onEntryStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _completeEntry();
  }

  void _completeEntry() {
    if (!mounted || _relatedReady) return;
    _entryAnimation?.removeStatusListener(_onEntryStatus);
    setState(() => _relatedReady = true);
    // Let the new build compute the local artist song slice before using it
    // as match evidence; deep-linked artist pages may pass no initial songs.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.isArtist) unawaited(_loadArtistVisuals());
    });
  }

  void _updateHeroVisibility() {
    if (!mounted || !widget.isArtist || !_scrollController.hasClients) return;
    final visible =
        _scrollController.offset < LokalDetailHeader.height(context, isArtist: widget.isArtist);
    if (_heroInView != visible) {
      setState(() => _heroInView = visible);
    }
  }

  Future<void> _loadArtistVisuals() async {
    if (!mounted || !widget.isArtist || !_relatedReady) return;
    final knownLocalSongs = widget.localSongs.isNotEmpty
        ? widget.localSongs
        : (_cachedLocal ?? const <Song>[]);
    final titles = <String>{
      for (final song in knownLocalSongs.take(80)) ...[
        song.title,
        if (song.album?.isNotEmpty == true) song.album!,
      ],
      for (final track in (_page?.tracks ?? <LokalCatalogueTrack>[]).take(40))
        track.metadata.title,
      for (final album in (_page?.albums ?? <LokalCatalogueAlbum>[]).take(40))
        album.title,
    }..removeWhere((title) => title.trim().isEmpty);
    if (titles.isEmpty) return;
    final sortedTitles = titles.map(recommendationKey).toList()..sort();
    final key = '${recommendationKey(widget.artist)}|${sortedTitles.join('|')}';
    if (_visualEvidenceKey == key) return;
    _visualEvidenceKey = key;
    final request = ++_visualRequest;
    final result = await AppleArtistVisualsService.instance.lookup(
      artistName: widget.artist,
      knownTitles: titles,
    );
    if (mounted && request == _visualRequest) {
      setState(() => _artistVisuals = result);
    }
  }

  @override
  void didUpdateWidget(covariant LokalMusicDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title ||
        oldWidget.artist != widget.artist ||
        oldWidget.isArtist != widget.isArtist) {
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      _cachedLibrary = null;
      _cachedLocal = null;
      _cachedRelated = null;
      _relatedSource = null;
      _entryCache = null;
      _artistVisuals = null;
      _visualEvidenceKey = null;
      ++_visualRequest;
      _onSavedAlbumsChanged();
      if (_relatedReady && widget.isArtist) unawaited(_loadArtistVisuals());
    }
  }

  List<Song> _localOnce(List<Song> library) {
    if (identical(library, _cachedLibrary) && _cachedLocal != null) {
      return _cachedLocal!;
    }
    _cachedLibrary = library;
    _cachedRelated = null;
    _relatedSource = null;
    return _cachedLocal = _local(library);
  }

  List<AlbumGroup> _relatedOnce(List<Song> library, List<Song> local) {
    if (identical(_relatedSource, library) && _cachedRelated != null) {
      return _cachedRelated!;
    }
    final artist = recommendationKey(widget.artist);
    // Album pages used to regroup/sort the ENTIRE library on every build,
    // including every tint/online-state update, while the route was entering.
    // Only this artist's releases are relevant to the UI.
    final relevant = widget.isArtist
        ? local
        : library.where((song) =>
            recommendationKey(song.albumArtist ?? song.artist) == artist).toList();
    final albums = lokalAlbums(relevant)
        .where((album) => widget.isArtist ||
            recommendationKey(album.albumArtist) == artist)
        .toList()
      ..sort((a, b) => (b.songs.first.year ?? 0)
          .compareTo(a.songs.first.year ?? 0));
    _relatedSource = library;
    return _cachedRelated = albums;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    await ArtistFollowStore.instance.load();
    if (!widget.isArtist) await OnlineAlbumStore.instance.load();
    if (!mounted) return;
    setState(() {
      _followed = ArtistFollowStore.instance.isFollowed(widget.artist);
      _savedAlbum = !widget.isArtist &&
          OnlineAlbumStore.instance.isSaved(widget.title, widget.artist);
    });
    if (widget.isArtist && Database.isInitialized) {
      try {
        final row = await Database.artists
            .filter()
            .nameEqualTo(widget.artist, caseSensitive: false)
            .findFirst();
        if (mounted) setState(() => _portrait = row?.artPath);
      } catch (_) {
        /* A missing portrait never blocks opening the page. */
      }
    }
    if (!mounted) return;
    if (shouldOpenLibraryPageOnline(
      initialOnline: widget.initialOnline,
      pagePreference: prefs.getBool(_consentKey),
      defaultOnline: prefs.getBool(onlinePagesDefaultPreferenceKey) ?? true,
    )) {
      setState(() => _online = true);
      _load();
    }
  }

  /// Persist resolved artist portraits for future visits without changing the
  /// page's background color. A late palette extraction used to abruptly
  /// recolor the entire screen while the route was still opening.
  Future<void> _cacheOnlinePortrait(String path) async {
    if (!widget.isArtist || !Database.isInitialized || !_online) return;
    try {
      // Consult the persistent artist row before downloading anything.
      // Spotify follows that were already cached should not re-fetch covers
      // on every artist-page visit.
      final previous = await Database.artists
          .filter()
          .nameEqualTo(widget.artist, caseSensitive: false)
          .findFirst();
      if (previous?.artPath?.isNotEmpty == true &&
          await File(previous!.artPath!).exists()) {
        // Migrate existing cached images to permanent storage when revisited.
        final savedRow = previous!;
        final durable = await persistArtistPortraitFile(
          widget.artist, savedRow.artPath!,
        );
        if (durable != savedRow.artPath) {
          savedRow.artPath = durable;
          await Database.instance.writeTxn(
            () => Database.artists.put(savedRow),
          );
        }
        if (!mounted) return;
        ref.read(artistMetadataProvider.notifier).publishSavedPortrait(
          widget.artist, durable,
        );
        return;
      }
      if (!mounted || !_online) return;
      if (path.startsWith('http')) {
        final fetched = (await DefaultCacheManager().getSingleFile(path)).path;
        path = await persistArtistPortraitFile(widget.artist, fetched);
      }
      if (!mounted || !_online) return;
      final artist = previous ?? (ArtistEntity()..name = widget.artist);
      artist.artPath = path;
      await Database.instance.writeTxn(() => Database.artists.put(artist));
      if (mounted) {
        ref.read(artistMetadataProvider.notifier).publishSavedPortrait(
          widget.artist, path,
        );
        setState(() => _portrait = path);
      }
    } catch (_) {
      // Portrait persistence must never interrupt navigation.
    }
  }

  Future<void> _setOnline(bool value) async {
    if (_busy || _loading || value == _online) return;
    setState(() => _online = value);
    ++_request;
    await (await SharedPreferences.getInstance()).setBool(_consentKey, value);
    if (!mounted) return;
    if (value) {
      await _load();
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _load({bool refresh = false}) {
    final work = _loadCatalogue(refresh: refresh);
    _catalogueLoad = work;
    return work;
  }

  Future<void> _loadCatalogue({bool refresh = false}) async {
    if (!_online) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await (widget.isArtist
          ? _catalogue.artist(
              widget.artist,
              refresh: refresh,
            )
          : _catalogue.album(
              widget.title,
              widget.artist,
              release: widget.release,
              refresh: refresh,
            ));
      if (!mounted || !_online || request != _request) return;
      setState(() => _page = page);
      final image = widget.isArtist
          ? page.portrait
          : page.albums.firstOrNull?.artwork;
      if (widget.isArtist && image?.isNotEmpty == true) {
        unawaited(_cacheOnlinePortrait(image!));
      }
      if (widget.isArtist) unawaited(_loadArtistVisuals());
    } catch (error) {
      if (mounted && _online && request == _request) {
        final message = discoveryError(error);
        setState(() => _error = message);
        // The large catalogue panel was removed. Preserve failure feedback
        // without reintroducing a row or a label beside the header icon.
        _progress.fail(message);
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  List<Song> _local(List<Song> library) {
    final artist = recommendationKey(widget.artist);
    final wantedTitle = albumTitleKey(widget.title);
    final found = library
        .where(
          (song) => widget.isArtist
              ? (recommendationKey(song.albumArtist ?? song.artist) == artist ||
                  recommendationKey(song.artist) == artist ||
                  catalogueArtistCredit(song.artist, widget.artist))
              : wantedTitle.isNotEmpty &&
                  albumTitleKey(song.album ?? '') == wantedTitle &&
                  albumArtistsMatch(widget.artist, song.albumArtist ?? song.artist),
        )
        .toList();
    return found;
  }

  List<_Entry> _entries(
    List<Song> library, List<Song> local, Map<String, int> counts, {
    bool matchLibrary = false,
  }) {
    // Rebuilding the hero (online toggle, artwork resolution, favorites) must
    // not re-sort every song or reconstruct the global catalogue match index.
    // Use object identity; repository/provider updates create new snapshots.
    final ready = _relatedReady || matchLibrary;
    if (_entryCache != null &&
        identical(local, _entryCacheLocal) &&
        identical(library, _entryCacheLibrary) &&
        identical(counts, _entryCacheCounts) &&
        identical(_page, _entryCachePage) &&
        _entryCacheOnline == _online &&
        _entryCacheReady == ready) {
      return _entryCache!;
    }
    final seen = <String>{};
    final seenOwned = <String>{};
    final rows = <_Entry>[];
    if (_online)
      for (final track in _page?.tracks ?? <LokalCatalogueTrack>[]) {
        if (!seen.add(track.metadata.key)) continue;
        // Even a cached online catalogue can return during the push.
        // Delay the first global match-index construction until the page
        // settles; entries are rematched in the next build.
        final owned = ready
            ? KonnektedLibraryIndex.of(library).match(track.metadata)
            : null;
        if (owned != null) seenOwned.add(owned.id);
        rows.add(_Entry(track, owned));
      }
    final ordered = List<Song>.of(local)
      ..sort((a, b) {
        if (widget.isArtist)
          return (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0);
        final disc = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
        return disc != 0
            ? disc
            : (a.trackNumber ?? 999).compareTo(b.trackNumber ?? 999);
      });
    for (final song in ordered) {
      final metadata = LokalDiscoveryTrack(
        title: song.title,
        artist: song.artist,
        album: song.album ?? '',
        artworkUrl: song.albumArt ?? '',
        duration: song.duration,
      );
      if (seen.add(metadata.key) && seenOwned.add(song.id))
        rows.add(
          _Entry(
            LokalCatalogueTrack(
              metadata,
              number: song.trackNumber,
              disc: song.discNumber,
            ),
            song,
          ),
        );
    }
    _entryCacheLocal = local;
    _entryCacheLibrary = library;
    _entryCacheCounts = counts;
    _entryCachePage = _page;
    _entryCacheOnline = _online;
    _entryCacheReady = ready;
    return _entryCache = rows;
  }

  // Online album actions must not capture the local-only rows painted while
  // the catalogue is loading. Wait for that request, then use the latest
  // full list, with owned files kept in their published positions.
  Future<List<_Entry>> _actionRows() async {
    while (_online && _catalogueLoad != null) {
      final work = _catalogueLoad!;
      await work;
      if (!mounted) return const [];
      if (identical(work, _catalogueLoad)) break;
    }
    if (!mounted) return const [];
    if (_online && (_error != null || _page?.tracks.isNotEmpty != true)) {
      throw DiscoveryException(_error ?? 'No online tracks found.');
    }
    final library =
        ref.read(konnektedLibraryProvider).value ?? widget.localSongs;
    return _entries(
      library,
      _localOnce(library),
      ref.read(lokalPlayCountsProvider).value ?? const {},
      matchLibrary: true,
    );
  }

  Future<Song> _prepare(_Entry entry) async {
    if (entry.owned != null) {
      if (entry.owned!.sourceType != 'lokal' ||
          await ref.read(lokalSongAvailableProvider(entry.owned!).future))
        return entry.owned!;
      if (!_online)
        throw const DiscoveryException(
          'This desktop song is offline and has not been downloaded.',
        );
    }
    final song = await prepareCatalogueTrack(
      entry.track,
      cancel: _cancel.future,
      onStatus: (text) {
        if (mounted) _progress.update(text);
      },
    );
    if (song == null)
      throw const DiscoveryException(
        'This recording could not be found on your playback sources.',
      );
    return song;
  }

  Future<void> _play(
    List<_Entry> rows, {
    int? start,
    bool shuffle = false,
  }) async {
    if (rows.isEmpty || _busy || _playPending) return;
    // Prevent duplicate concurrent play requests without rebuilding the
    // entire artist/album page or momentarily disabling its header controls.
    _playPending = true;
    final selected = start == null ? null : rows[start].track.metadata.key;
    try {
      final ordered = List<_Entry>.of(
        widget.isArtist ? rows : await _actionRows(),
      );
      if (ordered.isEmpty || !mounted) return;
      var selectedIndex = selected == null
          ? 0
          : ordered.indexWhere((entry) => entry.track.metadata.key == selected);
      if (selectedIndex < 0) return;
      if (shuffle) {
        ordered.shuffle();
        selectedIndex = 0;
      }
      final queue = [
        for (final entry in ordered) entry.owned ?? entry.track.pending(),
      ];
      await ref
          .read(playerProvider.notifier)
          .play(
            queue[selectedIndex],
            playlist: queue,
            playlistIndex: selectedIndex,
          );
      _progress.clear();
    } catch (error) {
      if (mounted) _progress.fail(discoveryError(error));
    } finally {
      _playPending = false;
    }
  }

  Future<void> _download(List<_Entry> rows) async {
    if (_busy) return;
    final missing = rows.where((row) => row.owned == null).toList();
    if (missing.isEmpty) return;
    setState(() => _busy = true);
    var saved = 0;
    try {
      for (final row in missing) {
        if (!mounted || _cancel.isCompleted) break;
        _progress.update(
          lokalText(
            'Downloading {title}…',
            args: {'title': row.track.metadata.title},
          ),
        );
        final song = await _prepare(row);
        if (!mounted) break;
        await LibraryDownloader().save(
          song,
          artwork: row.track.metadata.artworkUrl.isEmpty
              ? null
              : row.track.metadata.artworkUrl,
        );
        saved++;
        ref.invalidate(songsProvider);
      }
      if (mounted)
        _progress.fail(
          lokalText(
            'Saved {count} songs to your library.',
            args: {'count': saved},
          ),
        );
    } catch (error) {
      if (mounted)
        _progress.fail(
          lokalText(
            'Saved {count} songs. {error}',
            args: {'count': saved, 'error': discoveryError(error)},
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    try {
      final box = context.findRenderObject();
      await SharePlus.instance.share(
        ShareParams(
          text:
              '${widget.title}${widget.isArtist ? '' : ' — ${widget.artist}'}\n${_online && _page?.url.isNotEmpty == true ? _page!.url : 'Konnekted'}',
          sharePositionOrigin: box is RenderBox && box.hasSize
              ? box.localToGlobal(Offset.zero) & box.size
              : null,
        ),
      );
    } catch (error) {
      if (mounted) _progress.fail(lokalText('Could not share this page.'));
    }
  }

  @override
  void dispose() {
    _entryAnimation?.removeStatusListener(_onEntryStatus);
    OnlineAlbumStore.instance.removeListener(_onSavedAlbumsChanged);
    ++_request;
    ++_visualRequest;
    _cancel.complete();
    _client.close();
    _scrollController.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final library =
        ref.watch(konnektedLibraryProvider).value ?? widget.localSongs;
    // Known local songs render immediately. Full-library reconciliation is
    // deferred until entry completes, avoiding a multi-thousand-song scan in
    // the middle of the incoming animation.
    final local = !_relatedReady
        ? widget.localSongs
        : _localOnce(library);
    final rows = _entries(
      library, local, ref.watch(lokalPlayCountsProvider).value ?? const {},
    );
    final year = local.where((song) => song.year != null).firstOrNull?.year ??
        widget.release?.year;
    final runningTime = lokalAlbumRunningTime(
      rows.map((row) => row.owned).toList(),
    );
    final groups = _relatedReady
        ? _relatedOnce(library, local)
        : const <AlbumGroup>[];
    final albums = <LokalCatalogueAlbum>[];
    final albumIds = <String>{};
    final onlineTitles = <String>{};
    if (_online) {
      for (final album in _page?.albums ?? <LokalCatalogueAlbum>[]) {
        final title = recommendationKey(album.title);
        // Do not collapse distinct official editions solely because they
        // share a title. Artist lookup can return several release IDs.
        if (album.id?.isNotEmpty == true && !albumIds.add(album.id!)) continue;
        if (album.id?.isNotEmpty != true && !onlineTitles.add(title)) continue;
        onlineTitles.add(title);
        albums.add(album);
      }
    }
    for (final group in groups) {
      if (onlineTitles.add(recommendationKey(group.albumName)))
        albums.add(
          LokalCatalogueAlbum(
            title: group.albumName,
            artist: group.albumArtist,
            artwork:
                group.songs
                    .where((s) => s.albumArt?.isNotEmpty == true)
                    .firstOrNull
                    ?.albumArt ??
                '',
            date: group.songs.first.year == null
                ? null
                : '${group.songs.first.year}-01-01',
            releaseKind:
                widget.isArtist &&
                    !cataloguePrimaryArtist(group.albumArtist, widget.artist)
                ? LokalReleaseKind.feature
                : null,
          ),
        );
    }
    final localArtworkSong = local
        .where((song) => song.albumArt?.isNotEmpty == true)
        .firstOrNull ?? local.firstOrNull;
    final localCover = localArtworkSong?.albumArt;
    final cachedPortrait = widget.isArtist
        ? ref.watch(
            artistMetadataProvider.select(
              (paths) => paths[ArtistMetadata.key(widget.artist)],
            ),
          )
        : null;
    final heroImage = widget.isArtist
        ? (_artistVisuals?.heroUrl ?? cachedPortrait ??
              (_portrait?.isNotEmpty == true
                  ? _portrait
                  : _online
                  ? _page?.portrait
                  : null))
        : ((_online && _page?.albums.firstOrNull?.artwork.isNotEmpty == true
                  ? _page!.albums.first.artwork : null) ??
              localCover ?? widget.release?.artwork);
    final moreAlbums = albums
        .where(
          (album) =>
              recommendationKey(album.title) != recommendationKey(widget.title),
        )
        .toList();
    // Stable theme color is intentional: asynchronous palette extraction
    // previously repainted the entire hero in a bright flash mid-transition.
    final pageColor = t.bg;
    final show = widget.isArtist && !_allSongs ? rows.take(5).toList() : rows;
    final liked = ref.watch(favoritesProvider).value;
    final allLiked = local.isNotEmpty &&
        local.every((song) => liked?.isFavorite(song.id) == true);

    // The existing image-resolution chain is retained for online albums,
    // network/NAS artwork, cached artist portraits and local fallback art.
    final Widget heroArtwork;
    if (_online && !widget.isArtist && _page != null) {
      heroArtwork = DiscoveryArtwork(
        kind: DiscoveryArtworkKind.album,
        title: widget.title,
        artist: widget.artist,
        url: discoveryImageUrl(heroImage),
        revealOnLoad: true,
        placeholder: localCover?.isNotEmpty == true
            ? CachedImageWidget(
                imagePath: localCover,
                audioSourcePath: localArtworkSong?.filePath,
                fit: BoxFit.cover,
                errorWidget: ColoredBox(color: pageColor),
              )
            : ColoredBox(color: pageColor),
      );
    } else if (heroImage?.isNotEmpty == true) {
      heroArtwork = CachedImageWidget(
        imagePath: heroImage,
        audioSourcePath: widget.isArtist ? null : localArtworkSong?.filePath,
        fit: BoxFit.cover,
        revealOnLoad: true,
        // Decoding at the *actual rendered size* stays stable across route
        // completion. Switching cacheWidth at ~320ms caused a second decode
        // and visible image flash on album/artist pages.
        // Never display a track/featured-album cover under an artist's
        // portrait. A slow remote portrait must resolve against the theme,
        // not briefly masquerade as the artist's editorial image.
        placeholder: ColoredBox(color: pageColor),
        errorWidget: ColoredBox(color: pageColor),
      );
    } else if (!widget.isArtist && local.isNotEmpty) {
      // Album pages may use an owned recording's cover as their fallback.
      // Artist pages may not: album art is not an artist portrait.
      heroArtwork = CachedImageWidget(
        imagePath: localCover,
        audioSourcePath: localArtworkSong?.filePath ?? local.first.filePath,
        fit: BoxFit.cover,
        revealOnLoad: true,
        placeholder: ColoredBox(color: pageColor),
        errorWidget: ColoredBox(color: pageColor),
      );
    } else {
      heroArtwork = ColoredBox(
        color: pageColor,
        child: Center(
          child: Icon(
            widget.isArtist ? Icons.person_rounded : Icons.album_rounded,
            size: 110,
            color: t.muted2.withValues(alpha: .4),
          ),
        ),
      );
    }
    final prefs = ref.watch(appPreferencesProvider);
    final motionUrl = widget.isArtist ? _artistVisuals?.motionUrl : null;
    final artistArtwork = motionUrl == null
        ? heroArtwork
        : LokalArtistMotionBackdrop(
            url: motionUrl,
            fallback: heroArtwork,
            enabled: prefs.animatedAlbumArt && prefs.animationsEnabled,
            playbackActive:
                _heroInView && (ModalRoute.of(context)?.isCurrent ?? true),
          );
    final stagedArtwork = LokalArtworkReveal(
      // Artist identity must never be derived from local album artwork:
      // the first frame is the neutral hero until actual portrait arrives.
      identity: widget.isArtist
          ? 'artist:${recommendationKey(widget.artist)}:${heroImage ?? ''}'
          : 'album:${heroImage ?? localCover ?? ''}',
      // A full-bleed BoxFit.cover already fits square/non-square portraits
      // without adding bars. Re-decoding each file for automatic cropping
      // was redundant for verified editorial images and could cause jank.
      child: artistArtwork,
    );
    final heroHeight = LokalDetailHeader.height(context, isArtist: widget.isArtist);
    final diskLogo = widget.isArtist
        ? AppleArtistLogoCache.instance.cachedFor(widget.artist)
        : null;
    final performanceMode = ref.watch(
      lokalAppearanceProvider.select((appearance) =>
          appearance.performanceMode || appearance.ultraPerformanceMode),
    );
    return Scaffold(
      backgroundColor: pageColor,
      body: Stack(
        children: [
          // Artwork sits outside the scrolling slivers and stays fixed under
          // the system status bar. Both detail types share the same crop.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: heroHeight,
            child: IgnorePointer(
              child: LokalDetailFixedBackdrop(
                artwork: stagedArtwork,
                background: pageColor,
              ),
            ),
          ),
          // A separate, eased UI wash replaces the narrow masked-image strip.
          // It is not an image filter; the still/video hero remains untouched.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: heroHeight,
            child: LokalDetailHeroWash(background: pageColor),
          ),
          Positioned.fill(
            child: CustomScrollView(
              controller: _scrollController,
              primary: false,
              slivers: [
          SliverToBoxAdapter(
            child: LokalDetailHeader(
              title: widget.title,
              artwork: stagedArtwork,
              isArtist: widget.isArtist,
              fixedArtwork: true,
              controlsInOverlay: true,
              background: pageColor,
              artworkHeroTag: widget.artworkHeroTag,
              artistLogoPath: widget.isArtist
                  ? (diskLogo?.path ?? _artistVisuals?.logoLocalPath)
                  : null,
              artistLogoAspect: diskLogo?.aspect ?? _artistVisuals?.logoAspect ?? 1,
              metadata: widget.isArtist
                  ? (local.isEmpty ? null : lokalSongCount(local.length))
                  : [
                      if (year != null) '$year',
                      lokalSongCount(rows.length),
                      if (runningTime != null) runningTime,
                    ].join('  ·  '),
              onArtworkTap: () {
                final image = heroImage?.isNotEmpty == true
                    ? heroImage
                    : widget.isArtist ? null : localCover;
                if (image == null || image.isEmpty) return;
                showDialog<void>(
                  context: context,
                  barrierColor: Colors.black,
                  builder: (viewerContext) => Dialog.fullscreen(
                    backgroundColor: Colors.black,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        InteractiveViewer(
                          minScale: 1,
                          maxScale: 5,
                          child: Center(
                            child: CachedImageWidget(
                              imagePath: image,
                              audioSourcePath: widget.isArtist
                                  ? null : localArtworkSong?.filePath,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        Positioned(
                          top: MediaQuery.paddingOf(viewerContext).top + 12,
                          left: 16,
                          child: IconButton.filledTonal(
                            tooltip: l10n.back,
                            onPressed: () => Navigator.of(viewerContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              onBack: () => Navigator.of(context).maybePop(),
              onlineEnabled: _online,
              onlineLoading: _loading,
              onlineDisabled: _busy,
              onOnline: () => unawaited(_setOnline(!_online)),
              onMore: () => unawaited(_showMenu(rows, local, allLiked)),
              artistCredit: widget.isArtist ? null : ArtistCreditLinks(
                credit: widget.artist,
                style: TextStyle(fontSize: 17, color: t.accent),
                onArtistTap: (artist) => pushLokal(
                  context,
                  LokalMusicDetailPage.artist(
                    name: artist,
                    localSongs: KonnektedLibraryIndex.of(library).artist(artist),
                    initialOnline: _online,
                  ),
                ),
              ),
            ),
          ),
          // After the hero, the scrolling page is opaque. It passes across
          // the stationary image without exposing wallpaper behind song rows.
          DecoratedSliver(
            decoration: BoxDecoration(color: pageColor),
            sliver: SliverMainAxisGroup(
              slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: rows.isEmpty || _busy ? null : () => _play(rows),
                          // Busy here may mean a download or menu action, not
                          // header playback. Never flash the Play icon.
                          icon: const Icon(Icons.play_arrow_rounded, size: 27),
                          label: Text(
                            l10n.play,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: t.accent,
                            foregroundColor: t.onAccent,
                            minimumSize: const Size(0, 56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(19),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _control(
                        Icons.shuffle_rounded,
                        l10n.shuffle,
                        rows.isEmpty || _busy ? null : () => _play(rows, shuffle: true),
                      ),
                      const SizedBox(width: 12),
                      _control(
                        widget.isArtist
                            ? (_followed ? Icons.star_rounded : Icons.star_border_rounded)
                            : (_savedAlbum ? Icons.favorite_rounded : Icons.favorite_border_rounded),
                        widget.isArtist
                            ? (_followed ? lokalText('Unfollow artist') : lokalText('Follow artist'))
                            : (_savedAlbum ? lokalText('Remove from Albums') : lokalText('Save to Albums')),
                        _albumSaving || _busy
                            ? null
                            : () => widget.isArtist ? _follow() : _saveAlbum(
                                  LokalCatalogueAlbum(
                                    title: widget.title, artist: widget.artist,
                                    artwork: heroImage ?? '',
                                    id: (_page?.albums.firstOrNull ?? widget.release)?.id,
                                    date: (_page?.albums.firstOrNull ?? widget.release)?.date,
                                    trackCount: (_page?.albums.firstOrNull ?? widget.release)?.trackCount,
                                    url: (_page?.albums.firstOrNull ?? widget.release)?.url ?? '',
                                    releaseKind: (_page?.albums.firstOrNull ?? widget.release)?.releaseKind,
                                  ),
                                ),
                      ),
                    ],
                  ),

                ],
              ),
            ),
          ),
          if (widget.isArtist && albums.isNotEmpty)
            SliverToBoxAdapter(
              child: _recentRelease(albums.first, groups, library),
            ),
          SliverToBoxAdapter(
            child: LokalSectionTitle(
              title: widget.isArtist
                  ? lokalText('Top songs')
                  : lokalText('Songs'),
              onSeeAll: widget.isArtist && rows.length > 5
                  ? () => setState(() => _allSongs = !_allSongs)
                  : null,
              actionLabel: widget.isArtist && _allSongs
                  ? lokalText('Hide')
                  : null,
            ),
          ),
          if (show.isEmpty && !_loading)
            SliverToBoxAdapter(
              child: LokalEmptyState(
                icon: Icons.music_note_rounded,
                title: lokalText('Nothing here yet'),
                message: lokalText(
                  _online
                      ? (_error ?? 'No matching tracks found. Try refreshing the catalogue.')
                      : 'Enable online mode to discover songs and releases.',
                ),
              ),
            ),
          SliverList.builder(
            itemCount: show.length,
            itemBuilder: (context, index) =>
                _trackRow(show[index], rows, index),
          ),
          for (final kind in LokalReleaseKind.values)
            if (widget.isArtist &&
                albums.any((album) => album.kind == kind)) ...[
              SliverToBoxAdapter(
                child: LokalSectionTitle(
                  title: switch (kind) {
                    LokalReleaseKind.album => l10n.albums,
                    LokalReleaseKind.ep => lokalText('EPs'),
                    LokalReleaseKind.single => lokalText('Singles'),
                    LokalReleaseKind.compilation => lokalText('Compilations'),
                    LokalReleaseKind.live => lokalText('Live'),
                    LokalReleaseKind.feature => lokalText('Features'),
                    LokalReleaseKind.unknown => lokalText('Unknown albums'),
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 238,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: albums
                        .where((album) => album.kind == kind)
                        .length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (context, index) => SizedBox(
                      width: 156,
                      child: _albumCard(
                        albums
                            .where((album) => album.kind == kind)
                            .elementAt(index),
                        groups,
                        library,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          if (!widget.isArtist && rows.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Text(
                  lokalSongCount(rows.length),
                  style: TextStyle(color: t.muted, fontSize: 13),
                ),
              ),
            ),
          if (!widget.isArtist && moreAlbums.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: LokalSectionTitle(
                title: lokalText(
                  'More by {artist}',
                  args: {'artist': widget.artist},
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 238,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: moreAlbums.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, index) => SizedBox(
                    width: 156,
                    child: _albumCard(moreAlbums[index], groups, library),
                  ),
                ),
              ),
            ),
          ],
          if (widget.isArtist &&
              _online &&
              _page?.biography?.isNotEmpty == true)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _page!.biography!,
                  style: TextStyle(color: t.muted, height: 1.5),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
          ),
              ],
            ),
          ),
              ],
            ),
          ),
          // BitChord-style top frost samples the scrolling UI beneath it.
          // It belongs above the scroll view and remains while the hero exits.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LokalDetailProgressiveTopBlur(
              scrollController: _scrollController,
              heroHeight: heroHeight,
              background: pageColor,
              dynamicBlur: !performanceMode,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LokalDetailFloatingControls(
              title: widget.title,
              scrollController: _scrollController,
              heroHeight: heroHeight,
              onBack: () => Navigator.of(context).maybePop(),
              onlineEnabled: _online,
              onlineLoading: _loading,
              onlineDisabled: _busy,
              onOnline: () => unawaited(_setOnline(!_online)),
              onMore: () => unawaited(_showMenu(rows, local, allLiked)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _control(IconData icon, String label, VoidCallback? onTap) => Tooltip(
    message: label,
    child: LokalGlassButton(
      size: 56,
      semanticLabel: label,
      onPressed: onTap,
      child: Icon(
        icon,
        color: onTap == null ? context.lokal.muted2 : context.lokal.text,
        size: 26,
      ),
    ),
  );

  Future<void> _follow() async {
    final next = !_followed;
    try {
      await ArtistFollowStore.instance.setFollowed(widget.artist, next);
      if (mounted) setState(() => _followed = next);
    } catch (error) {
      if (mounted) _progress.fail(discoveryError(error));
    }
  }

  Future<void> _saveAlbum(LokalCatalogueAlbum album) async {
    if (_albumSaving) return;
    setState(() => _albumSaving = true);
    try {
      await OnlineAlbumStore.instance.setSaved(album, !_savedAlbum);
      if (mounted) {
        _progress.success(_savedAlbum
            ? lokalText('Saved to Albums.')
            : lokalText('Removed from Albums.'));
      }
    } catch (error) {
      if (mounted) _progress.fail(discoveryError(error));
    } finally {
      if (mounted) setState(() => _albumSaving = false);
    }
  }

  Future<void> _like(List<Song> songs, bool value) async {
    final notifier = ref.read(favoritesProvider.notifier);
    for (final song in songs) {
      if (value) {
        await notifier.addFavorite(song.id, song: song);
      } else {
        await notifier.removeFavorite(song.id);
      }
    }
  }

  Future<void> _showMenu(
    List<_Entry> rows,
    List<Song> local,
    bool allLiked,
  ) async {
    final value = await showLokalChoiceSheet<String>(
      context: context,
      title: widget.title,
      choices: [
        if (local.isNotEmpty)
          LokalChoice(value: 'playlist',
            label: lokalText('Add to a playlist'), icon: Icons.playlist_add_rounded),
        if (local.isNotEmpty)
          LokalChoice(value: 'like',
            label: allLiked ? lokalText('Unlike all') : lokalText('Like all'),
            icon: allLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded),
        if (rows.isNotEmpty || (_online && _loading))
          LokalChoice(value: 'queue', label: lokalText('Add to queue'),
            icon: Icons.queue_music_rounded),
        if (!widget.isArtist && local.isNotEmpty)
          LokalChoice(value: 'identify', label: lokalText('Identify album'),
            icon: Icons.album_rounded),
        if (_online && !_loading)
          LokalChoice(value: 'refresh',
            label: lokalText('Refresh online catalogue'), icon: Icons.refresh_rounded),
        if (_online && rows.any((row) => row.owned == null))
          LokalChoice(value: 'download',
            label: lokalText('Download missing songs'), icon: Icons.download_rounded),
        LokalChoice(value: 'share', label: l10n.share, icon: Icons.ios_share_rounded),
        LokalChoice(value: 'radio', label: lokalText('Start artist radio'),
          icon: Icons.radio_rounded),
      ],
    );
    if (value != null && mounted) await _menu(value, rows, local, allLiked);
  }

  Future<void> _menu(
    String value,
    List<_Entry> rows,
    List<Song> local,
    bool allLiked,
  ) async {
    if (_busy) return;
    try {
      switch (value) {
        case 'playlist':
          await AddToPlaylistSheet.showSongs(context, local);
        case 'like':
          await _like(local, !allLiked);
        case 'queue':
          setState(() => _busy = true);
          try {
            final album = await _actionRows();
            if (!mounted) return;
            final player = ref.read(playerProvider.notifier);
            for (final row in album) {
              await player.addToQueue(row.owned ?? row.track.pending());
            }
          } finally {
            if (mounted) setState(() => _busy = false);
          }
        case 'identify':
          await IdentifyAlbumSheet.show(
            context,
            songs: local,
            initialArtist: widget.artist,
            initialAlbum: widget.title,
          );
        case 'refresh':
          await _load(refresh: true);
        case 'download':
          await _download(rows);
        case 'share':
          await _share();
        case 'radio':
          await startLokalRadio(context, artist: widget.artist);
      }
    } catch (error) {
      if (mounted) _progress.fail(discoveryError(error));
    }
  }

  List<Song> _albumSongs(LokalCatalogueAlbum album, List<AlbumGroup> groups) =>
      groups
          .where(
            (group) =>
                recommendationKey(group.albumName) ==
                    recommendationKey(album.title) &&
                recommendationKey(group.albumArtist) ==
                    recommendationKey(album.artist),
          )
          .firstOrNull
          ?.songs ??
      const [];

  void _openAlbum(LokalCatalogueAlbum album, List<AlbumGroup> groups) {
    pushLokal(
      context,
      LokalMusicDetailPage.album(
        title: album.title,
        artist: album.artist,
        localSongs: _albumSongs(album, groups),
        initialOnline: _online,
        release: album,
      ),
    );
  }

  Widget _releaseArt(
    LokalCatalogueAlbum album,
    List<Song> songs,
    double size,
  ) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: SizedBox.square(
      dimension: size,
      child: CachedImageWidget(
        imagePath: album.artwork.isEmpty
            ? songs.firstOrNull?.albumArt
            : album.artwork,
        audioSourcePath: songs.firstOrNull?.filePath,
        fit: BoxFit.cover,
        placeholder: ColoredBox(
          color: context.lokal.surface2,
          child: Icon(Icons.album_rounded, color: context.lokal.muted),
        ),
        errorWidget: ColoredBox(
          color: context.lokal.surface2,
          child: Icon(Icons.album_rounded, color: context.lokal.muted),
        ),
      ),
    ),
  );

  String _ownership(LokalCatalogueAlbum album, List<Song> songs) {
    if (songs.isEmpty) return '';
    if (album.trackCount != null && songs.length >= album.trackCount!)
      return lokalText('In library');
    return album.trackCount == null
        ? lokalSongCount(songs.length)
        : lokalText(
            '{owned}/{total} in library',
            args: {'owned': songs.length, 'total': album.trackCount},
          );
  }

  Widget _recentRelease(
    LokalCatalogueAlbum album,
    List<AlbumGroup> groups,
    List<Song> library,
  ) {
    final t = context.lokal, songs = _albumSongs(album, groups);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Material(
        color: t.surface.withValues(alpha: .65),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: t.muted2.withValues(alpha: .2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openAlbum(album, groups),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _releaseArt(album, songs, 80),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.year?.toString() ??
                            (album.date == null
                                ? lokalText('Featured album')
                                : lokalText('Recent release')),
                        style: TextStyle(color: t.muted, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        album.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _ownership(album, songs).isEmpty
                            ? (album.date == null
                                  ? lokalText('Featured album')
                                  : lokalText('Recent release'))
                            : _ownership(album, songs),
                        style: TextStyle(color: t.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip:
                      !_online ||
                          (album.trackCount != null &&
                              songs.length >= album.trackCount!)
                      ? lokalText('Add to a playlist')
                      : lokalText('Add to library'),
                  onPressed: _busy
                      ? null
                      : () async {
                          if (!_online ||
                              (album.trackCount != null &&
                                  songs.length >= album.trackCount!)) {
                            if (songs.isNotEmpty)
                              await AddToPlaylistSheet.showSongs(
                                context,
                                songs,
                              );
                          } else {
                            await _downloadRelease(album, library);
                          }
                        },
                  icon: Icon(Icons.add_rounded, color: t.text),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _downloadRelease(
    LokalCatalogueAlbum album,
    List<Song> library,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _progress.update(lokalText('Loading album…'));
      final page = await LokalOnlineCatalogue.instance.album(
        album.title,
        album.artist,
        release: album,
      );
      if (!mounted) return;
      final index = KonnektedLibraryIndex.of(library);
      final rows = [
        for (final track in page.tracks)
          _Entry(track, index.match(track.metadata)),
      ];
      setState(() => _busy = false);
      if (rows.isEmpty) {
        _progress.fail(lokalText('No online tracks found.'));
        return;
      }
      if (rows.every((row) => row.owned != null)) {
        _progress.clear();
        await AddToPlaylistSheet.showSongs(context, [
          for (final row in rows) row.owned!,
        ]);
      } else {
        await _download(rows);
      }
    } catch (error) {
      if (mounted) _progress.fail(discoveryError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _albumCard(
    LokalCatalogueAlbum album,
    List<AlbumGroup> groups,
    List<Song> library,
  ) {
    final songs = _albumSongs(album, groups), t = context.lokal;
    return LokalPressable(
      radius: 16,
      semanticLabel: album.title,
      onTap: () => _openAlbum(album, groups),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _releaseArt(album, songs, 156),
          const SizedBox(height: 8),
          Text(
            album.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _ownership(album, songs).isEmpty
                ? album.year?.toString() ?? album.artist
                : _ownership(album, songs),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: t.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _songActions(_Entry row) => unawaited(
    SongActionsBottomSheet.show(
      context,
      row.owned ?? row.track.pending(),
      queueActions: false,
      hideMediaActions: true,
      extras: [
        if (row.owned == null)
          LokalSongMenuAction(
            icon: Icons.download_rounded,
            label: lokalText('Download to library'),
            onTap: () {
              if (mounted) unawaited(_download([row]));
            },
          ),
      ],
    ),
  );

  Widget _trackRow(_Entry row, List<_Entry> queue, int index) {
    final t = context.lokal, track = row.track.metadata;
    return LokalSwipeToQueue(
      song: row.owned ?? row.track.pending(),
      enabled: !_busy,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
        onTap: _busy ? null : () => _play(queue, start: index),
        onLongPress: _busy ? null : () => _songActions(row),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SizedBox.square(
            dimension: 48,
            child: row.owned == null
                ? DiscoveryArtwork(
                    kind: DiscoveryArtworkKind.track,
                    title: track.title,
                    artist: track.artist,
                    url: track.artworkUrl,
                    width: 48,
                    height: 48,
                    placeholder: ColoredBox(
                      color: t.surface2,
                      child: Icon(Icons.music_note_rounded, color: t.muted),
                    ),
                  )
                : CachedImageWidget(
                    imagePath: row.owned?.albumArt,
                    audioSourcePath: row.owned?.filePath,
                    fit: BoxFit.cover,
                    placeholder: ColoredBox(
                      color: t.surface2,
                      child: Icon(Icons.music_note_rounded, color: t.muted),
                    ),
                    errorWidget: ColoredBox(
                      color: t.surface2,
                      child: Icon(Icons.music_note_rounded, color: t.muted),
                    ),
                  ),
          ),
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: t.text,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        subtitle: Text(
          widget.isArtist
              ? track.artist
              : '${row.track.disc != null && row.track.disc! > 1 ? '${row.track.disc} · ' : ''}${row.track.number ?? index + 1} · ${track.artist}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: t.muted, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (row.owned != null)
              Tooltip(
                message: lokalText('In library'),
                child: Icon(
                  Icons.check_circle_outline_rounded,
                  color: t.accent,
                  size: 18,
                ),
              ),
            IconButton(
              tooltip: lokalText('More'),
              icon: Icon(Icons.more_vert_rounded, color: t.muted, size: 20),
              onPressed: _busy ? null : () => _songActions(row),
            ),
          ],
        ),
      ),
    );
  }
}
