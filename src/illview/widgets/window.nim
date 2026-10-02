## Window: framed, titled Group, riding the decoration mechanism (plan-2
## D1): the parent draws frame + title; border doubles while active. The
## window itself only fills its content background and hosts children.
##
## Move/resize (plan-2 D7, floating dkNone windows only):
##   mouse — drag the title row to move; drag the bottom-right corner
##   (marked ◢ while active) to resize; keyboard — Alt+Arrows move,
##   Alt+Shift+Arrows resize.

import std/unicode
import ../core/[geometry, theme, view, drawcontext, events]
import ./button

const
  MinW = 8
  MinH = 3

type
  DragMode = enum
    dmNone, dmMove, dmResize

  Window* = ref object of Group
    dragMode: DragMode
    dragOff: Point # window origin relative to the grab point (move)
    closable*: bool # show/allow the [■] close box (plan-4 P21)
    zoomable*: bool # show/allow the [↑]/[↓] zoom box
    zoomed: bool
    savedBounds: Rect # pre-zoom bounds, restored on un-zoom
    onClose*: proc(w: Window) {.gcsafe, raises: [].}
      ## Close override; nil = default (detach from the parent + dispose).

proc newWindow*(title: string, bounds: Rect): Window =
  result = Window(borderTitle: title, closable: true, zoomable: true)
  initView(result)
  result.bounds = bounds
  result.border = bkSingle # palette pDefault: the theme's base (gray, deviation #35)

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

method drawOverlay*(w: Window, dc: DrawContext) {.gcsafe, raises: [].} =
  ## Resize handle on the frame corner (dc spans the FULL rect incl. border).
  if w.isActive and w.dock == dkNone and w.bounds.w >= 2 and w.bounds.h >= 2:
    dc.putCell(w.bounds.w - 1, w.bounds.h - 1, "◢".runeAt(0), w.borderStyle)
  # title-row chrome (plan-4 P21): close box at the left, zoom box at the right
  if w.closable and w.bounds.w >= 6:
    dc.write(1, 0, "[■]", w.borderStyle)
    dc.write(2, 0, "■", w.styleOf(tkWindowCloseBox))
  if w.zoomable and w.dock == dkNone and w.bounds.w >= 10:
    dc.write(w.bounds.w - 4, 0, (if w.zoomed: "[↓]" else: "[↑]"), w.borderStyle)

proc defaultButton*(g: Group): Button =
  ## First visible, enabled `isDefault` Button in `g`'s subtree, else nil.
  for c in g.children:
    if not c.visible or not c.enabled:
      continue
    if c of Button and Button(c).isDefault:
      return Button(c)
    if c of Group:
      let d = defaultButton(Group(c))
      if d != nil:
        return d

func floating(w: Window): bool =
  w.dock == dkNone # docked windows are layout-owned: not movable/resizable

proc moveTo(w: Window, x, y: int) =
  # keep the window within the parent's content area so a drag can't push it
  # off and lose it (the parent group clips its children).
  var nx = x
  var ny = y
  if w.parent != nil:
    let pc = w.parent.clientRect
    nx = clamp(nx, 0, max(pc.w - w.bounds.w, 0))
    ny = clamp(ny, 0, max(pc.h - w.bounds.h, 0))
  w.bounds.x = nx
  w.bounds.y = ny
  w.invalidate()

proc resizeTo(w: Window, width, height: int) =
  w.bounds.w = max(width, MinW)
  w.bounds.h = max(height, MinH)
  w.invalidate()

proc close*(w: Window) {.gcsafe, raises: [].} =
  ## Fire onClose if set, else the default: detach from the parent + dispose.
  if w.onClose != nil:
    w.onClose(w)
  elif w.parent != nil:
    let p = w.parent
    p.remove(w)
    dispose(w)
    p.invalidate()

proc zoom*(w: Window) {.gcsafe, raises: [].} =
  ## Toggle maximize: fill the parent content, or restore the pre-zoom bounds.
  if not w.floating:
    return
  if w.zoomed:
    w.bounds = w.savedBounds
    w.zoomed = false
  else:
    w.savedBounds = w.bounds
    if w.parent != nil:
      let pc = w.parent.clientRect
      w.bounds = rect(0, 0, pc.w, pc.h)
    w.zoomed = true
  w.invalidate()

method handleEvent*(w: Window, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evMouse:
    # coords are content-local: y == -1 is the title/top-border row,
    # (contentW, contentH) is the bottom-right border corner
    let m = ev.imouse
    let contentAbs = w.absOrigin
    let abs = point(m.mx + contentAbs.x, m.my + contentAbs.y)
    case m.action
    of maPress:
      # title-row chrome takes precedence over the move-drag region
      if m.my == -1 and w.closable and m.mx >= 0 and m.mx <= 2:
        w.close()
        return true
      if m.my == -1 and w.zoomable and w.floating and
         m.mx >= w.contentW - 3 and m.mx <= w.contentW - 1:
        w.zoom()
        return true
      if w.floating:
        if m.my == -1 and m.mx >= -1 and m.mx <= w.contentW:
          w.dragMode = dmMove
          w.dragOff = point(w.bounds.x - abs.x, w.bounds.y - abs.y)
          w.captureMouse()
        elif m.mx == w.contentW and m.my == w.contentH:
          w.dragMode = dmResize
          w.captureMouse()
    of maMove:
      case w.dragMode
      of dmMove:
        w.moveTo(abs.x + w.dragOff.x, abs.y + w.dragOff.y)
      of dmResize:
        # full-rect origin = content origin - border inset
        let fullAbs = point(contentAbs.x - 1, contentAbs.y - 1)
        w.resizeTo(abs.x - fullAbs.x + 1, abs.y - fullAbs.y + 1)
      of dmNone:
        discard
    of maRelease:
      w.dragMode = dmNone # routing clears the capture itself
    else:
      discard
    # consume: clicks on frame/background never bubble under the window
    return true
  of evKey:
    # Alt+Arrows move, Alt+Shift+Arrows resize (plan-2 D7)
    let k = ev.ikey
    if modAlt in k.keyMods and w.floating:
      var dx, dy = 0
      case k.key
      of Key.Left: dx = -1
      of Key.Right: dx = 1
      of Key.Up: dy = -1
      of Key.Down: dy = 1
      else: return false
      if modShift in k.keyMods:
        w.resizeTo(w.bounds.w + dx, w.bounds.h + dy)
      else:
        w.moveTo(w.bounds.x + dx, w.bounds.y + dy)
      return true
    if k.key == Key.Enter and k.keyMods == {}:
      # Enter the focused widget did not consume fires the default button
      # (TV bfDefault, deviation #34)
      let d = w.defaultButton()
      if d != nil:
        d.activate()
        return true
  else:
    discard
  false
