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

The program never ends because Dart's `Future`s that are not _await_'ed for don't stop after their
_parent `Future` completes.

However, running `cancellableFutureStopsWhenItReturns`, you should see:

```
Tick
Tick
Tick
Tick
Stopped
```

And the program dies. When a `CancellableFuture` completes, _most_ asynchronous computation within it
are terminated (see also [_Limitations_](#limitations)). Any pending `Future`s and `Timer`s are completed
immediately, and attempting to create any new `Future` and `Timer` within the `CancellableFuture` computation
will fail from that point on.

To make it clearer what is going on, run example 2 (shown above) with the `time` option,
which will print the time since the program started (in ms) when each `print` is called:

```shell
dart example/readme_examples.dart 2 time
```

Result:

```
Time  | Message
------+--------
26    | Tick
542   | Tick
1046  | Tick
1243  | Tick
1249  | Stopped
```

Notice how the `Tick` messages are initially printed every 500ms, as the code intended, but once the `CancellableFuture`
completes, at `t=1200` approximately, the delayed `Future` in `_runForever` is awakened _early_, the loop continues
by again printing `Tick` (hence the last `Tick` message), and when it tries to await again on a new delayed `Future`,
its computation is aborted with a `FutureCancelled` Exception (because the `CancellableFuture` ended, any pending
computation is thus automatically cancelled) which in this example happens to be silently ignored.

You can register a callback to receive uncaught errors when you create a `CancellableFuture`
(notice that uncaught errors may be received just **after** the `CancellableFuture` returns, but are otherwise
unobservable):

```dart
await CancellableFuture(() {
  ...
}, uncaughtErrorHandler: (e, st) {
  print('Error: $e\n$st');
});
```

Running the example again, the result would be:

```
Time  | Message
------+--------
35    | Tick
550   | Tick
1051  | Tick
1252  | Tick
1257  | Error: FutureCancelled
#0      StructuredAsyncZoneState.remember (package:structured_async/src/_state.dart:47:7)
#1      _createZoneSpec.<anonymous closure> (package:structured_async/src/core.dart:164:20)
#2      _CustomZone.createTimer (dart:async/zone.dart:1388:19)
#3      new Timer (dart:async/timer.dart:54:10)
#4      new Future.delayed (dart:async/future.dart:388:9)
#5      _runForever (file:///projects/structured_async/example/readme_examples.dart:59:18)
<asynchronous suspension>

1258  | Stopped
```

### Cancelling computations

To cancel a `CancellableFuture`, you've guessed it: call the `cancel()` method.

> From within the `CancellableFuture` computation itself, throwing an error has a similar effect as
> being cancelled from the _outside_, i.e. stop everything and complete with an error.
> However, to be more explicit, you can either build the Future with `CancellableFuture.ctx`,
> then call `cancel()` on the provided context object (after which no more async computations may succeed
> within the same computation), or more simply, use `throw const FutureCancelled()`.

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

### CancellableFuture.group() and stream()

`CancellableFuture.group()` makes it easier to run multiple asynchronous computations within the same
`CancellableFuture` and waiting for all their results.

Example:

```dart
Future<void> groupExample() async {
  var result = 0;
  final group = CancellableFuture.group([
            () async => 10,
            () async => 20,
  ], receiver: (int item) => result += item);
  await group;
  print('Result: $result');
}
```

Result:

```
Result: 30
```

As with any `CancellableFuture`, if some error happens in any of the computations within a group,
all other computations are stopped and the error propagates to the `await`-er.

For convenience, there's also a `stream` factory method that returns a `Stream<T>` instead
of `CancellableFuture<void>`, but which has the exact same semantics as a group:

```dart
Future<void> streamExample() async {
  final group = CancellableFuture.stream([
    () async => 10,
    () async => 20,
  ]);
  print('Result: ${await group.toList()}');
}
```

Result:

```
Result: [10, 20]
```

### Limitations

Not everything can be stopped immediately when a `CancellableFuture` is cancelled.

Known issues are listed below.

#### stopped `Timer`s and `Future`s.

When `CancellableFuture` completes or is cancelled explicitly, any pending `Future` and `Timer` within it
will be immediately awakened so  the synchronous code that follows them will be executed.

For example, this simple code probably won't work as you think it should:

```dart
Future<void> scheduledFutureWillRun() async {
  final task = CancellableFuture(() =>
          Future.delayed(Duration(seconds: 2), () => print('2 seconds later')));
  await Future.delayed(Duration(seconds: 1), task.cancel);
  await task;
}
```

This will actually print `2 seconds later`, but after only 1 second, and the program will terminate successfully because
no more asynchronous calls were made within the Future.

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

Running with the `time` option proves that the `CancellableFuture` indeed returned after around 1 second:

```
Time  | Message
------+--------
1032  | Cancelled
```

> Notice that calling any async method or creating a `Future` from within a task
> would have caused the above `CancellableFuture` to abort with a `FutureCancelled` Exception.

As shown above, the `CancellableFuture.ctx` constructor must be used to get access to the context object which exposes
`isComputationCancelled()`, amongst other helper functions.

If passing the context object into where it's needed gets cumbersome, you can use the top-level function
`CancellableContext? currentCancellableContext()`, which returns `null` when it's not executed from within a
`CancellableFuture` computation.

#### `Isolate`s.

Dart `Isolate`s started within a `CancellableFuture` may continue running even after the `CancellableFuture` completes.

To work around this problem, use the context's `scheduleOnCompletion` function and the following general pattern
to ensure the `Isolate`s don't survive after a `CancellableFuture` it was created from returns:

```dart
Future<void> stoppingIsolates() async {
  final task = CancellableFuture.ctx((ctx) async {
    final responsePort = ReceivePort()..listen(print);

    final iso = await Isolate.spawn((message) async {
      message as SendPort;
      for (var i = 0; i < 10; i++) {
        await Future.delayed(Duration(milliseconds: 500),
                        () => message.send('Isolate says: hello'));
      }
      message.send('Isolate finished');
    }, responsePort.sendPort);

    Zone zone = Zone.current;
    // this runs in the root Zone
    ctx.scheduleOnCompletion(() {
      // ensure Isolate is terminated on completion
      zone.print('Killing ISO');
      responsePort.close();
      iso.kill();
    });

    // let this Future continue to run for a few seconds by
    // pretending to do some work
    for (var i = 0; i < 20; i++) {
      try {
        await Future.delayed(Duration(milliseconds: 200));
      } on FutureCancelled {
        break;
      }
    }
    // no more async computations, so it completes normally
    print('CancellableFuture finished');
  });

  Future.delayed(Duration(seconds: 2), () async {
    task.cancel();
    print('XXX Task was cancelled now! XXX');
  });

  await task;

  print('Done');
}
```

Result:

```
Isolate says: hello
Isolate says: hello
Isolate says: hello
XXX Task was cancelled now! XXX
CancellableFuture finished
Killing ISO
Done
```

## Examples

All examples on this page, and more, can be found in the [example](example) directory.
