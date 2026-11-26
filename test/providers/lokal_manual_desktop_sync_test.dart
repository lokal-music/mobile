import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the explicit-only sync wiring. A regression in the connection,
/// journal or periodic timer paths can silently trigger a full library walk
/// against thousands of desktop tracks before the user can use the app.
// Formatting does not change these static ownership/scheduling guards.
Matcher containsCode(String fragment) => predicate<String>(
  (code) => code
      .replaceAll(RegExp(r'\s+'), '')
      .contains(fragment.replaceAll(RegExp(r'\s+'), '')),
  'contains code $fragment',
);

void main() {
  final controller = File('lib/providers/lokal_remote_provider.dart')
      .readAsStringSync();
  final screen = File('lib/features/link/lokal_desktop_link_screen.dart')
      .readAsStringSync();

  String section(String start, String end) {
    final begin = controller.indexOf(start);
    final finish = controller.indexOf(end, begin + start.length);
    expect(begin, greaterThanOrEqualTo(0), reason: 'Missing $start');
    expect(finish, greaterThan(begin), reason: 'Missing $end');
    return controller.substring(begin, finish);
  }

  test('startup, reconnect, refresh and timer never start full sync', () {
    final startup = section(
      'LokalRemoteControllerState build()',
      'Future<void> _ensureRestored()',
    );
    final refresh = section(
      'Future<void> refresh()',
      'Future<void> sendCommand(',
    );
    final socket = section(
      'Future<void> _connectSocket()',
      'void _socketConnectionChanged(',
    );
    final timer = section('void _tickLink()', 'Future<void> _syncLink()');

    for (final path in [startup, refresh, socket, timer]) {
      expect(path, isNot(containsCode('_syncLink(')));
      expect(path, isNot(containsCode('.synchronize(')));
    }
    expect(controller, isNot(containsCode('_syncDebounce')));
    expect(controller, isNot(containsCode('_lastLibrarySyncAt')));
    expect(
      controller,
      isNot(containsCode('LinkJournal.instance.changes.stream.listen')),
    );
  });

  test('only an explicit Sync now invokes the full library coordinator', () {
    final manual = section(
      'Future<void> syncNow()',
      'LinkFileCopy _fileCopier()',
    );
    expect(manual, containsCode('state.mergeApproved'));
    expect(manual, containsCode('state.socketConnected'));
    expect(manual, containsCode('await _syncLink();'));
    expect(
      RegExp(r'_syncLink\(').allMatches(controller).length,
      2,
      reason: 'Only the user action and its method definition may reference _syncLink',
    );
    expect(RegExp(r'\.synchronize\(').allMatches(controller).length, 1);
    expect(screen, containsCode('Future<void> _syncNow()'));
    expect(screen, containsCode(': _syncNow,'));
    expect(
      screen,
      containsCode(
        'Listening history syncs automatically. Tap Sync now to update songs, likes, playlists and metadata.',
      ),
    );
  });
  test(
    'explicit Sync now rechecks desktop catalogue while startup stays light',
    () {
      final sync = File('lib/services/link/link_sync_coordinator.dart')
          .readAsStringSync();
      final source = File('lib/services/link/lokal_desktop_source.dart')
          .readAsStringSync();
      expect(sync, containsCode('final refreshCatalog = importCatalog ||'));
      expect(sync, containsCode('!_background ||'));
      expect(sync, containsCode('if (refreshCatalog) {'));
      expect(
        sync,
        containsCode(
          'await for (final progress in source.syncLibrary(server))',
        ),
      );
      expect(
        source,
        containsCode(r"queryParameters: {'offset': '$offset', 'limit': '250'}"),
      );
      expect(
        source,
        containsCode(
          'final matchCandidates = await SongRepository().getAllSongs();',
        ),
      );
      expect(source, containsCode('candidates: matchCandidates'));
      expect(source, containsCode('final local = entity == null'));
    },
  );

  test(
    'explicit sync reprojects already-pulled desktop history after catalogue',
    () {
      final sync = File('lib/services/link/link_sync_coordinator.dart')
          .readAsStringSync();
      expect(sync, containsCode('await _reconcileRecentDesktopHistory();'));
      expect(sync, containsCode('.sortByPlayedAtDesc()'));
      expect(sync, containsCode('.limit(500)'));
      expect(
        sync,
        containsCode(
          'await RecentlyPlayedRepository().recordLinkPlays(projected);',
        ),
      );
    },
  );

  test('automatic stats path is bounded and excludes catalog operations', () {
    final coordinator = File('lib/services/link/link_sync_coordinator.dart')
        .readAsStringSync();
    final journal = File('lib/services/link/link_journal.dart')
        .readAsStringSync();
    final statsStart = coordinator.indexOf('Future<void> _syncStatsBatch()');
    final statsEnd = coordinator.indexOf('Future<void> _synchronize(');
    expect(statsStart, greaterThanOrEqualTo(0));
    expect(statsEnd, greaterThan(statsStart));
    final stats = coordinator.substring(statsStart, statsEnd);

    expect(stats, containsCode('const pageSize = 50;'));
    expect(stats, containsCode("socket.request('history.push'"));
    expect(stats, containsCode("socket.request('history.pull'"));
    expect(stats, containsCode('getHistoryMatchCandidates'));
    expect(stats, isNot(containsCode('syncLibrary(')));
    expect(stats, isNot(containsCode('repairDesktopCopies(')));
    expect(stats, isNot(containsCode('syncCopiedLyrics(')));
    expect(stats, isNot(containsCode('_reconcileDesktopPlaylists(')));
    expect(coordinator, containsCode('fullSync: false'));
    expect(
      journal,
      containsCode(
        'final historyChanges = StreamController<void>.broadcast();',
      ),
    );
    expect(journal, containsCode('historyChanges.add(null);'));
    expect(journal, containsCode('int limit = 250'));
  });

  test('stats are scheduled separately on connection, play and polling', () {
    final socket = section(
      'Future<void> _connectSocket()',
      'void _socketConnectionChanged(',
    );
    final timer = section('void _tickLink()', 'Future<void> _syncLink()');
    final manual = section(
      'Future<void> syncNow()',
      'LinkFileCopy _fileCopier()',
    );
    expect(
      socket,
      containsCode('_scheduleStatsSync(const Duration(seconds: 8))'),
    );
    expect(socket, containsCode('_lastStatsSyncAt = DateTime.now()'));
    expect(timer, containsCode('unawaited(_syncStats())'));
    expect(
      controller,
      containsCode('LinkJournal.instance.historyChanges.stream.listen'),
    );
    expect(controller, containsCode('await coordinator.synchronizeStats();'));
    expect(manual, isNot(containsCode('synchronizeStats')));
  });

  test('unmatched remote events still count toward listening minutes', () {
    final recaps = File('lib/data/repositories/recently_played_repository.dart')
        .readAsStringSync();
    expect(recaps, containsCode('projectedEventIds.contains(event.eventId)'));
    expect(recaps, containsCode('.playEventEntitys'));
    expect(recaps, containsCode('listenedMs: event.msPlayed'));
    expect(recaps, containsCode('recordLinkPlays('));
    expect(recaps, containsCode('displayedEventIds.add(entry.eventId!)'));
    expect(recaps, containsCode(r"id: 'history:${event.trackKey}'"));
  });
}
