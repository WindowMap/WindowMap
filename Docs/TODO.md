# TODO

- README: add screenshot or GIF demo
- Pin Swift/Xcode version in CI workflow (local: 6.3.3, CI: macos-14 default)
- BUG: stale log file descriptor — launchd's StandardErrorPath doesn't survive process restarts reliably. App should manage its own log file.
- BUG: gesture tap background thread dies silently — auto-recovery added, awaiting confirmation
- BUG: resize cursors show on picker borders — `.fullSizeContentView` style mask causes AppKit to add resize zones on borderless panels
- BUG: Firefox window randomly changes context/workspace — logging added, awaiting reproduction
