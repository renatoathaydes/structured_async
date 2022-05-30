import 'dart:async';

import 'context.dart';
import 'error.dart';

/// A symbol that is used as key for accessing the status of a
/// [CancellableFuture].
const Symbol _stateZoneKey = #structured_async_zone_state;

class _TimerEntry {
  final Timer timer;
  final Function() function;

  _TimerEntry(this.timer, this.function);
}

class StructuredAsyncZoneState with CancellableContext {
  bool _isCancelled;

  bool get isCancelled => _isCancelled;
  List<_TimerEntry>? _timers;

  List<Function()>? _cancellables;

  List<FutureOr<void> Function()>? _completions;

  StructuredAsyncZoneState([this._isCancelled = false]) {
    nearestCancellableContext()?.scheduleOnCancel(cancel);
  }

  @override
  bool isComputationCancelled() => _isCancelled || isCurrentZoneCancelled();

  @override
  void scheduleOnCancel(void Function() onCancelled) {
    if (_isCancelled) return;
    (_cancellables ??= []).add(onCancelled);
  }

  @override
  void scheduleOnCompletion(void Function() onCompletion) {
    if (_isCancelled) return;
    (_completions ??= []).add(onCompletion);
  }

  Timer remember(Timer timer, Function() function) {
    if (_isCancelled) {
      timer.cancel();
      throw const FutureCancelled();
    }
    // periodicTimers are cancelled "early" because user-code cannot
    // block Future completion based on a periodic timer, normally,
    // so these timers are normally "fire-and-forget" as opposed to regular
    // timers, which the user might be waiting for, so we can't cancel.
    var timers = _timers;
    if (timers == null) {
      _timers = timers = <_TimerEntry>[];
    }
    timers.add(_TimerEntry(timer, function));
    if (timers.length % 10 == 0) {
      timers.removeWhere((t) => !t.timer.isActive);
    }
    return timer;
  }

  @override
  void cancel([bool isCompletion = false]) {
    if (isCompletion) {
      _completions = _callOnRootZone(_completions);
    } else {
      // cancellables only run when future is explicitly cancelled...
      _cancellables = _callOnRootZone(_cancellables);
    }
    _timers = _stopTimers(_timers);
    _isCancelled = true;
  }

  // ignore: prefer_void_to_null
  static Null _stopTimers(Iterable<_TimerEntry>? timers) {
    if (timers == null) return;
    for (final t in timers) {
      if (t.timer.isActive) {
        t.timer.cancel();
        // wake up the timer function so the caller may continue
        scheduleMicrotask(t.function);
      }
    }
  }

  // ignore: prefer_void_to_null
  static Null _callOnRootZone(Iterable<Function()>? functions) {
    if (functions != null) {
      for (final c in functions) {
        Zone.root.run(c);
      }
    }
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
