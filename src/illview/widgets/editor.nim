## Editor (deliberately scope-locked): multiline editor on
## a plain `seq[string]` model with cursor, two-axis scrolling and basic
## editing (`onChange`). NO soft-wrap, NO piece table, NO undo in v1.
## Tab is NOT consumed (focus traversal wins in v1).
##
## Selection and copy (deviation #47): Shift + navigation keys or a mouse
## drag select, Ctrl+A selects all, F5 / Ctrl+Insert copy to the system
## clipboard (Midnight Commander / Turbo Vision keys; Ctrl+C stays SIGINT).
## Editable: F6 / Shift+Delete cut; typing, Enter, Backspace, Delete and
## paste replace the selection. `readOnly` keeps navigation, selection and
## copy, and lets every editing key bubble.

import std/[unicode, strutils]
import ../core/[geometry, theme, view, drawcontext, events, selection, clipboard]
import ../vocab

type
  Editor* = ref object of View
    lines*: seq[string]
    curLine*: int  # 0..lines.high
    curCol*: int   # rune index, 0..len(line)
    scrollX*: int  # first visible display column (wide characters take 2)
    scrollY*: int
    readOnly*: bool ## no editing: navigation, selection and copy only
    selAnchor: TextPos ## selection start; the caret is the other end
    hasSelAnchor: bool
    dragging: bool
    onChange*: proc(sender: Editor) {.gcsafe, raises: [].}

proc setText*(e: Editor, s: string) =
  ## Programmatic replace: no onChange, no re-emit.
  e.lines = s.splitLines
  e.hasSelAnchor = false
  e.curLine = clamp(e.curLine, 0, e.lines.high)
  e.curCol = clamp(e.curCol, 0, e.lines[e.curLine].runeLen)
  e.scrollX = 0
  e.scrollY = 0
  e.invalidate()

proc newEditor*(text = ""): Editor =
  result = Editor(lines: text.splitLines)
  initView(result)
  result.focusable = true
  result.hint = (prefHint(20, stretch = 1), prefHint(5, stretch = 1))
  let e = result
  e.installSignal(SetText):
    e.setText(sig.text)
  e.installFocusMe()

proc text*(e: Editor): string =
  e.lines.join("\n")

func runesToStr(rs: seq[Rune]): string =
  for r in rs:
    result.add r.toUTF8

proc lineLen(e: Editor, i: int): int =
  e.lines[i].runeLen

proc changed(e: Editor) =
  if e.onChange != nil:
    e.onChange(e)
  if e.hasBrokerCtx: TextChanged.emit(e.brokerCtx, TextChanged(text: e.text))
  e.invalidate()

proc clampCursor(e: Editor) =
  e.curLine = clamp(e.curLine, 0, e.lines.high)
  e.curCol = clamp(e.curCol, 0, e.lineLen(e.curLine))

proc ensureVisible(e: Editor) =
  let w = max(e.contentW, 1)
  let h = max(e.contentH, 1)
  if e.curLine < e.scrollY: e.scrollY = e.curLine
  elif e.curLine >= e.scrollY + h: e.scrollY = e.curLine - h + 1
  # horizontal: in display columns, so wide characters keep their place
  let rs = e.lines[e.curLine].toRunes
  let cx = rs.colOf(e.curCol)
  let cw = if e.curCol < rs.len: max(rs[e.curCol].runeWidth, 1) else: 1
  if cx < e.scrollX: e.scrollX = cx
  elif cx + cw > e.scrollX + w: e.scrollX = cx + cw - w

proc moveCursor*(e: Editor, dLine, dCol: int) =
  if dLine != 0:
    e.curLine += dLine
    e.clampCursor()
  else:
    e.curCol += dCol
    if e.curCol < 0 and e.curLine > 0: # wrap to end of previous line
      dec e.curLine
      e.curCol = e.lineLen(e.curLine)
    elif e.curLine < e.lines.high and e.curCol > e.lineLen(e.curLine):
      inc e.curLine
      e.curCol = 0
    e.clampCursor()
  e.invalidate()

# --- selection (deviation #47) -----------------------------------------------

proc caret(e: Editor): TextPos =
  textPos(e.curLine, e.curCol)

proc selRange(e: Editor): (TextPos, TextPos) =
  if e.hasSelAnchor: ordered(e.selAnchor, e.caret) else: (e.caret, e.caret)

proc hasSelection*(e: Editor): bool =
  e.hasSelAnchor and e.selAnchor != e.caret

proc selectedText*(e: Editor): string =
  let (lo, hi) = e.selRange
  e.lines.selectedText(lo, hi)

proc selectAll*(e: Editor) =
  e.selAnchor = textPos(0, 0)
  e.hasSelAnchor = true
  e.curLine = e.lines.high
  e.curCol = e.lineLen(e.curLine)
  e.invalidate()

proc clearSelection*(e: Editor) =
  e.hasSelAnchor = false
  e.invalidate()

proc copySelection*(e: Editor): bool =
  ## Copy the selection to the clipboard; false when nothing is selected.
  if not e.hasSelection:
    return false
  copyToClipboard(e.selectedText)
  true

proc deleteSelection*(e: Editor): bool =
  ## Remove the selected text (caret to its start); false when none.
  if not e.hasSelection:
    e.hasSelAnchor = false
    return false
  let (lo, hi) = e.selRange
  let head = e.lines[lo.line].toRunes[0 ..< lo.col]
  let tail = e.lines[hi.line].toRunes[hi.col .. ^1]
  e.lines[lo.line] = runesToStr(head & tail)
  for _ in lo.line ..< hi.line:
    e.lines.delete(lo.line + 1)
  e.curLine = lo.line
  e.curCol = lo.col
  e.hasSelAnchor = false
  e.changed()
  true

proc cutSelection*(e: Editor): bool =
  ## Copy the selection to the clipboard and remove it; false when none.
  e.copySelection() and e.deleteSelection()

template navigate(e: Editor, extend: bool, body: untyped) =
  ## Move the caret; with `extend` (Shift held) the selection follows it.
  if extend:
    if not e.hasSelAnchor:
      e.selAnchor = e.caret
      e.hasSelAnchor = true
  else:
    e.hasSelAnchor = false
  body
  e.invalidate()

proc caretAt(e: Editor, mx, my: int) =
  e.curLine = clamp(e.scrollY + my, 0, e.lines.high)
  e.curCol = e.lines[e.curLine].toRunes.indexAtCol(e.scrollX + mx)

# --- editing -------------------------------------------------------------------

proc insertRune*(e: Editor, r: Rune) =
  var rs = e.lines[e.curLine].toRunes
  rs.insert(r, e.curCol)
  e.lines[e.curLine] = runesToStr(rs)
  inc e.curCol
  e.changed()

proc insertNewline*(e: Editor) =
  let rs = e.lines[e.curLine].toRunes
  e.lines[e.curLine] = runesToStr(rs[0 ..< e.curCol])
  e.lines.insert(runesToStr(rs[e.curCol .. ^1]), e.curLine + 1)
  inc e.curLine
  e.curCol = 0
  e.changed()

proc deleteBack*(e: Editor) =
  if e.curCol > 0:
    var rs = e.lines[e.curLine].toRunes
    rs.delete(e.curCol - 1)
    e.lines[e.curLine] = runesToStr(rs)
    dec e.curCol
    e.changed()
  elif e.curLine > 0: # join with previous line
    e.curCol = e.lineLen(e.curLine - 1)
    e.lines[e.curLine - 1] &= e.lines[e.curLine]
    e.lines.delete(e.curLine)
    dec e.curLine
    e.changed()

proc deleteForward*(e: Editor) =
  if e.curCol < e.lineLen(e.curLine):
    var rs = e.lines[e.curLine].toRunes
    rs.delete(e.curCol)
    e.lines[e.curLine] = runesToStr(rs)
    e.changed()
  elif e.curLine < e.lines.high: # join with next line
    e.lines[e.curLine] &= e.lines[e.curLine + 1]
    e.lines.delete(e.curLine + 1)
    e.changed()

proc insertText*(e: Editor, s: string) =
  ## Insert at the caret, replacing the selection.
  discard e.deleteSelection()
  for r in s.replace("\r\n", "\n").runes:
    if r == "\n".runeAt(0):
      e.insertNewline()
    elif r.int32 >= 32:
      e.insertRune(r)

method draw*(e: Editor, dc: DrawContext) {.gcsafe, raises: [].} =
  let st = e.styleOf(if e.isFocused: tkInputFocused else: tkInput) # field surface
  e.ensureVisible()
  let selSt = e.styleOf(tkTextSelection)
  let (lo, hi) = e.selRange
  dc.fill(rect(0, 0, e.contentW, e.contentH), " ", st)
  for y in 0 ..< max(e.contentH, 0):
    let idx = e.scrollY + y
    if idx > e.lines.high:
      break
    var col = 0 # display column of the next rune
    var ri = 0
    for r in e.lines[idx].runes:
      if col - e.scrollX >= e.contentW:
        break
      let cs = if selected(lo, hi, textPos(idx, ri)): selSt else: st
      dc.putCell(col - e.scrollX, y, r, cs) # left of the view: clipped
      col += r.runeWidth
      inc ri
    if idx < hi.line and selected(lo, hi, textPos(idx, ri)): # the line break
      dc.putCell(col - e.scrollX, y, " ".runeAt(0), selSt)
  if e.isFocused:
    let rs = e.lines[e.curLine].toRunes
    var ch = if e.curCol < rs.len: rs[e.curCol] else: " ".runeAt(0)
    if ch.runeWidth == 0: ch = " ".runeAt(0) # a combining mark: mark the cell
    dc.putCell(rs.colOf(e.curCol) - e.scrollX, e.curLine - e.scrollY, ch,
               e.styleOf(tkCursor))

method handleEvent*(e: Editor, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    let k = ev.ikey
    if modAlt in k.keyMods:
      return false # Alt-chords are window/app level (move/resize)
    if k.isTabSwitch:
      return false # Ctrl+PgUp/PgDn switch tabs (deviation #39)
    let shift = modShift in k.keyMods
    case k.key
    of Key.Up:
      e.navigate(shift): e.moveCursor(-1, 0)
    of Key.Down:
      e.navigate(shift): e.moveCursor(1, 0)
    of Key.Left:
      e.navigate(shift): e.moveCursor(0, -1)
    of Key.Right:
      e.navigate(shift): e.moveCursor(0, 1)
    of Key.Home:
      e.navigate(shift): e.curCol = 0
    of Key.End:
      e.navigate(shift): e.curCol = e.lineLen(e.curLine)
    of Key.PageUp:
      e.navigate(shift): e.moveCursor(-max(e.contentH, 1), 0)
    of Key.PageDown:
      e.navigate(shift): e.moveCursor(max(e.contentH, 1), 0)
    of Key.CtrlA: e.selectAll()
    of Key.F5: return e.copySelection()
    of Key.Insert:
      if modCtrl notin k.keyMods: return false
      return e.copySelection()
    else:
      if e.readOnly:
        return false # editing keys bubble
      case k.key
      of Key.F6:
        return e.cutSelection()
      of Key.Enter:
        discard e.deleteSelection()
        e.insertNewline()
      of Key.Backspace:
        if not e.deleteSelection(): e.deleteBack()
      of Key.Delete:
        if shift: return e.cutSelection()
        if not e.deleteSelection(): e.deleteForward()
      else:
        if k.rune.int32 >= 32 and k.keyMods * {modCtrl, modAlt} == {}:
          discard e.deleteSelection()
          e.insertRune(k.rune)
        else:
          return false
    return true
  of evPaste:
    if e.readOnly:
      return false
    e.insertText(ev.pasteText)
    return true
  of evMouse:
    let m = ev.imouse
    case m.action
    of maPress:
      if modShift in m.mouseMods: # Shift+click extends from the caret
        if not e.hasSelAnchor:
          e.selAnchor = e.caret
          e.hasSelAnchor = true
        e.caretAt(m.mx, m.my)
      else:
        e.caretAt(m.mx, m.my)
        e.selAnchor = e.caret
        e.hasSelAnchor = true
      e.dragging = true
      e.captureMouse() # drag selects, also past the edges (scrolls)
      e.invalidate()
      return true
    of maMove:
      if e.dragging:
        e.caretAt(m.mx, m.my)
        e.invalidate()
        return true
    of maRelease:
      if e.dragging:
        e.dragging = false
        e.releaseMouse()
        return true
    else:
      discard
  of evFocusGained, evFocusLost:
    e.invalidate()
  else:
    discard
  false
