import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/lokal_remote_state.dart';
import '../lokal_remote_service.dart';
import 'link_protocol.dart';
import 'link_identity.dart';

class LokalDiscoveredDesktop {
  const LokalDiscoveredDesktop({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
  });
  final String id, name, host;
  final int port;
  Uri get origin => Uri(scheme: 'http', host: host, port: port);
}

class LokalPairingLink {
  const LokalPairingLink(this.origin, this.desktopId, this.code);
  final Uri origin;
  final String desktopId, code;
  factory LokalPairingLink.parse(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri?.scheme != 'lokal' || uri?.host != 'pair')
      throw const FormatException('Scan a Lokal desktop pairing code.');
    final query = uri!.queryParameters;
    final host = query['host'] ?? '';
    final address = InternetAddress.tryParse(host);
    final port = int.tryParse(query['port'] ?? '') ?? 0;
    final code = query['code'] ?? '', id = query['id'] ?? '';
    if (address == null ||
        port < 1 ||
        port > 65535 ||
        !RegExp(r'^\d{6}$').hasMatch(code) ||
        !RegExp(r'^[a-zA-Z0-9_-]{8,128}$').hasMatch(id))
      throw const FormatException('This pairing code is incomplete.');
    return LokalPairingLink(
      Uri(scheme: 'http', host: host, port: port),
      id,
      code,
    );
  }
}

/// Paired LAN socket. Secrets stay in headers and encrypted storage, never URLs.
class LokalLinkService {
  LokalLinkService({http.Client? identityClient})
    : _identityClient = identityClient ?? http.Client();

  final http.Client _identityClient;
  static const channel = MethodChannel('lokal/desktop_link');
  final _messages = StreamController<LinkMessage>.broadcast();
  final _connections = StreamController<bool>.broadcast();
  final Map<String, Completer<LinkMessage>> _requests = {};
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Set<String>? _peerCapabilities;
  bool _closed = false;
  int _epoch = 0;
  int get connectionGeneration => _epoch;
  Stream<LinkMessage> get messages => _messages.stream;
  Stream<bool> get connections => _connections.stream;
  bool get connected => _socket?.readyState == WebSocket.open;
  bool get supportsTrackLifecycle =>
      _peerCapabilities == null ||
      _peerCapabilities!.contains('track_lifecycle');

  Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('lokal.link.device_id');
    if (id == null) {
      id = linkUuid();
      await prefs.setString('lokal.link.device_id', id);
    }
    return id;
  }

  /// Optional presentation metadata. Missing native support must never block
  /// pairing/reconnect or replace a previously reported name with a fallback.
  Future<String?> deviceDisplayName() async {
    try {
      final value = await channel
          .invokeMethod<Object?>('getDeviceName')
          .timeout(const Duration(seconds: 2));
      return _cleanDeviceName(value);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  static String? _cleanDeviceName(Object? value) {
    if (value is! String) return null;
    final clean = value
        .replaceAll(RegExp(r'[\x00-\x1f\x7f-\x9f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.isEmpty) return null;
    return String.fromCharCodes(clean.runes.take(100));
  }

  Future<void> _requestLocalNetwork() async {
    try {
      if (await channel.invokeMethod<bool>('requestLocalNetwork') == false)
        throw const LokalRemoteConfigurationException(
          'Allow local network access to connect to your desktop.',
        );
    } on MissingPluginException {
      /* Desktop and non-Android hosts. */
    }
  }

  Future<List<LokalDiscoveredDesktop>> discover() async {
    await _requestLocalNetwork();
    try {
      final values = await channel.invokeListMethod<dynamic>('discover');
      return [
        for (final raw in values ?? <dynamic>[])
          if (raw is Map && raw['host'] is String && raw['port'] is int)
            LokalDiscoveredDesktop(
              id: raw['id']?.toString() ?? '',
              name: raw['name']?.toString() ?? 'Lokal desktop',
              host: raw['host'] as String,
              port: raw['port'] as int,
            ),
      ];
    } on MissingPluginException {
      return [];
    } on PlatformException catch (error) {
      throw LokalRemoteConfigurationException(
        error.message ?? 'Local discovery could not start. Enter the desktop address or try again.',
      );
    }
  }

  String? _lastPairedDesktopName;

  /// Friendly name reported by the most recent `/api/remote/pair` response,
  /// including OS platform when provided (e.g. `pop-os (Linux)`).
  String? get lastPairedDesktopName => _lastPairedDesktopName;

  static String? formatDesktopDisplayName(Object? rawName, [Object? rawPlatform]) {
    final base = _cleanDeviceName(rawName);
    final platformLabel = switch (rawPlatform) {
      'linux' => 'Linux',
      'win32' => 'Windows',
      'darwin' => 'macOS',
      _ => null,
    };
    if (base == null && platformLabel == null) return null;
    if (base == null) return 'Lokal ($platformLabel)';
    if (platformLabel == null ||
        base.toLowerCase().contains(platformLabel.toLowerCase())) {
      return base;
    }
    return '$base ($platformLabel)';
  }

  Future<LokalRemoteCredentials> pair({
    required Uri origin,
    required String code,
    String? expectedDesktopId,
    String? deviceName,
  }) async {
    if (!RegExp(r'^\d{6}$').hasMatch(code))
      throw const LokalRemoteConfigurationException(
        'Enter the six-digit code shown on your desktop.',
      );
    await _requestLocalNetwork();
    final normalized = LokalRemoteService.normalizeOrigin(origin.toString());
    final port = normalized.hasPort
        ? normalized.port
        : (normalized.scheme == 'https' ? 443 : 3421);
    final name =
        _cleanDeviceName(deviceName) ??
        await deviceDisplayName() ??
        (Platform.isIOS
            ? 'iOS device'
            : Platform.isAndroid
            ? 'Android device'
            : 'Mobile device');
    late final http.Response response;
    try {
      response = await http
          .post(
            normalized.replace(path: '/api/remote/pair'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'code': code,
              'deviceName': name,
              'deviceId': await deviceId(),
            }),
          )
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw LokalRemoteNetworkException(
        'Could not reach Lokal at ${normalized.authority} (connection timed out — check that both devices share the same Wi-Fi/LAN and TCP port $port is allowed through your desktop firewall).',
      );
    } on SocketException {
      throw LokalRemoteNetworkException(
        'Could not reach Lokal at ${normalized.authority}. Check that Lokal is open on the same Wi-Fi/LAN and TCP port $port is allowed through your desktop firewall.',
      );
    } on HandshakeException {
      throw const LokalRemoteNetworkException(
        'TLS handshake with Lokal failed. Check the certificate or use LAN HTTP.',
      );
    } on http.ClientException {
      throw LokalRemoteNetworkException(
        'Could not reach Lokal at ${normalized.authority}. Check Wi-Fi/LAN connectivity and allow TCP port $port in your desktop firewall.',
      );
    }
    if (response.statusCode != 200) {
      String? serverError;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['error'] is String) {
          final text = (decoded['error'] as String).trim();
          if (text.isNotEmpty) serverError = text;
        }
      } on FormatException {
        // Non-JSON error response; fall back to status-based error below.
      }
      if (response.statusCode == 401) {
        if (serverError != null) {
          throw LokalRemoteConfigurationException(serverError);
        }
        throw const LokalRemoteAuthException();
      }
      throw LokalRemoteProtocolException(
        serverError ??
            'Desktop pairing failed (HTTP ${response.statusCode}). Try generating a new code.',
      );
    }
    final Object? value;
    try {
      value = jsonDecode(response.body);
    } on FormatException {
      throw const LokalRemoteProtocolException(
        'Lokal returned an invalid pairing response.',
      );
    }
    if (value is! Map ||
        value['token'] is! String ||
        value['desktopId'] is! String ||
        (expectedDesktopId != null && value['desktopId'] != expectedDesktopId))
      throw const LokalRemoteProtocolException(
        'Pairing response did not match this desktop.',
      );
    _lastPairedDesktopName = formatDesktopDisplayName(
      value['name'],
      value['platform'],
    );
    return LokalRemoteCredentials(
      origin: normalized,
      remoteToken: value['token'] as String,
      desktopId: value['desktopId'] as String,
      desktopUserId: value['user'] is Map
          ? (value['user'] as Map)['id']?.toString()
          : null,
      pairingID: linkUuid(),
    );
  }

  /// Zero-secret challenge check proving whether the desktop currently running
  /// at [origin] holds the paired verifier for [credentials] (e.g. after a
  /// dual-boot machine reboots into another already-paired OS at the same IP).
  Future<bool> verifyDesktopIdentity(
    Uri origin,
    LokalRemoteCredentials credentials,
  ) async {
    if (credentials.desktopId == null || credentials.remoteToken.isEmpty) {
      return false;
    }
    try {
      return await verifyLinkedDesktop(
        client: _identityClient,
        origin: origin,
        credentials: credentials,
        deviceId: await deviceId(),
      );
    } on Object {
      return false;
    }
  }

  Future<Uri> connect(LokalRemoteCredentials credentials) async {
    final epoch = ++_epoch;
    await _disconnectSocket();
    await _requestLocalNetwork();
    _checkEpoch(epoch);
    try {
      await _openSocket(credentials, credentials.origin, epoch);
      return credentials.origin;
    } catch (_) {
      _checkEpoch(epoch);
      if (credentials.desktopId == null ||
          credentials.remoteToken.isEmpty ||
          credentials.origin.scheme != 'http')
        rethrow;
      // A DHCP lease or Wi-Fi/Ethernet change can invalidate the QR address.
      // Retain the same pairing; discovery never creates or replaces one.
      final discovered = await discover().timeout(const Duration(seconds: 8));
      _checkEpoch(epoch);
      final seen = <Uri>{credentials.origin};
      for (final desktop
          in discovered
              .where((item) => item.id == credentials.desktopId)
              .take(8)) {
        final address = InternetAddress.tryParse(desktop.host);
        if (address == null ||
            desktop.port < 1 ||
            desktop.port > 65535 ||
            address.isMulticast ||
            address.rawAddress.every((byte) => byte == 0))
          continue;
        final origin = desktop.origin;
        if (!seen.add(origin)) continue;
        try {
          final verified = await verifyLinkedDesktop(
            client: _identityClient,
            origin: origin,
            credentials: credentials,
            deviceId: await deviceId(),
          );
          _checkEpoch(epoch);
          if (!verified) continue;
          await _openSocket(credentials, origin, epoch);
          return origin;
        } on Object {
          _checkEpoch(epoch);
          // Try another address of this same desktop, never another pairing.
        }
      }
      rethrow;
    }
  }

  void _checkEpoch(int epoch) {
    if (_closed || epoch != _epoch) {
      throw const LokalRemoteNetworkException('Desktop connection changed.');
    }
  }

  Future<void> _openSocket(
    LokalRemoteCredentials credentials,
    Uri origin,
    int epoch,
  ) async {
    _checkEpoch(epoch);
    _peerCapabilities = null;
    final uri = origin.replace(
      scheme: origin.scheme == 'https' ? 'wss' : 'ws',
      path: '/api/remote/ws',
    );
    final name = await deviceDisplayName();
    _checkEpoch(epoch);
    var expired = false;
    final socket =
        await WebSocket.connect(
              uri.toString(),
              headers: {
                'x-remote-token': credentials.remoteToken,
                if (credentials.apiKey.isNotEmpty)
                  'x-api-key': credentials.apiKey,
              },
            )
            .then((socket) {
              if (expired || _closed || epoch != _epoch) {
                unawaited(socket.close());
                throw const LokalRemoteNetworkException(
                  'Desktop connection changed.',
                );
              }
              return socket;
            })
            .timeout(
              const Duration(seconds: 8),
              onTimeout: () {
                expired = true;
                throw TimeoutException('Desktop connection timed out.');
              },
            );
    _checkEpoch(epoch);
    _socket = socket;
    socket.pingInterval = const Duration(seconds: 25);
    _subscription = socket.listen(
      (raw) {
        if (!identical(_socket, socket)) return;
        if (raw is! String || raw.length > 1024 * 1024) return;
        try {
          final message = LinkMessage.decode(raw);
          if (message.type == 'hello') {
            final rawCaps = message.body['capabilities'];
            if (rawCaps is List) {
              _peerCapabilities = Set<String>.from(
                rawCaps.whereType<String>(),
              );
            } else {
              _peerCapabilities = <String>{};
            }
          }
          final request = _requests.remove(message.id);
          if (request != null) {
            request.complete(message);
          }
          _messages.add(message);
        } on Object {
          unawaited(disconnect());
        }
      },
      onError: (Object error) {
        _lost(socket);
      },
      onDone: () => _lost(socket),
      cancelOnError: true,
    );
    send('hello', {
      'capabilities': const ['track_lifecycle'],
      if (name != null) 'deviceName': name,
    });
    _connections.add(true);
  }

  void _lost(WebSocket socket) {
    if (!identical(_socket, socket)) return;
    ++_epoch;
    _socket = null;
    _peerCapabilities = null;
    _failRequests();
    if (!_closed) _connections.add(false);
  }

  void _failRequests() {
    for (final request in _requests.values) {
      if (!request.isCompleted)
        request.completeError(
          const LokalRemoteNetworkException('Desktop link disconnected.'),
        );
    }
    _requests.clear();
  }

  void send(String type, Map<String, dynamic> body, {String? id}) {
    if (!connected)
      throw const LokalRemoteNetworkException('Connect to your desktop first.');
    _socket!.add(LinkMessage.create(type, body, id: id).encode());
  }

  Future<LinkMessage> request(String type, Map<String, dynamic> body) async {
    final id = linkUuid(), completer = Completer<LinkMessage>();
    _requests[id] = completer;
    try {
      send(type, body, id: id);
      final reply = await completer.future.timeout(const Duration(seconds: 12));
      if (reply.type == 'ack' && reply.body['ok'] == false)
        throw LokalRemoteProtocolException(
          reply.body['error'] is String
              ? reply.body['error'] as String
              : 'Desktop command was rejected.',
        );
      return reply;
    } finally {
      _requests.remove(id);
    }
  }

  Future<void> disconnect() async {
    ++_epoch;
    await _disconnectSocket();
  }

  Future<void> _disconnectSocket() async {
    final socket = _socket;
    final subscription = _subscription;
    _socket = null;
    _subscription = null;
    _peerCapabilities = null;
    _failRequests();
    if (socket != null && !_closed) _connections.add(false);
    await subscription?.cancel();
    await socket?.close(WebSocketStatus.normalClosure);
  }

  Future<void> close() async {
    _closed = true;
    await disconnect();
    _identityClient.close();
    await _messages.close();
    await _connections.close();
  }
}
