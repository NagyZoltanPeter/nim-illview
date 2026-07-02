## Desktop: the root Group. Fills its area with the classic pattern and
## draws its children (windows) in z-order.

import std/unicode
import ../core/[geometry, theme, view, drawcontext]

type
  Desktop* = ref object of Group

proc newDesktop*(theme: Theme = nil): Desktop =
  result = Desktop()
  initView(result)
  result.theme = if theme != nil: theme else: defaultTheme()

method draw*(d: Desktop, dc: DrawContext) {.gcsafe, raises: [].} =
  dc.fill(rect(0, 0, d.bounds.w, d.bounds.h), "▒".runeAt(0), d.styleOf(tkDesktop))
  procCall Group(d).draw(dc)
