## Phase 2+10 demo: two overlapping windows, click-to-raise, Tab/Shift-Tab
## cycles focus, all drawing clipped through DrawContext. Drag a title to
## move, drag the ◢ corner to resize, Alt+Arrows / Alt+Shift+Arrows work
## too. ESC quits.

import std/strformat
import chronos
import illview

type
  FocusBox = ref object of View
    ## Focusable pane showing its own focus/click state.
    label: string
    clicks: int
    hasFocus: bool

proc newFocusBox(label: string, bounds: Rect): FocusBox =
  result = FocusBox(label: label)
  initView(result)
  result.bounds = bounds
  result.focusable = true

method draw(v: FocusBox, dc: DrawContext) =
  let st = v.styleOf(if v.hasFocus: tkButtonFocused else: tkButton)
  dc.fill(rect(0, 0, v.bounds.w, v.bounds.h), " ", st)
  dc.write(1, 0, v.label, st)
  dc.write(1, 1, (if v.hasFocus: "focused" else: "       "), st)
  dc.write(1, 2, &"clicks: {v.clicks}", st)

method handleEvent(v: FocusBox, ev: Event): bool =
  case ev.kind
  of evFocusGained:
    v.hasFocus = true
    v.invalidate()
  of evFocusLost:
    v.hasFocus = false
    v.invalidate()
  of evMouse:
    if ev.imouse.action == maPress:
      inc v.clicks
      v.invalidate()
      return true
  else:
    discard
  false

proc addWindow(app: App, title: string, r: Rect) =
  let win = newWindow(title, r)
  win.add newFocusBox("pane 1", rect(1, 1, 14, 3))
  win.add newFocusBox("pane 2", rect(1, 5, 14, 3))
  app.desktop.add win

proc main() {.async.} =
  let app = newApp()
  app.addWindow("First", rect(4, 2, 34, 12))
  app.addWindow("Second", rect(24, 8, 34, 12))

  app.onInput = proc(ev: InputEvent) {.gcsafe, raises: [].} =
    if ev.kind == ikKey and ev.key == Key.Escape:
      app.stop()

  await app.run()

waitFor main()
