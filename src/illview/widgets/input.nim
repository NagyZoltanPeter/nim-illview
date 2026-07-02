## Input (Phase 4.3): single-line editor with cursor, horizontal scroll on
## overflow, and the full slot set: onChange (text edited), onSubmit
## (Enter), onFocus / onBlur (focus in / out) — deliberately NOT collapsed
## into one event (plan Phase 4 note).

import std/unicode
import ../core/[geometry, theme, view, drawcontext, events, bus]

type
  Input* = ref object of View
    runes: seq[Rune]
    cursor*: int  # rune index, 0..runes.len
    scrollX*: int # first visible rune
    command*: Command
    onChange*: proc(sender: Input) {.gcsafe, raises: [].}
    onSubmit*: proc(sender: Input) {.gcsafe, raises: [].}
    onFocus*: proc(sender: Input) {.gcsafe, raises: [].}
    onBlur*: proc(sender: Input) {.gcsafe, raises: [].}

proc text*(i: Input): string =
  for r in i.runes:
    result.add r.toUTF8

proc setText*(i: Input, s: string) =
  i.runes = s.toRunes
  i.cursor = i.runes.len
  i.scrollX = 0
  i.invalidate()

proc newInput*(text = "", command = cmdNone): Input =
  result = Input(command: command)
  initView(result)
  result.focusable = true
  result.hint = (prefHint(16, stretch = 1), fixedHint(1))
  result.runes = text.toRunes
  result.cursor = result.runes.len

proc changed(i: Input) =
  if i.onChange != nil:
    i.onChange(i)
  i.invalidate()

proc ensureCursorVisible(i: Input) =
  let w = max(i.bounds.w, 1)
  if i.cursor < i.scrollX:
    i.scrollX = i.cursor
  elif i.cursor >= i.scrollX + w:
    i.scrollX = i.cursor - w + 1

proc insertText*(i: Input, s: string) =
  var at = i.cursor
  for r in s.runes:
    if r.int32 >= 32: # strip control chars (incl. newlines from paste)
      i.runes.insert(r, at)
      inc at
  i.cursor = at
  i.changed()

method draw*(i: Input, dc: DrawContext) {.gcsafe, raises: [].} =
  let focused = i.isFocused
  let st = i.styleOf(if focused: tkInputFocused else: tkInput)
  i.ensureCursorVisible()
  dc.fill(rect(0, 0, i.bounds.w, 1), " ", st)
  var x = 0
  for idx in i.scrollX ..< i.runes.len:
    if x >= i.bounds.w:
      break
    dc.putCell(x, 0, i.runes[idx], st)
    inc x
  if focused:
    let cx = i.cursor - i.scrollX
    let ch = if i.cursor < i.runes.len: i.runes[i.cursor] else: " ".runeAt(0)
    dc.putCell(cx, 0, ch, i.styleOf(tkSelection)) # cell-style cursor

method handleEvent*(i: Input, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    let k = ev.ikey
    case k.key
    of Key.Left:
      i.cursor = max(i.cursor - 1, 0)
      i.invalidate()
    of Key.Right:
      i.cursor = min(i.cursor + 1, i.runes.len)
      i.invalidate()
    of Key.Home:
      i.cursor = 0
      i.invalidate()
    of Key.End:
      i.cursor = i.runes.len
      i.invalidate()
    of Key.Backspace:
      if i.cursor > 0:
        i.runes.delete(i.cursor - 1)
        dec i.cursor
        i.changed()
    of Key.Delete:
      if i.cursor < i.runes.len:
        i.runes.delete(i.cursor)
        i.changed()
    of Key.Enter:
      if i.onSubmit != nil:
        i.onSubmit(i)
      i.publish(i.command)
    else:
      # printable rune with no Ctrl/Alt chord -> insert
      if k.rune.int32 >= 32 and k.keyMods * {modCtrl, modAlt} == {}:
        i.runes.insert(k.rune, i.cursor)
        inc i.cursor
        i.changed()
      else:
        return false
    return true
  of evPaste:
    i.insertText(ev.pasteText)
    return true
  of evMouse:
    if ev.imouse.action == maPress:
      i.cursor = clamp(i.scrollX + ev.imouse.mx, 0, i.runes.len)
      i.invalidate()
      return true
  of evFocusGained:
    if i.onFocus != nil:
      i.onFocus(i)
    i.invalidate()
  of evFocusLost:
    if i.onBlur != nil:
      i.onBlur(i)
    i.invalidate()
  else:
    discard
  false
