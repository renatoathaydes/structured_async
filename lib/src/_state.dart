import 'dart:async';

/// A symbol that is used as key for accessing the status of a
/// [CancellableFuture].
const Symbol _stateZoneKey = #structured_async_zone_state;

class StructuredAsyncZoneState {
  bool _isCancelled;

  bool get isCancelled => _isCancelled;
  List<Timer>? _timers = [];

  StructuredAsyncZoneState([this._isCancelled = false]);

  void addTimer(Timer entry) {
    _timers?.add(entry);
  }

  void cancel([bool cancelTimers = false]) {
    _isCancelled = true;
    if (cancelTimers) {
      final timers = _timers;
      if (timers == null) return;
      while (timers.isNotEmpty) {
        final timer = timers.removeLast();
        if (timer.isActive) {
          Zone.root.run(() => Future(timer.cancel));
        }
      }
      _timers = null;
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

extension StructuredAsyncZoneExtras on Zone {
  Timer remember(Timer timer) {
    final state = this[_stateZoneKey] as StructuredAsyncZoneState;
    state.addTimer(timer);
    return timer;
  }
}
