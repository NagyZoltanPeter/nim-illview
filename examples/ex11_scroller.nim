## Phase 19 demo: a Scroller over a tall column of buttons, with a synced
## vertical ScrollBar beside it. Tab / Shift-Tab walk the buttons and the
## viewport auto-scrolls to keep the focused one visible; the mouse wheel and
## PageUp/PageDown scroll; dragging the scrollbar thumb scrolls too. ESC quits.

import std/strformat
import chronos
import ../src/illview
import ../src/illview/layout/layout

proc main() {.async.} =
  let app = newApp()

  let win = newWindow("scroller", rect(0, 0, 0, 0))
  win.dock = dkFill

  let row = newHBox(spacing = 0)
  row.dock = dkFill

  # tall content: 30 focusable buttons stacked in a VBox
  let col = newVBox(spacing = 0)
  for i in 1 .. 30:
    let b = newButton(&"Item {i:02}")
    b.hint = (prefHint(0, stretch = 1), fixedHint(1)) # full width, 1 row tall
    col.add b

  let sc = newScroller(col)
  sc.hint = (prefHint(0, stretch = 1), prefHint(0, stretch = 1))

  let bar = newScrollBar(axV)
  bar.onScroll = proc(pos: int) {.gcsafe, raises: [].} =
    sc.scrollTo(0, pos) # the bar drives the scroller

  row.add sc
  row.add bar
  win.add row
  app.desktop.add win

  app.onInput = proc(ev: InputEvent) {.gcsafe, raises: [].} =
    if ev.kind == ikKey and ev.key == Key.Escape:
      app.stop()
    # keep the bar in step with the scroller after every input (post-routing)
    bar.setRange(sc.virtualSize.h, sc.contentH, sc.offY)

  await app.run()

waitFor main()
