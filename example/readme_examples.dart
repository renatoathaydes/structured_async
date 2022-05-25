import 'package:structured_async/structured_async.dart';

Future<void> main() async {
  await single();
  await groups();
}

Future<void> single() async {
  // from a lambda
  final cancellable = () async {
    return 42;
  }.cancellable();

  Future<int> theAnswer() async => 42;

  // from a function
  final cancellable2 = theAnswer.cancellable();

  // either way, the `create` factory can also be used
  final cancellable3 = CancellableFuture.create(theAnswer);

  // use cancellables as you would any other Future,
  // but make sure to catch FutureCancelled
  try {
    print(await cancellable);
  } on FutureCancelled {
    print('Got cancelled!');
  }
}

Future<void> groups() async {
  Future<int> theAnswer() async => 42;
  Future<int> wrongAnswer() async => 0;

// create a group from a List
  CancellableFuture<int> group = [
    theAnswer,
    wrongAnswer,
    theAnswer,
  ].cancellableGroup(0, (a, b) => a + b);

  print(await group); // prints 84

// create a group using the group() method
  final group2 = CancellableFuture.group([
    theAnswer,
    wrongAnswer,
  ], 0, (int a, int b) => a + b);

  print(await group2); // prints 42
}
