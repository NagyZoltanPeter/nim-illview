## Radio (Phase 4.1): TurboVision-style exclusive group as ONE view with
## multiple items (one per row); `onSelect` slot.

import std/unicode
import ../core/[geometry, theme, view, drawcontext, events, bus]

type
  Radio* = ref object of View
    items*: seq[string]
    selected*: int
    command*: Command
    onSelect*: proc(sender: Radio) {.gcsafe, raises: [].}

proc newRadio*(items: seq[string], selected = 0, command = cmdNone): Radio =
  result = Radio(items: items, selected: selected, command: command)
  initView(result)
  result.focusable = true
  var w = 0
  for it in items:
    w = max(w, it.runeLen + 4)
  result.hint = (fixedHint(w), fixedHint(items.len))

proc select*(r: Radio, i: int) =
  if not r.enabled or i < 0 or i >= r.items.len or i == r.selected:
    return
  r.selected = i
  if r.onSelect != nil:
    r.onSelect(r)
  r.publish(r.command)
  r.invalidate()

method draw*(r: Radio, dc: DrawContext) {.gcsafe, raises: [].} =
  for i, it in r.items:
    let focusedRow = r.isFocused and i == r.selected
    let st = r.styleOf(if focusedRow: tkCheckboxFocused else: tkCheckbox)
    dc.write(0, i, (if i == r.selected: "(•) " else: "( ) ") & it, st)

method handleEvent*(r: Radio, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    case ev.ikey.key
    of Key.Up:
      r.select(r.selected - 1)
      return true
    of Key.Down:
      r.select(r.selected + 1)
      return true
    else:
      discard
  of evMouse:
    if ev.imouse.action == maPress:
      r.select(ev.imouse.my)
      return true
  of evFocusGained, evFocusLost:
    r.invalidate()
  else:
    discard
  false
