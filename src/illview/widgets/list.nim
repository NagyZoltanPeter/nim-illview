## ListView (Phase 4.2): viewport + selection + key/wheel navigation.
## Slots: onSelect (selection moved), onActivate (Enter / item re-click).

import std/unicode
import ../core/[geometry, theme, view, drawcontext, events, bus]
import ../vocab

type
  ListView* = ref object of View
    items*: seq[string]
    selected*: int
    top*: int # first visible row
    command*: Command
    showScrollbar*: bool # draw a thumb indicator in the last column when overflowing
    onSelect*: proc(sender: ListView) {.gcsafe, raises: [].}
    onActivate*: proc(sender: ListView) {.gcsafe, raises: [].}

proc ensureVisible*(l: ListView) =
  let h = max(l.contentH, 1)
  if l.selected < l.top:
    l.top = l.selected
  elif l.selected >= l.top + h:
    l.top = l.selected - h + 1
  l.top = clamp(l.top, 0, max(l.items.len - 1, 0))

proc newListView*(items: seq[string] = @[], command = cmdNone): ListView =
  result = ListView(items: items, command: command)
  initView(result)
  result.focusable = true
  var w = 0
  for it in items:
    w = max(w, it.runeLen)
  result.hint = (prefHint(w, stretch = 1), prefHint(items.len, stretch = 1))
  let l = result
  l.installSignal(SetSelected):
    # programmatic apply: no slot, no re-emit (plan-3 D8)
    if l.items.len > 0:
      l.selected = clamp(sig.selected, 0, l.items.high)
      l.ensureVisible()
      l.invalidate()
  l.installFocusMe()

proc setItems*(l: ListView, items: seq[string]) =
  l.items = items
  l.selected = clamp(l.selected, 0, max(items.high, 0))
  l.top = 0
  var w = 0
  for it in items:
    w = max(w, it.runeLen)
  l.hint = (prefHint(w, stretch = 1), prefHint(items.len, stretch = 1))
  l.invalidate()

proc select*(l: ListView, i: int) =
  let ni = clamp(i, 0, l.items.high)
  if l.items.len == 0 or ni == l.selected:
    return
  l.selected = ni
  l.ensureVisible()
  if l.onSelect != nil:
    l.onSelect(l)
  if l.hasBrokerCtx: SelectionChanged.emit(l.brokerCtx, SelectionChanged(selected: l.selected))
  l.invalidate()

proc activate*(l: ListView) =
  if l.items.len == 0:
    return
  if l.onActivate != nil:
    l.onActivate(l)
  l.publish(l.command)
  if l.hasBrokerCtx: Activated.emit(l.brokerCtx, Activated(selected: l.selected))

method draw*(l: ListView, dc: DrawContext) {.gcsafe, raises: [].} =
  let normal = l.styleOf(tkList)
  let sel = l.styleOf(if l.isFocused: tkSelectionFocused else: tkSelection)
  let bar = l.showScrollbar and l.items.len > l.contentH
  dc.fill(rect(0, 0, l.contentW, l.contentH), " ", normal) # list surface
  let rowW = if bar: max(l.contentW - 1, 0) else: l.contentW
  for y in 0 ..< max(l.contentH, 0):
    let idx = l.top + y
    if idx > l.items.high:
      break
    let st = if idx == l.selected: sel else: normal
    if idx == l.selected:
      dc.fill(rect(0, y, rowW, 1), " ", st)
    dc.write(0, y, l.items[idx], st)
  if bar:
    let sbSt = l.styleOf(tkScrollBar)
    let (ts, tl) = thumbGeom(l.contentH, l.items.len, l.contentH, l.top)
    for y in 0 ..< l.contentH:
      dc.write(l.contentW - 1, y,
               (if y >= ts and y < ts + tl: "█" else: "░"), sbSt)

method handleEvent*(l: ListView, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    if modAlt in ev.ikey.keyMods:
      return false # Alt-chords are window/app level (move/resize)
    let page = max(l.contentH, 1)
    case ev.ikey.key
    of Key.Up: l.select(l.selected - 1)
    of Key.Down: l.select(l.selected + 1)
    of Key.Home: l.select(0)
    of Key.End: l.select(l.items.high)
    of Key.PageUp: l.select(l.selected - page)
    of Key.PageDown: l.select(l.selected + page)
    of Key.Enter:
      l.activate()
    else:
      return false
    return true
  of evMouse:
    case ev.imouse.action
    of maWheelUp:
      l.top = max(l.top - 1, 0)
      l.invalidate()
      return true
    of maWheelDown:
      l.top = clamp(l.top + 1, 0, max(l.items.len - l.contentH, 0))
      l.invalidate()
      return true
    of maPress:
      let idx = l.top + ev.imouse.my
      if idx >= 0 and idx <= l.items.high:
        if idx == l.selected:
          l.activate() # second click on the selection activates
        else:
          l.select(idx)
      return true
    else:
      discard
  of evFocusGained, evFocusLost:
    l.invalidate()
  else:
    discard
  false
