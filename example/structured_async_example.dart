import 'dart:async';

import 'package:structured_async/structured_async.dart';

Future<int> theAnswer() async => 42;

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
  final cancellableAnswer = () async {
    // the function can only be cancelled at async points,
    // so returning a number here, for example, would be impossible
    // to cancel! So we call another async function instead.
    return await theAnswer();
  }.cancellable();

  if (cancel) {
    cancellableAnswer.cancel();
  }

  try {
    print('The answer is ${await cancellableAnswer}');
  } on InterruptedException {
    print('Could not compute the answer!');
  }

  // it is also possible to check if a computation has been cancelled
  // explicitly by calling isComputationCancelled()...
  // Also notice we can use the factory constructor instead of cancellable().
  final cancelFriendlyTask = CancellableFuture.create(() async {
    if (isComputationCancelled()) {
      // the caller will get an InterruptedException as long as they await
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
  } on InterruptedException {
    print('Still cannot compute the answer!');
  }
}

Future<void> groupExample(bool cancel) async {
  final group = CancellableFuture.group([
    () async => 1,
    () async => 2,
    () async => 3,
  ], <int>[], intoList());

  if (cancel) {
    // group.cancel();
  }

  try {
    print('Group basic result: ${await group}');
  } on InterruptedException {
    print('Group basic result was cancelled');
  }

  final group2 = [
    () async => print('Started group 2, should print every second, up to 3s.'),
    () => sleep(Duration(seconds: 1), () => print('1 second')),
    () => sleep(Duration(seconds: 2), () => print('2 seconds')),
    () => sleep(Duration(seconds: 3), () => print('3 seconds')),
  ].cancellable(null, (void a, void b) => null);

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
  } on InterruptedException {
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
Future<void> sleep(Duration duration, [void Function()? function]) async {
  final stopTime = now() + duration.inMilliseconds;
  while (now() < stopTime) {
    await Future.delayed(const Duration(milliseconds: 50));
  }
  function?.call();
}
