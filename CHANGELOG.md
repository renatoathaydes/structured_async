## 0.3.2 - 2023-05-11

### Changed
- Updated dependencies, allow Dart 3.

## 0.3.1 - 2022-05-30

### Changed
- Descendant `CancellableContext.scheduleOnCancel` callbacks are now called when ancestor is cancelled.

## 0.3.0 - 2022-05-29

### Added
- New `CancellableContext.cancel` method.
- New `CancellableContext.scheduleOnCompletion` method.
- New `CancellableFuture.stream` factory method.

### Changed
- `CancellableFuture.group` factory method signature changed and returns `CancellableFuture<void>`.
- `CancellableFuture` constructors take new parameters `debugName` and `uncaughtErrorHandler`.
- Changed behavior when cancelling `CancellableFuture` to always complete pending `Future`s and `Timer`s.

### Removed
- `toList`, `toSet` and `toNothing` accumulators as the `group` method no longer takes accumulators.

## 0.2.0 - 2022-05-28

### Added
- Also cancel periodicTimers, not just simple timers.
- New `CancellableContext` class and `CancellableFuture.ctx` constructor.
- New `ctx.scheduleOnCancel` function to run callbacks on cancellation.
- Added `currentCancellableContext()` function.

## 0.1.0 - 2022-05-27

- Initial version.
