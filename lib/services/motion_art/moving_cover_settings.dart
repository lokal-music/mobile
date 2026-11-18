import 'package:flick/models/song.dart';

import 'moving_cover_matcher.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const movingCoverSources = {
  'apple': 'Apple Music',
  'tidal': 'Tidal',
  'community': 'Community list',
  'm8tec': 'm8tec Artwork',
  'spotify': 'Spotify Canvas',
};
String movingCoverSongKey(Song song) =>
    '${motionName(song.artist)}|${motionName(song.title)}';
final movingCoverRevision = ValueNotifier<int>(0);

class MovingCoverSettings {
  const MovingCoverSettings({
    this.sources = const {'apple'},
    this.spotifyFirst = false,
    this.disabledSongs = const {},
  });
  final Set<String> sources;
  final bool spotifyFirst;
  final Set<String> disabledSongs;
  List<String> get order => [
    if (spotifyFirst && sources.contains('spotify')) 'spotify',
    ...movingCoverSources.keys.where(
      (id) => sources.contains(id) && !(spotifyFirst && id == 'spotify'),
    ),
  ];
  static Future<MovingCoverSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return MovingCoverSettings(
      sources: (p.getStringList('lokal.motion.sources') ?? ['apple'])
          .where(movingCoverSources.containsKey)
          .toSet(),
      spotifyFirst: p.getBool('lokal.motion.spotify_first') ?? false,
      disabledSongs: (p.getStringList('lokal.motion.disabled_songs') ?? [])
          .toSet(),
    );
  }
}

class MovingCoverSettingsNotifier extends Notifier<MovingCoverSettings> {
  int _mutationEpoch = 0;

  @override
  MovingCoverSettings build() {
    unawaited(_load());
    return const MovingCoverSettings();
  }

  Future<void> _load() async {
    final epoch = _mutationEpoch;
    final saved = await MovingCoverSettings.load();
    // A footer tap can arrive before preferences hydration completes. Do not
    // let that older load undo a newly saved Cover toggle.
    if (ref.mounted && epoch == _mutationEpoch) state = saved;
  }

  Future<void> setSource(String id, bool enabled) async {
    final sources = {...state.sources};
    if (enabled) {
      sources.add(id);
    } else {
      sources.remove(id);
    }
    await _save(
      MovingCoverSettings(
        sources: sources,
        spotifyFirst: state.spotifyFirst,
        disabledSongs: state.disabledSongs,
      ),
    );
  }

  Future<void> prioritizeSpotify(bool value) => _save(
    MovingCoverSettings(
      sources: value ? {...state.sources, 'spotify'} : state.sources,
      spotifyFirst: value,
      disabledSongs: state.disabledSongs,
    ),
  );
  Future<void> setSongEnabled(String songId, bool enabled) {
    final disabled = {...state.disabledSongs};
    if (enabled) {
      disabled.remove(songId);
    } else {
      disabled.add(songId);
    }
    return _save(
      MovingCoverSettings(
        sources: state.sources,
        spotifyFirst: state.spotifyFirst,
        disabledSongs: disabled,
      ),
    );
  }

  Future<void> _save(MovingCoverSettings settings) async {
    final sourcesChanged = state.order.join(',') != settings.order.join(',');
    _mutationEpoch++;
    state = settings;
    final p = await SharedPreferences.getInstance();
    await p.setStringList('lokal.motion.sources', settings.sources.toList());
    await p.setBool('lokal.motion.spotify_first', settings.spotifyFirst);
    await p.setStringList(
      'lokal.motion.disabled_songs',
      settings.disabledSongs.toList(),
    );
    if (sourcesChanged) movingCoverRevision.value++;
  }
}

final movingCoverSettingsProvider =
    NotifierProvider<MovingCoverSettingsNotifier, MovingCoverSettings>(
      MovingCoverSettingsNotifier.new,
    );
