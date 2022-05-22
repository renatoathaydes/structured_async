import 'dart:async';

import 'package:structured_async/structured_async.dart';

Future<int> theAnswer() async => 42;

Future<void> main(List<String> args) async {
  // create a cancellable from any async function
  final cancellableAnswer = () async {
    // the function can only be cancelled at async points,
    // so returning a number here, for example, would be impossible
    // to cancel! So we call another async function instead.
    return await theAnswer();
  }.cancellable();

  if (args.contains('cancel')) {
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

  if (args.contains('cancel')) {
    cancelFriendlyTask.cancel();
  }

  try {
    print('The answer is still ${await cancelFriendlyTask}');
  } on InterruptedException {
    print('Still cannot compute the answer!');
  }
}
