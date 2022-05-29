/// An Exception thrown when an asynchronous computation is attempted after a
/// [CancellableFuture] has been cancelled or completed.
///
/// Every [Future] and [Timer] running inside a [CancellableFuture]'s
/// [Zone] terminates early when this Exception occurs, and attempting to
/// create new ones causes this Exception to be thrown synchronously.
class FutureCancelled implements Exception {
  const FutureCancelled();

  @override
  String toString() {
    return 'FutureCancelled';
  }
}
