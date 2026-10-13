## Horizontal scrolling shared by ListView, Table, TreeView and TextView
## (deviation #49): which bars a view shows, the one-row horizontal bar at
## its bottom, and the bar's mouse behaviour (as ScrollBar: arrow = one step,
## rail = one page, thumb = drag).

import ../core/[geometry, theme, drawcontext, events, view]

type
  BarLayout* = object
    vbar*, hbar*: bool ## vertical bar (last column), horizontal bar (last row)
    rows*: int ## item rows visible (header and horizontal bar excluded)
    cols*: int ## content columns visible (vertical bar excluded)

func barLayout*(w, h, header, items, contentWidth: int, vbarEnabled: bool): BarLayout =
  ## Settle both bars: each takes room the other's decision depends on. The
  ## horizontal bar needs at least one item row left above it.
  var hb = false
  for _ in 0 .. 2:
    let rows = max(h - header - ord(hb), 0)
    let vb = vbarEnabled and items > rows
    let cols = max(w - ord(vb), 0)
    hb = contentWidth > cols and h - header >= 2
  let rows = max(h - header - ord(hb), 0)
  let vb = vbarEnabled and items > rows
  BarLayout(vbar: vb, hbar: hb, rows: rows, cols: max(w - ord(vb), 0))

func hScrollMax*(contentWidth, cols: int): int =
  max(contentWidth - cols, 0)

proc drawHBar*(dc: DrawContext, y, cols, contentWidth, pos: int, st: Style) =
  ## The bar along row `y`, `cols` cells wide.
  for i, g in scrollGlyphs(cols, contentWidth, cols, pos, axH):
    dc.write(i, y, g, st)

func hbarPress*(cell, cols, contentWidth, pos, step: int):
    tuple[pos: int, drag: bool] =
  ## A press on bar cell `cell`: the new position, or `drag` for the thumb.
  let a = arrowCells(cols)
  let th = a + thumbCell(cols, contentWidth, cols, pos)
  let mx = hScrollMax(contentWidth, cols)
  if a == 1 and cell == 0: (clamp(pos - step, 0, mx), false)
  elif a == 1 and cell == cols - 1: (clamp(pos + step, 0, mx), false)
  elif cell < th: (clamp(pos - cols, 0, mx), false)
  elif cell > th: (clamp(pos + cols, 0, mx), false)
  else: (pos, true)

func hbarDrag*(cell, cols, contentWidth: int): int =
  ## The position for a thumb dragged to bar cell `cell`.
  let a = arrowCells(cols)
  let span = max(cols - 2 * a - 1, 1)
  hScrollMax(contentWidth, cols) * clamp(cell - a, 0, span) div span

# --- shared input handling: the widget provides `scrollX`, `hScrollStep`,
# `hDragging` and `scrollToX` (generic, resolved per widget type) -----------

proc hbarKey*[T](v: T, k: InputEvent, plainArrows: bool): bool =
  ## Shift+Left/Right (plain Left/Right too when `plainArrows`) scroll by
  ## `hScrollStep`; Shift+Home/End go to either edge.
  let shift = modShift in k.keyMods
  case k.key
  of Key.Left, Key.Right:
    if not (plainArrows or shift):
      return false
    v.scrollToX(v.scrollX + (if k.key == Key.Left: -v.hScrollStep else: v.hScrollStep))
  of Key.Home:
    if not shift: return false
    v.scrollToX(0)
  of Key.End:
    if not shift: return false
    v.scrollToX(high(int) div 2) # clamped to the far edge
  else:
    return false
  true

proc hbarMouse*[T](v: T, m: InputEvent, lay: BarLayout, contentWidth: int): bool =
  ## Horizontal wheel, Shift+wheel, and presses / drags on the bar row.
  let step = v.hScrollStep
  case m.action
  of maWheelLeft:
    v.scrollToX(v.scrollX - step)
  of maWheelRight:
    v.scrollToX(v.scrollX + step)
  of maWheelUp, maWheelDown:
    if modShift notin m.mouseMods:
      return false
    v.scrollToX(v.scrollX + (if m.action == maWheelUp: -step else: step))
  of maPress:
    if not (lay.hbar and m.my == lay.rows + v.hbarTop and m.mx >= 0 and m.mx < lay.cols):
      return false
    let (p, drag) = hbarPress(m.mx, lay.cols, contentWidth, v.scrollX, step)
    v.scrollToX(p)
    if drag:
      v.hDragging = true
      v.captureMouse()
  of maMove:
    if not v.hDragging:
      return false
    v.scrollToX(hbarDrag(m.mx, lay.cols, contentWidth))
  of maRelease:
    if not v.hDragging:
      return false
    v.hDragging = false
    v.releaseMouse()
  true
