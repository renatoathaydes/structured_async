## 0.3.0 - 2022-05-29

### Added
- New `CancellableContext.cancel` method.
- New `CancellableFuture.stream` factory method.

### Changed
- `CancellableFuture.group` factory method signature changed to return `CancellableFuture<void>`.

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
