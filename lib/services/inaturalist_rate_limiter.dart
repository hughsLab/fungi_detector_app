class INaturalistRateLimiter {
  INaturalistRateLimiter({
    this.minimumInterval = const Duration(seconds: 1),
  });

  final Duration minimumInterval;
  Future<void> _tail = Future<void>.value();
  DateTime? _lastStartedAt;

  Future<void> waitForTurn() {
    final next = _tail.then((_) async {
      final last = _lastStartedAt;
      if (last != null) {
        final remaining = minimumInterval - DateTime.now().difference(last);
        if (remaining > Duration.zero) {
          await Future<void>.delayed(remaining);
        }
      }
      _lastStartedAt = DateTime.now();
    });
    _tail = next.catchError((_) {});
    return next;
  }
}

