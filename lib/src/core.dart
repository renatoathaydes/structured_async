import 'dart:async';

import '_state.dart';
import 'error.dart';
import 'context.dart';

/// A [Future] that may be cancelled.
///
/// To cancel a [CancellableFuture], call [CancellableFuture.cancel].
///
/// Notice that any computation occurring within a [CancellableFuture] is
/// automatically cancelled by an error being thrown within it, so a simple
/// way to cancel a computation from "within" is to throw an Exception,
/// including [FutureCancelled] to make the intent explicit (though any
/// error has the effect of stopping computation).
///
/// Once a [CancellableFuture] has been cancelled, any async function call,
/// or [Future] and [Timer] creation, will fail
/// within the same [Zone] and its descendants.
/// Isolates created within the same computation, however, will not be killed
/// automatically. Use [CancellableContext.scheduleOnCompletion] to ensure
/// Isolates are killed appropriately in such cases.
///
/// Only the first error within a [CancellableFuture] propagates to any
/// potential listeners.
/// If the `cancel` method was called while the computation had not completed,
/// the first error will be a [FutureCancelled] Exception.
class CancellableFuture<T> implements Future<T> {
  final StructuredAsyncZoneState _state;
  final Future<T> _delegate;

  CancellableFuture._(this._state, this._delegate);

  /// Default constructor of [CancellableFuture].
  factory CancellableFuture(Future<T> Function() function,
      {String? debugName, Function(Object, StackTrace)? uncaughtErrorHandler}) {
    return _createCancellableFuture(
        (_) => function(), debugName, uncaughtErrorHandler);
  }

  /// Create a [CancellableFuture] that accepts a function whose single
  /// argument is the returned Future's [CancellableContext].
  ///
  /// This context can be used within the function to obtain information about
  /// the status of the computation (e.g. whether it's been cancelled)
  /// and access other functionality related to its lifecycle.
  factory CancellableFuture.ctx(Future<T> Function(CancellableContext) function,
      {String? debugName, Function(Object, StackTrace)? uncaughtErrorHandler}) {
    return _createCancellableFuture(function, debugName, uncaughtErrorHandler);
  }

  /// Create a group of asynchronous computations.
  ///
  /// Each of the provided `functions` is called immediately and asynchronously.
  /// As the `Future` they return complete, the optional `receiver` function
  /// is called in whatever order the results are emitted.
  ///
  /// The returned [CancellableFuture] completes when all computations complete,
  /// or on the first error. When a computation fails, all other computations
  /// are immediately cancelled and this Future completes with the initial
  /// error.
  ///
  /// If this Future is cancelled, all computations are cancelled immediately
  /// and this Future completes with the [FutureCancelled] error.
  ///
  /// If you prefer to collect the computation results in a [Stream], use the
  /// [CancellableFuture.stream] method instead.
  static CancellableFuture<void> group<T>(
      Iterable<Future<T> Function()> functions,
      {FutureOr<void> Function(T)? receiver,
      String? debugName,
      Function(Object, StackTrace)? uncaughtErrorHandler}) {
    final counterStream = StreamController<bool>();
    final callback = receiver ?? (T _) {};
    return CancellableFuture(() async {
      var elementCount = 0;
      for (final function in functions) {
        elementCount++;
        function()
            .then(callback, onError: counterStream.addError)
            .whenComplete(() => counterStream.add(false));
      }
      final totalElements = elementCount;
      try {
        await for (var _ in counterStream.stream.take(totalElements)) {}
      } finally {
        counterStream.close();
      }
    });
  }

  /// Create a group of asynchronous computations, sending their completions
  /// to a [Stream] as they are emitted.
  ///
  /// The [CancellableFuture.group] method is used to run the provided
  /// `functions`. See that method for more details.
  static Stream<T> stream<T>(Iterable<Future<T> Function()> functions,
      {String? debugName, Function(Object, StackTrace)? uncaughtErrorHandler}) {
    final controller = StreamController<T>();
    group(functions,
            receiver: controller.add,
            debugName: debugName,
            uncaughtErrorHandler: uncaughtErrorHandler)
        .then((_) {}, onError: controller.addError)
        .whenComplete(controller.close);
    return controller.stream;
  }

  @override
  Stream<T> asStream() {
    return _delegate.asStream();
  }

  @override
  Future<T> catchError(Function onError, {bool Function(Object error)? test}) {
    return _delegate.catchError(onError, test: test);
  }

  @override
  Future<R> then<R>(FutureOr<R> Function(T value) onValue,
      {Function? onError}) {
    return _delegate.then(onValue, onError: onError);
  }

  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout}) {
    return _delegate.timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Future<T> whenComplete(FutureOr<void> Function() action) {
    return _delegate.whenComplete(action);
  }

  /// Cancel this [CancellableFuture].
  ///
  /// Currently dormant computations will not be immediately interrupted,
  /// but any [Future] or [Timer] started within this computation
  /// after a call to this method will throw [FutureCancelled].
  ///
  /// Any "nested" [CancellableFuture]s started within this computation
  /// will also be cancelled.
  void cancel() {
    _state.cancel();
  }
}

/// Get the nearest [CancellableContext] if this computation is running within
/// a [CancellableFuture], otherwise, return null.
///
/// Prefer to use [CancellableFuture.ctx] to obtain the non-nullable
/// [CancellableContext] object as an argument to the Future's async function.
CancellableContext? currentCancellableContext() {
  return nearestCancellableContext();
}

ZoneSpecification _createZoneSpec(StructuredAsyncZoneState state) =>
    ZoneSpecification(createTimer: (self, parent, zone, d, f) {
      return state.remember(parent.createTimer(zone, d, f), f);
    }, createPeriodicTimer: (self, parent, zone, d, f) {
      final timer = parent.createPeriodicTimer(zone, d, f);
      return state.remember(timer, () => f(timer));
    });

CancellableFuture<T> _createCancellableFuture<T>(
    Future<T> Function(CancellableContext) function,
    String? debugName,
    Function(Object, StackTrace)? uncaughtErrorHandler) {
  final state = StructuredAsyncZoneState();
  final result = Completer<T>();

  void onError(e, st) {
    state.cancel();
    try {
      uncaughtErrorHandler?.call(e, st);
      // ignore: empty_catches
    } catch (ignore) {}
    if (result.isCompleted) return;
    result.completeError(e, st);
  }

  scheduleMicrotask(() {
    runZonedGuarded(() async {
      if (state.isComputationCancelled()) {
        throw const FutureCancelled();
      }
      function(state)
          .then((v) => scheduleMicrotask(() => result.complete(v)))
          .catchError(onError)
          .whenComplete(() {
        // make sure that nothing can run after Future returns
        return state.cancel(true);
      });
    }, onError,
        zoneValues: state.createZoneValues(),
        zoneSpecification: _createZoneSpec(state));
  });

  return CancellableFuture._(state, result.future);
}
