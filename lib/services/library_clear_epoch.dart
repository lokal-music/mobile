/// Monotonic epoch bumped whenever the user clears the library.
///
/// Active scanner instances, detached post-scan enrichment tasks, and
/// background metadata extractors capture [current] when they begin and abort
/// any further database or fingerprint-cache writes once [isCurrent] becomes
/// false. This prevents pre-clear background work from resurrecting deleted
/// rows or writing stale fingerprints after a library clear.
abstract final class LibraryClearEpoch {
  static int _epoch = 0;

  static int get current => _epoch;

  static bool isCurrent(int epoch) => _epoch == epoch;

  static int bump() => ++_epoch;
}
