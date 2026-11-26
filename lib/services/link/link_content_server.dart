import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../sources/local_network_access.dart';
import '../casting/cast_lan_address.dart';

/// Short-lived, token-scoped LAN file server for a paired Lokal Desktop.
/// The filesystem path never leaves the phone; Desktop receives only an
/// opaque URL and can use HTTP Range for seeking without copying the file.
class LinkContentServer {
  LinkContentServer._();
  static final instance = LinkContentServer._();

  HttpServer? _server;
  String? _baseUrl;
  final _files = <String, String>{};
  final _tokensByPath = <String, String>{};
  final _random = Random.secure();

  Future<String> urlFor(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) throw StateError('The phone song is no longer available.');
    await _ensureServer();
    final existing = _tokensByPath[filePath];
    if (existing != null && _files.containsKey(existing)) return '$_baseUrl/$existing';
    final token = _token();
    _files[token] = filePath;
    _tokensByPath[filePath] = token;
    return '$_baseUrl/$token';
  }

  Future<void> _ensureServer() async {
    if (_server != null && _baseUrl != null) return;
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final ip = castLanAddress({
      for (final network in interfaces)
        network.name: network.addresses.map((address) => address.address),
    });
    if (ip == null) {
      throw const SocketException('Connect the phone and desktop to the same Wi-Fi or LAN.');
    }
    await NetworkLocalAccess.ensure(Uri(scheme: 'http', host: ip));
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    server.listen((request) {
      _handle(request).catchError((Object _) {
        try { request.response.close(); } catch (_) {}
      });
    }, onError: (_) {});
    _server = server;
    _baseUrl = 'http://$ip:${server.port}';
  }

  String _token() {
    final bytes = List<int>.generate(24, (_) => _random.nextInt(256));
    return base64UrlNoPadding(bytes);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      response.contentLength = 0;
      await response.close();
      return;
    }
    final token = request.uri.pathSegments.isEmpty ? '' : request.uri.pathSegments.first;
    final path = _files[token];
    if (path == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      _files.remove(token);
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final total = await file.length();
    var start = 0;
    var end = total - 1;
    var status = HttpStatus.ok;
    final range = request.method == 'HEAD' ? null : request.headers.value(HttpHeaders.rangeHeader);
    if (range != null) {
      final match = RegExp(r'^bytes=(\\d*)-(\\d*)$').firstMatch(range.trim());
      if (match != null && (match.group(1)!.isNotEmpty || match.group(2)!.isNotEmpty)) {
        final first = match.group(1)!;
        final last = match.group(2)!;
        if (total == 0) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */0');
          response.contentLength = 0;
          await response.close();
          return;
        }
        if (first.isEmpty) {
          final suffix = int.tryParse(last) ?? 0;
          if (suffix <= 0) {
            response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
            response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
            response.contentLength = 0;
            await response.close();
            return;
          }
          start = max(0, total - suffix);
        } else {
          start = int.tryParse(first) ?? total;
          end = last.isEmpty ? total - 1 : min(total - 1, int.tryParse(last) ?? -1);
          if (start >= total || end < start) {
            response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
            response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
            response.contentLength = 0;
            await response.close();
            return;
          }
        }
        status = HttpStatus.partialContent;
      }
    }
    final length = end - start + 1;
    response.statusCode = status;
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(HttpHeaders.contentTypeHeader, _mime(path));
    response.contentLength = length;
    if (status == HttpStatus.partialContent) {
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total');
    }
    if (request.method == 'HEAD' || length == 0) {
      await response.close();
      return;
    }
    final handle = await file.open();
    try {
      await handle.setPosition(start);
      var remaining = length;
      while (remaining > 0) {
        final chunk = await handle.read(min(64 * 1024, remaining));
        if (chunk.isEmpty) break;
        response.add(chunk);
        remaining -= chunk.length;
        await response.flush();
      }
    } finally {
      await handle.close();
      await response.close();
    }
  }

  String _mime(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'mp3' => 'audio/mpeg',
      'flac' => 'audio/flac',
      'wav' => 'audio/wav',
      'm4a' || 'mp4' => 'audio/mp4',
      'aac' => 'audio/aac',
      'ogg' || 'oga' || 'opus' => 'audio/ogg',
      'aiff' || 'aif' => 'audio/aiff',
      'dsf' || 'dff' => 'audio/dsd',
      'wv' => 'audio/x-wavpack',
      _ => 'application/octet-stream',
    };
  }

  Future<void> close() async {
    _files.clear();
    _tokensByPath.clear();
    _baseUrl = null;
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }
}

String base64UrlNoPadding(List<int> bytes) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  final out = StringBuffer();
  for (var i = 0; i < bytes.length; i += 3) {
    final a = bytes[i];
    final hasB = i + 1 < bytes.length;
    final hasC = i + 2 < bytes.length;
    final b = hasB ? bytes[i + 1] : 0;
    final c = hasC ? bytes[i + 2] : 0;
    out
      ..write(alphabet[a >> 2])
      ..write(alphabet[((a & 3) << 4) | (b >> 4)]);
    if (hasB) out.write(alphabet[((b & 15) << 2) | (c >> 6)]);
    if (hasC) out.write(alphabet[c & 63]);
  }
  return out.toString();
}
