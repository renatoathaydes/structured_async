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

  static CancellableFuture<V> group<T, V>(
      Iterable<Future<T> Function()> functions,
      V initialValue,
      Function(V, T) merge) {
    return functions.cancellable(initialValue, merge);
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
  String toString() {
    var s = StringBuffer('_StructuredAsyncZoneState{');
    _forEachZone((zone) {
      final isCancelled = zone[_structuredAsyncCancelledFlag]?.isCancelled;
      if (isCancelled == null) {
        s.write(' x');
      } else {
        s.write(' $isCancelled');
      }
      return true;
    });
    s.write('}');
    return s.toString();
  }
}

/// Check if the computation within the [Zone] this function is called from
/// has been cancelled.
///
/// If any [CancellableFuture]'s [Zone] is cancelled, then every
/// child [Zone] is also automatically cancelled.
bool isComputationCancelled() {
  var isCancelled = false;
  _forEachZone((zone) {
    if (zone[_structuredAsyncCancelledFlag]?.isCancelled == true) {
      isCancelled = true;
      return false; // stop iteration
    }
    return true;
  });
  return isCancelled;
}

void _forEachZone(bool Function(Zone) action) {
  Zone? zone = Zone.current;
  while (zone != null) {
    if (!action(zone)) break;
    zone = zone.parent;
  }
}

ZoneSpecification _createZoneSpec() {
  return ZoneSpecification(createTimer: (self, parent, zone, d, f) {
    if (isComputationCancelled()) {
      throw const InterruptedException();
    }
    return parent.createTimer(zone, d, f);
  }, scheduleMicrotask: (self, parent, zone, f) {
    if (isComputationCancelled()) {
      throw const InterruptedException();
    }
    parent.scheduleMicrotask(zone, f);
  });
}

CancellableFuture<T> _createCancellableFuture<T>(Future<T> Function() function,
    _StructuredAsyncZoneState state, Map<Object, Object> zoneValues) {
  return CancellableFuture._(state, Future(() {
    return runZoned(() async {
      try {
        return await function();
      } catch (e) {
        state.isCancelled = true;
        rethrow;
      }
    }, zoneValues: zoneValues, zoneSpecification: _createZoneSpec());
  }));
}

extension StructuredAsyncFuture<T> on Future<T> Function() {
  CancellableFuture<T> cancellable() {
    final state = _StructuredAsyncZoneState();
    final zoneValues = {_structuredAsyncCancelledFlag: state};
    return _createCancellableFuture(this, state, zoneValues);
  }
}

extension StructuredAsyncFutures<T> on Iterable<Future<T> Function()> {
  CancellableFuture<V> cancellable<V>(V initialValue, Function(V, T) merge) {
    final state = _StructuredAsyncZoneState();
    final zoneValues = {_structuredAsyncCancelledFlag: state};
    final group = map((f) => _createCancellableFuture(f, state, zoneValues))
        .toList(growable: false);

    return _createCancellableFuture(() async {
      var v = initialValue;
      Object? error;
      for (final f in group) {
        try {
          v = merge(v, await f);
        } catch (e) {
          state.isCancelled = true;
          // from now on, all futures should fail,
          // but we only remember the first error
          error ??= e;
        }
      }
      if (error != null) {
        throw error;
      }
      return v;
    }, state, zoneValues);
  }
}
