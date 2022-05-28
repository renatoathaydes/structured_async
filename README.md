# structured_async

![Project CI](https://github.com/renatoathaydes/structured_async/workflows/Project%20CI/badge.svg)
[![pub package](https://img.shields.io/pub/v/structured_async.svg)](https://pub.dev/packages/structured_async)

[Structured concurrency](https://en.wikipedia.org/wiki/Structured_concurrency)
for the [Dart](https://dart.dev/) Programming Language.

## User Guide

### CancellableFuture

The basic construct in `structured_async` is `CancellableFuture`. It looks like a normal Dart `Future`
but with the following differences:

* it has a `cancel` method.
* if any unhandled error occurs within it:
  * all asynchronous computations started within it are stopped.
  * the error is propagated to the caller even if the `Future` it comes from was not `await`-ed.
* when it completes, anything[^1] it started but not waited for is cancelled.

[^1]: See the [_Limitations_](#limitations) section for computations that may _escape_ the context of a `CancellableFuture`.
Please file a bug if you find any other cases.

This example shows the basic difference:

```dart
_runForever() async {
  while (true) {
    print('Tick');
    await Future.delayed(Duration(milliseconds: 500));
  }
}

Future<void> futureNeverStops() async {
  await Future(() {
    _runForever(); // no await here
    return Future.delayed(Duration(milliseconds: 1200));
  });
  print('Stopped');
}

Future<void> cancellableFutureStopsWhenItReturns() async {
  await CancellableFuture(() { // <--- this is the only difference!
    _runForever(); // no await here
    return Future.delayed(Duration(milliseconds: 1200));
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

However, running `cancellableFutureStopsWhenItReturns`, you should see:

```
Tick
Tick
Tick
Stopped
```

And the program dies. When a `CancellableFuture` completes, _most_ asynchronous computation within it
are terminated (see also [_Limitations_](#limitations)).

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

### Periodic Timers

Any periodic timers started within a `CancellableFuture` will be cancelled when the `CancellableFuture` itself
completes, successfully or not, including when it gets cancelled.

This example shows how that works:

```dart
Future<void> periodicTimerIsCancelledOnCompletion() async {
  final task = CancellableFuture(() async {
    // fire and forget a periodic timer
    Timer.periodic(Duration(milliseconds: 500), (_) => print('Tick'));
    await Future.delayed(Duration(milliseconds: 1200));
    return 10;
  });
  print(await task);
}
```

We fire and forget a periodic timer, wait a second or so, then finish the `CancellableFuture` with the value `10`.

Outside the `CancellableFuture`, we `await` its completion and print its result.

Result:

```
Tick
Tick
10
```

As you can see, the periodic timer is immediately stopped when the `CancellableFuture` that created it completes.

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

Not everything can be stopped immediately in Dart when a `CancellableFuture` is cancelled.

The following Dart features are known to not play well with cancellations:

#### already scheduled `Timer`s and `Future`s.

For example, this simple code you might try probably won't work as you think it should:

```dart
Future<void> scheduledFutureWillRun() async {
  final task = CancellableFuture(() =>
          Future.delayed(Duration(seconds: 2), () => print('2 seconds later')));
  await Future.delayed(Duration(seconds: 1), task.cancel);
  await task;
}
```

This will print `2 seconds later` and terminate successfully because an already scheduled `Future`
cannot be stopped from running.

If you ever run into this problem, you can try to insert a few explicit checks to see if your task has been cancelled
before doing anything.

That's what the `isComputationCancelled()` function is for, as this example demonstrates:

```dart
Future<void> explicitCheckForCancellation() async {
  final task = CancellableFuture.ctx((ctx) =>
          Future.delayed(Duration(seconds: 2), () {
            if (ctx.isComputationCancelled()) return 'Cancelled';
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

As shown above, the `CancellableFuture.ctx` constructor must be used to get access to the context object which exposes
`isComputationCancelled()`, amongst other helper functions.

#### `Isolate`s.

Dart `Isolate`s started within a `CancellableFuture` may continue running even after the `CancellableFuture` completes.

To work around this problem, use the context's `scheduleOnCancel` function and the following general pattern:

```dart
Future<void> stoppingIsolates() async {
  final task = CancellableFuture.ctx((ctx) async {
    final iso = await Isolate.spawn((message) async {
      for (var i = 0; i < 5; i++) {
        await Future.delayed(
                Duration(seconds: 1), () => print('Isolate says: $message'));
      }
      print('Isolate finished');
    }, 'hello');

    final responsePort = ReceivePort();
    final responseStream = responsePort.asBroadcastStream();

    ctx.scheduleOnCancel(() {
      // ensure Isolate is terminated on cancellation
      print('Killing ISO');
      responsePort.close();
      iso.kill();
    });

    // wait until the Isolate stops responding or timeout
    final waitLimit = now() + 10000;
    while (now() < waitLimit) {
      iso.ping(responsePort.sendPort);
      print('Waiting for ping response');
      try {
        await responseStream.first.timeout(Duration(seconds: 1));
        print('Ping OK');
        await Future.delayed(Duration(seconds: 1));
      } on TimeoutException {
        print('Isolate not responding');
        break;
      }
    }
  });

  try {
    await task;
  } on FutureCancelled {
    print('Cancelled');
  }
}
```

## Examples

All examples on this page, and more, can be found in the [example](example) directory.
