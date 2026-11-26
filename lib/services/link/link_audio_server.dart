import 'dart:io';
import 'dart:math';

import '../sources/local_network_access.dart';
import '../casting/cast_lan_address.dart';

/// Serves explicitly requested local song files to the paired desktop.
/// This server has an independent lifecycle from Cast.
class LinkAudioServer {
  LinkAudioServer._();
  static final instance = LinkAudioServer._();

  HttpServer? _server;
  Future<HttpServer>? _binding;
  final Map<String, String> _files = {};
  final Random _random = Random.secure();

  Future<String> publish(String path) async {
    final file = File(path);
    if (!await file.exists())
      throw StateError('The phone audio file is unavailable.');
    final ip = await _lanAddress();
    await NetworkLocalAccess.ensure(Uri(scheme: 'http', host: ip));
    final server = await _ensureServer();
    final token = List<int>.generate(
      24,
      (_) => _random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    _files[token] = path;
    while (_files.length > 32) {
      _files.remove(_files.keys.first);
    }
    return 'http://$ip:${server.port}/$token';
  }

  Future<HttpServer> _ensureServer() {
    final current = _server;
    if (current != null) return Future.value(current);
    final pending = _binding;
    if (pending != null) return pending;
    final opening = HttpServer.bind(InternetAddress.anyIPv4, 0).then((server) {
      _server = server;
      server.listen(_handle, onError: (_) {});
      return server;
    });
    _binding = opening;
    return opening.whenComplete(() {
      if (identical(_binding, opening)) _binding = null;
    });
  }

  Future<String> _lanAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final address = castLanAddress({
      for (final network in interfaces)
        network.name: network.addresses.map((item) => item.address),
    });
    if (address == null) {
      throw const SocketException(
        'Connect both devices to the same Wi-Fi or LAN.',
      );
    }
    return address;
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      request.response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      await request.response.close();
      return;
    }
    final token = request.uri.pathSegments.isEmpty
        ? ''
        : request.uri.pathSegments.first;
    final path = _files[token];
    if (path == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      _files.remove(token);
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final total = await file.length();
    var start = 0, end = total - 1, status = HttpStatus.ok;
    final range = request.method == 'GET'
        ? request.headers.value(HttpHeaders.rangeHeader)
        : null;
    if (range != null) {
      final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range.trim());
      if (match == null ||
          (match.group(1)!.isEmpty && match.group(2)!.isEmpty)) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */$total',
        );
        await request.response.close();
        return;
      }
      final first = match.group(1)!, last = match.group(2)!;
      if (first.isEmpty) {
        final suffix = int.tryParse(last);
        if (suffix == null || suffix <= 0 || total == 0) {
          request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes */$total',
          );
          await request.response.close();
          return;
        }
        start = suffix >= total ? 0 : total - suffix;
      } else {
        start = int.tryParse(first) ?? total;
        end = last.isEmpty ? total - 1 : (int.tryParse(last) ?? -1);
        if (start >= total || end < start) {
          request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes */$total',
          );
          await request.response.close();
          return;
        }
        if (end >= total) end = total - 1;
      }
      status = HttpStatus.partialContent;
    }
    final length = end - start + 1;
    request.response.statusCode = status;
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    request.response.headers.set(HttpHeaders.contentLengthHeader, '$length');
    request.response.headers.contentType = _contentType(path);
    if (status == HttpStatus.partialContent) {
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$total',
      );
    }
    if (request.method == 'HEAD' || length == 0) {
      await request.response.close();
      return;
    }
    final handle = await file.open();
    try {
      await handle.setPosition(start);
      var remaining = length;
      while (remaining > 0) {
        final chunk = await handle.read(min(64 * 1024, remaining));
        if (chunk.isEmpty) break;
        request.response.add(chunk);
        remaining -= chunk.length;
        await request.response.flush();
      }
    } finally {
      await handle.close();
      await request.response.close();
    }
  }

  ContentType _contentType(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'mp3' => ContentType('audio', 'mpeg'),
      'flac' => ContentType('audio', 'flac'),
      'wav' => ContentType('audio', 'wav'),
      'm4a' || 'mp4' => ContentType('audio', 'mp4'),
      'aac' => ContentType('audio', 'aac'),
      'ogg' || 'opus' => ContentType('audio', 'ogg'),
      'aiff' || 'aif' => ContentType('audio', 'aiff'),
      'wv' => ContentType('audio', 'x-wavpack'),
      'dsf' || 'dff' => ContentType('audio', 'dsd'),
      _ => ContentType.binary,
    };
  }

  Future<void> close() async {
    _files.clear();
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }
}
