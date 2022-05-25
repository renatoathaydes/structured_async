import 'dart:async';

import 'package:structured_async/structured_async.dart';
import 'package:test/test.dart';

void main() {
  group('Should be able to', () {
    test('run CancellableFuture', () async {
      final future = (() async => 'run').cancellable();
      expect(await future, equals('run'));
    });

    group('cancel future', () {
      var isRun = false, interrupted = false, index = 0;
      setUp(() {
        isRun = false;
        interrupted = false;
      });
      final interruptableActions = <Future<void> Function()>[
        () async => scheduleMicrotask(() => isRun = true),
        () => Future(() => isRun = true),
        () => Future.delayed(Duration(milliseconds: 1), () => isRun = true),
        () async => await Future(() => isRun = true),
        () async => Timer.run(() => isRun = true),
        () async {
          await for (final i in Stream.fromFuture(Future(() => 1))) {
            if (i == 1) isRun = true;
          }
        },
        () => Future(() => runZoned(() => isRun = true)),
        () => runZoned(() => Future(() => isRun = true)),
      ];

      for (final action in interruptableActions) {
        test('for interrupt-able action ${index++}', () async {
          final future = action.cancellable();
          future.cancel();
          try {
            await future;
          } on FutureCancelled {
            interrupted = true;
          }
          expect(isRun, isFalse, reason: 'should not have run the action');
          expect(interrupted, isTrue, reason: 'should be interrupted');
        });
      }
    });

    test('check for cancellation explicitly from within a computation', () {
      CancellableFuture<int> createFuture() =>
          CancellableFuture.create(() async {
            if (isComputationCancelled()) {
              throw FutureCancelled();
            }
            return 1;
          });

      // interrupted if cancelled
      expect(Future(() {
        final future = createFuture();
        future.cancel();
        return future;
      }), throwsA(isA<FutureCancelled>()));

      // not interrupted otherwise
      expect(Future(() {
        final future = createFuture();
        return future;
      }), completion(equals(1)));
    });
  });

  group('Should not be able to', () {
    group('cancel future', () {
      var isRun = false, interrupted = false, index = 0;
      setUp(() {
        isRun = false;
        interrupted = false;
      });
      final nonInterruptableActions = <Future<void> Function()>[
        () async => isRun = true,
        () => (() async => isRun = true)(),
        () async {
          for (final i in [1, 2, 3, 4]) {
            isRun = i % 2 == 0;
          }
        },
        () => runZoned(() async => isRun = true),
        () async => runZoned(() => isRun = true),
      ];

      for (final action in nonInterruptableActions) {
        test('for non-async action ${index++}', () async {
          final future = action.cancellable();
          future.cancel();
          try {
            await future;
          } on FutureCancelled {
            interrupted = true;
          }
          expect(isRun, isTrue, reason: 'should have run the action');

          // Future was still cancelled, even if its action ran
          expect(interrupted, isTrue, reason: 'should be interrupted');
        });
      }
    });
  });
}
