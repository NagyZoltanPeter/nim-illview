## ProgressBar (Phase 8): determinate progress with optional percent label.
## (Indeterminate/animated mode deliberately out — it would need a ticker.)

import std/strformat
import ../core/[geometry, theme, view, drawcontext]

type
  ProgressBar* = ref object of View
    value*: int
    maxValue*: int
    showPercent*: bool

proc newProgressBar*(maxValue = 100, showPercent = true): ProgressBar =
  result = ProgressBar(maxValue: max(maxValue, 1), showPercent: showPercent)
  initView(result)
  result.hint = (prefHint(20, stretch = 1), fixedHint(1))

proc setValue*(p: ProgressBar, v: int) =
  let nv = clamp(v, 0, p.maxValue)
  if nv != p.value:
    p.value = nv
    p.invalidate()

method draw*(p: ProgressBar, dc: DrawContext) {.gcsafe, raises: [].} =
  let w = max(p.contentW, 1)
  let st = p.styleOf(tkProgress)
  let filled = p.value * w div p.maxValue
  for x in 0 ..< w:
    dc.write(x, 0, (if x < filled: "█" else: "░"), st)
  if p.showPercent:
    let label = &" {p.value * 100 div p.maxValue}% "
    let x = max((w - label.len) div 2, 0)
    dc.write(x, 0, label, st)
