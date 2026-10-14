## Table: header row + row selection + vertical scrolling. Column
## widths are size hints distributed by the layout engine's distribute().
## NOT in v1 (scope-locked): sorting, cell editing.
##
## Long cells (deviation #49): the columns keep their widths and each cell
## scrolls inside its own: one shared offset, `scrollX`, clamped per cell to
## that cell's overflow, so short cells stay put. `◀` / `▶` in a cell's edge
## mark text cut on that side; a one-row bar at the bottom shows the offset
## while any cell is cut. Left/Right or Shift+Left/Right by `hScrollStep`,
## Shift+Home/End, Shift+wheel or the horizontal wheel.

import ../core/[geometry, theme, view, drawcontext, events, bus]
import ../layout/layout
import ../vocab
import ./hbar

type
  TableColumn* = object
    title*: string
    hint*: SizeHint

  Table* = ref object of View
    columns*: seq[TableColumn]
    rows*: seq[seq[string]]
    selected*: int
    top*: int # first visible data row
    command*: Command
    showScrollbar*: bool # thumb indicator in the last column when overflowing
    scrollX*: int ## offset into every cut cell, in columns (deviation #49)
    hScrollStep*: int = 4
    hDragging: bool
    cellW: seq[seq[int]] ## display width of each cell (cache, rows order)
    onSelect*: proc(sender: Table) {.gcsafe, raises: [].}
    onActivate*: proc(sender: Table) {.gcsafe, raises: [].}

proc tableColumn*(title: string, hint: SizeHint): TableColumn =
  TableColumn(title: title, hint: hint)

proc recomputeHint(t: Table) =
  var w = max(t.columns.len - 1, 0) # 1-cell column spacing
  for c in t.columns:
    w += clamp(c.hint.pref, c.hint.min, c.hint.max)
  t.hint = (prefHint(w, stretch = 1), prefHint(t.rows.len + 1, stretch = 1))

proc cellWidths(t: Table): lent seq[seq[int]] =
  ## Cached per-cell display widths; rebuilt when the row count changed
  ## (setRows / addRow also drop the cache).
  if t.cellW.len != t.rows.len:
    t.cellW.setLen(0)
    for r in t.rows:
      var ws: seq[int]
      for c in r:
        ws.add c.textWidth
      t.cellW.add ws
  t.cellW

proc widthsFor(t: Table, cols: int): seq[int] =
  var hints: seq[SizeHint]
  for c in t.columns:
    hints.add c.hint
  distribute(cols, hints, spacing = 1)

proc overflow(t: Table, widths: seq[int]): int =
  ## How far the most-cut cell runs past its column.
  for r in t.cellWidths:
    for i, w in r:
      if i < widths.len:
        result = max(result, w - widths[i])

type TableLayout = object
  bars: BarLayout
  widths: seq[int]
  total: int ## bar range: visible columns + the largest overflow

proc layout(t: Table): TableLayout =
  var lay = barLayout(t.contentW, t.contentH, 1, t.rows.len, 0, t.showScrollbar)
  let ov = t.overflow(t.widthsFor(lay.cols))
  if ov > 0: # a bar row may bring the vertical bar (one column less)
    lay = barLayout(t.contentW, t.contentH, 1, t.rows.len, lay.cols + ov, t.showScrollbar)
  let widths = t.widthsFor(lay.cols)
  TableLayout(bars: lay, widths: widths, total: lay.cols + t.overflow(widths))

func hbarTop(t: Table): int = 1 # below the header

proc viewportRows(t: Table): int =
  max(t.layout.bars.rows, 1) # minus the header row (and the bar row)

proc scrollToX*(t: Table, x: int) =
  let tl = t.layout
  let nx = clamp(x, 0, hScrollMax(tl.total, tl.bars.cols))
  if nx != t.scrollX:
    t.scrollX = nx
    t.invalidate()

proc ensureVisible*(t: Table) =
  let h = t.viewportRows
  if t.selected < t.top:
    t.top = t.selected
  elif t.selected >= t.top + h:
    t.top = t.selected - h + 1
  t.top = clamp(t.top, 0, max(t.rows.len - 1, 0))

proc newTable*(columns: seq[TableColumn] = @[],
               rows: seq[seq[string]] = @[], command = cmdNone): Table =
  result = Table(columns: columns, rows: rows, command: command)
  initView(result)
  result.focusable = true
  result.recomputeHint()
  let t = result
  t.installSignal(SetSelected):
    # programmatic apply: no slot, no re-emit
    if t.rows.len > 0:
      t.selected = clamp(sig.selected, 0, t.rows.high)
      t.ensureVisible()
      t.invalidate()
  t.installFocusMe()

proc setRows*(t: Table, rows: seq[seq[string]]) =
  ## Replace the rows, keeping the selection and the viewport where they were
  ## (clamped): a live table refreshed every second must not jump to the top
  ## (deviation #30).
  t.rows = rows
  t.cellW.setLen(0)
  t.selected = clamp(t.selected, 0, max(rows.high, 0))
  t.top = clamp(t.top, 0, max(rows.len - max(t.viewportRows, 1), 0))
  t.ensureVisible()
  t.recomputeHint()
  t.invalidate()

proc addRow*(t: Table, row: seq[string]) =
  t.rows.add row
  t.cellW.setLen(0)
  t.recomputeHint()
  t.invalidate()

proc select*(t: Table, i: int) =
  let ni = clamp(i, 0, t.rows.high)
  if t.rows.len == 0 or ni == t.selected:
    return
  t.selected = ni
  t.ensureVisible()
  if t.onSelect != nil:
    t.onSelect(t)
  if t.hasBrokerCtx: SelectionChanged.emit(t.brokerCtx, SelectionChanged(selected: t.selected))
  t.invalidate()

proc activate*(t: Table) =
  if t.rows.len == 0:
    return
  if t.onActivate != nil:
    t.onActivate(t)
  t.publish(t.command)
  if t.hasBrokerCtx: Activated.emit(t.brokerCtx, Activated(selected: t.selected))

func fit(s: string, w: int): string =
  ## The part of s that fits w columns (draw clipping would bleed into the
  ## next column); wide characters count 2 (deviation #45).
  if w <= 0:
    return ""
  s.clipWidth(w)

proc drawCell(dc: DrawContext, x, y, w: int, s: string, sw, scrollX: int, st: Style) =
  ## One cell `w` wide: scrolled by `scrollX` clamped to its own overflow,
  ## with `◀` / `▶` where text is cut (deviation #49).
  if w <= 0:
    return
  if sw <= w:
    dc.write(x, y, s, st)
    return
  let off = min(scrollX, sw - w)
  dc.write(x, y, s.sliceCols(off, w), st)
  if off > 0:
    dc.write(x, y, "◀", st)
  if off + w < sw:
    dc.write(x + w - 1, y, "▶", st)

method draw*(t: Table, dc: DrawContext) {.gcsafe, raises: [].} =
  if t.columns.len == 0:
    return
  let tl = t.layout
  let lay = tl.bars
  let widths = tl.widths
  t.scrollX = clamp(t.scrollX, 0, hScrollMax(tl.total, lay.cols))
  let header = t.styleOf(tkTableHeader)
  let normal = t.styleOf(tkList)
  let sel = t.styleOf(if t.isFocused: tkSelectionFocused else: tkSelection)
  let cw = lay.cols
  let cellW = t.cellWidths
  dc.fill(rect(0, 0, t.contentW, t.contentH), " ", normal) # list surface
  dc.fill(rect(0, 0, cw, 1), " ", header)
  var x = 0
  for i, col in t.columns:
    dc.write(x, 0, fit(col.title, widths[i]), header)
    x += widths[i] + 1
  for y in 1 .. lay.rows:
    let idx = t.top + y - 1
    if idx > t.rows.high:
      break
    let st = if idx == t.selected: sel else: normal
    if idx == t.selected:
      dc.fill(rect(0, y, cw, 1), " ", st)
    x = 0
    for i, _ in t.columns:
      if i < t.rows[idx].len:
        dc.drawCell(x, y, widths[i], t.rows[idx][i], cellW[idx][i], t.scrollX, st)
      x += widths[i] + 1
  let sbSt = t.styleOf(tkScrollBar)
  if lay.vbar:
    for y, g in scrollGlyphs(lay.rows, t.rows.len, lay.rows, t.top, axV):
      dc.write(t.contentW - 1, y + 1, g, sbSt) # rows start below the header
  if lay.hbar:
    dc.drawHBar(1 + lay.rows, cw, tl.total, t.scrollX, sbSt)

method handleEvent*(t: Table, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    if modAlt in ev.ikey.keyMods:
      return false # Alt-chords are window/app level (move/resize)
    if ev.ikey.isTabSwitch:
      return false # Ctrl+PgUp/PgDn switch tabs (deviation #39)
    if t.hbarKey(ev.ikey, plainArrows = true):
      return true
    let page = t.viewportRows
    case ev.ikey.key
    of Key.Up: t.select(t.selected - 1)
    of Key.Down: t.select(t.selected + 1)
    of Key.Home: t.select(0)
    of Key.End: t.select(t.rows.high)
    of Key.PageUp: t.select(t.selected - page)
    of Key.PageDown: t.select(t.selected + page)
    of Key.Enter: t.activate()
    else:
      return false
    return true
  of evMouse:
    let tl = t.layout
    if t.hbarMouse(ev.imouse, tl.bars, tl.total):
      return true
    case ev.imouse.action
    of maWheelUp:
      t.top = max(t.top - 1, 0)
      t.invalidate()
      return true
    of maWheelDown:
      t.top = clamp(t.top + 1, 0, max(t.rows.len - t.viewportRows, 0))
      t.invalidate()
      return true
    of maPress:
      let idx = t.top + ev.imouse.my - 1 # row 0 is the header
      if ev.imouse.my >= 1 and ev.imouse.my <= tl.bars.rows and idx >= 0 and
          idx <= t.rows.high:
        if idx == t.selected:
          t.activate()
        else:
          t.select(idx)
      return true
    else:
      discard
  of evFocusGained, evFocusLost:
    t.invalidate()
  else:
    discard
  false
