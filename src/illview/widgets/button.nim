## Button (Phase 4.1): `onClick` closure slot + optional broker `command`
## (§3.9). Slot fires synchronously inside dispatch, before the next frame.

import std/unicode
import ../core/[geometry, theme, view, drawcontext, events, bus]

type
  Button* = ref object of View
    caption*: string
    command*: Command
    onClick*: proc(sender: Button) {.gcsafe, raises: [].}

proc newButton*(caption: string, command = cmdNone): Button =
  result = Button(caption: caption, command: command)
  initView(result)
  result.focusable = true
  result.hint = (fixedHint(caption.runeLen + 4), fixedHint(1))

proc activate*(b: Button) =
  if not b.enabled:
    return
  if b.onClick != nil:
    b.onClick(b)
  b.publish(b.command)
  b.invalidate()

method draw*(b: Button, dc: DrawContext) {.gcsafe, raises: [].} =
  let st = b.styleOf(if b.isFocused: tkButtonFocused else: tkButton)
  dc.fill(rect(0, 0, b.contentW, b.contentH), " ", st)
  dc.write(0, 0, (if b.isFocused: "▶ " else: "[ "), st)
  dc.write(2, 0, b.caption, st)
  dc.write(2 + b.caption.runeLen, 0, (if b.isFocused: " ◀" else: " ]"), st)

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
