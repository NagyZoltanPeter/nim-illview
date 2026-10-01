## Phase 19 exit criteria (plan-4 D16): a Scroller places over-sized content
## at a negative offset and inherits clipping (DrawContext.sub) and mouse
## routing (hit-test bounds translation). Verifies virtual sizing, clamped
## scrolling, clipped drawing, offset-correct mouse routing, and — the headline
## feature — focus-driven auto-scroll (Tab/focus into an off-screen widget
## brings it into view). No terminal.

import std/[unittest, unicode, strutils]
import ../src/illview/backend/illwill_vendored
import ../src/illview/core/[geometry, theme, view, events, drawcontext, routing]
import ../src/illview/layout/layout
import ../src/illview/widgets/scroller

type Row = ref object of View
  idx: int
  pressedLocalY: int

var lastPressed = -1

proc newRow(idx: int): Row =
  result = Row(idx: idx, pressedLocalY: -1)
  initView(result)
  result.focusable = true
  result.hint = (prefHint(6), fixedHint(1))

method draw(v: Row, dc: DrawContext) {.gcsafe, raises: [].} =
  dc.write(0, 0, "row" & $v.idx, v.styleOf(tkText))

method handleEvent(v: Row, ev: Event): bool {.gcsafe, raises: [].} =
  if ev.kind == evMouse and ev.imouse.action == maPress:
    v.pressedLocalY = ev.imouse.my
    {.cast(gcsafe).}: lastPressed = v.idx
    return true
  false

proc buildScroller(rows, viewW, viewH: int): tuple[root: Group, sc: Scroller] =
  let root = newGroup()
  root.bounds = rect(0, 0, viewW, viewH)
  let vb = newVBox()
  for i in 0 ..< rows:
    vb.add newRow(i)
  let sc = newScroller(vb)
  sc.dock = dkFill
  root.add sc
  root.arrangeChildren()
  (root, sc)

proc rowStr(tb: TerminalBuffer, y: int): string =
  for x in 0 ..< tb.width: result.add $tb[x, y].ch

proc render(root: Group, w, h: int): TerminalBuffer =
  result = newTerminalBuffer(w, h)
  root.bounds = rect(0, 0, w, h)
  root.arrange(rect(0, 0, w, h))
  root.draw(initDrawContext(result))

suite "Scroller model":
  test "virtual size is the content pref, clamped to at least the viewport":
    let (_, sc) = buildScroller(20, 20, 5)
    check sc.virtualSize.h == 20
    check sc.scrollMaxY == 15 # 20 content - 5 viewport
    check sc.scrollMaxX == 0  # content no wider than the viewport

  test "scrollBy clamps to [0, scrollMax]":
    let (_, sc) = buildScroller(20, 20, 5)
    sc.scrollBy(0, 100)
    check sc.offY == 15
    sc.scrollBy(0, -100)
    check sc.offY == 0

  test "onScroll fires only on an actual change":
    let (_, sc) = buildScroller(20, 20, 5)
    var hits = 0
    sc.onScroll = proc(s: Scroller) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: inc hits
    sc.scrollTo(0, 4)
    sc.scrollTo(0, 4) # no change
    check hits == 1

suite "Scroller drawing is clipped to the viewport":
  test "only the visible slice is drawn; scrolling reveals lower rows":
    let (root, sc) = buildScroller(20, 20, 5)
    var tb = render(root, 20, 5)
    check "row0" in rowStr(tb, 0)
    check "row4" in rowStr(tb, 4)      # last visible row
    check "row5" notin rowStr(tb, 0)   # off the bottom, not drawn anywhere
    sc.scrollTo(0, 7)
    tb = render(root, 20, 5)
    check "row7" in rowStr(tb, 0)      # scrolled to the top of the viewport
    check "row0" notin rowStr(tb, 0)

suite "Scroller mouse routing translates by the offset":
  test "a viewport click lands on the scrolled-in child":
    let (root, sc) = buildScroller(20, 20, 5)
    sc.scrollTo(0, 7)
    lastPressed = -1
    dispatchMouse(root, mouseEvent(maPress, mbLeft, 2, 0)) # viewport top row
    check lastPressed == 7 # row7 is what's shown there after scrolling

suite "Scroller wheel bubbles up through unconsuming content":
  test "wheel over a non-scrolling child scrolls the Scroller":
    let (root, sc) = buildScroller(20, 20, 5)
    dispatchMouse(root, mouseEvent(maWheelDown, mbNone, 2, 2))
    check sc.offY == sc.wheelStep
    dispatchMouse(root, mouseEvent(maWheelUp, mbNone, 2, 2))
    check sc.offY == 0

suite "Scroller focus-driven auto-scroll":
  test "focusing an off-screen widget scrolls it into view":
    let (root, sc) = buildScroller(20, 20, 5)
    check sc.offY == 0
    setFocus(root, Group(sc.content).children[12]) # a row below the fold
    root.arrangeChildren()                          # arrange reconciles scroll
    check sc.offY == 8 # 12 + 1 - 5 : row12 pinned to the viewport bottom

  test "focusing a widget already visible does not scroll":
    let (root, sc) = buildScroller(20, 20, 5)
    setFocus(root, Group(sc.content).children[2])
    root.arrangeChildren()
    check sc.offY == 0

suite "Scroller default size hint (deviation #30)":
  test "in a box, a Scroller with no hand-set hint fills its slot":
    # before: default SizeHint() (pref 0, stretch 0) collapsed it to width 0
    let root = newGroup()
    root.bounds = rect(0, 0, 30, 5)
    let row = newHBox()
    row.dock = dkFill
    let vb = newVBox()
    for i in 0 ..< 20:
      vb.add newRow(i)
    let sc = newScroller(vb)
    let side = newRow(99)
    side.hint = (fixedHint(4), prefHint(0, stretch = 1))
    row.add sc
    row.add side
    root.add row
    root.arrangeChildren()
    check sc.bounds.w == 26 # everything the fixed-width sibling leaves
    check sc.bounds.h == 5
