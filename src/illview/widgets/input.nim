## Input (Phase 4.3): single-line editor with cursor, horizontal scroll on
## overflow, and the full slot set: onChange (text edited), onSubmit
## (Enter), onFocus / onBlur (focus in / out) — deliberately NOT collapsed
## into one event (plan Phase 4 note).

import std/[unicode, strutils]
import results
import ../core/[geometry, theme, view, drawcontext, events, bus]
import ../vocab

type
  KeyFilter* = proc(r: Rune, text: string): bool {.gcsafe, raises: [].}
    ## Per-key validator (plan-4 D18): given a candidate rune and the current
    ## text, return true to accept it. Rejected runes are swallowed silently.

  Input* = ref object of View
    runes: seq[Rune]
    cursor*: int  # rune index, 0..runes.len
    scrollX*: int # first visible rune
    command*: Command
    filter*: KeyFilter # nil = accept everything
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
  let i = result
  i.installSignal(SetText):
    i.setText(sig.text) # programmatic apply: no onChange, no re-emit (D8)
  i.installFocusMe()

proc changed(i: Input) =
  if i.onChange != nil:
    i.onChange(i)
  TextChanged.emit(i.brokerCtx, TextChanged(text: i.text))
  i.invalidate()

proc ensureCursorVisible(i: Input) =
  let w = max(i.contentW, 1)
  if i.cursor < i.scrollX:
    i.scrollX = i.cursor
  elif i.cursor >= i.scrollX + w:
    i.scrollX = i.cursor - w + 1

proc accepts(i: Input, r: Rune): bool =
  i.filter == nil or i.filter(r, i.text)

proc insertText*(i: Input, s: string) =
  var at = i.cursor
  var any = false
  for r in s.runes:
    if r.int32 >= 32 and i.accepts(r): # control chars + rejected runes dropped
      i.runes.insert(r, at)
      inc at
      any = true
  i.cursor = at
  if any:
    i.changed()

method draw*(i: Input, dc: DrawContext) {.gcsafe, raises: [].} =
  let focused = i.isFocused
  let st = i.styleOf(if focused: tkInputFocused else: tkInput)
  i.ensureCursorVisible()
  dc.fill(rect(0, 0, i.contentW, 1), " ", st)
  var x = 0
  for idx in i.scrollX ..< i.runes.len:
    if x >= i.contentW:
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
    if modAlt in k.keyMods:
      return false # Alt-chords are window/app level (move/resize)
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
      Submitted.emit(i.brokerCtx, Submitted(text: i.text))
    else:
      # printable rune with no Ctrl/Alt chord -> insert (if the filter allows)
      if k.rune.int32 >= 32 and k.keyMods * {modCtrl, modAlt} == {}:
        if i.accepts(k.rune):
          i.runes.insert(k.rune, i.cursor)
          inc i.cursor
          i.changed()
        # rejected: consume the key, no change (silent, per D18)
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

# --- shipped validators (plan-4 D18) -----------------------------------------

proc digitsOnly*(): KeyFilter =
  ## Accept only ASCII digits.
  (proc(r: Rune, text: string): bool {.gcsafe, raises: [].} =
    r.int32 >= ord('0') and r.int32 <= ord('9'))

proc charSet*(allowed: string): KeyFilter =
  ## Accept only runes present in `allowed`.
  let set = allowed.toRunes
  (proc(r: Rune, text: string): bool {.gcsafe, raises: [].} =
    {.cast(gcsafe).}: r in set)

proc maxLen*(n: int): KeyFilter =
  ## Accept only while the text is shorter than `n` runes.
  (proc(r: Rune, text: string): bool {.gcsafe, raises: [].} =
    text.runeLen < n)

proc allOf*(filters: varargs[KeyFilter]): KeyFilter =
  ## Compose: accept only when every filter accepts (e.g. digitsOnly + maxLen).
  let fs = @filters
  (proc(r: Rune, text: string): bool {.gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      for f in fs:
        if not f(r, text): return false
      true)

proc intRange*(lo, hi: int): proc(value: string): Result[string, string]
    {.gcsafe, raises: [].} =
  ## A bindRequest provider (value-level): vetoes out-of-range integers, lets
  ## an empty in-progress value through. Pair with Name.replaceProvider.
  (proc(value: string): Result[string, string] {.gcsafe, raises: [].} =
    if value.len == 0:
      return ok(value)
    try:
      let n = parseInt(value)
      if n < lo or n > hi: err("out of range [" & $lo & ".." & $hi & "]")
      else: ok(value)
    except ValueError:
      err("not an integer"))
