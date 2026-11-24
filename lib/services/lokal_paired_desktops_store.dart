import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/lokal_remote_state.dart';
import 'playback_secure_storage.dart';

/// Secure registry for every desktop paired with this phone. The legacy
/// credential store remains the active-session adapter; this registry owns
/// the durable collection and selected desktop identity.
class LokalPairedDesktop {
  const LokalPairedDesktop({
    required this.id,
    required this.name,
    required this.credentials,
    this.lastConnectedAt,
  });

  final String id;
  final String name;
  final LokalRemoteCredentials credentials;
  final DateTime? lastConnectedAt;
}

class LokalPairedDesktopsStore {
  LokalPairedDesktopsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const PlaybackSecureStorage();

  static const storageKey = 'konnekted.lokal_paired_desktops.v1';
  final FlutterSecureStorage _storage;
  Future<void> _tail = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final pending = _tail.then((_) => operation());
    _tail = pending.then<void>((_) {}, onError: (Object _) {});
    return pending;
  }

  static String identity(LokalRemoteCredentials credentials) =>
      credentials.desktopId?.trim().isNotEmpty == true
          ? credentials.desktopId!
          : credentials.pairingID?.trim().isNotEmpty == true
              ? credentials.pairingID!
              : credentials.origin.authority;

  Future<List<LokalPairedDesktop>> readAll({
    LokalRemoteCredentials? legacyActive,
  }) => _serial(() async {
    final entries = await _readEntries();
    if (entries.isEmpty && legacyActive != null) {
      final id = identity(legacyActive);
      final migrated = _entry(legacyActive, id: id);
      await _writeEntries([migrated], activeId: id);
      return [migrated];
    }
    return entries;
  });

  Future<String?> activeId() => _serial(() async {
    final raw = await _storage.read(key: storageKey);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      return data is Map ? data['activeId'] as String? : null;
    } on Object {
      return null;
    }
  });

  Future<void> add(LokalRemoteCredentials credentials) => _serial(() async {
    final entries = await _readEntries();
    final id = identity(credentials);
    final next = _entry(credentials, id: id);
    final index = entries.indexWhere((entry) => entry.id == id);
    if (index < 0) {
      entries.add(next);
    } else {
      entries[index] = next;
    }
    await _writeEntries(entries, activeId: id);
  });

  Future<LokalRemoteCredentials?> select(String id) => _serial(() async {
    final entries = await _readEntries();
    final index = entries.indexWhere((entry) => entry.id == id);
    if (index < 0) throw StateError('This paired desktop is no longer saved.');
    await _writeEntries(entries, activeId: id);
    return entries[index].credentials;
  });

  Future<LokalRemoteCredentials?> remove(
    LokalRemoteCredentials expected,
  ) => _serial(() async {
    final entries = await _readEntries();
    final id = identity(expected);
    final index = entries.indexWhere((entry) => entry.id == id);
    if (index < 0 ||
        !SecureCredentialComparison.matches(
          entries[index].credentials,
          expected,
        )) {
      throw StateError('Desktop pairing changed. Refresh and retry.');
    }
    entries.removeAt(index);
    final raw = await _storage.read(key: storageKey);
    String? active;
    try {
      final data = raw == null ? null : jsonDecode(raw);
      active = data is Map ? data['activeId'] as String? : null;
    } on Object {}
    final nextActive = active == id
        ? (entries.isEmpty ? null : entries.last.id)
        : active;
    await _writeEntries(entries, activeId: nextActive);
    return entries.firstWhereOrNull((entry) => entry.id == nextActive)?.credentials;
  });

  Future<List<LokalPairedDesktop>> _readEntries() async {
    final raw = await _storage.read(key: storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final data = jsonDecode(raw);
      if (data is! Map || data['version'] != 1 || data['devices'] is! List) {
        return [];
      }
      return [
        for (final value in data['devices'] as List)
          if (value is Map)
            _decodeEntry(Map<String, dynamic>.from(value)),
      ];
    } on Object {
      return [];
    }
  }

  LokalPairedDesktop _decodeEntry(Map<String, dynamic> value) {
    final credentials = LokalRemoteCredentials(
      origin: Uri.parse(value['origin'] as String),
      remoteToken: value['remoteToken'] as String? ?? '',
      apiKey: value['apiKey'] as String? ?? '',
      desktopId: value['desktopId'] as String?,
      desktopUserId: value['desktopUserId'] as String?,
      pairingID: value['pairingID'] as String?,
    );
    return _entry(
      credentials,
      id: value['id'] as String,
      name: value['name'] as String? ?? credentials.origin.host,
      lastConnectedAt: value['lastConnectedAt'] is String
          ? DateTime.tryParse(value['lastConnectedAt'] as String)
          : null,
    );
  }

  LokalPairedDesktop _entry(
    LokalRemoteCredentials credentials, {
    required String id,
    String? name,
    DateTime? lastConnectedAt,
  }) => LokalPairedDesktop(
    id: id,
    name: name ?? credentials.origin.host,
    credentials: credentials,
    lastConnectedAt: lastConnectedAt,
  );

  Future<void> _writeEntries(
    List<LokalPairedDesktop> entries, {
    required String? activeId,
  }) async {
    await _storage.write(
      key: storageKey,
      value: jsonEncode({
        'version': 1,
        'activeId': activeId,
        'devices': [
          for (final entry in entries)
            {
              'id': entry.id,
              'name': entry.name,
              'origin': entry.credentials.origin.toString(),
              'remoteToken': entry.credentials.remoteToken,
              'apiKey': entry.credentials.apiKey,
              'desktopId': entry.credentials.desktopId,
              'desktopUserId': entry.credentials.desktopUserId,
              'pairingID': entry.credentials.pairingID,
              'lastConnectedAt': entry.lastConnectedAt?.toIso8601String(),
            },
        ],
      }),
    );
  }
}

class SecureCredentialComparison {
  static bool matches(
    LokalRemoteCredentials a,
    LokalRemoteCredentials b,
  ) =>
      a.origin == b.origin &&
      a.desktopId == b.desktopId &&
      a.desktopUserId == b.desktopUserId &&
      a.pairingID == b.pairingID &&
      a.remoteToken == b.remoteToken &&
      a.apiKey == b.apiKey;
}

extension on List<LokalPairedDesktop> {
  T? firstWhereOrNull<T>(T Function(LokalPairedDesktop) test) {
    for (final value in this) {
      if (test(value)) return value as T;
    }
    return null;
  }
}
