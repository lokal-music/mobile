import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/lokal_remote_state.dart';

class LokalRemoteException implements Exception {
  const LokalRemoteException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LokalRemoteConfigurationException extends LokalRemoteException {
  const LokalRemoteConfigurationException(super.message);
}

class LokalRemoteAuthException extends LokalRemoteException {
  const LokalRemoteAuthException()
    : super(
        'Lokal rejected the remote credentials. Check the token or API key.',
      );
}

class LokalRemoteProtocolException extends LokalRemoteException {
  const LokalRemoteProtocolException(super.message);
}

class LokalRemoteNetworkException extends LokalRemoteException {
  const LokalRemoteNetworkException(super.message);
}

/// HTTP client for Lokal desktop's authenticated LAN remote protocol.
class LokalRemoteService {
  LokalRemoteService({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 5),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration requestTimeout;

  void close() => _client.close();

  static const _allowedActions = {
    'togglePlay',
    'play',
    'pause',
    'next',
    'prev',
    'volume',
    'seek',
    'toggleLike',
  };

  /// Accepts the desktop's `/remote` link as well as its origin, but never
  /// carries a token in the URI. Only the known desktop paths are accepted so
  /// a typo cannot silently send credentials to another web application.
  static Uri normalizeOrigin(String input) {
    final value = input.trim();
    if (value.isEmpty) {
      throw const LokalRemoteConfigurationException(
        'Enter the Lokal desktop address.',
      );
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const LokalRemoteConfigurationException(
        'Use a complete http:// or https:// Lokal address without credentials.',
      );
    }
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.isNotEmpty &&
        path != '/remote' &&
        path != '/api' &&
        path != '/api/remote') {
      throw const LokalRemoteConfigurationException(
        'Use the Lokal address or its /remote link.',
      );
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    );
  }

  Future<LokalRemoteSnapshot> fetchState(
    LokalRemoteCredentials credentials,
  ) async {
    final response = await _request(
      () => _client
          .get(
            _endpoint(credentials.origin, 'state'),
            headers: _headers(credentials),
          )
          .timeout(requestTimeout),
    );
    try {
      return LokalRemoteSnapshot.fromJson(jsonDecode(response.body));
    } on FormatException catch (error) {
      throw LokalRemoteProtocolException(error.message);
    } on Object {
      throw const LokalRemoteProtocolException(
        'Lokal returned an invalid remote state.',
      );
    }
  }

  /// Fetch a PC cover without requiring a synced library/database on this device.
  /// Redirects lose all desktop credentials and may target HTTPS images only.
  Future<List<int>> fetchArtwork(
    LokalRemoteCredentials credentials,
    String trackId,
  ) async {
    final request =
        http.Request(
            'GET',
            credentials.origin.replace(
              pathSegments: ['api', 'artwork', trackId],
              queryParameters: {'full': '1'},
            ),
          )
          ..headers.addAll(_headers(credentials))
          ..followRedirects = false;
    var response = await _client.send(request).timeout(requestTimeout);
    if ({301, 302, 307, 308}.contains(response.statusCode)) {
      final target = Uri.tryParse(response.headers['location'] ?? '');
      await response.stream.drain<void>().timeout(requestTimeout);
      if (target == null ||
          target.scheme != 'https' ||
          target.host.isEmpty ||
          target.userInfo.isNotEmpty) {
        throw const LokalRemoteProtocolException(
          'Invalid desktop artwork redirect.',
        );
      }
      response = await _client
          .send(http.Request('GET', target)..followRedirects = false)
          .timeout(requestTimeout);
    }
    if (response.statusCode != 200) {
      await response.stream.drain<void>().timeout(requestTimeout);
      throw const LokalRemoteProtocolException(
        'Desktop artwork is unavailable.',
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(requestTimeout)) {
      bytes.addAll(chunk);
      if (bytes.length > 10 * 1024 * 1024) {
        throw const LokalRemoteProtocolException(
          'Desktop artwork is too large.',
        );
      }
    }
    if (bytes.isEmpty) {
      throw const LokalRemoteProtocolException('Desktop artwork is empty.');
    }
    return bytes;
  }

  Future<void> sendCommand(
    LokalRemoteCredentials credentials,
    LokalRemoteAction action, {
    double? value,
  }) async {
    if (action.requiresValue && (value == null || !value.isFinite)) {
      throw const LokalRemoteProtocolException(
        'This remote command needs a finite value.',
      );
    }
    final actionName = action.wireName;
    if (!_allowedActions.contains(actionName)) {
      throw const LokalRemoteProtocolException(
        'Remote command is not supported.',
      );
    }
    final body = <String, Object?>{'action': actionName};
    if (value != null) body['value'] = value;
    final response = await _request(
      () => _client
          .post(
            _endpoint(credentials.origin, 'command'),
            headers: {
              ..._headers(credentials),
              'content-type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(requestTimeout),
    );
    try {
      final json = jsonDecode(response.body);
      if (json is! Map || json['ok'] != true) {
        throw const LokalRemoteProtocolException(
          'Lokal did not accept the remote command.',
        );
      }
    } on LokalRemoteProtocolException {
      rethrow;
    } on Object {
      throw const LokalRemoteProtocolException(
        'Lokal returned an invalid command response.',
      );
    }
  }

  /// Desktop library playback also works if the paired WebSocket has dropped
  /// but the authenticated HTTP remote remains reachable.
  Future<void> sendLibraryCommand(
    LokalRemoteCredentials credentials,
    String action,
    Map<String, dynamic> value,
  ) async {
    if (action != 'playLibraryTrack' && action != 'queueTracks') {
      throw const LokalRemoteProtocolException(
        'This remote library command is not supported.',
      );
    }
    await _postCommand(credentials, action, value);
  }

  /// Preserve boolean/string mode values when the paired socket is offline.
  Future<void> sendPlaybackModeCommand(
    LokalRemoteCredentials credentials,
    String action,
    Object? value,
  ) async {
    final valid =
        action == 'setShuffle' && value is bool ||
        action == 'setRepeat' && const {'none', 'all', 'one'}.contains(value);
    if (!valid) {
      throw const LokalRemoteProtocolException(
        'Invalid playback mode command.',
      );
    }
    await _postCommand(credentials, action, value);
  }

  Future<void> _postCommand(
    LokalRemoteCredentials credentials,
    String action,
    Object? value,
  ) async {
    final response = await _request(
      () => _client
          .post(
            _endpoint(credentials.origin, 'command'),
            headers: {
              ..._headers(credentials),
              'content-type': 'application/json',
            },
            body: jsonEncode({'action': action, 'value': value}),
          )
          .timeout(requestTimeout),
    );
    try {
      final payload = jsonDecode(response.body);
      if (payload is! Map || payload['ok'] != true) {
        throw const LokalRemoteProtocolException(
          'The desktop rejected the playback command.',
        );
      }
    } on LokalRemoteProtocolException {
      rethrow;
    } on Object {
      throw const LokalRemoteProtocolException(
        'The desktop returned an invalid playback response.',
      );
    }
  }

  /// Look up a shared phone recording without requiring the user to resync
  /// their whole library. The desktop already exposes an authenticated,
  /// paginated title search; never download or transfer audio here.
  ///
  /// If the result would be incomplete, fail closed rather than choosing a
  /// plausible track from only the first page.
  Future<List<Map<String, dynamic>>> findDesktopTrackCandidates(
    LokalRemoteCredentials credentials,
    String title,
  ) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return const [];
    // Desktop's ?q= uses SQL LIKE. Strip parentheticals/brackets and trailing
    // " - ..." suffixes so "Song (Artist Mix)" also returns "Song - Artist Mix"
    // for recording-level verification in matchedDesktopIdFromCandidates.
    final stripped = trimmed
        .replaceFirst(RegExp(r'\s*[(\[].*$'), '')
        .replaceFirst(RegExp(r'\s+[-–—]\s+.*$'), '')
        .trim();
    final query = stripped.length >= 3 ? stripped : trimmed;
    const pageSize = 250;
    const maxPages = 4;
    final candidates = <Map<String, dynamic>>[];
    for (var page = 0; page < maxPages; page++) {
      final uri = _endpoint(credentials.origin, 'library/tracks').replace(
        queryParameters: {
          'q': query,
          'limit': '$pageSize',
          'offset': '${page * pageSize}',
        },
      );
      final response = await _request(
        () => _client
            .get(uri, headers: _headers(credentials))
            .timeout(requestTimeout),
      );
      Map<String, dynamic> payload;
      try {
        payload = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      } on Object {
        throw const LokalRemoteProtocolException(
          'Lokal returned invalid desktop library search results.',
        );
      }
      final items = payload['items'];
      if (items is! List) {
        throw const LokalRemoteProtocolException(
          'Lokal returned invalid desktop library search results.',
        );
      }
      for (final item in items) {
        if (item is Map) {
          candidates.add(Map<String, dynamic>.from(item));
        }
      }
      if (payload['hasMore'] != true) return candidates;
      if (items.isEmpty) break;
    }
    return const [];
  }

  Uri _endpoint(Uri origin, String resource) => origin.replace(
    path: '/api/remote/$resource',
    query: null,
    fragment: null,
  );

  Map<String, String> _headers(LokalRemoteCredentials credentials) => {
    if (credentials.remoteToken.isNotEmpty)
      'x-remote-token': credentials.remoteToken,
    if (credentials.apiKey.isNotEmpty) 'x-api-key': credentials.apiKey,
    'accept': 'application/json',
  };

  Future<http.Response> _request(
    Future<http.Response> Function() request,
  ) async {
    try {
      final response = await request();
      if (response.statusCode == 401) throw const LokalRemoteAuthException();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LokalRemoteProtocolException(switch (response.statusCode) {
          400 => 'Lokal rejected the remote request.',
          503 => 'Lokal remote control is not ready on the desktop.',
          _ => 'Lokal remote control returned HTTP ${response.statusCode}.',
        });
      }
      return response;
    } on LokalRemoteException {
      rethrow;
    } on TimeoutException {
      throw const LokalRemoteNetworkException(
        'Lokal did not respond before the connection timed out.',
      );
    } on Object {
      throw const LokalRemoteNetworkException(
        'Could not reach Lokal on the local network.',
      );
    }
  }
}
