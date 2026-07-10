## ScrollBar (Phase 18, plan-4 D15): a passive 1-cell-thick scroll control
## (vertical or horizontal) plus a shared thumb-geometry helper reused by the
## list/table/textview indicator columns. Click-page, drag-thumb (via mouse
## capture) and wheel; reports through `onScroll(pos)`.

import ../core/[geometry, theme, view, events, drawcontext]

type
  ScrollBar* = ref object of View
    axis*: Axis            # axV = vertical (default), axH = horizontal
    total*: int            # total content units
    page*: int             # visible units (viewport)
    pos*: int              # current offset in 0 .. scrollMax
    onScroll*: proc(pos: int) {.gcsafe, raises: [].}
    dragging: bool
    dragGrab: int          # thumb-cell offset where the drag started

# scrollMax(total, page) and thumbGeom live in core/geometry (shared, pure).

proc newScrollBar*(axis = axV): ScrollBar =
  result = ScrollBar(axis: axis, page: 1, total: 1)
  initView(result)
  result.focusable = false
  if axis == axV:
    result.hint = (fixedHint(1),
                   SizeHint(min: 2, pref: 8, max: high(int), stretch: 1))
  else:
    result.hint = (SizeHint(min: 2, pref: 8, max: high(int), stretch: 1),
                   fixedHint(1))

proc scrollMax*(sb: ScrollBar): int = scrollMax(sb.total, sb.page)

proc emitScroll(sb: ScrollBar) =
  sb.invalidate()
  if sb.onScroll != nil:
    sb.onScroll(sb.pos)

proc setPos*(sb: ScrollBar, p: int) =
  let np = clamp(p, 0, sb.scrollMax)
  if np != sb.pos:
    sb.pos = np
    sb.emitScroll()

proc setRange*(sb: ScrollBar, total, page: int, pos = -1) =
  ## Update the modeled content; pos < 0 keeps the current offset (re-clamped).
  sb.total = max(total, 0)
  sb.page = max(page, 1)
  sb.pos = clamp((if pos < 0: sb.pos else: pos), 0, sb.scrollMax)
  sb.invalidate()

func track(sb: ScrollBar): int =
  if sb.axis == axV: sb.contentH else: sb.contentW

method draw*(sb: ScrollBar, dc: DrawContext) {.gcsafe, raises: [].} =
  let st = sb.styleOf(tkScrollBar)
  let t = sb.track
  let (ts, tl) = thumbGeom(t, sb.total, sb.page, sb.pos)
  for i in 0 ..< t:
    let glyph = if i >= ts and i < ts + tl: "█" else: "░"
    if sb.axis == axV: dc.write(0, i, glyph, st)
    else: dc.write(i, 0, glyph, st)

method handleEvent*(sb: ScrollBar, ev: Event): bool {.gcsafe, raises: [].} =
  if ev.kind != evMouse:
    return false
  let m = ev.imouse
  let cell = if sb.axis == axV: m.my else: m.mx
  let t = sb.track
  case m.action
  of maWheelUp:
    sb.setPos(sb.pos - 1); return true
  of maWheelDown:
    sb.setPos(sb.pos + 1); return true
  of maPress:
    let (ts, tl) = thumbGeom(t, sb.total, sb.page, sb.pos)
    if cell < ts:
      sb.setPos(sb.pos - sb.page)      # page towards the start
    elif cell >= ts + tl:
      sb.setPos(sb.pos + sb.page)      # page towards the end
    else:
      sb.dragging = true
      sb.dragGrab = cell - ts
      sb.captureMouse()
    return true
  of maMove:
    if sb.dragging:
      let (_, tl) = thumbGeom(t, sb.total, sb.page, sb.pos)
      let span = max(t - tl, 1)
      let newStart = clamp(cell - sb.dragGrab, 0, span)
      sb.setPos(sb.scrollMax * newStart div span)
      return true
  of maRelease:
    if sb.dragging:
      sb.dragging = false
      sb.releaseMouse()
      return true
  return false
