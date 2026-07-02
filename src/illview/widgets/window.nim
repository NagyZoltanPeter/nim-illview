## Window: framed, titled Group, riding the decoration mechanism (plan-2
## D1): the parent draws frame + title; border doubles while active. The
## window itself only fills its content background and hosts children.

import ../core/[geometry, theme, view, drawcontext, events]

type
  Window* = ref object of Group

proc newWindow*(title: string, bounds: Rect): Window =
  result = Window(borderTitle: title)
  initView(result)
  result.bounds = bounds
  result.border = bkSingle

proc title*(w: Window): string =
  w.borderTitle

proc `title=`*(w: Window, s: string) =
  w.borderTitle = s
  w.invalidate()

func isActive*(w: Window): bool =
  ## Active = the focus chain passes through this window.
  w.parent != nil and w.parent.focused == w

method borderKind*(w: Window): BorderKind {.gcsafe, raises: [].} =
  if w.isActive: bkDouble else: bkSingle

method borderStyle*(w: Window): Style {.gcsafe, raises: [].} =
  w.styleOf(if w.isActive: tkWindowFrameActive else: tkWindowFrame)

method titleStyle*(w: Window): Style {.gcsafe, raises: [].} =
  w.styleOf(tkWindowTitle)

method draw*(w: Window, dc: DrawContext) {.gcsafe, raises: [].} =
  dc.fill(rect(0, 0, w.contentW, w.contentH), " ", w.styleOf(tkWindowBg))
  procCall Group(w).draw(dc)

method handleEvent*(w: Window, ev: Event): bool {.gcsafe, raises: [].} =
  ## Consume mouse events so clicks on the frame/background never bubble to
  ## views underneath the window.
  ev.kind == evMouse
