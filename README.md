# structured_async

[Structured concurrency](https://en.wikipedia.org/wiki/Structured_concurrency)
programming for the [Dart](https://dart.dev/) Programming Language.

## User Guide

### CancellableFuture

The basic construct in `structured_async` is `CancellableFuture`. It looks like a normal Dart `Future`
but with the following differences:

* it has a `cancel` method.
* if any unhandled error occurs within it:
  * all asynchronous computations started within it are stopped.
  * the error is propagated to the caller even if the `Future` it comes from was not `await`-ed. 

This example shows the difference:

```dart
_runForever() async {
  while (true) {
    await Future.delayed(Duration(seconds: 1), () => print('Tick'));
  }
}

Future<void> futureNeverStops() async {
  await Future(() {
    _runForever(); // no await here
    return Future.delayed(Duration(milliseconds: 3500));
  });
  print('Stopped');
}

Future<void> cancellableFutureStopsWhenItReturns() async {
  await CancellableFuture(() { // <--- this is the only difference!
    _runForever(); // no await here
    return Future.delayed(Duration(milliseconds: 3500));
  });
  print('Stopped');
}
```

If you run `futureNeverStops`, you'll see this:

```
Tick
Tick
Tick
Stopped
Tick
Tick
Tick
...
```

The program never ends, because Dart's `Future`s that are not _await_'ed for don't stop after their
_parent `Future` completes.

However, running `cancellableFutureStopsWhenItReturns`, you see:

```
Tick
Tick
Tick
Stopped
Tick
```

And the program dies. When a `CancellableFuture` completes, _most_ asynchronous computation within it
are terminated (unfortunately, there are a few exceptions, see the **Limitations** section).

The reason there's a last `Tick` printed after `Stopped` is that the last iteration of the loop in
`_runForever` had already been _scheduled_, and currently, there's no way to prevent that from executing.
But any asynchronous computation that the last iteration might've attempted to run would've been
stopped.

### Cancelling computations

To cancel a `CancellableFuture`, you've guessed it: call the `cancel()` method.

> From within the `CancellableFuture` computation itself, throwing an error has a similar effect as
> being cancelled from the _outside_, i.e. stop everything and complete with an error.
> You can use `throw const FutureCancelled()` achieve the exact same effect.

Example:

```dart
Future<void> explicitCancel() async {
  Future<void> printForever(String message) async {
    while(true) {
      await Future.delayed(Duration(seconds: 1), () => print(message));
    }
  }
  final future = CancellableFuture(() async {
    printForever('Tic'); // no await
    await Future.delayed(Duration(milliseconds: 500));
    await printForever('Tac');
  });

  // cancel after 3 seconds
  Future.delayed(Duration(seconds: 3), future.cancel);

  try {
    await future;
  } on FutureCancelled {
    print('Future was cancelled');
  }
}
```

Result:

```
Tic
Tac
Tic
Tac
Tic
Future was cancelled
Tac
```

### Error Propagation

With `CancellableFuture`, any error that occurs within its computation, even on non-awaited `Future`s it has
started, propagate to the caller as long as the `CancellableFuture` has not completed yet.

To illustrate the difference with `Future`, let's look at what happens when we run this:

```dart
_throw() async {
  throw 'not great';
}

Future<void> futureWillNotPropagateThisError() async {
  try {
    await Future(() {
      _throw();
      return Future.delayed(Duration(milliseconds: 100));
    });
  } catch (e) {
    print('ERROR: $e');
  } finally {
    print('Stopped');
  }
}
```

Result:

```
Unhandled exception:
not great
#0      _throw
...
```

The program crashes without running the `catch` block.

Replacing `Future` with `CancellableFuture`, this is the result:

```
ERROR: not great
Stopped
```

The error is handled correctly and the program terminates successfully.

> If you want to explicitly allow a computation to fail, use Dart's
> [runZoneGuarded](https://api.dart.dev/stable/dart-async/runZonedGuarded.html).

### CancellableFuture.group()

`CancellableFuture.group()` makes it easier to run multiple asynchronous computations within the same
`CancellableFuture` and waiting for all their results.

Example:

```dart
Future<void> groupExample() async {
  final group = CancellableFuture.group([
    () async => 10,
    () async => 20,
  ], 0, (int a, int b) => a + b);
  print('Result: ${await group}');
}
```

Result:

```
Result: 30
```

As with any `CancellableFuture`, if some error happens in any of the computations within a group,
all other computations are stopped and the error propagates to the `await`-er.

> The results of a `group` are combined as with `List.fold`: start with a provided initial value,
> then call the `merge` function with the current result and each completed element, in order.

### Limitations

Not everything can be cancelled in Dart. For example, `Isolate`s and `Timer`s cannot be cancelled easily.

For this reason, this simple example never stops running:

```dart
Future<void> neverStops() async {
  final task = CancellableFuture(() async {
    Timer.periodic(Duration(seconds: 1), (_) => print('Tick'));
  });
  Future.delayed(Duration(seconds: 3), task.cancel);
}
```

Another simple example you might try that won't work as you think is this:

```dart
Future<void> scheduledFutureWillRun() async {
  final task = CancellableFuture(() =>
          Future.delayed(Duration(seconds: 2), () => print('2 seconds later')));
  await Future.delayed(Duration(seconds: 1), task.cancel);
}
```

This will print `2 seconds later` because an already scheduled `Future` cannot be stopped from running,
as explained previously.

If you ever run into this problem, you can try to insert a few explicit checks to see if your task has been cancelled
before doing anything.

That's what the `isComputationCancelled()` function is for, as this example demonstrates:

```dart
Future<void> explicitCheckForCancellation() async {
  final task = CancellableFuture(() =>
          Future.delayed(Duration(seconds: 2), () {
            if (isComputationCancelled()) return 'Cancelled';
            return '2 seconds later';
          }));
  await Future.delayed(Duration(seconds: 1), task.cancel);
  print(await task);
}
```

Result:

```
Cancelled
```

> Notice that calling any async method, creating a `Future` or even calling `scheduleMicrotask()` from within a task
> would have caused the above examples to get cancelled properly without the need to call `isComputationCancelled()`.

## Examples

More examples can be found in the [example](example) directory.
