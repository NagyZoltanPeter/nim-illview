## Button (Phase 4.1): `onClick` closure slot + optional broker `command`
## (§3.9). Slot fires synchronously inside dispatch, before the next frame.

import std/unicode
import ../core/[geometry, theme, view, drawcontext, events, bus, hotkey]
import ../vocab

type
  Button* = ref object of View
    caption*: string # tilde-stripped display text
    hlCol*: int      # hotkey highlight column, -1 = none
    command*: Command
    onClick*: proc(sender: Button) {.gcsafe, raises: [].}

proc applyCaption*(b: Button, s: string) =
  ## Set the caption, parsing ~tilde~ hotkey markup (plan-4 P22).
  let hk = parseHotkey(s)
  b.caption = hk.text
  b.hotkey = hk.key
  b.hlCol = hk.col
  b.hint = (fixedHint(hk.text.runeLen + 4), fixedHint(1))
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

method draw*(b: Button, dc: DrawContext) {.gcsafe, raises: [].} =
  let dis = b.disabled
  let st = if dis: b.styleOf(tkTextDisabled)
           else: b.styleOf(if b.isFocused: tkButtonFocused else: tkButton)
  dc.fill(rect(0, 0, b.contentW, b.contentH), " ", st)
  dc.write(0, 0, (if b.isFocused: "▶ " else: "[ "), st)
  dc.write(2, 0, b.caption, st)
  dc.write(2 + b.caption.runeLen, 0, (if b.isFocused: " ◀" else: " ]"), st)
  if b.hlCol >= 0 and not dis: # highlight the accelerator letter
    dc.write(2 + b.hlCol, 0, $b.caption.runeAtPos(b.hlCol),
             b.styleOf(tkStatusBarHotkey))

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
      b.activate()
      return true
  of evFocusGained, evFocusLost:
    b.invalidate()
  else:
    discard
  false
