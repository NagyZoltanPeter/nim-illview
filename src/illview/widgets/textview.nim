## TextView (Phase 4.4): buffered read-only log/output widget — capped line
## buffer + viewport + scrolling. `follow` keeps the view pinned to the
## bottom while new lines arrive (until the user scrolls up).

import std/deques
import ../core/[geometry, theme, view, drawcontext, events]

type
  TextView* = ref object of View
    maxLines*: int # buffer cap; oldest lines are dropped
    lines*: Deque[string] # ring: O(1) at the cap (deviation #30); len/[] as before
    top*: int      # manual viewport start (used when follow == false)
    follow*: bool  # auto-scroll to the bottom
    showScrollbar*: bool # thumb indicator in the last column when overflowing
    lineStyle*: proc(line: string): ThemeToken {.gcsafe, raises: [].}
      ## Optional per-line token (a log level colorer); nil = tkText.

proc newTextView*(maxLines = 1000): TextView =
  result = TextView(maxLines: max(maxLines, 1), follow: true)
  initView(result)
  result.focusable = true
  result.hint = (prefHint(0, stretch = 1), prefHint(0, stretch = 1))

proc addLine*(tv: TextView, s: string) =
  tv.lines.addLast s
  if tv.lines.len > tv.maxLines:
    discard tv.lines.popFirst()
    if not tv.follow:
      tv.top = max(tv.top - 1, 0) # keep the same content in view
  tv.invalidate()

proc clear*(tv: TextView) =
  tv.lines.clear()
  tv.top = 0
  tv.follow = true
  tv.invalidate()

func effectiveTop(tv: TextView): int =
  if tv.follow:
    max(tv.lines.len - max(tv.contentH, 1), 0)
  else:
    tv.top

proc scrollBy*(tv: TextView, delta: int) =
  let maxTop = max(tv.lines.len - max(tv.contentH, 1), 0)
  tv.top = clamp(tv.effectiveTop + delta, 0, maxTop)
  tv.follow = tv.top >= maxTop
  tv.invalidate()

method draw*(tv: TextView, dc: DrawContext) {.gcsafe, raises: [].} =
  let st = tv.styleOf(tkList) # read-only data pane: list surface (deviation #35)
  let start = tv.effectiveTop
  dc.fill(rect(0, 0, tv.contentW, tv.contentH), " ", st)
  for y in 0 ..< max(tv.contentH, 0):
    let idx = start + y
    if idx >= tv.lines.len:
      break
    let line = tv.lines[idx]
    dc.write(0, y, line, if tv.lineStyle != nil: tv.styleOf(tv.lineStyle(line)) else: st)
  if tv.showScrollbar and tv.lines.len > tv.contentH:
    let sbSt = tv.styleOf(tkScrollBar)
    for y, g in scrollGlyphs(tv.contentH, tv.lines.len, tv.contentH, start, axV):
      dc.write(tv.contentW - 1, y, g, sbSt)

method handleEvent*(tv: TextView, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    if modAlt in ev.ikey.keyMods:
      return false # Alt-chords are window/app level (move/resize)
    case ev.ikey.key
    of Key.Up: tv.scrollBy(-1)
    of Key.Down: tv.scrollBy(1)
    of Key.PageUp: tv.scrollBy(-max(tv.contentH, 1))
    of Key.PageDown: tv.scrollBy(max(tv.contentH, 1))
    of Key.Home:
      tv.top = 0
      tv.follow = tv.lines.len <= tv.contentH
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
