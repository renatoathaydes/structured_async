import 'dart:async';

import 'package:structured_async/structured_async.dart';
import 'package:test/test.dart';

void main() {
  group('Should be able to', () {
    Future<int> async10() => Future(() => 10);

    test('run CancellableFuture', () async {
      final future = CancellableFuture(() async => 'run');
      expect(await future, equals('run'));
    });

    test('get context of CancellableFuture', () async {
      final future = CancellableFuture(() async => currentCancellableContext());
      expect(await future, isNotNull);
      expect(currentCancellableContext(), isNull);
    });

    test(
        'know that async actions within CancellableFuture stop after it terminates',
        () async {
      var counter = 0;
      final future = CancellableFuture(() async {
        // schedule Future but don't wait
        Future(() async {
          counter++;
          await Future(() {});
          counter++;
        });
      });

      await future;
      await Future.delayed(Duration(milliseconds: 10));

      expect(counter, equals(1),
          reason: 'As the Future within CancellableFuture was not awaited, '
              'it should be interrupted after CancellableFuture returns');
    });

    test('collect uncaught errors', () async {
      final errors = [];
      final future = CancellableFuture(() async {
        Future(() {
          throw 'error 1';
        });
        // no await, so inner Future should failed as it gets cancelled
        Future(() async {
          await Future(() {});
        });
      }, uncaughtErrorHandler: (e, st) => errors.add(e));

      await future;
      await Future.delayed(Duration.zero);

      expect(errors, equals(const ['error 1', FutureCancelled()]));
    });

    group('cancel future before it starts', () {
      var isRun = false, interrupted = false, index = 0;
      setUp(() {
        isRun = false;
        interrupted = false;
      });
      final interruptableActions = <Future<void> Function()>[
        () async => isRun = true,
        () => (() async => isRun = true)(),
        () => runZoned(() async => isRun = true),
        () async => runZoned(() => isRun = true),
        () async => scheduleMicrotask(() => isRun = true),
        () => Future(() => isRun = true),
        () => Future.delayed(Duration.zero, () => isRun = true),
        () async => await Future(() => isRun = true),
        () async => Timer.run(() => isRun = true),
      ];

      for (final action in interruptableActions) {
        test('for action-${index++}', () async {
          final future = CancellableFuture(action);
          future.cancel();
          try {
            await future;
          } on FutureCancelled {
            interrupted = true;
          }
          expect([isRun, interrupted], equals([false, true]),
              reason: 'should not have run (ran? $isRun), '
                  'should be interrupted (was? $interrupted)');
        });
      }
    });

    group('cancel async actions after CancellableFuture started', () {
      var isRun = false, interrupted = false, index = 0;
      setUp(() {
        isRun = false;
        interrupted = false;
      });
      final interruptableActions = <Future<void> Function()>[
        () => Future(() {
              isRun = true;
              return Future(() {});
            }),
        () async {
          isRun = true;
          await Future.delayed(Duration.zero);
          return Future(() {});
        },
        () async {
          isRun = true;
          await async10();
          return Future(() {});
        },
        () async {
          isRun = true;
          await async10();
          await async10();
        },
        () {
          isRun = true;
          return async10().then((x) {
            return async10().then((y) => x * y);
          });
        },
      ];

      for (final action in interruptableActions) {
        test('for action-${index++}', () async {
          final future = CancellableFuture(action);
          Future.delayed(Duration.zero, future.cancel);
          try {
            await future;
          } on FutureCancelled {
            interrupted = true;
          }

          expect([isRun, interrupted], equals([true, true]),
              reason: 'should have run (ran? $isRun), '
                  'should be interrupted (was? $interrupted)');
        });
      }
    });

    test('check for cancellation explicitly from within a computation', () {
      CancellableFuture<int> createFuture() =>
          CancellableFuture.ctx((ctx) async {
            if (ctx.isComputationCancelled()) {
              throw const FutureCancelled();
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

    test('schedule onCancel callback that does not run if not cancelled',
        () async {
      var onCancelRun = false;
      final future = CancellableFuture.ctx((ctx) async {
        ctx.scheduleOnCancel(() {
          onCancelRun = true;
        });
        return await async10() + await async10();
      });

      await future;
      expect(onCancelRun, isFalse);
    });

    test('schedule onCancel callback that runs on cancellation', () async {
      Zone? onCancelZone;
      final future = CancellableFuture.ctx((ctx) async {
        ctx.scheduleOnCancel(() {
          onCancelZone = Zone.current;
        });
        return await async10() + await async10();
      });

      Future(future.cancel);

      try {
        await future;
        fail('Future should have been cancelled');
      } on FutureCancelled {
        // good
      }
      expect(onCancelZone, same(Zone.root),
          reason: 'onCancel callback should run at the root Zone');
    });

    test('cancel Future from within itself', () async {
      int value = 0;
      final future = CancellableFuture.ctx((ctx) async {
        value += await async10();
        ctx.cancel();
        value += await async10();
      });

      try {
        await future;
        fail('Future should have been cancelled');
      } on FutureCancelled {
        // good
      }
      expect(value, equals(10),
          reason:
              'only the async call before cancellation should have executed');
    });
  }, timeout: Timeout(Duration(seconds: 5)));

  group('Should not be able to cancel future that has already been started',
      () {
    var isRun = false, interrupted = false, index = 0;
    setUp(() {
      isRun = false;
      interrupted = false;
    });

    // if no async action is performed within the Futures, there's no
    // suspend point to be able to cancel
    final nonInterruptableActions = <Future<int> Function()>[
      () => Future(() {
            isRun = true;
            return 10;
          }),
      () async {
        isRun = true;
        return 10;
      },
      () async {
        isRun = true;
        return Future(() => 10);
      },
      () async {
        isRun = true;
        scheduleMicrotask(() {});
        return 10;
      },
    ];

    for (final action in nonInterruptableActions) {
      test('for action-${index++}', () async {
        final future = CancellableFuture(action);
        await Future.delayed(Duration.zero, future.cancel);
        int result = 0;
        try {
          result = await future;
        } on FutureCancelled {
          interrupted = true;
        }

        expect([isRun, interrupted, result], equals([true, false, 10]),
            reason: 'should have run (ran? $isRun), '
                'should be interrupted (was? $interrupted), '
                'should return 10 (v=$result)');
      });
    }
  }, timeout: Timeout(Duration(seconds: 5)));

  group('When an error occurs within a CancellableFuture', () {
    Future<void> badAction() async {
      await Future.delayed(Duration(milliseconds: 10));
      throw 'bad';
    }

    test('it propagates to the caller', () async {
      expect(badAction, throwsA(equals('bad')));
      final cancellableBadAction = CancellableFuture(badAction);
      expect(() => cancellableBadAction, throwsA(equals('bad')));
    });

    test('if cancelled first, the caller gets FutureCancelled', () async {
      final cancellableBadAction = CancellableFuture(badAction);
      cancellableBadAction.cancel();
      expect(() => cancellableBadAction, throwsA(isA<FutureCancelled>()));
    });

    test('the error propagates to the caller even after a delay', () async {
      final cancellableBadAction = CancellableFuture(badAction);
      cancellableBadAction
          .then(expectAsync1((_) {}, count: 0))
          .catchError(expectAsync1((e) {
        expect(e, equals('bad'));
      }));
      await Future.delayed(Duration(milliseconds: 100));
    });

    test('if cancelled later, the original error propagates to the caller',
        () async {
      final cancellableBadAction = CancellableFuture(badAction);
      cancellableBadAction
          .then(expectAsync1((_) {}, count: 0))
          .catchError(expectAsync1((e) {
        expect(e, equals('bad'));
      }));
      await Future.delayed(Duration(milliseconds: 100));
      cancellableBadAction.cancel();
    });
  }, timeout: Timeout(Duration(seconds: 5)));
}
