## Checkbox (Phase 4.1): `onToggle` slot + optional broker `command`.

import std/unicode
import ../core/[geometry, theme, view, drawcontext, events, bus]

type
  Checkbox* = ref object of View
    caption*: string
    checked*: bool
    command*: Command
    onToggle*: proc(sender: Checkbox) {.gcsafe, raises: [].}

proc newCheckbox*(caption: string, checked = false, command = cmdNone): Checkbox =
  result = Checkbox(caption: caption, checked: checked, command: command)
  initView(result)
  result.focusable = true
  result.hint = (fixedHint(caption.runeLen + 4), fixedHint(1))

proc toggle*(c: Checkbox) =
  if not c.enabled:
    return
  c.checked = not c.checked
  if c.onToggle != nil:
    c.onToggle(c)
  c.publish(c.command)
  c.invalidate()

method draw*(c: Checkbox, dc: DrawContext) {.gcsafe, raises: [].} =
  let st = c.styleOf(if c.isFocused: tkCheckboxFocused else: tkCheckbox)
  dc.write(0, 0, (if c.checked: "[x] " else: "[ ] ") & c.caption, st)

method handleEvent*(c: Checkbox, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    if ev.ikey.key in [Key.Space, Key.Enter]:
      c.toggle()
      return true
  of evMouse:
    if ev.imouse.action == maPress:
      c.toggle()
      return true
  of evFocusGained, evFocusLost:
    c.invalidate()
  else:
    discard
  false
