# structured_async

Structured asynchronous programming for Dart.

## User Guide

Using this library is very simple, but some structured asynchronous programming concepts can be tricky to demonstrate.
This guide focuses on this library itself.

### CancellableFuture

The most basic class of this library is [CancellableFuture], which is just like Dart's `Future`,
but with a `cancel` method so that the asynchronous computation within the `Future` can be cancelled
_from the outside_ world.

Creating `CancellableFuture`:

```dart
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
```

### Grouping CancellableFutures

To actually use structured asynchronous programming, however, you will need **groups** of `CancellableFuture`s,
where cancelling any of a group's members causes all other members within the same group, including child groups,
to be cancelled as well.

To create a group, instead of using a single asynchronous function as shown above, use many:

```dart
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
```

> Notice that, as with Dart's `Future`, just creating a `CancellableFuture` is enough to dispatch its
> computation, no need to `await` it.

The results of the computations within a group must be _folded_, or collected, into something, which is why
when creating a group, as with `Iterable.fold`, you must provide an initial value as well as a `merge` function.

The example above shows the common case of adding up numbers so the result is the sum of the results of all computations.

This library provides a few _merge_ functions to collect results into `List`, `Set` or just nothing (i.e. `void`):

* `Cancellable.group([...], <int>[], intoList())`
* `Cancellable.group([...], <int>{}, intoSet())`
* `Cancellable.group([...], null, intoNothing)`

## Examples

More advanced examples can be found in the [example](example) directory.
