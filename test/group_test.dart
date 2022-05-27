import 'dart:async';

import 'package:structured_async/structured_async.dart';
import 'package:test/test.dart';

class FunctionCounter<R> {
  int count = 0;
  final R Function() delegate;

  FunctionCounter(this.delegate);

  R call() {
    count++;
    return delegate();
  }
}

void main() {
  Future<int> call10TimesIn100Ms(int Function() f) async {
    final i = f();
    for (var i = 0; i < 9; i++) {
      await Future.delayed(Duration(milliseconds: 10), f);
    }
    return i;
  }

  group('Group of Cancellable actions', () {
    test('can run successfully', () async {
      Future<int> do1() async => 1;
      Future<int> do2() async => 2;
      Future<int> do3() async => 3;
      Future<List<int>> values =
          CancellableFuture.group([do1, do2, do3], <int>[], intoList());
      expect(await values, equals([1, 2, 3]));
    });

    test('can be cancelled before all complete', () async {
      var f1 = FunctionCounter(() => 1);
      var f2 = FunctionCounter(() => 2);
      var f3 = FunctionCounter(() => 3);

      final values = CancellableFuture.group([
        () => call10TimesIn100Ms(f1),
        () => call10TimesIn100Ms(f2),
        () => call10TimesIn100Ms(f3),
      ], null, intoNothing);

      Future.delayed(Duration(milliseconds: 20), values.cancel);

      try {
        await values;
        fail('Unexpected success after cancelling tasks');
      } on FutureCancelled {
        // good
      }

      // wait until the functions would've been called too many times
      await Future.delayed(Duration(milliseconds: 60));

      expect(f1.count, allOf(greaterThan(1), lessThan(5)));
      expect(f2.count, allOf(greaterThan(1), lessThan(5)));
      expect(f3.count, allOf(greaterThan(1), lessThan(5)));
    });

    test('can have sub-groups that get cancelled without affecting others',
        () async {
      var f1 = FunctionCounter(() => 1);
      var f2 = FunctionCounter(() => 2);
      // will run in a separate group, to completion
      var f3 = FunctionCounter(() => 3);

      var subGroupCancelled = false;

      final values = CancellableFuture.group([
        () async {
          final subGroup = CancellableFuture.group([
            () => call10TimesIn100Ms(f1),
            () => call10TimesIn100Ms(f2),
          ], 0, (int a, int b) => a + b, debugName: 'sub-group');

          Future.delayed(Duration(milliseconds: 20), subGroup.cancel);

          try {
            return await subGroup;
          } on FutureCancelled {
            subGroupCancelled = true;
          }
          // should get here after cancellation
          return 10;
        },
        () async => 2 * await call10TimesIn100Ms(f3),
      ], <int>[], intoList(), debugName: 'main-group');

      expect(await values, equals([10, 6]));
      expect(subGroupCancelled, isTrue);

      expect(f1.count, allOf(greaterThan(1), lessThan(5)));
      expect(f2.count, allOf(greaterThan(1), lessThan(5)));
      expect(f3.count, equals(10));
    });

    test('starts roughly at the same time', () async {
      int now() => DateTime.now().millisecondsSinceEpoch;

      final startTime = now();

      final cancellables = CancellableFuture.group([
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
      ], <int>[], intoList());

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
  }, timeout: Timeout(Duration(seconds: 5)));
}
