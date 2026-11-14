import 'package:flick/services/casting/cast_receiver_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CastReceiverTransport? accept(Map<dynamic, dynamic> message) =>
      castReceiverTransport(
        message,
        currentTrackId: 'song-2',
        currentLoadId: 'load-5',
      );

  test('receiver next and previous navigate current mobile queue', () {
    expect(accept({
      'type': 'transport', 'action': 'next',
      'trackId': 'song-2', 'loadId': 'load-5',
    }), CastReceiverTransport.next);
    expect(accept({
      'type': 'transport', 'action': 'previous',
      'trackId': 'song-2', 'loadId': 'load-5',
    }), CastReceiverTransport.previous);
  });

  test('reject commands from previous tracks or loads', () {
    expect(accept({
      'type': 'transport', 'action': 'next',
      'trackId': 'song-1', 'loadId': 'load-5',
    }), isNull);
    expect(accept({
      'type': 'transport', 'action': 'next',
      'trackId': 'song-2', 'loadId': 'load-4',
    }), isNull);
    expect(accept({
      'type': 'transport', 'action': 'previous',
      'trackId': 'song-2', 'loadId': 5,
    }), isNull);
  });

  test('reject unknown commands and missing current identities', () {
    expect(accept({'type': 'transport', 'action': 'seek',
      'trackId': 'song-2'}), isNull);
    expect(accept({'type': 'view', 'action': 'next',
      'trackId': 'song-2'}), isNull);
    expect(castReceiverTransport({
      'type': 'transport', 'action': 'next', 'trackId': 'song-2',
    }, currentTrackId: null, currentLoadId: 'load-5'), isNull);
  });

  test('older receiver without load identity remains compatible', () {
    expect(accept({
      'type': 'transport', 'action': 'next', 'trackId': 'song-2',
    }), CastReceiverTransport.next);
  });
}
