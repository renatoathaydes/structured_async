import 'dart:async';
import 'dart:isolate';
import 'package:structured_async/structured_async.dart';

int now() => DateTime.now().millisecondsSinceEpoch;

void main(List<String> args, [SendPort? testIsolatePort]) {
  if (args.isEmpty) {
    args = ['1'];
  }
  final exampleIndex = int.parse(args[0]) - 1;
  if (testIsolatePort != null) {
    runZoned(() {
      _run(exampleIndex);
    }, zoneSpecification: ZoneSpecification(print: (a, b, c, msg) {
      testIsolatePort.send(msg);
    }));
  } else {
    _run(exampleIndex);
  }
}

Future<void> _run(int exampleIndex) async {
  final examples = [
    futureNeverStops,
    cancellableFutureStopsWhenItReturns,
    futureWillNotPropagateThisError,
    cancellableFutureDoesPropagateThisError,
    explicitCancel,
    groupExample,
    streamExample,
    periodicTimerIsCancelledOnCompletion,
    scheduledFutureWillRun,
    explicitCheckForCancellation,
    stoppingIsolates,
  ];

  if (exampleIndex < examples.length) {
    return await examples[exampleIndex]();
  }
  throw 'Cannot recognize arguments. Give a number from 1 to ${examples.length}.';
}

_runForever() async {
  while (true) {
    print('Tick');
    await Future.delayed(Duration(milliseconds: 500));
  }
}

Future<void> futureNeverStops() async {
  await Future(() {
    _runForever();
    return Future.delayed(Duration(milliseconds: 1200));
  });
  print('Stopped');
}

Future<void> cancellableFutureStopsWhenItReturns() async {
  await CancellableFuture(() {
    // <--- this is the only difference!
    _runForever(); // no await here
    return Future.delayed(Duration(milliseconds: 1200));
  });
  print('Stopped');
}

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

Future<void> cancellableFutureDoesPropagateThisError() async {
  try {
    await CancellableFuture(() {
      _throw();
      return Future.delayed(Duration(milliseconds: 100));
    });
  } catch (e) {
    print('ERROR: $e');
  } finally {
    print('Stopped');
  }
}

Future<void> explicitCancel() async {
  Future<void> printForever(String message) async {
    while (true) {
      await Future.delayed(Duration(seconds: 1), () => print(message));
    }
  }

  final future = CancellableFuture(() async {
    printForever('Tic'); // no await
    await Future.delayed(Duration(milliseconds: 500));
    await printForever('Tac');
  });

  // cancel after 2 seconds
  Future.delayed(Duration(seconds: 2), future.cancel);

  try {
    await future;
  } on FutureCancelled {
    print('Future was cancelled');
  }
}

Future<void> groupExample() async {
  var result = 0;
  final group = CancellableFuture.group([
    () async => 10,
    () async => 20,
  ], (int item) => result += item);
  await group;
  print('Result: $result');
}

Future<void> streamExample() async {
  final group = CancellableFuture.stream([
    () async => 10,
    () async => 20,
  ]);
  print('Result: ${await group.toList()}');
}

Future<void> periodicTimerIsCancelledOnCompletion() async {
  final task = CancellableFuture(() async {
    // fire and forget a periodic timer
    Timer.periodic(Duration(milliseconds: 500), (_) => print('Tick'));
    await Future.delayed(Duration(milliseconds: 1200));
    return 10;
  });
  print(await task);
}

Future<void> scheduledFutureWillRun() async {
  final task = CancellableFuture(() =>
      Future.delayed(Duration(seconds: 2), () => print('2 seconds later')));
  await Future.delayed(Duration(seconds: 1), task.cancel);
  await task;
}

Future<void> explicitCheckForCancellation() async {
  final task =
      CancellableFuture.ctx((ctx) => Future.delayed(Duration(seconds: 2), () {
            if (ctx.isComputationCancelled()) return 'Cancelled';
            return '2 seconds later';
          }));
  await Future.delayed(Duration(seconds: 1), task.cancel);
  print(await task);
}

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

  Future.delayed(Duration(seconds: 3), () async {
    task.cancel();
    print('XXX Isolate should be cancelled now! XXX');
  });

  try {
    await task;
  } on FutureCancelled {
    print('Cancelled');
  }

  print('Done');
}
