import 'dart:async';
import 'dart:isolate';
import 'package:structured_async/structured_async.dart';

import 'structured_async_example.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    args = ['1'];
  }
  switch (int.parse(args[0])) {
    case 1:
      return await futureNeverStops();
    case 2:
      return await cancellableFutureStopsWhenItReturns();
    case 3:
      return await futureWillNotPropagateThisError();
    case 4:
      return await cancellableFutureDoesPropagateThisError();
    case 5:
      return await explicitCancel();
    case 6:
      return await groupExample();
    case 7:
      return await neverStops();
    case 8:
      return await scheduledFutureWillRun();
    case 9:
      return await explicitCheckForCancellation();
    default:
      throw 'Cannot recognize arguments. Give a number from 1 to 9.';
  }
}

_runForever() async {
  while (true) {
    await Future.delayed(Duration(seconds: 1), () => print('Tick'));
  }
}

Future<void> futureNeverStops() async {
  await Future(() {
    _runForever();
    return Future.delayed(Duration(milliseconds: 3500));
  });
  print('Stopped');
}

Future<void> cancellableFutureStopsWhenItReturns() async {
  await CancellableFuture(() {
    _runForever();
    return Future.delayed(Duration(milliseconds: 3500));
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

  // cancel after 3 seconds
  Future.delayed(Duration(seconds: 3), future.cancel);

  try {
    await future;
  } on FutureCancelled {
    print('Future was cancelled');
  }
}

Future<void> groupExample() async {
  final group = CancellableFuture.group([
    () async => 10,
    () async => 20,
  ], 0, (int a, int b) => a + b);
  print('Result: ${await group}');
}

Future<void> neverStops() async {
  final task = CancellableFuture(() async {
    Timer.periodic(Duration(seconds: 1), (_) => print('Tick'));
  });
  Future.delayed(Duration(seconds: 3), task.cancel);
}

Future<void> scheduledFutureWillRun() async {
  final task = CancellableFuture(() =>
      Future.delayed(Duration(seconds: 2), () => print('2 seconds later')));
  await Future.delayed(Duration(seconds: 1), task.cancel);
}

Future<void> explicitCheckForCancellation() async {
  final task = CancellableFuture(() => Future.delayed(Duration(seconds: 2), () {
        if (isComputationCancelled()) return 'Cancelled';
        return '2 seconds later';
      }));
  await Future.delayed(Duration(seconds: 1), task.cancel);
  print(await task);
}

Future<void> cannotStopIsolate() async {
  final task = CancellableFuture(() async {
    final iso = await Isolate.spawn((message) async {
      for (var i = 0; i < 5; i++) {
        await Future.delayed(
            Duration(seconds: 1), () => print('Isolate says: $message'));
      }
      print('Isolate finished');
    }, 'hello');
    print(
        'iso capabilities - pause: ${iso.pauseCapability}, terminate: ${iso.terminateCapability}');
    return iso;
  });

  await Future.delayed(Duration(seconds: 3), task.cancel);

  final iso = await task;
  final responsePort = ReceivePort();
  final responseStream = responsePort.asBroadcastStream();
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

  // ensure Isolate is terminated
  responsePort.close();
  iso.kill();

  print('Done');
}
