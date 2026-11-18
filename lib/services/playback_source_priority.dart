import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// One order for automatic playback lookups across artist/album pages,
/// recommendations and pending queues. Explicit Search source picks stay exact.
/// Opt-in low-bandwidth lookup policy. Active only when the device uses mobile
/// data, not Wi-Fi or wired connectivity. Never changes the saved source order.
abstract final class EcoDataMode {
  static const key = 'lokal.playback.eco_data_mode';

  /// Notify motion-art views when the preference or network changes.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static StreamSubscription<List<ConnectivityResult>>? _connectivityWatcher;

  static void observeConnectionChanges() {
    if (_connectivityWatcher != null) return;
    try {
      _connectivityWatcher = Connectivity().onConnectivityChanged.listen(
        (_) => revision.value++,
        onError: (Object _) {},
      );
    } catch (_) {
      // Not every test/platform exposes a connectivity event stream.
    }
  }

  static Future<bool> enabled() async =>
      (await SharedPreferences.getInstance()).getBool(key) ?? false;

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getBool(key);
    try {
      if (!await prefs.setBool(key, value)) {
        throw StateError('Could not save Eco Data Mode.');
      }
    } catch (_) {
      try {
        if (previous == null) {
          await prefs.remove(key);
        } else {
          await prefs.setBool(key, previous);
        }
      } catch (_) {}
      rethrow;
    }
    revision.value++;
  }

  static bool isCellularOnly(List<ConnectivityResult> transports) =>
      transports.contains(ConnectivityResult.mobile) &&
      !transports.contains(ConnectivityResult.wifi) &&
      !transports.contains(ConnectivityResult.ethernet);

  static Future<bool> activeOnCellular() async {
    if (!await enabled()) return false;
    try {
      return isCellularOnly(await Connectivity().checkConnectivity());
    } catch (_) {
      // Do not change playback order if the platform cannot identify the link.
      return false;
    }
  }

  /// Airplane mode/no transport must use fully saved motion clips, not a
  /// memoized provider URL. This deliberately does not treat Wi-Fi without
  /// Internet as definitively offline: connectivity_plus reports transports,
  /// not end-to-end Internet reachability.
  static Future<bool> isOffline() async {
    try {
      final transports = await Connectivity().checkConnectivity();
      return transports.isEmpty ||
          transports.every((transport) => transport == ConnectivityResult.none);
    } catch (_) {
      // Some platforms/tests do not expose a connectivity plugin.
      return false;
    }
  }
}

abstract final class PlaybackSourcePriority {
  static const key = 'lokal.playback.source_order';

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(key);
    if (saved != null) return saved.toSet().toList();
    // Preserve the user's earlier pinned source as their first preference.
    final previous = prefs.getString('lokal.catalogue.playback_source');
    final order = previous == null ? <String>[] : [previous];
    await prefs.setStringList(key, order);
    await prefs.remove('lokal.catalogue.playback_source');
    return order;
  }

  static Future<List<T>> order<T>(
    List<T> available,
    String Function(T) id, {
    // Stable provider ids supersede the old HTTP ids derived from display
    // labels. A rename must not silently restore YouTube as first choice.
    Map<String, String> aliases = const {},
    // Applied to automatic source discovery only, never an explicit Search
    // selection or a pinned queue entry. No persistent reordering.
    bool ecoOnCellular = false,
    Future<bool> Function()? ecoActive,
  }) async {
    final saved = await load();
    final sources = {for (final source in available) id(source): source};
    final migrated = <String>[for (final key in saved) aliases[key] ?? key]
        .toSet()
        .toList();
    if (migrated.join('\u0000') != saved.join('\u0000')) {
      await (await SharedPreferences.getInstance()).setStringList(
        key,
        migrated,
      );
    }
    final ordered = [
      for (final sourceId in {...migrated, ...sources.keys})
        if (sources[sourceId] case final source?) source,
    ];
    if (!ecoOnCellular ||
        !await (ecoActive ?? EcoDataMode.activeOnCellular)()) {
      return ordered;
    }
    const economical = ['yt', 'sc'];
    return [
      for (final sourceId in economical)
        if (sources[sourceId] case final source?) source,
      for (final source in ordered)
        if (!economical.contains(id(source))) source,
    ];
  }

  /// Put a newly installed add-on first, without changing the order of all
  /// other sources. Called only for new installs, not package updates.
  static Future<void> promoteNewAddon(String sourceId) async {
    final saved = await load();
    await _save([sourceId, ...saved.where((id) => id != sourceId)]);
  }

  /// Reorder visible sources using Flutter's pre-removal drop index.
  /// Hidden/disabled sources retain their relative positions in the saved list.
  static Future<void> reorder(
    List<String> visible,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex < 0 ||
        oldIndex >= visible.length ||
        newIndex < 0 ||
        newIndex > visible.length) {
      throw RangeError('Invalid playback source reorder indices');
    }
    if (visible.toSet().length != visible.length) {
      throw ArgumentError('Playback source IDs must be unique');
    }
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (target == oldIndex) return;
    final reordered = [...visible];
    final moving = reordered.removeAt(oldIndex);
    reordered.insert(target, moving);

    final saved = <String>{...await load(), ...visible}.toList();
    final visibleIds = visible.toSet();
    var cursor = 0;
    final result = [
      for (final id in saved)
        if (visibleIds.contains(id)) reordered[cursor++] else id,
    ];
    await _save(result);
  }

  static Future<void> _save(List<String> order) async {
    final preferences = await SharedPreferences.getInstance();
    final previous = preferences.getStringList(key);
    try {
      if (!await preferences.setStringList(key, order)) {
        throw StateError('Could not save source priority.');
      }
    } catch (_) {
      // The legacy preferences API updates its cache before the platform reply.
      // Restore that cache too, so retry/loading agrees with the rolled-back UI.
      try {
        if (previous == null) {
          await preferences.remove(key);
        } else {
          await preferences.setStringList(key, previous);
        }
      } catch (_) {}
      rethrow;
    }
  }

  /// Move a row to a final visible index (rather than exchanging two rows).
  static Future<void> move(List<String> visible, int from, int to) =>
      reorder(visible, from, from < to ? to + 1 : to);
}
