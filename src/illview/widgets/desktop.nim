## Desktop: the root Group. Fills its area with the classic pattern and
## draws its children (windows) in z-order.

import std/unicode
import ../core/[geometry, theme, view, drawcontext, events, routing]

type
  Desktop* = ref object of Group

proc newDesktop*(theme: Theme = nil): Desktop =
  result = Desktop()
  initView(result)
  result.theme = if theme != nil: theme else: defaultTheme()

proc floatingWindows*(d: Desktop): seq[View] =
  ## Direct floating (dkNone) children, in z-order (bottom -> top).
  for c in d.children:
    if c.visible and c.dock == dkNone:
      result.add c

proc selectWindow*(d: Desktop, idx: int) =
  ## Raise and activate the idx-th floating window (Alt+1..9 / commands).
  let ws = d.floatingWindows
  if idx >= 0 and idx < ws.len:
    raiseToTop(Group(d), ws[idx])
    d.focused = ws[idx] # active even when the window has no focusable content
    if ws[idx] of Group:
      focusInto(Group(d), Group(ws[idx])) # refine into its first focusable child

proc tile*(d: Desktop) =
  ## Non-overlapping grid over the desktop; near-square column count.
  let ws = d.floatingWindows
  if ws.len == 0:
    return
  let cr = d.clientRect
  var cols = 1
  while cols * cols < ws.len:
    inc cols
  let rows = (ws.len + cols - 1) div cols
  let cw = max(cr.w div cols, 1)
  let ch = max(cr.h div rows, 1)
  for i, w in ws:
    w.bounds = rect((i mod cols) * cw, (i div cols) * ch, cw, ch)
  d.invalidate()

proc cascade*(d: Desktop) =
  ## Overlap the windows diagonally at a uniform two-thirds size.
  let ws = d.floatingWindows
  if ws.len == 0:
    return
  let cr = d.clientRect
  let ww = max(cr.w * 2 div 3, 8)
  let wh = max(cr.h * 2 div 3, 4)
  for i, w in ws:
    w.bounds = rect(min(i * 2, max(cr.w - ww, 0)),
                    min(i, max(cr.h - wh, 0)), ww, wh)
  d.invalidate()

method draw*(d: Desktop, dc: DrawContext) {.gcsafe, raises: [].} =
  dc.fill(rect(0, 0, d.contentW, d.contentH), "░".runeAt(0), d.styleOf(tkDesktop))
  procCall Group(d).draw(dc)

method handleEvent*(d: Desktop, ev: Event): bool {.gcsafe, raises: [].} =
  ## Alt+1..9 selects the Nth floating window (bubbles here as the scope root).
  if ev.kind == evKey and modAlt in ev.ikey.keyMods:
    let c = int(ev.ikey.rune)
    if c >= ord('1') and c <= ord('9'):
      d.selectWindow(c - ord('1'))
      return true
  false
