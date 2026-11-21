import 'dart:async';

import 'package:flick/services/link/lokal_link_service.dart';
import 'package:flick/services/link/phone_command_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('playback commands proceed while a transfer is still running', () async {
    final queue = IncomingPhoneCommandQueue();
    final transferGate = Completer<void>();
    var transferStarted = false,
        secondTransferStarted = false,
        playbackCompleted = false;
    final transfer = queue.enqueue(
      transfer: true,
      operation: () async {
        transferStarted = true;
        await transferGate.future;
      },
    );
    await Future<void>.delayed(Duration.zero);
    expect(transferStarted, isTrue);

    final secondTransfer = queue.enqueue(
      transfer: true,
      operation: () async {
        secondTransferStarted = true;
      },
    );
    await queue.enqueue(
      transfer: false,
      operation: () async {
        playbackCompleted = true;
      },
    );
    expect(playbackCompleted, isTrue);
    expect(secondTransferStarted, isFalse);
    expect(transferGate.isCompleted, isFalse);

    transferGate.complete();
    await Future.wait([transfer, secondTransfer]);
    expect(secondTransferStarted, isTrue);
  });

  test(
    'commands delivered on an invalidated connection never run or ack',
    () async {
      var generation = 7, handled = false, acknowledged = false;
      bool isCurrent() => generation == 7;

      await runIncomingPhoneCommand(
        isCurrent: isCurrent,
        handle: () async {
          handled = true;
        },
        acknowledgeSuccess: () async {
          acknowledged = true;
        },
        acknowledgeFailure: (_) async {
          acknowledged = true;
        },
      );
      expect(handled, isTrue);
      expect(acknowledged, isTrue);

      generation++;
      handled = false;
      acknowledged = false;
      await runIncomingPhoneCommand(
        isCurrent: isCurrent,
        handle: () async {
          handled = true;
        },
        acknowledgeSuccess: () async {
          acknowledged = true;
        },
        acknowledgeFailure: (_) async {
          acknowledged = true;
        },
      );
      expect(handled, isFalse);
      expect(acknowledged, isFalse);
    },
  );

  test('disconnect during handling prevents an acknowledgement', () async {
    var current = true, acknowledged = false;
    await runIncomingPhoneCommand(
      isCurrent: () => current,
      handle: () async {
        current = false;
      },
      acknowledgeSuccess: () async {
        acknowledged = true;
      },
      acknowledgeFailure: (_) async {
        acknowledged = true;
      },
    );
    expect(acknowledged, isFalse);
  });

  test('explicit disconnect invalidates the link generation', () async {
    final link = LokalLinkService();
    final generation = link.connectionGeneration;
    await link.disconnect();
    expect(link.connectionGeneration, generation + 1);
    await link.close();
  });
}
