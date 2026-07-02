## ListView (Phase 4.2): viewport + selection + key/wheel navigation.
## Slots: onSelect (selection moved), onActivate (Enter / item re-click).

import std/unicode
import ../core/[geometry, theme, view, drawcontext, events, bus]

type
  ListView* = ref object of View
    items*: seq[string]
    selected*: int
    top*: int # first visible row
    command*: Command
    onSelect*: proc(sender: ListView) {.gcsafe, raises: [].}
    onActivate*: proc(sender: ListView) {.gcsafe, raises: [].}

proc newListView*(items: seq[string] = @[], command = cmdNone): ListView =
  result = ListView(items: items, command: command)
  initView(result)
  result.focusable = true
  var w = 0
  for it in items:
    w = max(w, it.runeLen)
  result.hint = (prefHint(w, stretch = 1), prefHint(items.len, stretch = 1))

proc setItems*(l: ListView, items: seq[string]) =
  l.items = items
  l.selected = clamp(l.selected, 0, max(items.high, 0))
  l.top = 0
  var w = 0
  for it in items:
    w = max(w, it.runeLen)
  l.hint = (prefHint(w, stretch = 1), prefHint(items.len, stretch = 1))
  l.invalidate()

proc ensureVisible*(l: ListView) =
  let h = max(l.bounds.h, 1)
  if l.selected < l.top:
    l.top = l.selected
  elif l.selected >= l.top + h:
    l.top = l.selected - h + 1
  l.top = clamp(l.top, 0, max(l.items.len - 1, 0))

proc select*(l: ListView, i: int) =
  let ni = clamp(i, 0, l.items.high)
  if l.items.len == 0 or ni == l.selected:
    return
  l.selected = ni
  l.ensureVisible()
  if l.onSelect != nil:
    l.onSelect(l)
  l.invalidate()

proc activate*(l: ListView) =
  if l.items.len == 0:
    return
  if l.onActivate != nil:
    l.onActivate(l)
  l.publish(l.command)

method draw*(l: ListView, dc: DrawContext) {.gcsafe, raises: [].} =
  let normal = l.styleOf(tkText)
  let sel = l.styleOf(if l.isFocused: tkSelectionFocused else: tkSelection)
  for y in 0 ..< max(l.bounds.h, 0):
    let idx = l.top + y
    if idx > l.items.high:
      break
    let st = if idx == l.selected: sel else: normal
    if idx == l.selected:
      dc.fill(rect(0, y, l.bounds.w, 1), " ", st)
    dc.write(0, y, l.items[idx], st)

method handleEvent*(l: ListView, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    let page = max(l.bounds.h, 1)
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
      l.top = clamp(l.top + 1, 0, max(l.items.len - l.bounds.h, 0))
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
