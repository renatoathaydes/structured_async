import 'dart:async';

import 'package:structured_async/structured_async.dart';
import 'package:test/test.dart';

List<int> addTo(List<int> list, int i) {
  list.add(i);
  return list;
}

void main() {
  group('Group of Cancellable actions', () {
    test('can run successfully', () async {
      final values = await [
        () async => 1,
        () async => 2,
        () async => 3,
      ].cancellable(<int>[], addTo);
      expect(values, equals([1, 2, 3]));
    });

    test('can be cancelled before all complete', () async {
      var f1 = expectAsync0(() => 1,
          count: 1,
          max: 5,
          reason: 'f1 is called immediately, '
              'then once every 10ms until cancelled around 10ms later.');
      var f2 = expectAsync0(() {
        return 3;
      }, count: 0, reason: 'f2 should never be called');
      var f3 =
          expectAsync0(() => 5, count: 0, reason: 'f3 should never be called');

      final values = [
        () async {
          f1();
          for (var i = 0; i < 10; i++) {
            await Future.delayed(Duration(milliseconds: 10));
            f1();
          }
          return f1();
        },
        () => Future.delayed(Duration(milliseconds: 250), () async => f2()),
        () async {
          for (var i = 0; i < 10; i++) {
            await Future.delayed(Duration(milliseconds: 10));
          }
          return f3();
        },
      ].cancellable<int>(-1, (a, b) => a + b);

      await Future.delayed(Duration(milliseconds: 10));

      values.cancel();

      try {
        await values;
        fail('Unexpected success after cancelling tasks');
      } on InterruptedException {
        // good
      }
      // FIXME throws InterruptedException again somehow
    }, timeout: Timeout(Duration(seconds: 5)), skip: true);

    test('starts roughly at the same time', () async {
      int now() => DateTime.now().millisecondsSinceEpoch;

      final startTime = now();

      final cancellables = [
        () async => now(),
        () async {
          final start = now();
          await Future.delayed(Duration(milliseconds: 100));
          return start;
        },
        () async {
          final start = now();
          await Future.delayed(Duration(milliseconds: 200));
          return start;
        }
      ].cancellable(<int>[], addTo);

      final results = await cancellables;

      final endTime = now();

      expect(results, hasLength(equals(3)));

      // all actions should have started immediately
      expect(results[0] - startTime, lessThanOrEqualTo(80),
          reason: 'first action took too long to start');
      expect(results[1] - startTime, lessThanOrEqualTo(80),
          reason: 'second action took too long to start');
      expect(results[2] - startTime, lessThanOrEqualTo(80),
          reason: 'third action took too long to start');

      // the whole computation needs to take at least
      // as much as the longest computation
      expect(endTime, greaterThanOrEqualTo(200));
    });
  });
}
