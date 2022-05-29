import 'dart:async';

import 'package:structured_async/structured_async.dart';

Future<int> theAnswer() async => 42;

/// Run with the "cancel" argument to show what happens when
/// a Future gets cancelled.
Future<void> main(List<String> args) async {
  final cancel = args.contains('cancel');
  final startTime = now();

  print('Time  | Message\n'
      '------+--------');

  runZoned(() async {
    await simpleExample(cancel);
    await groupExample(cancel);
  }, zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
    parent.print(zone, '${(now() - startTime).toString().padRight(5)} | $line');
  }));
}

Future<void> simpleExample(bool cancel) async {
  // create a cancellable from any async function
  final cancellableAnswer = CancellableFuture(() async {
    // the function can only be cancelled at async points,
    // so returning a number here, for example, would be impossible
    // to cancel! So we call another async function instead.
    return await theAnswer();
  });

  if (cancel) {
    cancellableAnswer.cancel();
  }

  try {
    print('The answer is ${await cancellableAnswer}');
  } on FutureCancelled {
    print('Could not compute the answer!');
  }

  // it is also possible to check if a computation has been cancelled
  // explicitly by calling isComputationCancelled()...
  // Also notice we can use the factory constructor instead of cancellable().
  final cancelFriendlyTask = CancellableFuture.ctx((ctx) async {
    if (ctx.isComputationCancelled()) {
      // the caller will get a FutureCancelled Exception as long as they await
      // after the task has been cancelled.
      return null;
    }
    return 42;
  });

  if (cancel) {
    cancelFriendlyTask.cancel();
  }

  try {
    print('The answer is still ${await cancelFriendlyTask}');
  } on FutureCancelled {
    print('Still cannot compute the answer!');
  }
}

Future<void> groupExample(bool cancel) async {
  final results = <int?>[];

  final group = CancellableFuture.group([
    () async => sleep(Duration(milliseconds: 30), () => 1),
    () async => sleep(Duration(milliseconds: 10), () => 2),
    () async => sleep(Duration(milliseconds: 20), () => 3),
  ], receiver: (int? n) {
    // values are received in the order they are emitted!
    results.add(n);
  });

  if (cancel) {
    // group.cancel();
  }

  try {
    await group;
    print('Group basic result: $results');
  } on FutureCancelled {
    print('Group basic result was cancelled');
  }

  final group2 = CancellableFuture.group([
    () async => print('Started group 2, should print every second, up to 3s.'),
    () => sleep(Duration(seconds: 1), () => print('1 second')),
    () => sleep(Duration(seconds: 2), () => print('2 seconds')),
    () => sleep(Duration(seconds: 3), () => print('3 seconds')),
  ]);

  scheduleMicrotask(() async {
    if (cancel) {
      print('Will cancel group 2 after 1 second, approximately...');
      await sleep(Duration(milliseconds: 1100));
      print('Cancelling!');
      group2.cancel();
    }
  });

  try {
    await group2;
    print('Done');
  } on FutureCancelled {
    print('Group2 interrupted!');
  }
}

int now() => DateTime.now().millisecondsSinceEpoch;

/// Sleep for the given duration of time using small "ticks"
/// to check if it's time to "wake up" yet.
///
/// This is done because it's not possible to cancel a submitted
/// [Future.delayed] call. In the real world, actual async code
/// would be used rather than [Future.delayed] anyway, so this
/// should not be a problem in most applications.
Future<T?> sleep<T>(Duration duration, [T Function()? function]) async {
  final stopTime = now() + duration.inMilliseconds;
  while (now() < stopTime) {
    await Future.delayed(const Duration(milliseconds: 50));
  }
  return function?.call();
}
