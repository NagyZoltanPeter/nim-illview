## Input: single-line editor with cursor, horizontal scroll on
## overflow, and the full slot set: onChange (text edited), onSubmit
## (Enter), onFocus / onBlur (focus in / out) — deliberately NOT collapsed
## into one event.
##
## Selection and copy as in Editor (deviation #47): Shift+Left/Right/Home/End
## or a mouse drag select, Ctrl+A selects all, F5 / Ctrl+Insert copy,
## F6 / Shift+Delete cut; typing and paste replace the selection.
## `readOnly` keeps selection and copy only (Enter, Down and editing keys
## bubble). Ctrl+C stays SIGINT.

import std/[unicode, strutils]
import results
import ../core/[geometry, theme, view, drawcontext, events, bus, clipboard]
import ../vocab

type
  KeyFilter* = proc(r: Rune, text: string): bool {.gcsafe, raises: [].}
    ## Per-key validator: given a candidate rune and the current
    ## text, return true to accept it. Rejected runes are swallowed silently.

  Input* = ref object of View
    runes: seq[Rune]
    cursor*: int  # rune index, 0..runes.len
    scrollX*: int # first visible display column (wide characters take 2)
    command*: Command
    filter*: KeyFilter # nil = accept everything
    history*: seq[string] # most-recent-first; Down opens a picker
    historyMax*: int      # cap; 0 = unbounded
    readOnly*: bool ## no editing: selection and copy only
    selAnchor: int  ## selection start (rune index); the cursor is the other end
    hasSelAnchor: bool
    dragging: bool
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
  i.hasSelAnchor = false
  i.invalidate()

proc newInput*(text = "", command = cmdNone): Input =
  result = Input(command: command, historyMax: 50)
  initView(result)
  result.focusable = true
  result.hint = (prefHint(16, stretch = 1), fixedHint(1))
  result.runes = text.toRunes
  result.cursor = result.runes.len
  let i = result
  i.installSignal(SetText):
    i.setText(sig.text) # programmatic apply: no onChange, no re-emit
  i.installFocusMe()

proc changed(i: Input) =
  if i.onChange != nil:
    i.onChange(i)
  if i.hasBrokerCtx: TextChanged.emit(i.brokerCtx, TextChanged(text: i.text))
  i.invalidate()

proc ensureCursorVisible(i: Input) =
  let w = max(i.contentW, 1)
  let cx = i.runes.colOf(i.cursor)
  let cw = if i.cursor < i.runes.len: max(i.runes[i.cursor].runeWidth, 1) else: 1
  if cx < i.scrollX:
    i.scrollX = cx
  elif cx + cw > i.scrollX + w:
    i.scrollX = cx + cw - w

proc accepts(i: Input, r: Rune): bool =
  i.filter == nil or i.filter(r, i.text)

# --- selection (deviation #47) -----------------------------------------------

proc selRange(i: Input): (int, int) =
  if not i.hasSelAnchor: (i.cursor, i.cursor)
  else: (min(i.selAnchor, i.cursor), max(i.selAnchor, i.cursor))

proc hasSelection*(i: Input): bool =
  i.hasSelAnchor and i.selAnchor != i.cursor

proc selectedText*(i: Input): string =
  let (a, b) = i.selRange
  for r in i.runes[a ..< b]:
    result.add r.toUTF8

proc selectAll*(i: Input) =
  i.selAnchor = 0
  i.hasSelAnchor = true
  i.cursor = i.runes.len
  i.invalidate()

proc clearSelection*(i: Input) =
  i.hasSelAnchor = false
  i.invalidate()

proc copySelection*(i: Input): bool =
  ## Copy the selection to the clipboard; false when nothing is selected.
  if not i.hasSelection:
    return false
  copyToClipboard(i.selectedText)
  true

proc deleteSelection*(i: Input): bool =
  ## Remove the selected text (cursor to its start); false when none.
  if not i.hasSelection:
    i.hasSelAnchor = false
    return false
  let (a, b) = i.selRange
  for _ in a ..< b:
    i.runes.delete(a)
  i.cursor = a
  i.hasSelAnchor = false
  i.changed()
  true

proc cutSelection*(i: Input): bool =
  ## Copy the selection to the clipboard and remove it; false when none.
  i.copySelection() and i.deleteSelection()

template navigate(i: Input, extend: bool, body: untyped) =
  ## Move the cursor; with `extend` (Shift held) the selection follows it.
  if extend:
    if not i.hasSelAnchor:
      i.selAnchor = i.cursor
      i.hasSelAnchor = true
  else:
    i.hasSelAnchor = false
  body
  i.invalidate()

# --- editing -------------------------------------------------------------------

proc insertText*(i: Input, s: string) =
  ## Insert at the cursor, replacing the selection.
  discard i.deleteSelection()
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

proc addHistory*(i: Input, s: string) =
  ## Record `s` at the front (most recent), de-duplicated and capped.
  if s.len == 0:
    return
  let idx = i.history.find(s)
  if idx >= 0:
    i.history.delete(idx)
  i.history.insert(s, 0)
  if i.historyMax > 0 and i.history.len > i.historyMax:
    i.history.setLen(i.historyMax)

# --- history dropdown --------------------------------------------------------

type
  HistoryPopup = ref object of Group
    items: seq[string]
    selected: int
    onPick: proc(s: string) {.gcsafe, raises: [].}

method draw*(p: HistoryPopup, dc: DrawContext) {.gcsafe, raises: [].} =
  let st = p.styleOf(tkMenu)
  let sel = p.styleOf(tkMenuSelected)
  dc.fill(rect(0, 0, p.contentW, p.contentH), " ", st)
  dc.box(rect(0, 0, p.contentW, p.contentH), st)
  for k, it in p.items:
    let s = if k == p.selected: sel else: st
    if k == p.selected:
      dc.fill(rect(1, 1 + k, p.contentW - 2, 1), " ", s)
    dc.write(2, 1 + k, it, s)

method handleEvent*(p: HistoryPopup, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    case ev.ikey.key
    of Key.Up: p.selected = (p.selected - 1 + p.items.len) mod p.items.len; p.invalidate()
    of Key.Down: p.selected = (p.selected + 1) mod p.items.len; p.invalidate()
    of Key.Enter:
      if p.onPick != nil: p.onPick(p.items[p.selected])
      p.endModal(cmdNone)
    of Key.Escape: p.endModal(cmdNone)
    else: discard
    return true
  of evMouse:
    let m = ev.imouse
    if m.action == maPress:
      if not rect(0, 0, p.contentW, p.contentH).contains(point(m.mx, m.my)):
        p.endModal(cmdNone)
      else:
        let idx = m.my - 1
        if idx >= 0 and idx < p.items.len:
          p.selected = idx
          if p.onPick != nil: p.onPick(p.items[idx])
          p.endModal(cmdNone)
    return true
  else:
    discard
  false

proc openHistory(i: Input) =
  if i.history.len == 0:
    return
  let shown = i.history[0 ..< min(i.history.len, 8)]
  var w = 0
  for h in shown:
    w = max(w, h.textWidth)
  let o = i.absOrigin
  let popup = HistoryPopup(items: shown, selected: 0)
  initView(popup)
  popup.onPick = proc(s: string) {.gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      i.setText(s)
      i.addHistory(s) # picking bumps recency
      i.changed()
  popup.bounds = rect(o.x, o.y + 1, w + 4, shown.len + 2)
  i.runModal(popup)

method draw*(i: Input, dc: DrawContext) {.gcsafe, raises: [].} =
  let focused = i.isFocused
  let st = i.styleOf(if focused: tkInputFocused else: tkInput)
  i.ensureCursorVisible()
  let selSt = i.styleOf(tkTextSelection)
  let (a, b) = i.selRange
  dc.fill(rect(0, 0, i.contentW, 1), " ", st)
  var col = 0 # display column of the next rune
  for k, r in i.runes:
    if col - i.scrollX >= i.contentW:
      break
    let cs = if k >= a and k < b: selSt else: st
    dc.putCell(col - i.scrollX, 0, r, cs) # left of the view: clipped
    col += r.runeWidth
  if focused:
    let cx = i.runes.colOf(i.cursor) - i.scrollX
    var ch = if i.cursor < i.runes.len: i.runes[i.cursor] else: " ".runeAt(0)
    if ch.runeWidth == 0: ch = " ".runeAt(0) # a combining mark: mark the cell
    dc.putCell(cx, 0, ch, i.styleOf(tkCursor)) # cell-style cursor

method handleEvent*(i: Input, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    let k = ev.ikey
    if modAlt in k.keyMods:
      return false # Alt-chords are window/app level (move/resize)
    let shift = modShift in k.keyMods
    case k.key
    of Key.Left:
      i.navigate(shift): i.cursor = max(i.cursor - 1, 0)
    of Key.Right:
      i.navigate(shift): i.cursor = min(i.cursor + 1, i.runes.len)
    of Key.Home:
      i.navigate(shift): i.cursor = 0
    of Key.End:
      i.navigate(shift): i.cursor = i.runes.len
    of Key.CtrlA:
      i.selectAll()
    of Key.F5:
      return i.copySelection()
    of Key.Insert:
      if modCtrl notin k.keyMods: return false
      return i.copySelection()
    else:
      if i.readOnly:
        return false # editing keys bubble
      case k.key
      of Key.F6:
        return i.cutSelection()
      of Key.Backspace:
        if i.deleteSelection(): discard
        elif i.cursor > 0:
          i.runes.delete(i.cursor - 1)
          dec i.cursor
          i.changed()
      of Key.Delete:
        if shift: return i.cutSelection()
        if i.deleteSelection(): discard
        elif i.cursor < i.runes.len:
          i.runes.delete(i.cursor)
          i.changed()
      of Key.Down:
        if i.history.len > 0:
          i.openHistory()
        else:
          return false
      of Key.Enter:
        i.addHistory(i.text) # record before firing (recency)
        # consumed only when someone may listen for submit (slot, command, or
        # an instance route anyone asked for); otherwise Enter bubbles on to
        # the window's default button (TV, deviation #34)
        let listened = i.onSubmit != nil or i.command != cmdNone or i.hasBrokerCtx
        if i.onSubmit != nil:
          i.onSubmit(i)
        i.publish(i.command)
        if i.hasBrokerCtx: Submitted.emit(i.brokerCtx, Submitted(text: i.text))
        return listened
      else:
        # printable rune with no Ctrl/Alt chord -> insert (if the filter allows)
        if k.rune.int32 >= 32 and k.keyMods * {modCtrl, modAlt} == {}:
          if i.accepts(k.rune):
            discard i.deleteSelection()
            i.runes.insert(k.rune, i.cursor)
            inc i.cursor
            i.changed()
          # rejected: consume the key, no change (silent by design)
        else:
          return false
    return true
  of evPaste:
    if i.readOnly:
      return false
    i.insertText(ev.pasteText)
    return true
  of evMouse:
    let m = ev.imouse
    case m.action
    of maPress:
      if modShift in m.mouseMods: # Shift+click extends from the cursor
        if not i.hasSelAnchor:
          i.selAnchor = i.cursor
          i.hasSelAnchor = true
        i.cursor = i.runes.indexAtCol(i.scrollX + m.mx)
      else:
        i.cursor = i.runes.indexAtCol(i.scrollX + m.mx)
        i.selAnchor = i.cursor
        i.hasSelAnchor = true
      i.dragging = true
      i.captureMouse() # drag selects, also past the edges (scrolls)
      i.invalidate()
      return true
    of maMove:
      if i.dragging:
        i.cursor = i.runes.indexAtCol(i.scrollX + m.mx)
        i.invalidate()
        return true
    of maRelease:
      if i.dragging:
        i.dragging = false
        i.releaseMouse()
        return true
    else:
      discard
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

# --- shipped validators ------------------------------------------------------

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
