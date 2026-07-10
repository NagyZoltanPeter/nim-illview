## Phase 20 demo: a horizontal Splitter with a peer list on the left and a log
## on the right. Drag the divider with the mouse, or Tab to it and nudge with
## Alt+Left / Alt+Right. Tab also cycles the list and the log (wheel scrolls
## each). ESC quits.

import std/strformat
import chronos
import ../src/illview

proc main() {.async.} =
  let app = newApp()

  let win = newWindow("splitter", rect(0, 0, 0, 0))
  win.dock = dkFill

  var peers: seq[string]
  for i in 1 .. 12: peers.add &"peer-{i:02}"
  let list = newListView(peers)
  list.showScrollbar = true

  let log = newTextView()
  log.showScrollbar = true
  for i in 1 .. 40: log.addLine &"[{i:03}] event on the wire"

  let split = newSplitter(axH, list, log, pos = 16)
  split.dock = dkFill
  win.add split
  app.desktop.add win

  app.onInput = proc(ev: InputEvent) {.gcsafe, raises: [].} =
    if ev.kind == ikKey and ev.key == Key.Escape:
      app.stop()

  await app.run()

waitFor main()
