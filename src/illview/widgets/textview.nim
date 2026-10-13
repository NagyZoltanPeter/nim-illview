## TextView (Phase 4.4): buffered read-only log/output widget — capped line
## buffer + viewport + scrolling. `follow` keeps the view pinned to the
## bottom while new lines arrive (until the user scrolls up).
##
## Selection (deviation #47): a mouse drag selects (the view stops following
## while text is selected), Ctrl+A selects all, F5 / Ctrl+Insert copy to
## the system clipboard.
##
## Lines wider than the view scroll horizontally (deviation #49): Left/Right
## or Shift+Left/Right by `hScrollStep`, Shift+Home/End, Shift+wheel or the
## horizontal wheel, and a one-row bar at the bottom while any line is cut.

import std/[deques, unicode]
import ../core/[geometry, theme, view, drawcontext, events, selection, clipboard,
                textwidth]
import ./hbar

type
  TextView* = ref object of View
    maxLines*: int # buffer cap; oldest lines are dropped
    lines*: Deque[string] # ring: O(1) at the cap (deviation #30); len/[] as before
    top*: int      # manual viewport start (used when follow == false)
    follow*: bool  # auto-scroll to the bottom
    showScrollbar*: bool # thumb indicator in the last column when overflowing
    lineStyle*: proc(line: string): ThemeToken {.gcsafe, raises: [].}
      ## Optional per-line token (a log level colorer); nil = tkText.
    scrollX*: int # first visible column (deviation #49)
    hScrollStep*: int = 4
    hDragging: bool
    widths: Deque[int] ## display width of each line, as `lines`
    widest: int        ## max of `widths`; -1 = recount
    selAnchor, selCaret: TextPos ## selection ends, as buffer positions
    dragging: bool

proc newTextView*(maxLines = 1000): TextView =
  result = TextView(maxLines: max(maxLines, 1), follow: true)
  initView(result)
  result.focusable = true
  result.hint = (prefHint(0, stretch = 1), prefHint(0, stretch = 1))

proc addLine*(tv: TextView, s: string) =
  tv.lines.addLast s
  if tv.widths.len == tv.lines.len - 1:
    let w = s.textWidth
    tv.widths.addLast w
    if tv.widest >= 0: tv.widest = max(tv.widest, w)
  if tv.lines.len > tv.maxLines:
    discard tv.lines.popFirst()
    if tv.widths.len > tv.lines.len and tv.widths.popFirst() >= tv.widest:
      tv.widest = -1 # the widest line may have gone
    if not tv.follow:
      tv.top = max(tv.top - 1, 0) # keep the same content in view
    for p in [addr tv.selAnchor, addr tv.selCaret]: # the selection moves up too
      p[] = if p.line > 0: textPos(p.line - 1, p.col) else: textPos(0, 0)
  tv.invalidate()

proc clear*(tv: TextView) =
  tv.lines.clear()
  tv.widths.clear()
  tv.widest = 0
  tv.scrollX = 0
  tv.selAnchor = textPos(0, 0)
  tv.selCaret = textPos(0, 0)
  tv.top = 0
  tv.follow = true
  tv.invalidate()

proc contentWidth*(tv: TextView): int =
  ## Widest line, in cells.
  if tv.widths.len != tv.lines.len: # `lines` changed directly: re-measure
    tv.widths.clear()
    for l in tv.lines:
      tv.widths.addLast l.textWidth
    tv.widest = -1
  if tv.widest < 0:
    tv.widest = 0
    for w in tv.widths:
      tv.widest = max(tv.widest, w)
  tv.widest

proc layout(tv: TextView): BarLayout =
  barLayout(tv.contentW, tv.contentH, 0, tv.lines.len, tv.contentWidth, tv.showScrollbar)

func hbarTop(tv: TextView): int = 0

proc viewRows(tv: TextView): int =
  max(tv.layout.rows, 1)

proc scrollToX*(tv: TextView, x: int) =
  let nx = clamp(x, 0, hScrollMax(tv.contentWidth, tv.layout.cols))
  if nx != tv.scrollX:
    tv.scrollX = nx
    tv.invalidate()

proc effectiveTop(tv: TextView): int =
  if tv.follow:
    max(tv.lines.len - tv.viewRows, 0)
  else:
    tv.top

proc scrollBy*(tv: TextView, delta: int) =
  let maxTop = max(tv.lines.len - tv.viewRows, 0)
  tv.top = clamp(tv.effectiveTop + delta, 0, maxTop)
  tv.follow = tv.top >= maxTop
  tv.invalidate()

# --- selection (deviation #47) -----------------------------------------------

proc hasSelection*(tv: TextView): bool =
  tv.selAnchor != tv.selCaret

proc selectedText*(tv: TextView): string =
  let (lo, hi) = ordered(tv.selAnchor, tv.selCaret)
  tv.lines.selectedText(lo, hi)

proc selectAll*(tv: TextView) =
  if tv.lines.len == 0:
    return
  tv.selAnchor = textPos(0, 0)
  tv.selCaret = textPos(tv.lines.len - 1, tv.lines[tv.lines.len - 1].runeLen)
  tv.invalidate()

proc clearSelection*(tv: TextView) =
  tv.selAnchor = tv.selCaret
  tv.invalidate()

proc copySelection*(tv: TextView): bool =
  ## Copy the selection to the clipboard; false when nothing is selected.
  if not tv.hasSelection:
    return false
  copyToClipboard(tv.selectedText)
  true

proc posAt(tv: TextView, mx, my: int): TextPos =
  if tv.lines.len == 0:
    return textPos(0, 0)
  let line = clamp(tv.effectiveTop + my, 0, tv.lines.len - 1)
  textPos(line, tv.lines[line].toRunes.indexAtCol(mx + tv.scrollX))

method draw*(tv: TextView, dc: DrawContext) {.gcsafe, raises: [].} =
  let st = tv.styleOf(tkList) # read-only data pane: list surface (deviation #35)
  let cw = tv.contentWidth
  let lay = tv.layout
  tv.scrollX = clamp(tv.scrollX, 0, hScrollMax(cw, lay.cols))
  let start = tv.effectiveTop
  let selSt = tv.styleOf(tkTextSelection)
  let (lo, hi) = ordered(tv.selAnchor, tv.selCaret)
  dc.fill(rect(0, 0, tv.contentW, tv.contentH), " ", st)
  let body = dc.sub(rect(0, 0, lay.cols, lay.rows)) # text clips at the bars
  let x0 = -tv.scrollX
  for y in 0 ..< lay.rows:
    let idx = start + y
    if idx >= tv.lines.len:
      break
    let line = tv.lines[idx]
    let lst = if tv.lineStyle != nil: tv.styleOf(tv.lineStyle(line)) else: st
    if idx < lo.line or idx > hi.line or not tv.hasSelection:
      body.write(x0, y, line, lst)
    else: # cell by cell, the selected part in the selection style
      var col = x0
      var ri = 0
      for r in line.runes:
        if col >= lay.cols:
          break
        body.putCell(col, y, r, if selected(lo, hi, textPos(idx, ri)): selSt else: lst)
        col += r.runeWidth
        inc ri
      if idx < hi.line: # the line break
        body.putCell(col, y, " ".runeAt(0), selSt)
  let sbSt = tv.styleOf(tkScrollBar)
  if lay.vbar:
    for y, g in scrollGlyphs(lay.rows, tv.lines.len, lay.rows, start, axV):
      dc.write(tv.contentW - 1, y, g, sbSt)
  if lay.hbar:
    dc.drawHBar(lay.rows, lay.cols, cw, tv.scrollX, sbSt)

method handleEvent*(tv: TextView, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    if modAlt in ev.ikey.keyMods:
      return false # Alt-chords are window/app level (move/resize)
    if ev.ikey.isTabSwitch:
      return false # Ctrl+PgUp/PgDn switch tabs (deviation #39)
    if tv.hbarKey(ev.ikey, plainArrows = true):
      return true
    case ev.ikey.key
    of Key.Up: tv.scrollBy(-1)
    of Key.Down: tv.scrollBy(1)
    of Key.PageUp: tv.scrollBy(-tv.viewRows)
    of Key.PageDown: tv.scrollBy(tv.viewRows)
    of Key.Home:
      tv.top = 0
      tv.follow = tv.lines.len <= tv.viewRows
      tv.invalidate()
    of Key.End:
      tv.follow = true
      tv.invalidate()
    of Key.CtrlA:
      tv.selectAll()
    of Key.F5:
      return tv.copySelection()
    of Key.Insert:
      if modCtrl notin ev.ikey.keyMods: return false
      return tv.copySelection()
    else:
      return false
    return true
  of evMouse:
    let m = ev.imouse
    let lay = tv.layout
    if not tv.dragging and tv.hbarMouse(m, lay, tv.contentWidth):
      return true
    case m.action
    of maWheelUp:
      tv.scrollBy(-1)
      return true
    of maWheelDown:
      tv.scrollBy(1)
      return true
    of maPress:
      let p = tv.posAt(m.mx, min(m.my, max(lay.rows - 1, 0)))
      if modShift notin m.mouseMods: # Shift+click extends
        tv.selAnchor = p
      tv.selCaret = p
      tv.dragging = true
      tv.captureMouse()
      tv.invalidate()
      return true
    of maMove:
      if tv.dragging:
        if m.my < 0: tv.scrollBy(-1) # dragging past an edge scrolls
        elif m.my >= lay.rows: tv.scrollBy(1)
        if m.mx < 0: tv.scrollToX(tv.scrollX - 1)
        elif m.mx >= lay.cols: tv.scrollToX(tv.scrollX + 1)
        tv.selCaret = tv.posAt(clamp(m.mx, 0, max(lay.cols - 1, 0)),
                               clamp(m.my, 0, max(lay.rows - 1, 0)))
        if tv.hasSelection and tv.follow: # hold the text still while selecting
          tv.top = tv.effectiveTop
          tv.follow = false
        tv.invalidate()
        return true
    of maRelease:
      if tv.dragging:
        tv.dragging = false
        tv.releaseMouse()
        return true
    of maWheelLeft, maWheelRight:
      discard # taken by hbarMouse
  else:
    discard
  false
