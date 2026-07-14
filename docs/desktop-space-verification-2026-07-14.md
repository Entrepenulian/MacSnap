# Desktop Space Visibility Verification — 2026-07-14

## Behavior contract

While at least one screenshot preview is open, the same MacSnap overlay panel must:

- follow the currently active macOS Desktop Space;
- remain on-screen and fully opaque during every Desktop transition;
- keep its WindowServer identity and full card dimensions;
- move without an `orderOut`/`orderFront` hide-show cycle or visible flicker;
- recover after wake and display-layout changes;
- remain available in full-screen Spaces.

## Root cause

The overlay previously relied on `NSWindow.CollectionBehavior.canJoinAllSpaces`.
For MacSnap's shield-level, nonactivating `NSPanel`, WindowServer intermittently kept
the visible surface on its creation Desktop instead of exposing it on every Desktop.
The screenshot and card still existed, but the panel was off-screen in the active Space.

MacSnap now keeps one panel surface with `moveToActiveSpace` and moves it on
`NSWorkspace.activeSpaceDidChangeNotification`. It reasserts once after the Desktop
transition settles and retains its periodic non-hiding keep-alive.

## Automated regression

Run:

```sh
scripts/verify-desktop-spaces.sh
```

The verifier launches the real `OverlayStack` demo, discovers the current Desktop order,
cycles through every normal Desktop, and fails if the panel is missing, off-screen,
transparent, collapsed, or replaced with another WindowServer window.

## Live installed-app evidence

The signed `/Applications/MacSnap.app` was tested with an actual screenshot from the
production `ScreenshotWatcher`. Across Desktop 1 through Desktop 6 and back:

- panel ID stayed `25951`;
- `kCGWindowIsOnscreen` stayed `1`;
- alpha stayed `1.0`;
- preview height stayed `216` points;
- exactly one MacSnap process was running.

The full Swift self-test suite and the separate persistent demo verification both passed.
