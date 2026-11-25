import 'package:flick/models/lokal_remote_state.dart';
import 'package:flick/services/lokal_paired_desktops_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('keeps multiple independent desktop credentials and switches selection', () async {
    final store = LokalPairedDesktopsStore(storage: storage);
    final first = LokalRemoteCredentials(
      origin: Uri.parse('http://192.0.2.10:3421'),
      desktopId: 'desktop-one',
      desktopUserId: 'owner-one',
      remoteToken: 'synthetic-token-one',
      pairingID: '11111111-1111-4111-8111-111111111111',
    );
    final second = LokalRemoteCredentials(
      origin: Uri.parse('http://192.0.2.20:3421'),
      desktopId: 'desktop-two',
      desktopUserId: 'owner-two',
      remoteToken: 'synthetic-token-two',
      pairingID: '22222222-2222-4222-8222-222222222222',
    );

    await store.add(first);
    await store.add(second);

    final paired = await store.readAll();
    expect(paired.map((desktop) => desktop.id), ['desktop-one', 'desktop-two']);
    expect(paired.first.credentials.remoteToken, first.remoteToken);
    expect(paired.last.credentials.remoteToken, second.remoteToken);
    expect(await store.activeId(), 'desktop-two');

    final selected = await store.select('desktop-one');
    expect(selected!.remoteToken, first.remoteToken);
    expect(await store.activeId(), 'desktop-one');

    final fallback = await store.remove(first);
    expect(fallback!.desktopId, 'desktop-two');
    expect((await store.readAll()).map((desktop) => desktop.id), ['desktop-two']);
    expect(await store.activeId(), 'desktop-two');
  });

  test('an intentionally empty registry does not resurrect a forgotten legacy pair', () async {
    final store = LokalPairedDesktopsStore(storage: storage);
    final legacy = LokalRemoteCredentials(
      origin: Uri.parse('http://forgotten-pc:3421'),
      desktopId: 'forgotten-desktop',
      remoteToken: 'synthetic-forgotten-token',
    );
    await store.add(legacy);
    await store.remove(legacy);
    expect(await store.resolveActive(legacyActive: legacy), isNull);
    expect(await store.readAll(legacyActive: legacy), isEmpty);
  });

  test('migrates an existing single desktop without changing its credentials', () async {
    final store = LokalPairedDesktopsStore(storage: storage);
    final legacy = LokalRemoteCredentials(
      origin: Uri.parse('http://legacy-pc:3421'),
      desktopId: 'legacy-desktop',
      remoteToken: 'synthetic-legacy-token',
    );
    final migrated = await store.readAll(legacyActive: legacy);
    expect(migrated, hasLength(1));
    expect(migrated.single.credentials.remoteToken, legacy.remoteToken);
    expect(migrated.single.id, 'legacy-desktop');
    expect(await store.activeId(), 'legacy-desktop');
  });

  test('dual-boot OS installations sharing an IP:port stay distinct and retain names', () async {
    final store = LokalPairedDesktopsStore(storage: storage);
    final sharedOrigin = Uri.parse('http://192.168.1.178:3421');
    final windows = LokalRemoteCredentials(
      origin: sharedOrigin,
      desktopId: 'windows-partition-id',
      desktopUserId: 'guest',
      remoteToken: 'windows-token',
      pairingID: '11111111-1111-4111-8111-111111111111',
    );
    final linux = LokalRemoteCredentials(
      origin: sharedOrigin,
      desktopId: 'linux-partition-id',
      desktopUserId: 'guest',
      remoteToken: 'linux-token',
      pairingID: '22222222-2222-4222-8222-222222222222',
    );

    await store.add(windows);
    await store.updateMetadata('windows-partition-id', name: 'MY-PC (Windows)');
    await store.add(linux);
    await store.updateMetadata('linux-partition-id', name: 'pop-os (Linux)');

    // Re-adding credentials (e.g. after switching or address verification)
    // preserves the learned hostname/platform label.
    await store.add(windows);

    final paired = await store.readAll();
    expect(paired, hasLength(2));
    expect(paired.map((d) => d.id), ['windows-partition-id', 'linux-partition-id']);
    expect(paired.map((d) => d.name), ['MY-PC (Windows)', 'pop-os (Linux)']);

    final winConfig = LokalRemoteConfig.fromCredentials(windows);
    final linConfig = LokalRemoteConfig.fromCredentials(linux);
    expect(winConfig.origin, linConfig.origin);
    expect(winConfig.identity, 'windows-partition-id');
    expect(linConfig.identity, 'linux-partition-id');
    expect(winConfig.identity == linConfig.identity, isFalse);
  });
}
