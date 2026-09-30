## Scroller (Phase 19, plan-4 D16): a viewport over one over-sized content
## view. The content is arranged at its virtual (preferred) size positioned at
## (-offX, -offY); the framework's DrawContext.sub() clip and the hit-test's
## bounds translation then give clipped drawing and correct mouse routing for
## free — this widget only overrides arrange (to place/clamp the content and
## keep the focused descendant visible) and handleEvent (wheel + paging).
##
## Scrollbar sync is compositional (deviation #4 style): set `onScroll` to push
## the model to an external ScrollBar, and drive `scrollTo` from the bar's
## onScroll. No embedded bar — the bar lives beside the Scroller in the layout.

import ../core/[geometry, view, events, routing]

type
  Scroller* = ref object of Group
    content*: View
    offX*, offY*: int
    wheelStep*: int          # rows per wheel notch
    autoFocusScroll*: bool   # keep the focused descendant in view (default on)
    onScroll*: proc(s: Scroller) {.gcsafe, raises: [].}

proc newScroller*(content: View): Scroller =
  result = Scroller(content: content, wheelStep: 3, autoFocusScroll: true)
  initView(result)
  result.focusable = false
  # a viewport wants the slot it is given; the default zero hint made a
  # Scroller in a box collapse to nothing (plan-5 P36, same fix as Splitter)
  result.hint = (prefHint(0, stretch = 1), prefHint(0, stretch = 1))
  add(Group(result), content) # the sole child; z-order irrelevant

proc virtualSize*(s: Scroller): tuple[w, h: int] =
  ## Content's preferred size, never smaller than the viewport.
  let o = s.content.outerHints()
  (max(o.w.pref, s.contentW), max(o.h.pref, s.contentH))

proc scrollMaxX*(s: Scroller): int = max(s.virtualSize.w - s.contentW, 0)
proc scrollMaxY*(s: Scroller): int = max(s.virtualSize.h - s.contentH, 0)

proc clampOffsets(s: Scroller) =
  s.offX = clamp(s.offX, 0, s.scrollMaxX)
  s.offY = clamp(s.offY, 0, s.scrollMaxY)

proc placeContent(s: Scroller) =
  let vs = s.virtualSize
  s.content.arrange(rect(-s.offX, -s.offY, vs.w, vs.h))

proc ensureFocusedVisible(s: Scroller): bool =
  ## Nudge the offsets so the globally-focused descendant is fully in view.
  ## Returns true if an offset changed. Requires the content already arranged.
  let leaf = focusedLeaf(Group(s))
  if leaf == nil or not leaf.isFocused:
    return false
  # leaf position in the content's virtual space (offset-independent: both
  # absOrigins carry the same -off translation, which cancels in the delta).
  let co = s.content.absOrigin
  let lo = leaf.absOrigin
  let relX = lo.x - co.x
  let relY = lo.y - co.y
  let lw = max(leaf.bounds.w, 1)
  let lh = max(leaf.bounds.h, 1)
  let viewW = s.contentW
  let viewH = s.contentH
  let ox = s.offX
  let oy = s.offY
  if relY < s.offY: s.offY = relY
  elif relY + lh > s.offY + viewH: s.offY = relY + lh - viewH
  if relX < s.offX: s.offX = relX
  elif relX + lw > s.offX + viewW: s.offX = relX + lw - viewW
  s.clampOffsets()
  s.offX != ox or s.offY != oy

method arrange*(s: Scroller, r: Rect) {.gcsafe, raises: [].} =
  s.bounds = r
  s.clampOffsets()
  s.placeContent()
  if s.autoFocusScroll and s.ensureFocusedVisible():
    s.placeContent() # re-place after the auto-scroll adjustment

proc scrollTo*(s: Scroller, x, y: int) =
  let ox = s.offX
  let oy = s.offY
  s.offX = x
  s.offY = y
  s.clampOffsets()
  if s.offX != ox or s.offY != oy:
    s.placeContent()
    s.invalidate()
    if s.onScroll != nil:
      s.onScroll(s)

proc scrollBy*(s: Scroller, dx, dy: int) = s.scrollTo(s.offX + dx, s.offY + dy)

proc ensureVisible*(s: Scroller, r: Rect) =
  ## Scroll the minimal amount so virtual-space rect `r` is in the viewport.
  var nx = s.offX
  var ny = s.offY
  if r.y < ny: ny = r.y
  elif r.y + r.h > ny + s.contentH: ny = r.y + r.h - s.contentH
  if r.x < nx: nx = r.x
  elif r.x + r.w > nx + s.contentW: nx = r.x + r.w - s.contentW
  s.scrollTo(nx, ny)

method handleEvent*(s: Scroller, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evMouse:
    case ev.imouse.action
    of maWheelUp: s.scrollBy(0, -s.wheelStep); return true
    of maWheelDown: s.scrollBy(0, s.wheelStep); return true
    else: return false
  of evKey:
    if modAlt in ev.ikey.keyMods:
      return false # Alt-chords belong to the window/app
    let pg = max(s.contentH, 1)
    case ev.ikey.key
    of Key.PageUp: s.scrollBy(0, -pg); return true
    of Key.PageDown: s.scrollBy(0, pg); return true
    else: return false
  else:
    return false
