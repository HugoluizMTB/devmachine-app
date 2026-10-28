# Tests, verifying UI and website videos

Part of the devmachine-app guidelines. `CLAUDE.md` is the index and
holds the rules that apply everywhere; this file is binding for its area.

## Tests never spawn ssh
`~/.ssh/config` maps `*-devmachine` to the real host, so a fixture alias such as
`acme-devmachine` logs into the VPS as the Mac user. `ProcessRunner` refuses
ssh/mosh/mosh-client/scp under XCTest; tests inject a fake `CommandRunner`.

## A test that blocks must let go
A fake that holds a call (`BlockingRunner`, a semaphore gate) holds one of
Swift's cooperative threads, and a CI runner has only as many as it has cores
(3 on `macos-15`). Three held calls left behind stopped every later
`Task.detached`, and ~80 unrelated tests timed out in the release job while
passing on a 12-core Mac. `BlockingRunner` opens itself when each test ends;
a new gate must be released the same way. To check, run the built bundle with
one thread: `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 xcrun xctest
.build/debug/DevmachineAppPackageTests.xctest`. (Not through `swift test`:
SwiftPM itself then hangs.) Only the tests that need two calls in flight at
once may fail there.

## Verifying UI
- Screenshot flow: `./scripts/install.sh` (relaunches), `osascript` to front the app,
  `screencapture -x -R<x,y,w,h>` of the window, downscale with `sips` before reading.
- Never send keystrokes into the app while the owner's sessions are open: `⌘K` +
  typing has landed in his live Claude sessions twice. Verify with screenshots,
  `tmux list-clients`/`capture-pane` over ssh, or ask him to try.

- **`ImageRenderer` does not lay out a `ScrollView`.** A snapshot of a view whose
  body scrolls comes back with the chrome and an empty middle, which reads as a
  bug that is not there. Snapshot the header and the state, and check scrolled
  content in the running app.

## Website videos
- `scripts/site_demo_videos.sh <dir>` runs `DEVMACHINE_DEMO_WALK=site`
  (`DemoSiteWalk`) hidden, then writes `<scene>.webm`, `<scene>.mp4` and
  `<scene>-poster.webp` for the home-page loops (operator, sessions, cli,
  context, publish, scheduled, share, home, quickchat, chats, ask). Each opens on its own subject, with no click
  first, at a reading pace: 0.5 s pointer moves, ~15 typed characters a second,
  a second after each change and labels on screen for at least two seconds.
  The walk writes numbered frames per scene at 1600×1000 and a
  `frames.ffconcat` with each frame's hold; `SITE_DEMO_FRAMES=<dir>` re-encodes
  frames already written.
- Every frame is a real app state from demo data. The walk's only setters are
  demo-only: `DemoData.transcriptOverride` (a terminal fed step by step),
  `DemoContextOverride` (the context panel moving along) and
  `SessionShareStore.seedDemo`. The Share sheets are drawn into the frame
  where macOS shows them, since a sheet is a window of its own.
- A bitmap capture has no pointer, so the walk draws the system arrow onto
  its frames (`DemoPointer`): it eases to the control a state comes from,
  shows a shrinking ring for the click, and stays there. Controls mark
  themselves with `.demoClickTarget(id)`, which records their frame only
  while a demo walk captures (`DemoClickTargets`). Short captions are drawn
  the same way (`DemoPointer.drawLabel`), one at a time. Home's drag and
  resize move the real board frame step by step; the "Add a widget"
  popover is drawn under its button. A right-click's menu is
  not drawn: an `NSMenu` is a window the capture never sees.
- A frame's `zoom` names a control the camera eases to (`DemoCamera`, 0.8 s,
  1.8x), by cropping the real frame; a scene with any zoom is captured at 4x
  so the zoomed text stays sharp. `SITE_DEMO_SCENES="context"` renders one
  scene. The context scene's Links rows come from the app's own extraction
  (`contextExtractRefs` + `contextMapLinks`) over the demo transcript.
- `quickchat` draws the quick panel alone over a gradient desktop
  (`desktopView(for:)`), since the real panel is a window of its own. A
  default-walk screen with `zoom` (`27-ask.png`) is cropped the same way,
  then scaled back to the window's 2x size; a screen may set its own
  `windowSize`. A zoom on Ask (`zoomsReachingThePane`) widens to the session
  pane's left edge, and that session gets a transcript that fills the pane,
  so the terminal beside Ask shows output instead of empty rows.
- `cacheDisplay` does not catch `NSProgressIndicator`'s animation, so a
  spinner is one still frame; Home's board is written again for the walk's
  window, since the one written at launch was laid out for a smaller one.
