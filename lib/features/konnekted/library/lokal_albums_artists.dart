import 'dart:io';
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flick/features/library_jobs/artist_metadata.dart';
import 'package:flick/features/discovery/recommendation_match.dart';
import 'package:flick/features/spotify/spotify_api.dart';
import 'package:flick/features/spotify/spotify_oauth.dart';
import 'package:flick/features/spotify/spotify_storage.dart';
import 'package:flick/features/spotify/spotify_web_api.dart';
import 'package:flick/features/library_jobs/library_jobs.dart';
import 'package:flick/features/library_jobs/library_job_control.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/core/theme/lokal_interaction.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/features/konnekted/konnekted_home.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/models/song.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'artist_follow_store.dart';
import 'online_album_store.dart';
import 'package:flick/widgets/common/cached_image_widget.dart';
import 'lokal_library_kit.dart';
import 'lokal_library_groups.dart';
import 'lokal_music_detail_page.dart';

export 'lokal_library_groups.dart';

final lokalAlbumsProvider = Provider<AsyncValue<List<AlbumGroup>>>(
  (ref) => ref.watch(konnektedLibraryProvider).whenData(lokalAlbums),
);

final lokalArtistsProvider = Provider<AsyncValue<List<LokalArtist>>>(
  (ref) => ref.watch(konnektedLibraryProvider).whenData(lokalArtists),
);

/// An album's cover.
class _AlbumArt extends StatelessWidget {
  const _AlbumArt(this.songs);

  final List<Song> songs;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => songs.isEmpty
        ? LokalCollage(songs: songs)
        : KonnektedArtwork(
            song: songs.firstWhere(
              (s) => s.albumArt != null,
              orElse: () => songs.first,
            ),
            size: c.maxWidth,
            radius: 0,
          ),
  );
}

/// A filterable list page: a search field under the title, then [build].
class _SearchablePage<T> extends StatefulWidget {
  const _SearchablePage({
    required this.title,
    required this.items,
    required this.nameOf,
    required this.builder,
    required this.hint,
    required this.emptyIcon,
    required this.emptyMessage,
    required this.job,
    required this.preferencesKey,
    this.controls,
  });

  final String title;
  final AsyncValue<List<T>> items;
  final String Function(T) nameOf;
  final Widget Function(List<T> items) builder;
  final String hint;
  final IconData emptyIcon;
  final String emptyMessage;
  final LibraryJob job;
  final String preferencesKey;
  final Widget? controls;

  @override
  State<_SearchablePage<T>> createState() => _SearchablePageState<T>();
}

class _SearchablePageState<T> extends State<_SearchablePage<T>> {
  final _search = TextEditingController();
  String _query = '';
  bool _queryModified = false;
  Future<void> _saveTail = Future<void>.value();

  @override
  void initState() {
    super.initState();
    unawaited(_restoreQuery());
  }

  @override
  void didUpdateWidget(covariant _SearchablePage<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferencesKey == widget.preferencesKey) return;
    _queryModified = false;
    _query = '';
    _search.clear();
    unawaited(_restoreQuery());
  }

  Future<void> _restoreQuery() async {
    final key = widget.preferencesKey;
    try {
      final prefs = await SharedPreferences.getInstance();
      final query = prefs.getString(key);
      if (!mounted ||
          widget.preferencesKey != key ||
          _queryModified ||
          query == null)
        return;
      final validated = query.length > 200 ? query.substring(0, 200) : query;
      setState(() {
        _query = validated;
        _search.text = validated;
      });
    } catch (_) {
      // A storage error must not prevent Albums/Artists browsing.
    }
  }

  void _onQueryChanged(String value) {
    _queryModified = true;
    setState(() => _query = value);
    final saved = value.length > 200 ? value.substring(0, 200) : value;
    final key = widget.preferencesKey;
    _saveTail = _saveTail
        .then((_) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(key, saved);
        })
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.items.value;
    final query = _query.trim().toLowerCase();
    final items = all == null
        ? null
        : query.isEmpty
        ? all
        : [
            for (final item in all)
              if (widget.nameOf(item).toLowerCase().contains(query)) item,
          ];
    return LokalLibraryPage(
      title: widget.title,
      subtitle: all == null
          ? null
          : lokalText(
              "{arg0} {arg1}",
              args: {'arg0': all.length, 'arg1': widget.title.toLowerCase()},
            ),
      slivers: [
        SliverToBoxAdapter(child: LibraryJobControl(widget.job)),
        if (widget.controls != null)
          SliverToBoxAdapter(child: widget.controls!),
        if (all != null && all.isNotEmpty)
          SliverPersistentHeader(
            pinned: true,
            delegate: LokalPinnedHeader(
              height:
                  60 *
                  MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: LokalSearchField(
                  controller: _search,
                  hint: widget.hint,
                  onChanged: _onQueryChanged,
                ),
              ),
            ),
          ),
        if (items == null)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (items.isEmpty)
          SliverToBoxAdapter(
            child: LokalEmptyState(
              icon: widget.emptyIcon,
              title: query.isEmpty
                  ? lokalText('Nothing here yet')
                  : lokalText('No results'),
              message: query.isEmpty
                  ? widget.emptyMessage
                  : lokalText(
                      "Nothing matches “{arg0}”.",
                      args: {'arg0': _query},
                    ),
            ),
          )
        else
          const SliverPadding(padding: EdgeInsets.only(top: 8)),
        if (items != null && items.isNotEmpty) widget.builder(items),
      ],
    );
  }
}

/// Library › Albums includes catalogue bookmarks as well as local audio tags.
class _AlbumLibraryEntry {
  const _AlbumLibraryEntry.local(this.local) : saved = null;
  const _AlbumLibraryEntry.online(this.saved) : local = null;
  final AlbumGroup? local;
  final SavedOnlineAlbum? saved;
  String get title => local?.albumName ?? saved!.title;
  String get artist => local?.albumArtist ?? saved!.artist;
}

class LokalAlbumsPage extends ConsumerStatefulWidget {
  const LokalAlbumsPage({super.key});

  @override
  ConsumerState<LokalAlbumsPage> createState() => _LokalAlbumsPageState();
}

class _LokalAlbumsPageState extends ConsumerState<LokalAlbumsPage> {
  final OnlineAlbumStore _saved = OnlineAlbumStore.instance;

  @override
  void initState() {
    super.initState();
    _saved.addListener(_changed);
    unawaited(_saved.load().catchError((Object _) {}));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _saved.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(lokalAlbumsProvider).whenData((albums) {
      final localKeys = albums
          .map((a) => OnlineAlbumStore.keyOf(a.albumName, a.albumArtist))
          .toSet();
      final rows = <_AlbumLibraryEntry>[
        for (final album in albums) _AlbumLibraryEntry.local(album),
        for (final album in _saved.albums)
          if (!localKeys.contains(album.key)) _AlbumLibraryEntry.online(album),
      ];
      rows.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      return rows;
    });
    return _SearchablePage<_AlbumLibraryEntry>(
      title: lokalText('Albums'),
      job: LibraryJob.releases,
      preferencesKey: 'lokal.library.albums.search.v1',
      items: entries,
      nameOf: (row) => '${row.title}\n${row.artist}',
      hint: 'Search albums',
      emptyIcon: Icons.album_rounded,
      emptyMessage: 'Save online albums or add music folders to your library.',
      builder: (rows) => LokalCardGrid(
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          final album = row.local;
          final saved = row.saved;
          return LokalCoverCard(
            art: album != null
                ? _AlbumArt(album.songs)
                : saved!.artwork.isEmpty
                    ? const Center(child: Icon(Icons.album_rounded, size: 44))
                    : CachedImageWidget(
                        imagePath: saved.artwork, fit: BoxFit.cover,
                      ),
            title: row.title,
            subtitle: row.artist,
            heroTag: album != null
                ? 'lokal:album:${album.key}'
                : 'lokal:online-album:${saved!.key}',
            onTap: () => album != null
                ? pushLokal(context, LokalAlbumPage(album: album))
                : pushLokal(
                    context,
                    LokalMusicDetailPage.album(
                      title: saved!.title,
                      artist: saved.artist,
                      localSongs: const [],
                      release: saved.release,
                      initialOnline: true,
                    ),
                  ),
          );
        },
      ),
    );
  }
}

/// Spotify favorites may not have local songs. Keep them in Artists anyway.
enum ArtistFavoritesFilter { all, favorites, nonFavorites }

List<LokalArtist> selectArtistFavorites(
  List<LokalArtist> local,
  ArtistFollowStore follows,
  ArtistFavoritesFilter filter,
) {
  final rows = <String, LokalArtist>{};
  for (final artist in local) {
    final key = recommendationKey(artist.name);
    if (key.isNotEmpty) rows.putIfAbsent(key, () => artist);
  }
  for (final name in follows.followedNames) {
    final key = recommendationKey(name);
    if (key.isNotEmpty) {
      rows.putIfAbsent(key, () => LokalArtist(name, const []));
    }
  }
  final selected = [
    for (final artist in rows.values)
      if (filter == ArtistFavoritesFilter.all ||
          follows.isFollowed(artist.name) ==
              (filter == ArtistFavoritesFilter.favorites))
        artist,
  ];
  selected.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return selected;
}

class LokalArtistsPage extends ConsumerStatefulWidget {
  const LokalArtistsPage({super.key});
  @override
  ConsumerState<LokalArtistsPage> createState() => _LokalArtistsPageState();
}

class _LokalArtistsPageState extends ConsumerState<LokalArtistsPage> {
  final _follows = ArtistFollowStore.instance;
  ArtistFavoritesFilter _filter = ArtistFavoritesFilter.all;
  bool _filterModified = false;
  Future<void> _filterSaveTail = Future<void>.value();
  static const _artistFilterKey = 'lokal.library.artists.favorite_filter.v1';
  bool _importing = false;
  String? _status, _error;

  @override
  void initState() {
    super.initState();
    _follows.addListener(_onFavoritesChanged);
    unawaited(_restoreArtistFilter());
    unawaited(
      _follows.load().catchError((Object _) {
        if (mounted)
          setState(
            () => _error = lokalText('Could not load favorite artists.'),
          );
      }),
    );
  }

  void _onFavoritesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _restoreArtistFilter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_artistFilterKey);
      final filter = ArtistFavoritesFilter.values
          .where((f) => f.name == saved)
          .firstOrNull;
      if (!mounted || _filterModified || filter == null) return;
      setState(() => _filter = filter);
    } catch (_) {
      // Browsing remains available if preference storage is unavailable.
    }
  }

  void _selectArtistFilter(ArtistFavoritesFilter filter) {
    _filterModified = true;
    setState(() => _filter = filter);
    _filterSaveTail = _filterSaveTail
        .then((_) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_artistFilterKey, filter.name);
        })
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    _follows.removeListener(_onFavoritesChanged);
    super.dispose();
  }

  Future<void> _importSpotify() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _error = null;
      _status = lokalText('Connecting to Spotify…');
    });
    final settings = SpotifySettingsStore();
    final oauth = SpotifyOAuthService(tokenStore: settings.tokenStore);
    SpotifyWebApi? api;
    try {
      if (!await oauth.isConnected) await oauth.signIn();
      api = SpotifyWebApi(store: settings.tokenStore, oauth: oauth);
      final names = await api.getFollowedArtists(
        onProgress: (count) {
          if (mounted) {
            setState(
              () => _status = lokalText(
                'Reading Spotify favorites… {count} artists',
                args: {'count': count},
              ),
            );
          }
        },
      );
      final imported = await _follows.importNames(names);
      if (!mounted) return;
      _selectArtistFilter(ArtistFavoritesFilter.favorites);
      setState(() {
        _status = imported.received == 0
            ? lokalText('No followed artists found on Spotify.')
            : lokalText(
                'Imported {added} new favorites ({received} found on Spotify).',
                args: {'added': imported.added, 'received': imported.received},
              );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = null;
        _error = error is SpotifyApiException || error is SpotifyOAuthException
            ? lokalText(error.toString())
            : lokalText(
                'Could not import Spotify artists. Check your connection and retry.',
              );
      });
    } finally {
      api?.close();
      if (mounted) setState(() => _importing = false);
    }
  }

  Widget _controls(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final option in ArtistFavoritesFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(switch (option) {
                      ArtistFavoritesFilter.all => lokalText('All'),
                      ArtistFavoritesFilter.favorites => lokalText('Favorites'),
                      ArtistFavoritesFilter.nonFavorites => lokalText(
                        'Non-favorites',
                      ),
                    }),
                    selected: _filter == option,
                    onSelected: (_) => _selectArtistFilter(option),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _importing ? null : _importSpotify,
          icon: _importing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.link_rounded, size: 18),
          label: Text(
            _importing
                ? lokalText('Importing Spotify artists…')
                : lokalText('Import favorites from Spotify'),
          ),
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _status!,
              style: TextStyle(fontSize: 12, color: context.lokal.muted),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(fontSize: 12, color: context.lokal.text),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(lokalArtistsProvider);
    return _SearchablePage<LokalArtist>(
      title: lokalText('Artists'),
      job: LibraryJob.artists,
      preferencesKey: 'lokal.library.artists.search.v1',
      items: source.whenData(
        (artists) => selectArtistFavorites(artists, _follows, _filter),
      ),
      nameOf: (artist) => artist.name,
      hint: lokalText('Search artists'),
      emptyIcon: Icons.person_rounded,
      emptyMessage: switch (_filter) {
        ArtistFavoritesFilter.all => lokalText(
          'Artists come from your library or artists you follow online.',
        ),
        ArtistFavoritesFilter.favorites => lokalText(
          'Follow an artist or import your Spotify favorites.',
        ),
        ArtistFavoritesFilter.nonFavorites => lokalText(
          'No non-favorite artists in your library.',
        ),
      },
      controls: _controls(context),
      builder: (artists) => SliverList.builder(
        itemCount: artists.length,
        itemBuilder: (context, index) => _ArtistRow(artist: artists[index]),
      ),
    );
  }
}

class _ArtistRow extends ConsumerWidget {
  const _ArtistRow({required this.artist});

  final LokalArtist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portrait = ref.watch(
      artistMetadataProvider.select(
        (paths) => paths[ArtistMetadata.key(artist.name)],
      ),
    );
    // Portraits, fallback album art and placeholders must occupy the same
    // circle; previously the first was 52 px but the others were 68 px.
    const diameter = 52.0;
    const radius = diameter / 2;
    final fallback = artist.songs.isEmpty
        ? CircleAvatar(
            radius: radius,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Icon(Icons.person_rounded, color: context.lokal.muted),
          )
        : KonnektedArtwork(
            song: artist.songs.first,
            size: diameter,
            radius: radius,
          );
    return LokalPressable(
      radius: 18,
      onTap: () => pushLokal(
        context,
        LokalArtistPage(
          name: artist.name,
          songs: artist.songs,
          initialOnline: artist.songs.isEmpty,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.lokal.surface.withValues(alpha: .7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: context.lokal.border.withValues(alpha: .6),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: diameter,
                  child: ClipOval(
                    child: portrait == null
                        ? fallback
                        : Image.file(
                            File(portrait),
                            width: diameter,
                            height: diameter,
                            cacheWidth: 156,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => fallback,
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        artist.songs.isEmpty
                            ? 'Followed online'
                            : lokalSongCount(artist.songs.length),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.lokal.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: ArtistFollowStore.instance.isFollowed(artist.name)
                      ? 'Remove from favorites'
                      : 'Add to favorites',
                  icon: Icon(
                    ArtistFollowStore.instance.isFollowed(artist.name)
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                  ),
                  onPressed: () async {
                    try {
                      final follows = ArtistFollowStore.instance;
                      await follows.setFollowed(
                        artist.name,
                        !follows.isFollowed(artist.name),
                      );
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not save artist favorite.'),
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An album: cover, name, artist, Play and Shuffle, the tracks, and more by
/// the artist.
class LokalAlbumPage extends StatelessWidget {
  const LokalAlbumPage({
    super.key,
    required this.album,
    this.initialOnline = false,
  });
  final AlbumGroup album;
  final bool initialOnline;
  @override
  Widget build(BuildContext context) => LokalMusicDetailPage.album(
    title: album.albumName,
    artist: album.albumArtist,
    localSongs: album.songs,
    initialOnline: initialOnline,
    artworkHeroTag: 'lokal:album:${album.key}',
  );
}

/// An artist: portrait, Play, Shuffle and Radio, top songs, albums.
class LokalArtistPage extends StatelessWidget {
  const LokalArtistPage({
    super.key,
    required this.name,
    required this.songs,
    this.initialOnline = false,
  });
  final String name;
  final List<Song> songs;
  final bool initialOnline;
  @override
  Widget build(BuildContext context) => LokalMusicDetailPage.artist(
    name: name,
    localSongs: songs,
    initialOnline: initialOnline,
  );
}
