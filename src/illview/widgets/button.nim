## Button (Phase 4.1): `onClick` closure slot + optional broker `command`
## (§3.9). Slot fires synchronously inside dispatch, before the next frame.
## Look (deviation #36): flat green face, `> caption <` while focused; the
## face sits one cell right of the button's left edge and shifts into that
## cell while pressed. Mouse fires on release over the button (TV); keys fire
## at once and flash the pressed face.

import std/unicode
import ../core/[geometry, theme, view, drawcontext, events, bus, hotkey]
import ../vocab

const PressFlash = 100.milliseconds # keyboard press: how long the face stays shifted

type
  Button* = ref object of View
    caption*: string # tilde-stripped display text
    hlCol*: int      # hotkey highlight column, -1 = none
    command*: Command
    onClick*: proc(sender: Button) {.gcsafe, raises: [].}
    isDefault*: bool # bright caption; Enter in the window fires it (Window)
    pressed*: bool   # face shifted one cell left (mouse held / key flash)

proc applyCaption*(b: Button, s: string) =
  ## Set the caption, parsing ~tilde~ hotkey markup (plan-4 P22).
  let hk = parseHotkey(s)
  b.caption = hk.text
  b.hotkey = hk.key
  b.hlCol = hk.col
  # "> caption <" face + the cell the face shifts into while pressed
  b.hint = (fixedHint(hk.text.runeLen + 5), fixedHint(1))
  b.invalidate()

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

proc unpressLater(b: Button) {.async: (raises: []).} =
  try:
    await sleepAsync(PressFlash)
  except CancelledError:
    discard
  b.pressed = false
  b.invalidate()

proc keyPress(b: Button) =
  ## Keys fire at once (TV) and flash the pressed face.
  if not b.enabled or b.disabled:
    return
  b.pressed = true
  b.activate()
  asyncSpawn b.unpressLater()

method draw*(b: Button, dc: DrawContext) {.gcsafe, raises: [].} =
  let dis = b.disabled
  let st = if dis: b.styleOf(tkTextDisabled) # greyed face (TV)
           elif b.isFocused: b.styleOf(tkButtonFocused)
           elif b.isDefault: b.styleOf(tkButtonDefault)
           else: b.styleOf(tkButton)
  let fw = max(b.contentW - 1, 0)
  let ox = if b.pressed: 0 else: 1 # the face shifts one cell left when pressed
  dc.fill(rect(ox, 0, fw, 1), " ", st)
  let x = ox + max((fw - b.caption.runeLen) div 2, 0)
  dc.write(x, 0, b.caption, st)
  if b.isFocused and fw >= 2:
    dc.write(ox, 0, ">", st)
    dc.write(ox + fw - 1, 0, "<", st)
  if b.hlCol >= 0 and not dis: # highlight the accelerator letter
    dc.write(x + b.hlCol, 0, $b.caption.runeAtPos(b.hlCol), b.hotkeyStyle(st))

method triggerHotkey*(b: Button, scope: Group) {.gcsafe, raises: [].} =
  b.keyPress()

method handleEvent*(b: Button, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    if ev.ikey.key in [Key.Enter, Key.Space]:
      b.keyPress()
      return true
  of evMouse:
    let m = ev.imouse
    let inside = m.my == 0 and m.mx >= 0 and m.mx < b.contentW
    case m.action
    of maPress:
      if inside and b.enabled and not b.disabled:
        b.pressed = true # fire on release (TV); capture follows the drag
        b.captureMouse()
        b.invalidate()
      return true
    of maMove:
      let r = b.root
      if b.pressed != inside and r of Group and Group(r).mouseCapture == View(b):
        b.pressed = inside # dragged off: un-press, back on: re-press
        b.invalidate()
      return true
    of maRelease:
      let fire = b.pressed and inside
      b.pressed = false
      b.releaseMouse()
      b.invalidate()
      if fire:
        b.activate()
      return true
    else:
      discard
  of evFocusGained, evFocusLost:
    b.invalidate()
  else:
    discard
  false
