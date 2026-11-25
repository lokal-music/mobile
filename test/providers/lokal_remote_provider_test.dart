import 'package:flick/models/lokal_remote_state.dart';
import 'package:flick/providers/lokal_remote_provider.dart';
import 'package:flick/providers/favorites_provider.dart';
import 'package:flick/services/favorites_service.dart';
import 'package:flick/services/lokal_remote_credentials_store.dart';
import 'package:flick/services/lokal_paired_desktops_store.dart';
import 'package:flick/services/lokal_remote_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async';
import 'dart:io' show WebSocketException;

import 'package:flick/services/link/lokal_link_service.dart';

class _DelayedPairing extends LokalLinkService {
  final started = Completer<void>();
  final response = Completer<LokalRemoteCredentials>();
  @override
  Future<LokalRemoteCredentials> pair({
    required Uri origin,
    required String code,
    String? expectedDesktopId,
    String? deviceName,
  }) {
    started.complete();
    return response.future;
  }
}

class _Favorites implements FavoritesService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SocketLink extends LokalLinkService {
  int attempts = 0;
  bool _connected = false;
  @override
  bool get connected => _connected;
  @override
  void send(String type, Map<String, dynamic> body, {String? id}) {}
  @override
  Future<void> disconnect() async {
    _connected = false;
    await super.disconnect();
  }

  Object? failure;
  Uri? recoveredOrigin;
  @override
  Future<Uri> connect(LokalRemoteCredentials credentials) async {
    attempts++;
    if (failure != null) throw failure!;
    _connected = true;
    return recoveredOrigin ?? credentials.origin;
  }
}

class _PairedStore extends LokalPairedDesktopsStore {
  final Map<String, LokalRemoteCredentials> entries = {};
  String? selected;

  @override
  Future<LokalRemoteCredentials?> resolveActive({
    LokalRemoteCredentials? legacyActive,
  }) async {
    if (entries.isEmpty && legacyActive != null) {
      final id = LokalPairedDesktopsStore.identity(legacyActive);
      entries[id] = legacyActive;
      selected = id;
    }
    if (entries.isEmpty) return null;
    return entries[selected] ?? entries.values.last;
  }

  @override
  Future<void> add(LokalRemoteCredentials credentials) async {
    final id = LokalPairedDesktopsStore.identity(credentials);
    entries[id] = credentials;
    selected = id;
  }

  @override
  Future<String?> activeId() async => selected;

  @override
  Future<LokalRemoteCredentials?> select(String id) async {
    selected = id;
    return entries[id];
  }

  @override
  Future<LokalRemoteCredentials?> remove(
    LokalRemoteCredentials expected,
  ) async {
    final id = LokalPairedDesktopsStore.identity(expected);
    final current = entries[id];
    if (current == null ||
        !SecureCredentialComparison.matches(current, expected)) {
      throw StateError('Desktop pairing changed. Refresh and retry.');
    }
    entries.remove(id);
    selected = entries.keys.lastOrNull;
    return selected == null ? null : entries[selected];
  }
}

class _Store implements LokalRemoteCredentialsStore {
  LokalRemoteCredentials? value;

  @override
  Future<LokalRemoteCredentials?> read() async => value;

  @override
  Future<void> write(LokalRemoteCredentials credentials) async =>
      value = credentials;

  @override
  Future<void> clearIfMatching(LokalRemoteCredentials? expected) async {
    if (!SecureLokalRemoteCredentialsStore.sameAuthority(value, expected)) {
      throw StateError('Pairing changed.');
    }
    value = null;
  }

  @override
  Future<LokalRemoteCredentials> relocateIfMatching(
    LokalRemoteCredentials expected,
    Uri origin,
  ) async {
    if (!SecureLokalRemoteCredentialsStore.sameAuthority(value, expected))
      throw StateError('Pairing changed.');
    final relocated = LokalRemoteCredentials(
      origin: origin,
      remoteToken: expected.remoteToken,
      apiKey: expected.apiKey,
      desktopId: expected.desktopId,
      desktopUserId: expected.desktopUserId,
      pairingID: expected.pairingID,
    );
    value = relocated;
    return relocated;
  }

  @override
  Future<void> clear() async => value = null;
}

class _Service extends LokalRemoteService {
  _Service(this.responses);

  final List<Object> responses;
  final commands = <(LokalRemoteAction, double?)>[];
  final modeCommands = <(String, Object?)>[];

  @override
  Future<void> sendPlaybackModeCommand(
    LokalRemoteCredentials credentials,
    String action,
    Object? value,
  ) async => modeCommands.add((action, value));

  @override
  Future<LokalRemoteSnapshot> fetchState(
    LokalRemoteCredentials credentials,
  ) async {
    final response = responses.removeAt(0);
    if (response is! LokalRemoteSnapshot) throw response;
    return response;
  }

  @override
  Future<void> sendCommand(
    LokalRemoteCredentials credentials,
    LokalRemoteAction action, {
    double? value,
  }) async {
    commands.add((action, value));
  }
}

final _credentials = LokalRemoteCredentials(
  origin: Uri.parse('http://desktop'),
  remoteToken: 'token',
);

LokalRemoteSnapshot _snapshot({
  required int updatedAt,
  String title = 'Track',
  bool shuffle = false,
  String repeat = 'none',
}) => LokalRemoteSnapshot(
  connected: true,
  isPlaying: true,
  progress: 2,
  duration: 10,
  volume: .7,
  repeat: repeat,
  shuffle: shuffle,
  currentTrack: LokalRemoteTrack(title: title, artist: 'Artist'),
  updatedAt: updatedAt,
);

ProviderContainer _container(_Store store, _Service service) =>
    ProviderContainer(
      overrides: [
        lokalRemoteCredentialsStoreProvider.overrideWithValue(store),
        lokalPairedDesktopsStoreProvider.overrideWithValue(_PairedStore()),
        lokalRemoteServiceProvider.overrideWithValue(service),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'HTTP mode commands refresh confirmed desktop shuffle and repeat',
    () async {
      final store = _Store()..value = _credentials;
      final service = _Service([
        _snapshot(updatedAt: 1),
        _snapshot(updatedAt: 2, shuffle: true),
        _snapshot(updatedAt: 3, shuffle: true, repeat: 'one'),
      ]);
      final container = _container(store, service);
      addTearDown(container.dispose);
      final controller = container.read(lokalRemoteControllerProvider.notifier);
      await controller.connect();
      await controller.sendRawCommand('setShuffle', true);
      expect(
        container.read(lokalRemoteControllerProvider).snapshot!.shuffle,
        isTrue,
      );
      await controller.sendRawCommand('setRepeat', 'one');
      expect(
        container.read(lokalRemoteControllerProvider).snapshot!.repeat,
        'one',
      );
      expect(service.modeCommands, [
        ('setShuffle', true),
        ('setRepeat', 'one'),
      ]);
    },
  );
  testWidgets(
    'saved pairing survives idle and resumes after a day, respecting Disconnect',
    (tester) async {
      final credentials = LokalRemoteCredentials(
        origin: Uri.parse('http://desktop'),
        remoteToken: 'synthetic-pair',
        desktopId: 'desktop-fixture',
      );
      final store = _Store()..value = credentials;
      final link = _SocketLink();
      final container = ProviderContainer(
        overrides: [
          lokalRemoteCredentialsStoreProvider.overrideWithValue(store),
          lokalPairedDesktopsStoreProvider.overrideWithValue(_PairedStore()),
          lokalLinkServiceProvider.overrideWithValue(link),
          favoritesServiceProvider.overrideWithValue(_Favorites()),
        ],
      );
      final controller = container.read(lokalRemoteControllerProvider.notifier);
      await tester.pump();
      expect(link.attempts, 1);
      await tester.pump(const Duration(minutes: 4));
      expect(
        container.read(lokalRemoteControllerProvider).socketConnected,
        isTrue,
        reason: container.read(lokalRemoteControllerProvider).error,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(days: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(link.attempts, 2);
      expect(store.value, same(credentials));
      controller.disconnect();
      await controller.resumeConnection();
      expect(link.attempts, 2);
      container.dispose();
      await link.close();
    },
  );

  testWidgets('temporary authentication failure retries the same saved pair', (
    tester,
  ) async {
    final store = _Store()
      ..value = LokalRemoteCredentials(
        origin: Uri.parse('http://desktop'),
        remoteToken: 'synthetic-pair',
        desktopId: 'desktop-fixture',
      );
    final link = _SocketLink()
      ..failure = const WebSocketException('Unauthorized', 401);
    final container = ProviderContainer(
      overrides: [
        lokalRemoteCredentialsStoreProvider.overrideWithValue(store),
        lokalPairedDesktopsStoreProvider.overrideWithValue(_PairedStore()),
        lokalLinkServiceProvider.overrideWithValue(link),
        favoritesServiceProvider.overrideWithValue(_Favorites()),
      ],
    );
    container.read(lokalRemoteControllerProvider);
    await tester.pump();
    expect(
      container.read(lokalRemoteControllerProvider).status,
      LokalRemoteConnectionStatus.unauthorized,
    );
    final saved = store.value;
    link.failure = null;
    await tester.pump(const Duration(seconds: 20));
    await tester.pump();
    expect(link.attempts, 2);
    expect(
      container.read(lokalRemoteControllerProvider).socketConnected,
      isTrue,
      reason: container.read(lokalRemoteControllerProvider).error,
    );
    expect(store.value, same(saved));
    container.dispose();
    await link.close();
  });

  testWidgets(
    'verified address recovery updates origin without replacing the pairing',
    (tester) async {
      final old = LokalRemoteCredentials(
        origin: Uri.parse('http://desktop'),
        remoteToken: 'synthetic-pair',
        desktopId: 'desktop-fixture',
      );
      final store = _Store()..value = old;
      final link = _SocketLink()
        ..recoveredOrigin = Uri.parse('http://new-address');
      final container = ProviderContainer(
        overrides: [
          lokalRemoteCredentialsStoreProvider.overrideWithValue(store),
          lokalLinkServiceProvider.overrideWithValue(link),
          favoritesServiceProvider.overrideWithValue(_Favorites()),
        ],
      );
      container.read(lokalRemoteControllerProvider);
      await tester.pump();
      expect(store.value!.origin, link.recoveredOrigin);
      expect(store.value!.remoteToken, old.remoteToken);
      expect(
        container.read(lokalRemoteControllerProvider).config!.origin,
        link.recoveredOrigin,
      );
      container.dispose();
      await link.close();
    },
  );

  test(
    'forgetting a desktop retires a pairing reply still in flight',
    () async {
      final store = _Store();
      final link = _DelayedPairing();
      final container = ProviderContainer(
        overrides: [
          lokalRemoteCredentialsStoreProvider.overrideWithValue(store),
          lokalRemoteServiceProvider.overrideWithValue(_Service([])),
          lokalLinkServiceProvider.overrideWithValue(link),
          favoritesServiceProvider.overrideWithValue(_Favorites()),
        ],
      );
      addTearDown(link.close);
      addTearDown(container.dispose);
      final controller = container.read(lokalRemoteControllerProvider.notifier);
      final pairing = controller.pairDesktop(
        origin: 'http://desktop',
        code: '123456',
      );
      await link.started.future;
      await controller.forgetConfiguration(expected: null);
      link.response.complete(
        LokalRemoteCredentials(
          origin: Uri.parse('http://desktop'),
          remoteToken: 'synthetic-retired-token',
          desktopId: 'retired-desktop',
        ),
      );
      await pairing;
      expect(store.value, isNull);
      expect(
        container.read(lokalRemoteControllerProvider).status,
        LokalRemoteConnectionStatus.unconfigured,
      );
    },
  );
  test(
    'a stale confirmed Forget leaves the replacement desktop intact',
    () async {
      final store = _Store()..value = _credentials;
      final container = _container(store, _Service([]));
      addTearDown(container.dispose);
      final controller = container.read(lokalRemoteControllerProvider.notifier);
      final expected = await store.read();
      final replacement = LokalRemoteCredentials(
        origin: Uri.parse('http://replacement-desktop'),
        desktopId: 'replacement-id',
        remoteToken: 'synthetic-replacement',
      );
      store.value = replacement;
      await expectLater(
        controller.forgetConfiguration(expected: expected),
        throwsStateError,
      );
      expect(store.value, same(replacement));
    },
  );
  test('Android notification takes the new desktop recording duration, not stale player duration', () {
    const oldRecording = LokalRemoteTrack(
      id: 'one',
      title: 'One',
      artist: 'Artist',
      duration: 237,
    );
    const newRecording = LokalRemoteTrack(
      id: 'two',
      title: 'Two',
      artist: 'Artist',
      duration: 174,
    );
    LokalRemoteSnapshot state(LokalRemoteTrack track, double duration) =>
        LokalRemoteSnapshot(
          connected: true,
          isPlaying: true,
          progress: 0,
          duration: duration,
          volume: 1,
          repeat: 'none',
          shuffle: false,
          currentTrack: track,
          updatedAt: 20,
        );

    expect(
      desktopNotificationDuration(state(oldRecording, 237)),
      const Duration(seconds: 237),
    );
    // Mobile next can deliver new title before desktop top-level duration
    // updates. Its currentTrack metadata already knows the recording length.
    expect(
      desktopNotificationDuration(state(newRecording, 237)),
      const Duration(seconds: 174),
    );
    expect(
      desktopNotificationDuration(state(newRecording, 174)),
      const Duration(seconds: 174),
    );
    // Older/online desktop tracks may omit metadata duration; later player
    // duration snapshots must still be able to correct the notification.
    const missingDuration = LokalRemoteTrack(
      id: 'three',
      title: 'Three',
      artist: 'Artist',
    );
    expect(
      desktopNotificationDuration(state(missingDuration, 237)),
      const Duration(seconds: 237),
    );
    expect(
      desktopNotificationDuration(state(missingDuration, 189)),
      const Duration(seconds: 189),
    );
  });

  test(
    'reconnect keeps the last good state through a transient failure',
    () async {
      final store = _Store()..value = _credentials;
      final service = _Service([
        _snapshot(updatedAt: 1),
        const LokalRemoteNetworkException('fixture offline'),
        _snapshot(updatedAt: 2, title: 'Recovered'),
      ]);
      final container = _container(store, service);
      addTearDown(container.dispose);
      final controller = container.read(lokalRemoteControllerProvider.notifier);

      await controller.connect();
      expect(
        container.read(lokalRemoteControllerProvider).status,
        LokalRemoteConnectionStatus.connected,
      );
      expect(
        container
            .read(lokalRemoteControllerProvider)
            .snapshot!
            .currentTrack!
            .title,
        'Track',
      );

      await controller.refresh();
      final offline = container.read(lokalRemoteControllerProvider);
      expect(offline.status, LokalRemoteConnectionStatus.offline);
      expect(offline.snapshot!.currentTrack!.title, 'Track');

      await controller.connect();
      final recovered = container.read(lokalRemoteControllerProvider);
      expect(recovered.status, LokalRemoteConnectionStatus.connected);
      expect(recovered.snapshot!.currentTrack!.title, 'Recovered');
    },
  );

  test('older desktop timestamps cannot overwrite a newer snapshot', () async {
    final store = _Store();
    final service = _Service([
      _snapshot(updatedAt: 20, title: 'New'),
      _snapshot(updatedAt: 10, title: 'Old'),
    ]);
    final container = _container(store, service);
    addTearDown(container.dispose);
    final controller = container.read(lokalRemoteControllerProvider.notifier);
    await controller.saveConfiguration(
      origin: 'http://desktop:3421/remote',
      remoteToken: 'token',
      apiKey: '',
    );
    await controller.connect();
    await controller.refresh();

    expect(
      container
          .read(lokalRemoteControllerProvider)
          .snapshot!
          .currentTrack!
          .title,
      'New',
    );
  });

  test(
    'commands are delivered through the remote service, not local playback',
    () async {
      final store = _Store()..value = _credentials;
      final service = _Service([
        _snapshot(updatedAt: 1),
        _snapshot(updatedAt: 2),
      ]);
      final container = _container(store, service);
      addTearDown(container.dispose);
      final controller = container.read(lokalRemoteControllerProvider.notifier);
      await controller.connect();
      await controller.sendCommand(LokalRemoteAction.volume, value: .25);

      expect(service.commands, [(LokalRemoteAction.volume, .25)]);
    },
  );
}
