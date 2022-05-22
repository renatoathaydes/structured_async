import 'dart:async';

/// A symbol that is used as key for accessing the status of a
/// [CancellableFuture].
const Symbol _structuredAsyncCancelledFlag = #structured_async_zone_state;

/// A [Future] that may be cancelled.
///
/// To cancel a [CancellableFuture], simply call [CancellableFuture.cancel].
///
/// It is also possible to cancel a computation by explicitly
class CancellableFuture<T> implements Future<T> {
  final _StructuredAsyncZoneState _state;
  final Future<T> _delegate;

  CancellableFuture._(this._state, this._delegate);

  factory CancellableFuture.create(Future<T> Function() function) {
    return function.cancellable();
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

  void cancel() {
    _state.isCancelled = true;
  }
}

/// An Exception thrown when awaiting for the completion of a
/// [CancellableFuture] that has been cancelled.
class InterruptedException implements Exception {
  const InterruptedException();

  @override
  String toString() {
    return 'InterruptedException{Future has been interrupted}';
  }
}

class _StructuredAsyncZoneState {
  bool isCancelled;

  _StructuredAsyncZoneState([this.isCancelled = false]);

  @override
  // ignore: hash_and_equals
  bool operator ==(Object other) => identical(this, other);

  @override
  String toString() {
    return '_StructuredAsyncZoneState{isCancelled: $isCancelled}';
  }
}

bool isComputationCancelled() {
  return Zone.current[_structuredAsyncCancelledFlag].isCancelled;
}

extension StructuredAsyncFuture<T> on Future<T> Function() {
  CancellableFuture<T> cancellable() {
    final state = _StructuredAsyncZoneState();
    return CancellableFuture._(state, Future(() {
      return runZoned(() async => await this(),
          zoneValues: {_structuredAsyncCancelledFlag: state},
          zoneSpecification:
              ZoneSpecification(createTimer: (self, parent, zone, d, f) {
            if (self[_structuredAsyncCancelledFlag].isCancelled) {
              throw const InterruptedException();
            }
            return parent.createTimer(zone, d, f);
          }, scheduleMicrotask: (self, parent, zone, f) {
            if (self[_structuredAsyncCancelledFlag].isCancelled) {
              throw const InterruptedException();
            }
            return parent.scheduleMicrotask(zone, f);
          }));
    }));
  }
}
