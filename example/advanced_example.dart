import 'dart:async';
import 'dart:math';

import 'package:structured_async/structured_async.dart';

import 'structured_async_example.dart' show sleep;

final random = Random();

/// This is the action executed by all CancellableFutures.
Future<void> cycle(String group) async {
  for (var i = 0; i < 100; i++) {
    if (i == random.nextInt(100)) {
      throw 'XXXX group $group killing itself XXXXX';
    }
    print('Group $group: $i');
    await sleep(const Duration(seconds: 1));
  }
  print('Group $group done');
}

/// Create a CancellableFuture group with [count] members.
/// All Futures in the group get cancelled together, if one dies,
/// all other members die too.
CancellableFuture<void> createGroup(String prefix, int count) =>
    CancellableFuture.group(
        List.generate(count, (index) => () => cycle('$prefix-${index + 1}')),
        null,
        intoNothing);

main() async {
  // run in an error Zone so the main process does not die when
  // any of the groups die.
  await runZonedGuarded(() async {
    // group A will have 4 members: A-1, A-2, A-3 and A-4
    final groupA = createGroup('A', 4);

    // because Groups B and C are inside the same group, if any of their
    // members die, all members of the other group also die!
    final groupsBAndC = CancellableFuture.group([
      () => createGroup('B', 2),
      () => createGroup('C', 2),
    ], null, intoNothing);

    // randomly cancel groups from "outside"
    final randomKiller = CancellableFuture(() async {
      void maybeCancel() {
        switch (random.nextInt(100)) {
          case 10:
          case 20:
            print('Cancelling all of group A from outside');
            return groupA.cancel();
          case 30:
          case 40:
            print('Cancelling parent of groups B and C from outside');
            return groupsBAndC.cancel();
        }
      }

      for (var i = 0; i < 100; i++) {
        await sleep(const Duration(seconds: 1), maybeCancel);
      }
    });

    final waiterA = groupA.then((_) {
      print('Group A ended successfully');
    }, onError: (e) {
      print('Group A did not finish successfully: $e');
    });

    final waiterBAndC = groupsBAndC.then((_) {
      print('Groups B and C ended successfully');
    }, onError: (e) {
      print('Groups B and C did not finish successfully: $e');
    });

    // when all groups are "done", kill the killer!
    await waiterA;
    await waiterBAndC;
    randomKiller.cancel();
  }, (e, st) {
    print(e);
  });
}
