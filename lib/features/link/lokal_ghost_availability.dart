import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../models/song.dart';
import '../../services/network_cache_service.dart';
import '../../providers/lokal_remote_provider.dart';

/// The paired desktop's HTTP media endpoint does not need a remote-control
/// websocket. Share credentials across Library rows rather than reading
/// secure storage separately for every desktop song in a large list.
@visibleForTesting
bool desktopStreamingCredentialsMatch({
  required String storedUsername,
  required String storedBaseUrl,
  required String? desktopId,
  required String? desktopUserId,
  required String? credentialOrigin,
}) {
  if (desktopId == null ||
      credentialOrigin == null ||
      storedUsername != '$desktopId:${desktopUserId ?? 'guest'}') {
    return false;
  }
  final server = Uri.tryParse(storedBaseUrl),
      credential = Uri.tryParse(credentialOrigin);
  bool rootOrigin(Uri? value) =>
      value != null &&
      {'http', 'https'}.contains(value.scheme) &&
      value.host.isNotEmpty &&
      value.userInfo.isEmpty &&
      (value.path.isEmpty || value.path == '/') &&
      !value.hasQuery &&
      !value.hasFragment;
  return rootOrigin(server) &&
      rootOrigin(credential) &&
      server!.origin == credential!.origin;
}

/// A bounded authenticated HTTP probe of the paired desktop. The remote
/// control *WebSocket* is optional: the GET state endpoint is available
/// independently and proves the PC is online before advertising an uncached
/// audio stream. This probe runs once per linked server, not once per row.
@visibleForTesting
Future<bool> desktopHttpReachable(
  Future<void> Function() probe, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  try {
    await probe().timeout(timeout);
    return true;
  } catch (_) {
    return false;
  }
}

final lokalDesktopStreamingAvailableProvider = FutureProvider.autoDispose
    .family<bool, int>((ref, serverId) async {
      // Both saveConfiguration and forgetConfiguration publish a new controller
      // config. Watching it prevents mounted Library rows retaining obsolete
      // results after pairing changes while keeping one HTTP probe per server.
      // Socket changes are refresh hints; HTTP never requires a live socket.
      ref.watch(
        lokalRemoteControllerProvider.select(
          (state) => (state.config, state.socketConnected),
        ),
      );
      final credentialsStore = ref.read(lokalRemoteCredentialsStoreProvider);
      final pairedStore = ref.read(lokalPairedDesktopsStoreProvider);
      final service = ref.read(lokalRemoteServiceProvider);
      final lease = ref.keepAlive();
      Timer? expiry;
      var disposed = false;
      ref.onDispose(() {
        disposed = true;
        expiry?.cancel();
      });
      try {
        final server = await Database.networkServers.get(serverId);
        if (server == null) return false;
        var credentials = await credentialsStore.read();
        bool matches(
          String? desktopId,
          String? desktopUserId,
          String? origin,
        ) => desktopStreamingCredentialsMatch(
          storedUsername: server.username ?? '',
          storedBaseUrl: server.baseUrl,
          desktopId: desktopId,
          desktopUserId: desktopUserId,
          credentialOrigin: origin,
        );
        if (credentials == null ||
            !matches(
              credentials.desktopId,
              credentials.desktopUserId,
              credentials.origin.toString(),
            )) {
          final legacyActive = credentials;
          credentials = null;
          try {
            final paired = await pairedStore.readAll(
              legacyActive: legacyActive,
            );
            for (final entry in paired) {
              final candidate = entry.credentials;
              if (matches(
                candidate.desktopId,
                candidate.desktopUserId,
                candidate.origin.toString(),
              )) {
                credentials = candidate;
                break;
              }
            }
            if (credentials == null) {
              for (final entry in paired) {
                final candidate = entry.credentials;
                if (candidate.desktopId != null &&
                    server.username ==
                        '${candidate.desktopId}:${candidate.desktopUserId ?? 'guest'}' &&
                    desktopStreamingCredentialsMatch(
                      storedUsername: server.username ?? '',
                      storedBaseUrl: candidate.origin.toString(),
                      desktopId: candidate.desktopId,
                      desktopUserId: candidate.desktopUserId,
                      credentialOrigin: candidate.origin.toString(),
                    )) {
                  credentials = candidate;
                  break;
                }
              }
            }
          } on Object {
            credentials = null;
          }
        }
        if (credentials == null) return false;

        final resolved = credentials;
        return await desktopHttpReachable(() async {
          await service.fetchState(resolved);
        });
      } catch (_) {
        return false;
      } finally {
        // Read-only bulk scans also reuse one result per server. Pairing
        // changes still invalidate this family immediately.
        if (!disposed) expiry = Timer(const Duration(seconds: 5), lease.close);
      }
    });

final lokalSongAvailableProvider = FutureProvider.autoDispose.family<bool, Song>(
  (ref, song) async {
    if (song.sourceType != 'lokal') return true;
    final serverId = song.remoteServerId, remoteId = song.remoteId;
    if (serverId == null || remoteId == null) return false;
    // Subscribe before the async cache lookup so a disposed row does not try to
    // watch a provider after its widget has already left the screen.
    final pairedDesktop = ref.watch(
      lokalDesktopStreamingAvailableProvider(serverId).future,
    );
    // Cached desktop originals remain playable when the PC is disconnected.
    if (await NetworkCacheService().getPath(serverId, remoteId) != null) {
      return true;
    }
    return pairedDesktop;
  },
);
