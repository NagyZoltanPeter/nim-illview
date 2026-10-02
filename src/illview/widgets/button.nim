## Button (Phase 4.1): `onClick` closure slot + optional broker `command`
## (§3.9). Slot fires synchronously inside dispatch, before the next frame.
## TV look (deviation #34): caption centred on the button face, half-block
## shadow (`▄` right, `▀` below) drawn over the surface underneath.

import std/unicode
import ../core/[geometry, theme, view, drawcontext, events, bus, hotkey]
import ../vocab

type
  Button* = ref object of View
    caption*: string # tilde-stripped display text
    hlCol*: int      # hotkey highlight column, -1 = none
    command*: Command
    onClick*: proc(sender: Button) {.gcsafe, raises: [].}
    shadowed*: bool = true # half-block shadow: +1 column, +1 row (setShadowed)
    isDefault*: bool # bright caption; Enter in the window fires it (Window)

proc updateHint(b: Button) =
  let s = if b.shadowed: 1 else: 0
  b.hint = (fixedHint(b.caption.runeLen + 4 + s), fixedHint(1 + s))

proc applyCaption*(b: Button, s: string) =
  ## Set the caption, parsing ~tilde~ hotkey markup (plan-4 P22).
  let hk = parseHotkey(s)
  b.caption = hk.text
  b.hotkey = hk.key
  b.hlCol = hk.col
  b.updateHint()
  b.invalidate()

proc setShadowed*(b: Button, on: bool) =
  b.shadowed = on
  b.updateHint()
  b.invalidate()

func faceW(b: Button): int =
  max(b.contentW - (if b.shadowed: 1 else: 0), 0)

proc newButton*(caption: string, command = cmdNone): Button =
  result = Button(command: command, hlCol: -1)
  initView(result)
  result.focusable = true
  result.applyCaption(caption)
  result.installFocusMe()

proc disabled(b: Button): bool =
  b.command != cmdNone and not b.commandEnabled(b.command)

proc activate*(b: Button) =
  if not b.enabled or b.disabled: # command gating (plan-4 D19)
    return
  if b.onClick != nil:
    b.onClick(b)
  b.publish(b.command)
  if b.hasBrokerCtx: Clicked.emit(b.brokerCtx) # instance-routed vocab event (plan-3 D8)
  b.invalidate()

method draw*(b: Button, dc: DrawContext) {.gcsafe, raises: [].} =
  let dis = b.disabled
  let st = if dis: b.styleOf(tkTextDisabled) # greyed face (TV)
           elif b.isFocused: b.styleOf(tkButtonFocused)
           elif b.isDefault: b.styleOf(tkButtonDefault)
           else: b.styleOf(tkButton)
  let fw = b.faceW
  dc.fill(rect(0, 0, fw, 1), " ", st)
  let x = max((fw - b.caption.runeLen) div 2, 0)
  dc.write(x, 0, b.caption, st)
  if b.hlCol >= 0 and not dis: # highlight the accelerator letter
    dc.write(x + b.hlCol, 0, $b.caption.runeAtPos(b.hlCol), b.hotkeyStyle(st))
  if b.shadowed and b.contentH >= 2: # no room = no shadow (1-line bars)
    let sh = b.styleOf(tkButtonShadow)
    dc.overlay(fw, 0, "▄".runeAt(0), sh)
    for sx in 1 .. fw:
      dc.overlay(sx, 1, "▀".runeAt(0), sh)

method triggerHotkey*(b: Button, scope: Group) {.gcsafe, raises: [].} =
  b.activate()

method handleEvent*(b: Button, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    if ev.ikey.key in [Key.Enter, Key.Space]:
      b.activate()
      return true
  of evMouse:
    if ev.imouse.action == maPress:
      if ev.imouse.my == 0 and ev.imouse.mx < b.faceW: # shadow cells are inert
        b.activate()
      return true
  of evFocusGained, evFocusLost:
    b.invalidate()
  else:
    discard
  false
