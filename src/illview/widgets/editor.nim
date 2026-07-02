## Editor (Phase 4.6, LAST, scope-locked by plan §0.8): multiline editor on
## a plain `seq[string]` model with cursor, two-axis scrolling and basic
## editing (`onChange`). NO soft-wrap, NO piece table, NO undo in v1.
## Tab is NOT consumed (focus traversal wins in v1).

import std/[unicode, strutils]
import ../core/[geometry, theme, view, drawcontext, events]

type
  Editor* = ref object of View
    lines*: seq[string]
    curLine*: int  # 0..lines.high
    curCol*: int   # rune index, 0..len(line)
    scrollX*, scrollY*: int
    onChange*: proc(sender: Editor) {.gcsafe, raises: [].}

proc newEditor*(text = ""): Editor =
  result = Editor(lines: text.splitLines)
  initView(result)
  result.focusable = true
  result.hint = (prefHint(20, stretch = 1), prefHint(5, stretch = 1))

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
  e.invalidate()

proc clampCursor(e: Editor) =
  e.curLine = clamp(e.curLine, 0, e.lines.high)
  e.curCol = clamp(e.curCol, 0, e.lineLen(e.curLine))

proc ensureVisible(e: Editor) =
  let w = max(e.contentW, 1)
  let h = max(e.contentH, 1)
  if e.curLine < e.scrollY: e.scrollY = e.curLine
  elif e.curLine >= e.scrollY + h: e.scrollY = e.curLine - h + 1
  if e.curCol < e.scrollX: e.scrollX = e.curCol
  elif e.curCol >= e.scrollX + w: e.scrollX = e.curCol - w + 1

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
  for r in s.replace("\r\n", "\n").runes:
    if r == "\n".runeAt(0):
      e.insertNewline()
    elif r.int32 >= 32:
      e.insertRune(r)

method draw*(e: Editor, dc: DrawContext) {.gcsafe, raises: [].} =
  let st = e.styleOf(tkText)
  e.ensureVisible()
  for y in 0 ..< max(e.contentH, 0):
    let idx = e.scrollY + y
    if idx > e.lines.high:
      break
    var x = 0
    var ri = 0
    for r in e.lines[idx].runes:
      if ri >= e.scrollX:
        if x >= e.contentW:
          break
        dc.putCell(x, y, r, st)
        inc x
      inc ri
  if e.isFocused:
    let rs = e.lines[e.curLine].toRunes
    let ch = if e.curCol < rs.len: rs[e.curCol] else: " ".runeAt(0)
    dc.putCell(e.curCol - e.scrollX, e.curLine - e.scrollY, ch,
               e.styleOf(tkSelection))

method handleEvent*(e: Editor, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    let k = ev.ikey
    if modAlt in k.keyMods:
      return false # Alt-chords are window/app level (move/resize)
    case k.key
    of Key.Up: e.moveCursor(-1, 0)
    of Key.Down: e.moveCursor(1, 0)
    of Key.Left: e.moveCursor(0, -1)
    of Key.Right: e.moveCursor(0, 1)
    of Key.Home:
      e.curCol = 0
      e.invalidate()
    of Key.End:
      e.curCol = e.lineLen(e.curLine)
      e.invalidate()
    of Key.PageUp: e.moveCursor(-max(e.contentH, 1), 0)
    of Key.PageDown: e.moveCursor(max(e.contentH, 1), 0)
    of Key.Enter: e.insertNewline()
    of Key.Backspace: e.deleteBack()
    of Key.Delete: e.deleteForward()
    else:
      if k.rune.int32 >= 32 and k.keyMods * {modCtrl, modAlt} == {}:
        e.insertRune(k.rune)
      else:
        return false
    return true
  of evPaste:
    e.insertText(ev.pasteText)
    return true
  of evMouse:
    if ev.imouse.action == maPress:
      e.curLine = clamp(e.scrollY + ev.imouse.my, 0, e.lines.high)
      e.curCol = clamp(e.scrollX + ev.imouse.mx, 0, e.lineLen(e.curLine))
      e.invalidate()
      return true
  of evFocusGained, evFocusLost:
    e.invalidate()
  else:
    discard
  false
