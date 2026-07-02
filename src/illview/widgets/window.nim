## Window: framed, titled Group. Children live in the content area
## (clientRect, inset by the 1-cell frame) and are clipped to it.

import std/unicode
import ../core/[geometry, theme, view, drawcontext, events]

type
  Window* = ref object of Group
    title*: string

proc newWindow*(title: string, bounds: Rect): Window =
  result = Window(title: title)
  initView(result)
  result.bounds = bounds

func isActive*(w: Window): bool =
  ## Active = the focus chain passes through this window.
  w.parent != nil and w.parent.focused == w

method clientRect*(w: Window): Rect {.gcsafe, raises: [].} =
  rect(1, 1, max(w.bounds.w - 2, 0), max(w.bounds.h - 2, 0))

method draw*(w: Window, dc: DrawContext) {.gcsafe, raises: [].} =
  let r = rect(0, 0, w.bounds.w, w.bounds.h)
  let frameStyle = w.styleOf(if w.isActive: tkWindowFrameActive else: tkWindowFrame)
  dc.fill(r, " ".runeAt(0), w.styleOf(tkWindowBg))
  dc.box(r, frameStyle, double = w.isActive)
  if w.title.len > 0 and w.bounds.w >= 4:
    let t = " " & w.title & " "
    let tlen = t.runeLen
    let x = max((w.bounds.w - tlen) div 2, 1)
    dc.write(x, 0, t, w.styleOf(tkWindowTitle))
  procCall Group(w).draw(dc)

method handleEvent*(w: Window, ev: Event): bool {.gcsafe, raises: [].} =
  ## Consume mouse events so clicks on the frame/background never bubble to
  ## views underneath the window.
  ev.kind == evMouse
