import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

void main() {
  group('Can run README examples', () {
    test('example 1', () async {
      final result = await _run(1, timeout: Duration(seconds: 3));
      expect(await result.firstError, isNull);
      expect(result.sysout,
          equals(['Tick', 'Tick', 'Tick', 'Stopped', 'Tick', 'Tick', 'Tick']));
    });

    test('example 2', () async {
      final result = await _run(2);
      expect(await result.firstError, isNull);
      expect(result.sysout, equals(['Tick', 'Tick', 'Tick', 'Stopped']));
    });

    test('example 3', () async {
      final result = await _run(3);
      expect(await result.firstError, contains('not great'));
      expect(result.sysout, equals([]));
    });

    test('example 4', () async {
      final result = await _run(4);
      expect(await result.firstError, isNull);
      expect(result.sysout, equals(['ERROR: not great', 'Stopped']));
    });

    test('example 5', () async {
      final result = await _run(5);
      expect(await result.firstError, isNull);
      expect(result.sysout,
          equals(['Tic', 'Tac', 'Tic', 'Future was cancelled', 'Tac']));
    });

    test('example 6', () async {
      final result = await _run(6);
      expect(await result.firstError, isNull);
      expect(result.sysout, equals(['Result: 30']));
    });

    test('example 7', () async {
      final result = await _run(7, timeout: Duration(seconds: 10));
      expect(await result.firstError, isNull);
      expect(result.sysout, equals(['Tick', 'Tick', '10']));
    });

    test('example 8', () async {
      final result = await _run(8);
      expect(await result.firstError, isNull);
      expect(result.sysout, equals(['2 seconds later']));
    });

    test('example 9', () async {
      final result = await _run(9);
      expect(await result.firstError, isNull);
      expect(result.sysout, equals(['Cancelled']));
    });

    test('example 10', () async {
      final result = await _run(10);
      expect(await result.firstError, isNull);
      final ping = 'Waiting for ping response';
      final ok = 'Ping OK';
      final cancelled = 'XXX Isolate should be cancelled now! XXX';
      expect(
          result.sysout,
          equals([
            ping,
            ok,
            ping,
            ok,
            ping,
            ok,
            cancelled,
            'Cancelled',
            'Done',
            ping,
          ]));
    });
  }, retry: 1);
}

class _RunResult {
  final List<String> sysout;
  final ReceivePort errors;

  _RunResult(this.sysout, this.errors);

  FutureOr get firstError async {
    try {
      return await errors.timeout(Duration(milliseconds: 50)).first;
    } on TimeoutException {
      return null;
    }
  }
}

Future<_RunResult> _run(int example,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final exitPort = ReceivePort();
  final errors = ReceivePort();
  final messages = ReceivePort();
  final sysout = <String>[];

  final iso = await Isolate.spawnUri(
      File('example/readme_examples.dart').absolute.uri,
      [example.toString()],
      messages.sendPort,
      onExit: exitPort.sendPort,
      onError: errors.sendPort);

  Future.delayed(timeout, iso.kill);

  messages.listen((message) {
    sysout.add(message.toString());
  });

  await exitPort.first;
  return _RunResult(sysout, errors);
}
