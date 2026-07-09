## Label: static text, no slots (Phase 4.1).

import std/unicode
import ../core/[geometry, theme, view, drawcontext]
import ../vocab

type
  Label* = ref object of View
    text*: string

proc setText*(l: Label, s: string) =
  l.text = s
  l.hint = (fixedHint(s.runeLen), fixedHint(1))
  l.invalidate()

proc newLabel*(text: string): Label =
  result = Label()
  initView(result)
  result.setText(text)
  let l = result
  l.installSignal(SetText):
    l.setText(sig.text)

method draw*(l: Label, dc: DrawContext) {.gcsafe, raises: [].} =
  dc.write(0, 0, l.text,
           l.styleOf(if l.enabled: tkText else: tkTextDisabled))
