# Changelog

Notable changes to Wreckingball. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and version numbers follow [semantic versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] — 2026-10-24

### Added

- **Presentation window.** A **Present** button next to Record opens a window containing nothing
  but the live canvas, to share in Google Meet, Zoom or Slack. There is no visible title bar: its
  close and resize buttons appear only while the pointer is over it, so the other end sees the
  canvas and nothing else. It keeps the canvas aspect ratio, goes full screen, and remembers where
  it was.
- **Separate camera switches for recording and presenting.** Presenting starts with the camera
  off, since in a call your camera usually has a tile of its own. Recording and presenting are
  mutually exclusive, so one composited canvas still serves the recorder, the preview and the
  presentation window alike.
- **Pause and resume while recording.** Time spent paused is cut out of both the video and the
  audio track, so the two never drift apart. The timer counts only what is in the file, and the
  border around the preview turns amber.
- **Remote control for pausing:** a "Pause or resume recording" shortcut in Settings, and the
  `wreckingball://pause/toggle`, `wreckingball://record/pause` and `wreckingball://record/resume`
  URL commands.
- **Search in the window list**, matching on app name and window title. Every word has to appear,
  so "chrome git" narrows to the Chrome window with the repo open, and Return presents the first
  match.

### Changed

- The keystroke overlay ignores keys pressed while Wreckingball itself is in front, so typing in
  the window search never reaches the canvas. Wreckingball's own windows can't be presented, so
  nothing on the canvas is ever Wreckingball.

## [0.1.0] — 2026-10-10

First release: record a single window framed over a background, with a camera overlay, a keystroke
overlay and microphone audio, straight to an `.mp4`. Live window switching with pinned windows,
global shortcuts and a `wreckingball://` URL scheme for Stream Deck control.

[0.2.0]: https://github.com/danielcooper/wreckingball/releases/tag/v0.2.0
[0.1.0]: https://github.com/danielcooper/wreckingball/releases/tag/v0.1.0
