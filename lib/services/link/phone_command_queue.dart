class IncomingPhoneCommandQueue {
  Future<void> _commandTail = Future<void>.value();
  Future<void> _transferTail = Future<void>.value();

  Future<void> enqueue({
    required bool transfer,
    required Future<void> Function() operation,
  }) {
    final tail = transfer ? _transferTail : _commandTail;
    final next = tail.then<void>(
      (_) => operation(),
      onError: (_) => operation(),
    );
    if (transfer) {
      _transferTail = next.then<void>((_) {}, onError: (_) {});
    } else {
      _commandTail = next.then<void>((_) {}, onError: (_) {});
    }
    return next;
  }
}

Future<void> runIncomingPhoneCommand({
  required bool Function() isCurrent,
  required Future<void> Function() handle,
  required Future<void> Function() acknowledgeSuccess,
  required Future<void> Function(Object error) acknowledgeFailure,
}) async {
  if (!isCurrent()) return;
  try {
    await handle();
  } on Object catch (error) {
    if (isCurrent()) await acknowledgeFailure(error);
    return;
  }
  if (isCurrent()) await acknowledgeSuccess();
}

@pragma('vm:prefer-inline')
bool isIncomingPhoneCommandCurrent({
  required int expectedGeneration,
  required int currentGeneration,
  required bool connected,
  required bool shouldPoll,
  required bool disposed,
}) =>
    !disposed &&
    shouldPoll &&
    connected &&
    expectedGeneration == currentGeneration;
