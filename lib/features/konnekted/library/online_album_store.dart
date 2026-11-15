import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flick/features/discovery/recommendation_match.dart';
import 'lokal_online_catalogue.dart';

/// A catalogue bookmark: no local audio file or download is required.
@immutable
class SavedOnlineAlbum {
  const SavedOnlineAlbum({
    required this.title,
    required this.artist,
    this.artwork = '',
    this.id,
    this.date,
    this.url = '',
    this.trackCount,
    this.kind,
  });

  final String title, artist, artwork, url;
  final String? id, date;
  final int? trackCount;
  final LokalReleaseKind? kind;

  String get key => OnlineAlbumStore.keyOf(title, artist);

  LokalCatalogueAlbum get release => LokalCatalogueAlbum(
    title: title, artist: artist, artwork: artwork, id: id,
    date: date, url: url, trackCount: trackCount, releaseKind: kind,
  );

  factory SavedOnlineAlbum.fromRelease(LokalCatalogueAlbum album) =>
      SavedOnlineAlbum(
        title: album.title.trim(),
        artist: album.artist.trim(),
        artwork: album.artwork,
        id: album.id,
        date: album.date,
        url: album.url,
        trackCount: album.trackCount,
        kind: album.releaseKind,
      );

  Map<String, Object?> toJson() => {
    'title': title, 'artist': artist, 'artwork': artwork,
    'id': id, 'date': date, 'url': url,
    'trackCount': trackCount, 'kind': kind?.name,
  };

  static SavedOnlineAlbum? fromJson(Object? value) {
    if (value is! Map) return null;
    final title = (value['title'] as String? ?? '').trim();
    final artist = (value['artist'] as String? ?? '').trim();
    if (title.isEmpty || artist.isEmpty || title.length > 500 ||
        artist.length > 500) return null;
    final kindName = value['kind'];
    final kind = LokalReleaseKind.values.where((v) => v.name == kindName).firstOrNull;
    return SavedOnlineAlbum(
      title: title, artist: artist,
      artwork: value['artwork'] is String ? value['artwork'] as String : '',
      id: value['id'] is String ? value['id'] as String : null,
      date: value['date'] is String ? value['date'] as String : null,
      url: value['url'] is String ? value['url'] as String : '',
      trackCount: value['trackCount'] is num
          ? (value['trackCount'] as num).toInt() : null,
      kind: kind,
    );
  }
}

/// Persists and notifies both album detail pages and the Albums collection.
class OnlineAlbumStore extends ChangeNotifier {
  OnlineAlbumStore({Future<SharedPreferences> Function()? preferences})
      : _preferences = preferences ?? SharedPreferences.getInstance;

  static final instance = OnlineAlbumStore();
  static const preferenceKey = 'lokal.library.saved_online_albums.v1';

  final Future<SharedPreferences> Function() _preferences;
  SharedPreferences? _prefs;
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();
  Map<String, SavedOnlineAlbum> _items = {};

  static String keyOf(String title, String artist) =>
      '${recommendationKey(title)}|${recommendationKey(artist)}';

  bool isSaved(String title, String artist) =>
      _items.containsKey(keyOf(title, artist));
  List<SavedOnlineAlbum> get albums => List.unmodifiable(_items.values);
  bool get isLoaded => _prefs != null;

  Future<void> load() {
    if (_prefs != null) return Future.value();
    return _loading ??= _restore().whenComplete(() => _loading = null);
  }

  Future<void> _restore() async {
    final prefs = await _preferences();
    final next = <String, SavedOnlineAlbum>{};
    try {
      final parsed = jsonDecode(prefs.getString(preferenceKey) ?? '[]');
      if (parsed is List) {
        for (final item in parsed) {
          final album = SavedOnlineAlbum.fromJson(item);
          if (album != null) next[album.key] = album;
        }
      }
    } catch (_) {
      // Invalid legacy settings must not block Albums browsing.
    }
    _items = next;
    _prefs = prefs;
    notifyListeners();
  }

  Future<void> setSaved(LokalCatalogueAlbum release, bool save) {
    final operation = _writes.then((_) async {
      await load();
      final album = SavedOnlineAlbum.fromRelease(release);
      if (album.title.isEmpty || album.artist.isEmpty) {
        throw StateError('Missing album title or artist.');
      }
      final next = Map<String, SavedOnlineAlbum>.of(_items);
      if (save) {
        final previous = next[album.key];
        next[album.key] = SavedOnlineAlbum(
          title: album.title, artist: album.artist,
          artwork: album.artwork.isNotEmpty ? album.artwork : (previous?.artwork ?? ''),
          id: album.id ?? previous?.id,
          date: album.date ?? previous?.date,
          url: album.url.isNotEmpty ? album.url : (previous?.url ?? ''),
          trackCount: album.trackCount ?? previous?.trackCount,
          kind: album.kind ?? previous?.kind,
        );
      } else {
        next.remove(album.key);
      }
      if (!await _prefs!.setString(
        preferenceKey, jsonEncode(next.values.map((e) => e.toJson()).toList()),
      )) {
        throw StateError('Could not save album to your library.');
      }
      _items = next;
      notifyListeners();
    });
    _writes = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }
}
