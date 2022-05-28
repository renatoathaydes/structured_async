import 'dart:async';

import 'context.dart';

/// A symbol that is used as key for accessing the status of a
/// [CancellableFuture].
const Symbol _stateZoneKey = #structured_async_zone_state;

class StructuredAsyncZoneState with CancellableContext {
  bool _isCancelled;

  bool get isCancelled => _isCancelled;
  List<Timer>? _timers = [];

  List<Function()>? _cancellables = [];

  StructuredAsyncZoneState([this._isCancelled = false]);

  @override
  bool isComputationCancelled() => isCurrentZoneCancelled();

  @override
  void scheduleOnCancel(Function() onCancelled) {
    _cancellables?.add(onCancelled);
  }

  Timer remember(Timer timer) {
    final timers = _timers;
    if (timers != null) {
      timers.add(timer);
      if (timers.length % 10 == 0) {
        timers.removeWhere((t) => !t.isActive);
      }
    }
    return timer;
  }

  void cancel([bool cancelTimers = false]) {
    final wasCancelled = _isCancelled;
    _isCancelled = true;
    if (!wasCancelled && !cancelTimers) {
      // cancellables only run when future is explicitly cancelled...
      // cancelTimers is true when the Cancellable completed successfully.
      _callCancellables();
    }
    if (cancelTimers) {
      _cancelTimers();
    }
  }

  void _callCancellables() {
    final cancellables = _cancellables;

    if (cancellables != null) {
      for (final c in cancellables) {
        Zone.root.run(c);
      }
      _cancellables = null;
    }
  }

  void _cancelTimers() {
    final timers = _timers;
    if (timers == null) return;
    for (final timer in timers) {
      if (timer.isActive) {
        // in the current Zone, Futures are cancelled
        Zone.root.run(() => Future(timer.cancel));
      }
    }
    _timers = null;
  }

  @override
  String toString() {
    var s = StringBuffer('_StructuredAsyncZoneState{');
    _forEachZone((zone) {
      final isCancelled = zone[_stateZoneKey]?.isCancelled;
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

  Map<Object, Object> createZoneValues() => {_stateZoneKey: this};
}

CancellableContext? nearestCancellableContext() {
  CancellableContext? result;
  _forEachZone((zone) {
    final ctx = zone[_stateZoneKey];
    if (ctx is CancellableContext) {
      result = ctx;
      return false;
    }
    return true;
  });
  return result;
}

bool isCurrentZoneCancelled() {
  var isCancelled = false;
  _forEachZone((zone) {
    if (zone[_stateZoneKey]?.isCancelled == true) {
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
