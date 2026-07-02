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

const
  MinW = 8
  MinH = 3

type
  DragMode = enum
    dmNone, dmMove, dmResize

  Window* = ref object of Group
    dragMode: DragMode
    dragOff: Point # window origin relative to the grab point (move)

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

method drawOverlay*(w: Window, dc: DrawContext) {.gcsafe, raises: [].} =
  ## Resize handle on the frame corner (dc spans the FULL rect incl. border).
  if w.isActive and w.dock == dkNone and w.bounds.w >= 2 and w.bounds.h >= 2:
    dc.putCell(w.bounds.w - 1, w.bounds.h - 1, "◢".runeAt(0), w.borderStyle)

func floating(w: Window): bool =
  w.dock == dkNone # docked windows are layout-owned: not movable/resizable

proc moveTo(w: Window, x, y: int) =
  w.bounds.x = x
  w.bounds.y = y
  w.invalidate()

proc resizeTo(w: Window, width, height: int) =
  w.bounds.w = max(width, MinW)
  w.bounds.h = max(height, MinH)
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
  else:
    discard
  false
