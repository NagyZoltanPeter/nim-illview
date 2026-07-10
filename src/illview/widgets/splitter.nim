## Splitter (Phase 20, plan-4): two panes divided by a draggable 1-cell
## handle. axH = side-by-side (vertical divider), axV = stacked (horizontal
## divider). The handle is a focusable child: drag it with the mouse (mouse
## capture) or, when it holds focus, nudge with Alt+Left/Right (axH) or
## Alt+Up/Down (axV). Pane minimums come from the children's size hints.

import ../core/[geometry, theme, view, events, drawcontext]

type
  Splitter* = ref object of Group
    axis*: Axis
    first*, second*: View
    pos*: int          # first-pane size in cells along the axis
    handle: SplitHandle

  SplitHandle = ref object of View
    owner: Splitter
    dragging: bool

func splitAvail(s: Splitter): int =
  let cr = s.clientRect
  max((if s.axis == axH: cr.w else: cr.h) - 1, 0) # minus the 1-cell divider

func axisMin(v: View, axis: Axis): int =
  let h = v.outerHints()
  if axis == axH: h.w.min else: h.h.min

proc clampPos(s: Splitter) =
  let avail = s.splitAvail
  let mf = axisMin(s.first, s.axis)
  let ms = axisMin(s.second, s.axis)
  s.pos = clamp(s.pos, mf, max(avail - ms, mf))
  s.pos = clamp(s.pos, 0, avail)

proc setPos*(s: Splitter, p: int) =
  let old = s.pos
  s.pos = p
  s.clampPos()
  if s.pos != old:
    s.invalidate()

# --- handle: draw + drag/keyboard --------------------------------------------

method draw*(h: SplitHandle, dc: DrawContext) {.gcsafe, raises: [].} =
  let st = h.styleOf(if h.isFocused: tkSelectionFocused else: tkBorder)
  let glyph = if h.owner.axis == axH: "│" else: "─"
  if h.owner.axis == axH:
    for y in 0 ..< max(h.bounds.h, 1): dc.write(0, y, glyph, st)
  else:
    for x in 0 ..< max(h.bounds.w, 1): dc.write(x, 0, glyph, st)

method handleEvent*(h: SplitHandle, ev: Event): bool {.gcsafe, raises: [].} =
  let s = h.owner
  case ev.kind
  of evMouse:
    case ev.imouse.action
    of maPress:
      h.dragging = true
      h.captureMouse()
      return true
    of maMove:
      if h.dragging:
        # position the divider directly under the mouse (absolute, drift-free)
        let hAbs = h.absOrigin
        let sAbs = s.absOrigin
        if s.axis == axH:
          s.setPos(ev.imouse.mx + hAbs.x - sAbs.x)
        else:
          s.setPos(ev.imouse.my + hAbs.y - sAbs.y)
        return true
    of maRelease:
      if h.dragging:
        h.dragging = false
        h.releaseMouse()
        return true
    else:
      discard
  of evKey:
    if modAlt in ev.ikey.keyMods:
      if s.axis == axH:
        case ev.ikey.key
        of Key.Left: s.setPos(s.pos - 1); return true
        of Key.Right: s.setPos(s.pos + 1); return true
        else: discard
      else:
        case ev.ikey.key
        of Key.Up: s.setPos(s.pos - 1); return true
        of Key.Down: s.setPos(s.pos + 1); return true
        else: discard
  of evFocusGained, evFocusLost:
    h.invalidate()
  else:
    discard
  false

# --- splitter ----------------------------------------------------------------

proc newSplitter*(axis: Axis, first, second: View, pos = 0): Splitter =
  ## pos = 0 means "split down the middle on first arrange".
  result = Splitter(axis: axis, first: first, second: second, pos: pos)
  initView(result)
  result.handle = SplitHandle(owner: result)
  initView(result.handle)
  result.handle.focusable = true
  add(Group(result), first)
  add(Group(result), result.handle)
  add(Group(result), second)

proc divider*(s: Splitter): View = s.handle
  ## The focusable divider handle — Tab to it to enable Alt+arrow nudging.

method arrange*(s: Splitter, r: Rect) {.gcsafe, raises: [].} =
  s.bounds = r
  let cr = s.clientRect
  if s.pos == 0: # unset: centre it
    s.pos = s.splitAvail div 2
  s.clampPos()
  if s.axis == axH:
    s.first.arrange(rect(0, 0, s.pos, cr.h))
    s.handle.arrange(rect(s.pos, 0, 1, cr.h))
    s.second.arrange(rect(s.pos + 1, 0, max(cr.w - s.pos - 1, 0), cr.h))
  else:
    s.first.arrange(rect(0, 0, cr.w, s.pos))
    s.handle.arrange(rect(0, s.pos, cr.w, 1))
    s.second.arrange(rect(0, s.pos + 1, cr.w, max(cr.h - s.pos - 1, 0)))
