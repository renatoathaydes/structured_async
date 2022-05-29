import 'dart:async';

import 'core.dart' show CancellableFuture;

/// Context within which a [CancellableFuture] runs.
///
/// See [CancellableFuture.ctx].
mixin CancellableContext {
  /// Check if the computation within this context has been cancelled.
  ///
  /// If any [CancellableFuture] or one of its ancestors is cancelled,
  /// then every child is also automatically cancelled.
  bool isComputationCancelled();

  /// Schedule a callback to run once the [CancellableFuture]
  /// this context belongs to is cancelled.
  ///
  /// If the [CancellableFuture] completes before being cancelled, this callback
  /// is never invoked.
  ///
  /// The callback is always executed from the root [Zone] because the current
  /// [Zone] during a cancellation would be hostile to starting any new
  /// asynchronous computations. The [CancellableFuture.cancel] method does not
  /// wait for callbacks registered via this method to complete before returning.
  void scheduleOnCancel(void Function() onCancelled);

  /// Schedule a callback to run when the [CancellableFuture] is about to
  /// complete.
  ///
  /// The result of the given callback is ignored even if it fails.
  ///
  /// The callback is always executed from the root [Zone] because the current
  /// [Zone] during a cancellation would be hostile to starting any new
  /// asynchronous computations.
  void scheduleOnCompletion(void Function() onCompletion);

  /// Cancel the [CancellableFuture] this context belongs to.
  void cancel();
}
