## Label: static text (Phase 4.1). A tilde-marked caption (e.g. "~N~ame")
## declares an Alt-accelerator that focuses `linkTo` (plan-4 P22).

import std/unicode
import ../core/[geometry, theme, view, drawcontext, routing, hotkey]
import ../vocab

type
  Label* = ref object of View
    text*: string       # tilde-stripped display text
    hlCol*: int         # hotkey highlight column, -1 = none
    linkTo*: View       # focused when the accelerator fires

proc setText*(l: Label, s: string) =
  let hk = parseHotkey(s)
  l.text = hk.text
  l.hotkey = hk.key
  l.hlCol = hk.col
  l.hint = (fixedHint(hk.text.runeLen), fixedHint(1))
  l.invalidate()

proc newLabel*(text: string): Label =
  result = Label(hlCol: -1)
  initView(result)
  result.setText(text)
  let l = result
  l.installSignal(SetText):
    l.setText(sig.text)

method triggerHotkey*(l: Label, scope: Group) {.gcsafe, raises: [].} =
  if l.linkTo != nil:
    setFocus(scope, l.linkTo)

method draw*(l: Label, dc: DrawContext) {.gcsafe, raises: [].} =
  let tok = if not l.enabled: tkTextDisabled
            elif l.linkTo != nil and l.linkTo.isFocused: tkLabelFocused # TV TLabel
            else: tkText
  let base = l.styleOf(tok)
  dc.write(0, 0, l.text, base)
  if l.hlCol >= 0 and l.enabled:
    dc.write(l.hlCol, 0, $l.text.runeAtPos(l.hlCol), l.hotkeyStyle(base))
