## Sparkline (deviation #30): a fixed-capacity ring of samples drawn as block
## glyphs on one row — a message rate, a peer count, anything a status
## console watches over time. `push(v)` appends (newest = rightmost); the
## scale is `maxValue`, or the largest sample in the window when 0. Drivable
## from a model through `SetProgress.signal(s.brokerCtx, …)` like a
## ProgressBar.

import std/deques
import ../core/[geometry, theme, view, drawcontext]
import ../vocab

type
  Sparkline* = ref object of View
    samples: Deque[int]
    capacity*: int
    maxValue*: int # 0 = auto-scale to the window's maximum

const Blocks = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

proc push*(s: Sparkline, v: int) =
  s.samples.addLast(max(v, 0))
  while s.samples.len > s.capacity:
    discard s.samples.popFirst()
  s.invalidate()

proc newSparkline*(capacity = 40, maxValue = 0): Sparkline =
  result = Sparkline(capacity: max(capacity, 1), maxValue: maxValue)
  initView(result)
  result.hint = (prefHint(capacity, stretch = 1), fixedHint(1))
  let s = result
  s.installSignal(SetProgress):
    s.push(sig.value)

func last*(s: Sparkline): int =
  if s.samples.len > 0: s.samples.peekLast else: 0

func len*(s: Sparkline): int = s.samples.len

method draw*(s: Sparkline, dc: DrawContext) {.gcsafe, raises: [].} =
  let w = max(s.contentW, 1)
  let st = s.styleOf(tkProgress)
  var top = s.maxValue
  if top <= 0:
    for v in s.samples:
      top = max(top, v)
  let n = min(s.samples.len, w)
  for i in 0 ..< n:
    let v = s.samples[s.samples.len - n + i]
    # ceiling division so any non-zero sample shows above the baseline
    let lvl = if top == 0: 0 else: min((v * 7 + top - 1) div top, 7)
    dc.write(w - n + i, 0, Blocks[lvl], st)
