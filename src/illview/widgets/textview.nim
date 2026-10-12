## TextView (Phase 4.4): buffered read-only log/output widget — capped line
## buffer + viewport + scrolling. `follow` keeps the view pinned to the
## bottom while new lines arrive (until the user scrolls up).
##
## Selection (deviation #47): a mouse drag selects (the view stops following
## while text is selected), Ctrl+A selects all, F5 / Ctrl+Insert copy to
## the system clipboard.

import std/[deques, unicode]
import ../core/[geometry, theme, view, drawcontext, events, selection, clipboard,
                textwidth]

type
  TextView* = ref object of View
    maxLines*: int # buffer cap; oldest lines are dropped
    lines*: Deque[string] # ring: O(1) at the cap (deviation #30); len/[] as before
    top*: int      # manual viewport start (used when follow == false)
    follow*: bool  # auto-scroll to the bottom
    showScrollbar*: bool # thumb indicator in the last column when overflowing
    lineStyle*: proc(line: string): ThemeToken {.gcsafe, raises: [].}
      ## Optional per-line token (a log level colorer); nil = tkText.
    selAnchor, selCaret: TextPos ## selection ends, as buffer positions
    dragging: bool

proc newTextView*(maxLines = 1000): TextView =
  result = TextView(maxLines: max(maxLines, 1), follow: true)
  initView(result)
  result.focusable = true
  result.hint = (prefHint(0, stretch = 1), prefHint(0, stretch = 1))

proc addLine*(tv: TextView, s: string) =
  tv.lines.addLast s
  if tv.lines.len > tv.maxLines:
    discard tv.lines.popFirst()
    if not tv.follow:
      tv.top = max(tv.top - 1, 0) # keep the same content in view
    for p in [addr tv.selAnchor, addr tv.selCaret]: # the selection moves up too
      p[] = if p.line > 0: textPos(p.line - 1, p.col) else: textPos(0, 0)
  tv.invalidate()

proc clear*(tv: TextView) =
  tv.lines.clear()
  tv.selAnchor = textPos(0, 0)
  tv.selCaret = textPos(0, 0)
  tv.top = 0
  tv.follow = true
  tv.invalidate()

func effectiveTop(tv: TextView): int =
  if tv.follow:
    max(tv.lines.len - max(tv.contentH, 1), 0)
  else:
    tv.top

proc scrollBy*(tv: TextView, delta: int) =
  let maxTop = max(tv.lines.len - max(tv.contentH, 1), 0)
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
  textPos(line, tv.lines[line].toRunes.indexAtCol(mx))

method draw*(tv: TextView, dc: DrawContext) {.gcsafe, raises: [].} =
  let st = tv.styleOf(tkList) # read-only data pane: list surface (deviation #35)
  let start = tv.effectiveTop
  let selSt = tv.styleOf(tkTextSelection)
  let (lo, hi) = ordered(tv.selAnchor, tv.selCaret)
  dc.fill(rect(0, 0, tv.contentW, tv.contentH), " ", st)
  for y in 0 ..< max(tv.contentH, 0):
    let idx = start + y
    if idx >= tv.lines.len:
      break
    let line = tv.lines[idx]
    let lst = if tv.lineStyle != nil: tv.styleOf(tv.lineStyle(line)) else: st
    if idx < lo.line or idx > hi.line or not tv.hasSelection:
      dc.write(0, y, line, lst)
    else: # cell by cell, the selected part in the selection style
      var col = 0
      var ri = 0
      for r in line.runes:
        if col >= tv.contentW:
          break
        dc.putCell(col, y, r, if selected(lo, hi, textPos(idx, ri)): selSt else: lst)
        col += r.runeWidth
        inc ri
      if idx < hi.line: # the line break
        dc.putCell(col, y, " ".runeAt(0), selSt)
  if tv.showScrollbar and tv.lines.len > tv.contentH:
    let sbSt = tv.styleOf(tkScrollBar)
    for y, g in scrollGlyphs(tv.contentH, tv.lines.len, tv.contentH, start, axV):
      dc.write(tv.contentW - 1, y, g, sbSt)

method handleEvent*(tv: TextView, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    if modAlt in ev.ikey.keyMods:
      return false # Alt-chords are window/app level (move/resize)
    if ev.ikey.isTabSwitch:
      return false # Ctrl+PgUp/PgDn switch tabs (deviation #39)
    case ev.ikey.key
    of Key.Up: tv.scrollBy(-1)
    of Key.Down: tv.scrollBy(1)
    of Key.PageUp: tv.scrollBy(-max(tv.contentH, 1))
    of Key.PageDown: tv.scrollBy(max(tv.contentH, 1))
    of Key.Home:
      tv.top = 0
      tv.follow = tv.lines.len <= tv.contentH
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
    case m.action
    of maWheelUp:
      tv.scrollBy(-1)
      return true
    of maWheelDown:
      tv.scrollBy(1)
      return true
    of maPress:
      let p = tv.posAt(m.mx, m.my)
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
        elif m.my >= tv.contentH: tv.scrollBy(1)
        tv.selCaret = tv.posAt(m.mx, clamp(m.my, 0, max(tv.contentH - 1, 0)))
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
  else:
    discard
  false
