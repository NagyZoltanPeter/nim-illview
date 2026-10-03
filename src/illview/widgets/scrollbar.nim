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

# scrollMax(total, page) and thumbGeom live in core/geometry (shared, pure).

proc newScrollBar*(axis = axV): ScrollBar =
  result = ScrollBar(axis: axis, page: 1, total: 1)
  initView(result)
  result.focusable = true # arrows / PgUp / PgDn / Home / End while focused
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
  var thumb = st
  thumb.bright = sb.isFocused # focus cue: a bright ■
  for i, glyph in scrollGlyphs(sb.track, sb.total, sb.page, sb.pos, sb.axis):
    let g = if glyph == "■": thumb else: st
    if sb.axis == axV: dc.write(0, i, glyph, g)
    else: dc.write(i, 0, glyph, g)

method handleEvent*(sb: ScrollBar, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    let k = ev.ikey
    if modAlt in k.keyMods:
      return false # Alt-chords are window/app level (move/resize)
    if k.isTabSwitch:
      return false # Ctrl+PgUp/PgDn switch tabs (deviation #39)
    let back = if sb.axis == axV: Key.Up else: Key.Left
    let fwd = if sb.axis == axV: Key.Down else: Key.Right
    if k.key == back: sb.setPos(sb.pos - 1)
    elif k.key == fwd: sb.setPos(sb.pos + 1)
    elif k.key == Key.PageUp: sb.setPos(sb.pos - sb.page)
    elif k.key == Key.PageDown: sb.setPos(sb.pos + sb.page)
    elif k.key == Key.Home: sb.setPos(0)
    elif k.key == Key.End: sb.setPos(sb.scrollMax)
    else: return false
    return true
  of evFocusGained, evFocusLost:
    sb.invalidate()
    return false
  of evMouse:
    discard
  else:
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
    let a = arrowCells(t)
    let th = a + thumbCell(t, sb.total, sb.page, sb.pos)
    if a == 1 and cell == 0:
      sb.setPos(sb.pos - 1)            # ▲ / ◄ arrow: one step
    elif a == 1 and cell == t - 1:
      sb.setPos(sb.pos + 1)            # ▼ / ► arrow: one step
    elif cell < th:
      sb.setPos(sb.pos - sb.page)      # page towards the start
    elif cell > th:
      sb.setPos(sb.pos + sb.page)      # page towards the end
    else:
      sb.dragging = true               # the ■ thumb
      sb.captureMouse()
    return true
  of maMove:
    if sb.dragging:
      let a = arrowCells(t)
      let span = max(t - 2 * a - 1, 1) # thumb positions within the rail
      let newCell = clamp(cell - a, 0, span)
      sb.setPos(sb.scrollMax * newCell div span)
      return true
  of maRelease:
    if sb.dragging:
      sb.dragging = false
      sb.releaseMouse()
      return true
  return false
