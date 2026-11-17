import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Serves completed offline HLS media to native video players over localhost.
///
/// iOS AVPlayer cannot reliably open a locally rewritten HLS manifest using
/// file://. ExoPlayer and AVPlayer both support an ordinary HLS HTTP URL.
/// Only an ephemeral loopback port is bound; no remote device can connect.
abstract final class LocalMotionHlsServer {
  static Future<HttpServer>? _server;
  static final Map<String, Directory> _folders = {};
  static final RegExp _assetName =
      RegExp(r'^asset_[0-9]+\.(?:mp4|m4s|ts|aac|bin)$');

  static Future<Uri> serve(File playlist) async {
    final server = await (_server ??= _start());
    final key = sha256.convert(utf8.encode(playlist.parent.path)).toString();
    _folders[key] = playlist.parent;
    return Uri.parse('http://127.0.0.1:${server.port}/$key/playlist.m3u8');
  }

  static Future<HttpServer> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(server.forEach((request) async {
      try {
        await _handle(request);
      } catch (_) {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } catch (_) {}
      }
    }));
    return server;
  }

  static Future<void> _handle(HttpRequest request) async {
    final parts = request.uri.pathSegments;
    if ((request.method != 'GET' && request.method != 'HEAD') ||
        parts.length != 2 ||
        !_folders.containsKey(parts.first) ||
        (parts.last != 'playlist.m3u8' && !_assetName.hasMatch(parts.last))) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final file = File('${_folders[parts.first]!.path}/${parts.last}');
    if (!await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final length = await file.length();
    if (length <= 0) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final name = parts.last;
    final mime = name.endsWith('.m3u8')
        ? 'application/vnd.apple.mpegurl'
        : name.endsWith('.ts')
            ? 'video/mp2t'
            : name.endsWith('.aac')
                ? 'audio/aac'
                : name.endsWith('.bin')
                    ? 'application/octet-stream'
                    : 'video/mp4';
    final response = request.response;
    response.headers.contentType = ContentType.parse(mime);
    response.headers.set('accept-ranges', 'bytes');
    response.headers.set('cache-control', 'no-store');
    var first = 0;
    var last = length - 1;

    final range = request.headers.value('range');
    if (range != null) {
      final match = RegExp(r'^bytes=([0-9]+)-([0-9]*)$').firstMatch(range);
      if (match == null) {
        await _invalidRange(response, length);
        return;
      }
      first = int.parse(match[1]!);
      if (match[2]!.isNotEmpty) last = int.parse(match[2]!);
      if (first >= length || last < first) {
        await _invalidRange(response, length);
        return;
      }
      if (last >= length) last = length - 1;
      response.statusCode = HttpStatus.partialContent;
      response.headers.set('content-range', 'bytes $first-$last/$length');
    }
    response.contentLength = last - first + 1;
    if (request.method == 'GET') {
      await response.addStream(file.openRead(first, last + 1));
    }
    await response.close();
  }

  static Future<void> _invalidRange(
    HttpResponse response,
    int length,
  ) async {
    response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
    response.headers.set('content-range', 'bytes */$length');
    await response.close();
  }

  @visibleForTesting
  static Future<void> closeForTesting() async {
    final previous = _server;
    _server = null;
    _folders.clear();
    if (previous != null) await (await previous).close(force: true);
  }
}
