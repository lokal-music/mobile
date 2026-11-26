import 'dart:convert';
import 'dart:math';

String linkUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

String linkTrackKey(String artist, String title, Duration duration) {
  String normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return '${normalize(artist)}|${normalize(title)}|${(duration.inMilliseconds / 1000).round()}';
}

String nextLinkClock(String previous, {String incoming = '', int? now}) {
  List<int> parse(String value) {
    final parts = value.split(':');
    return [
      int.tryParse(parts.first) ?? 0,
      parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    ];
  }

  final p = parse(previous),
      i = parse(incoming),
      current = now ?? DateTime.now().millisecondsSinceEpoch;
  if (i[0] > current + 300000)
    throw const FormatException('Clock is too far in the future.');
  final time = max(current, max(p[0], i[0]));
  final count = time == p[0] && time == i[0]
      ? max(p[1], i[1]) + 1
      : time == p[0]
      ? p[1] + 1
      : time == i[0]
      ? i[1] + 1
      : 0;
  return '${time.toString().padLeft(16, '0')}:${count.toString().padLeft(8, '0')}';
}

class LinkMessage {
  const LinkMessage(this.type, this.body, {required this.id, required this.ts});
  static const types = {
    'hello',
    'state',
    'command',
    'ack',
    'queue',
    'theme',
    'history.push',
    'history.pull',
    'history.events',
    'library.push',
    'library.pull',
    'library.ops',
    'catalog.begin',
    'catalog.push',
    'catalog.end',
    'bye',
  };
  final String type;
  final Map<String, dynamic> body;
  final String id;
  final int ts;
  factory LinkMessage.create(
    String type,
    Map<String, dynamic> body, {
    String? id,
  }) => LinkMessage(
    type,
    body,
    id: id ?? linkUuid(),
    ts: DateTime.now().millisecondsSinceEpoch,
  );
  factory LinkMessage.decode(Object raw) {
    final value = jsonDecode(raw as String);
    if (value is! Map ||
        value['v'] != 1 ||
        !types.contains(value['type']) ||
        value['id'] is! String ||
        (value['id'] as String).length > 128 ||
        value['ts'] is! int ||
        value['body'] is! Map)
      throw const FormatException('Invalid desktop link message.');
    return LinkMessage(
      value['type'] as String,
      Map<String, dynamic>.from(value['body'] as Map),
      id: value['id'] as String,
      ts: value['ts'] as int,
    );
  }
  String encode() =>
      jsonEncode({'v': 1, 'type': type, 'id': id, 'ts': ts, 'body': body});
}
