## Checkbox (Phase 4.1): `onToggle` slot + optional broker `command`.

import std/unicode
import ../core/[geometry, theme, view, drawcontext, events, bus, hotkey]
import ../vocab

type
  Checkbox* = ref object of View
    caption*: string
    hlCol*: int # hotkey highlight column, -1 = none
    checked*: bool
    command*: Command
    onToggle*: proc(sender: Checkbox) {.gcsafe, raises: [].}

proc applyCaption*(c: Checkbox, s: string) =
  let hk = parseHotkey(s)
  c.caption = hk.text
  c.hotkey = hk.key
  c.hlCol = hk.col
  c.hint = (fixedHint(hk.text.runeLen + 4), fixedHint(1))
  c.invalidate()

proc newCheckbox*(caption: string, checked = false, command = cmdNone): Checkbox =
  result = Checkbox(checked: checked, command: command, hlCol: -1)
  initView(result)
  result.focusable = true
  result.applyCaption(caption)
  let c = result
  c.installSignal(SetChecked):
    # programmatic apply: no slot, no publish, no re-emit (plan-3 D8)
    c.checked = sig.checked
    c.invalidate()
  c.installFocusMe()

proc disabled(c: Checkbox): bool =
  c.command != cmdNone and not c.commandEnabled(c.command)

proc toggle*(c: Checkbox) =
  if not c.enabled or c.disabled:
    return
  c.checked = not c.checked
  if c.onToggle != nil:
    c.onToggle(c)
  c.publish(c.command)
  if c.hasBrokerCtx: Toggled.emit(c.brokerCtx, Toggled(checked: c.checked))
  c.invalidate()

method triggerHotkey*(c: Checkbox, scope: Group) {.gcsafe, raises: [].} =
  c.toggle()

method draw*(c: Checkbox, dc: DrawContext) {.gcsafe, raises: [].} =
  let dis = c.disabled
  let st = if dis: c.styleOf(tkTextDisabled)
           else: c.styleOf(if c.isFocused: tkCheckboxFocused else: tkCheckbox)
  dc.write(0, 0, (if c.checked: "[x] " else: "[ ] ") & c.caption, st)
  if c.hlCol >= 0 and not dis: # box prefix "[x] " is 4 cells wide
    dc.write(4 + c.hlCol, 0, $c.caption.runeAtPos(c.hlCol),
             c.styleOf(tkStatusBarHotkey))

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
