## TextView (Phase 4.4): buffered read-only log/output widget — capped line
## buffer + viewport + scrolling. `follow` keeps the view pinned to the
## bottom while new lines arrive (until the user scrolls up).

import ../core/[geometry, theme, view, drawcontext, events]

type
  TextView* = ref object of View
    maxLines*: int # buffer cap; oldest lines are dropped
    lines*: seq[string]
    top*: int      # manual viewport start (used when follow == false)
    follow*: bool  # auto-scroll to the bottom

proc newTextView*(maxLines = 1000): TextView =
  result = TextView(maxLines: max(maxLines, 1), follow: true)
  initView(result)
  result.focusable = true
  result.hint = (prefHint(0, stretch = 1), prefHint(0, stretch = 1))

proc addLine*(tv: TextView, s: string) =
  tv.lines.add s
  if tv.lines.len > tv.maxLines:
    tv.lines.delete(0)
    if not tv.follow:
      tv.top = max(tv.top - 1, 0) # keep the same content in view
  tv.invalidate()

proc clear*(tv: TextView) =
  tv.lines.setLen(0)
  tv.top = 0
  tv.follow = true
  tv.invalidate()

func effectiveTop(tv: TextView): int =
  if tv.follow:
    max(tv.lines.len - max(tv.bounds.h, 1), 0)
  else:
    tv.top

proc scrollBy*(tv: TextView, delta: int) =
  let maxTop = max(tv.lines.len - max(tv.bounds.h, 1), 0)
  tv.top = clamp(tv.effectiveTop + delta, 0, maxTop)
  tv.follow = tv.top >= maxTop
  tv.invalidate()

method draw*(tv: TextView, dc: DrawContext) {.gcsafe, raises: [].} =
  let st = tv.styleOf(tkText)
  let start = tv.effectiveTop
  for y in 0 ..< max(tv.bounds.h, 0):
    let idx = start + y
    if idx > tv.lines.high:
      break
    dc.write(0, y, tv.lines[idx], st)

method handleEvent*(tv: TextView, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    case ev.ikey.key
    of Key.Up: tv.scrollBy(-1)
    of Key.Down: tv.scrollBy(1)
    of Key.PageUp: tv.scrollBy(-max(tv.bounds.h, 1))
    of Key.PageDown: tv.scrollBy(max(tv.bounds.h, 1))
    of Key.Home:
      tv.top = 0
      tv.follow = tv.lines.len <= tv.bounds.h
      tv.invalidate()
    of Key.End:
      tv.follow = true
      tv.invalidate()
    else:
      return false
    return true
  of evMouse:
    case ev.imouse.action
    of maWheelUp:
      tv.scrollBy(-1)
      return true
    of maWheelDown:
      tv.scrollBy(1)
      return true
    else:
      discard
  else:
    discard
  false
