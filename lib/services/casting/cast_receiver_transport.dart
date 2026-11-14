/// Commands from Lokal's custom Cast receiver are requests to the sender's
/// authoritative playback queue, not positions in the receiver's short CAF
/// queue. Keep the original load identity to reject late commands after LOAD.
enum CastReceiverTransport { next, previous }

CastReceiverTransport? castReceiverTransport(
  Map<dynamic, dynamic> message, {
  required String? currentTrackId,
  required String? currentLoadId,
}) {
  if (message['type'] != 'transport' ||
      currentTrackId == null ||
      currentTrackId.isEmpty ||
      message['trackId'] != currentTrackId) {
    return null;
  }
  final loadId = message['loadId'];
  if (loadId != null &&
      (loadId is! String ||
          loadId.isEmpty ||
          currentLoadId == null ||
          loadId != currentLoadId)) {
    return null;
  }
  return switch (message['action']) {
    'next' => CastReceiverTransport.next,
    'previous' => CastReceiverTransport.previous,
    _ => null,
  };
}
