## Phase 3 exit criteria (pure, no terminal): given a tree of hints and a
## root rect, assert computed child rects for HBox/VBox/Grid, stretch
## distribution, min/max clamping, and dock placement.

import std/unittest
import ../src/illview/core/[geometry, view]
import ../src/illview/layout/layout

type Box = ref object of View

proc newHinted(w, h: SizeHint, dock = dkNone): Box =
  result = Box()
  initView(result)
  result.hint = (w, h)
  result.dock = dock

suite "distribute":
  test "prefs fit, no stretch: everyone gets pref, leftover unused":
    check distribute(30, @[fixedHint(5), fixedHint(10)]) == @[5, 10]

  test "leftover shared by stretch weights":
    let hints = @[
      SizeHint(min: 0, pref: 4, max: high(int), stretch: 1),
      SizeHint(min: 0, pref: 4, max: high(int), stretch: 3)]
    # avail 28, sumPref 8, leftover 20 -> +5 / +15
    check distribute(28, hints) == @[9, 19]

  test "stretch respects max clamp; remainder goes to others":
    let hints = @[
      SizeHint(min: 0, pref: 4, max: 6, stretch: 1),
      SizeHint(min: 0, pref: 4, max: high(int), stretch: 1)]
    # leftover 12: first can only take 2, rest flows to second
    check distribute(20, hints) == @[6, 14]

  test "shrink below pref toward min, proportional":
    let hints = @[
      SizeHint(min: 2, pref: 10),
      SizeHint(min: 2, pref: 10)]
    check distribute(14, hints) == @[7, 7]

  test "cannot fit even minimums: everyone gets min":
    let hints = @[SizeHint(min: 5, pref: 10), SizeHint(min: 5, pref: 10)]
    check distribute(6, hints) == @[5, 5]

  test "spacing is reserved before distribution":
    check distribute(12, @[fixedHint(5), fixedHint(5)], spacing = 2) == @[5, 5]

  test "rounding: leftover cells swept deterministically":
    let hints = @[
      SizeHint(pref: 0, max: high(int), stretch: 1),
      SizeHint(pref: 0, max: high(int), stretch: 1),
      SizeHint(pref: 0, max: high(int), stretch: 1)]
    let sizes = distribute(10, hints)
    check sizes[0] + sizes[1] + sizes[2] == 10

suite "HBox / VBox":
  test "hbox: fixed + stretch fills the row":
    let box = newHBox()
    let a = newHinted(fixedHint(10), prefHint(1))
    let b = newHinted(prefHint(0, stretch = 1), prefHint(1))
    box.add a
    box.add b
    box.arrange(rect(0, 0, 40, 5))
    check a.bounds == rect(0, 0, 10, 5)
    check b.bounds == rect(10, 0, 30, 5)

  test "vbox with spacing":
    let box = newVBox(spacing = 1)
    let a = newHinted(prefHint(0, stretch = 1), fixedHint(3))
    let b = newHinted(prefHint(0, stretch = 1), prefHint(0, stretch = 1))
    box.add a
    box.add b
    box.arrange(rect(0, 0, 20, 10))
    check a.bounds == rect(0, 0, 20, 3)
    check b.bounds == rect(0, 4, 20, 6)

  test "cross axis clamps to child max":
    let box = newHBox()
    let a = newHinted(prefHint(0, stretch = 1), SizeHint(min: 0, pref: 1, max: 2))
    box.add a
    box.arrange(rect(0, 0, 10, 8))
    check a.bounds.h == 2

  test "nested boxes reflow on re-arrange (resize)":
    let outer = newVBox()
    let top = newHBox()
    let l = newHinted(fixedHint(8), prefHint(0, stretch = 1))
    let r = newHinted(prefHint(0, stretch = 1), prefHint(0, stretch = 1))
    top.add l
    top.add r
    top.hint = (prefHint(0, stretch = 1), prefHint(0, stretch = 1))
    let bottom = newHinted(prefHint(0, stretch = 1), fixedHint(1))
    outer.add top
    outer.add bottom
    outer.arrange(rect(0, 0, 30, 10))
    check top.bounds == rect(0, 0, 30, 9)
    check r.bounds == rect(8, 0, 22, 9)
    check bottom.bounds == rect(0, 9, 30, 1)
    outer.arrange(rect(0, 0, 50, 20)) # "terminal resized"
    check top.bounds == rect(0, 0, 50, 19)
    check r.bounds == rect(8, 0, 42, 19)
    check bottom.bounds == rect(0, 19, 50, 1)

  test "box measure aggregates children":
    let box = newHBox(spacing = 1)
    box.add newHinted(fixedHint(5), fixedHint(2))
    box.add newHinted(fixedHint(7), fixedHint(3))
    let m = box.measure()
    check m.w.pref == 13 # 5 + 7 + 1 spacing
    check m.w.min == 13
    check m.h.pref == 3  # cross: max

suite "Grid":
  test "2x2 grid: column/row sizing from loosest cell":
    let g = newGrid(cols = 2)
    g.add newHinted(fixedHint(4), fixedHint(1))                      # (0,0)
    g.add newHinted(prefHint(0, stretch = 1), fixedHint(1))          # (0,1)
    g.add newHinted(fixedHint(6), fixedHint(2))                      # (1,0)
    g.add newHinted(prefHint(0, stretch = 1), fixedHint(2))          # (1,1)
    g.arrange(rect(0, 0, 20, 3))
    # col0 = max(4,6) = 6 fixed; col1 stretches to 14
    check g.children[0].bounds == rect(0, 0, 6, 1)
    check g.children[1].bounds == rect(6, 0, 14, 1)
    check g.children[2].bounds == rect(0, 1, 6, 2)
    check g.children[3].bounds == rect(6, 1, 14, 2)

  test "grid with spacing":
    let g = newGrid(cols = 2, spacing = 1)
    for i in 0 ..< 4:
      g.add newHinted(prefHint(0, stretch = 1), prefHint(0, stretch = 1))
    g.arrange(rect(0, 0, 21, 11))
    check g.children[0].bounds == rect(0, 0, 10, 5)
    check g.children[1].bounds == rect(11, 0, 10, 5)
    check g.children[3].bounds == rect(11, 6, 10, 5)

suite "dock anchoring (Group.arrangeChildren)":
  test "top/bottom strips + fill content":
    let g = newGroup()
    g.bounds = rect(0, 0, 40, 12)
    let menu = newHinted(prefHint(0), fixedHint(1), dock = dkTop)
    let status = newHinted(prefHint(0), fixedHint(1), dock = dkBottom)
    let content = newHinted(prefHint(0), prefHint(0), dock = dkFill)
    g.add menu
    g.add status
    g.add content
    g.arrangeChildren()
    check menu.bounds == rect(0, 0, 40, 1)
    check status.bounds == rect(0, 11, 40, 1)
    check content.bounds == rect(0, 1, 40, 10)

  test "left dock consumes width; order matters":
    let g = newGroup()
    g.bounds = rect(0, 0, 40, 12)
    let side = newHinted(fixedHint(10), prefHint(0), dock = dkLeft)
    let top = newHinted(prefHint(0), fixedHint(2), dock = dkTop)
    let fill = newHinted(prefHint(0), prefHint(0), dock = dkFill)
    g.add side
    g.add top
    g.add fill
    g.arrangeChildren()
    check side.bounds == rect(0, 0, 10, 12)
    check top.bounds == rect(10, 0, 30, 2)
    check fill.bounds == rect(10, 2, 30, 10)

  test "dkNone children keep manual bounds":
    let g = newGroup()
    g.bounds = rect(0, 0, 40, 12)
    let free = newHinted(prefHint(5), prefHint(3))
    free.bounds = rect(7, 4, 5, 3)
    g.add free
    g.arrangeChildren()
    check free.bounds == rect(7, 4, 5, 3)

# --- iteration 4 (plan-4 D14): align / anchors / padding / FormLayout --------

const bounded6 = SizeHint(min: 0, pref: 6, max: 6)   # sizes to 6, alignable
const grow = SizeHint(min: 0, pref: 4, max: high(int)) # fills its span

suite "alignSpan (cross-axis / in-cell placement)":
  test "alStretch fills the span (clamped to max)":
    check alignSpan(alStretch, 20, grow) == (0, 20)
    check alignSpan(alStretch, 20, bounded6) == (0, 6) # clamp to max
  test "start / center / end size to pref and offset":
    check alignSpan(alStart, 20, bounded6) == (0, 6)
    check alignSpan(alCenter, 20, bounded6) == (7, 6)
    check alignSpan(alEnd, 20, bounded6) == (14, 6)
  test "avail smaller than pref: size clamps, offset floors at 0":
    check alignSpan(alCenter, 4, bounded6) == (0, 4)

suite "align wired through the box cross axis":
  test "vbox: alEnd pins the child to the right of the row":
    let vb = newVBox()
    let c = newHinted(bounded6, fixedHint(2))
    c.align = alEnd
    vb.add c
    vb.arrange(rect(0, 0, 20, 10))
    check c.bounds == rect(14, 0, 6, 2)
  test "vbox: default alStretch is unchanged for a bounded child":
    let vb = newVBox()
    let c = newHinted(bounded6, fixedHint(2)) # no align set
    vb.add c
    vb.arrange(rect(0, 0, 20, 10))
    check c.bounds == rect(0, 0, 6, 2) # cross clamps to max, offset 0

suite "align wired through grid cells":
  test "alCenter centers within the cell; alStretch still fills":
    # single column; the wide sibling forces col0 to 10 so the narrow
    # centered child has room to offset.
    let g = newGrid(1)
    let a = newHinted(bounded6, fixedHint(2)); a.align = alCenter
    let wide = newHinted(SizeHint(min: 0, pref: 10, max: 10), fixedHint(2))
    g.add a; g.add wide
    g.arrange(rect(0, 0, 20, 6))
    check a.bounds == rect(2, 0, 6, 2)     # (10-6)/2 = 2 within the 10-wide cell
    check wide.bounds == rect(0, 2, 10, 2) # alStretch fills its cell

suite "padding (plan-4 D14)":
  test "shrinks clientRect and composes with the border":
    let g = newGroup()
    g.bounds = rect(0, 0, 20, 10)
    g.padding = 2
    check g.clientRect == rect(2, 2, 16, 6)
    g.border = bkSingle
    check g.clientRect == rect(3, 3, 14, 4) # 1 border + 2 padding
  test "outerHints inflates by padding so content keeps its pref":
    let b = newHinted(fixedHint(4), fixedHint(3))
    b.padding = 1
    check b.outerHints().w.pref == 6
    check b.outerHints().h.pref == 5
  test "a padded container insets its dkFill child":
    let g = newGroup()
    g.bounds = rect(0, 0, 20, 10)
    g.padding = 1
    let fill = newHinted(SizeHint(), SizeHint()); fill.dock = dkFill
    g.add fill
    g.arrangeChildren()
    check fill.bounds == rect(0, 0, 18, 8) # content-local origin, inset both axes

suite "anchors (plan-4 D14)":
  test "single edge slides the child on resize":
    let g = newGroup()
    g.bounds = rect(0, 0, 20, 10)
    let c = newHinted(SizeHint(), SizeHint())
    c.bounds = rect(2, 2, 6, 3)
    c.anchor.edges = {aRight}
    g.add c
    g.arrangeChildren()               # capture at 20x10, no delta
    check c.bounds == rect(2, 2, 6, 3)
    g.bounds = rect(0, 0, 30, 10)     # dw = 10
    g.arrangeChildren()
    check c.bounds == rect(12, 2, 6, 3) # x slid, width unchanged
  test "both horizontal edges stretch the child; vertical untouched":
    let g = newGroup()
    g.bounds = rect(0, 0, 20, 10)
    let c = newHinted(SizeHint(), SizeHint())
    c.bounds = rect(2, 2, 6, 3)
    c.anchor.edges = {aLeft, aRight} # no vertical anchor => y/h stay put
    g.add c
    g.arrangeChildren()
    g.bounds = rect(0, 0, 30, 14)     # dw = 10, dh = 4
    g.arrangeChildren()
    check c.bounds == rect(2, 2, 16, 3) # width +10, position and height fixed
  test "aBottom alone slides vertically":
    let g = newGroup()
    g.bounds = rect(0, 0, 20, 10)
    let c = newHinted(SizeHint(), SizeHint())
    c.bounds = rect(2, 2, 6, 3)
    c.anchor.edges = {aBottom}
    g.add c
    g.arrangeChildren()
    g.bounds = rect(0, 0, 20, 14)     # dh = 4
    g.arrangeChildren()
    check c.bounds == rect(2, 6, 6, 3)

suite "FormLayout (plan-4 D14)":
  test "col0 auto-sizes to the label, col1 stretches":
    let f = newFormLayout(1)
    let lab = newHinted(SizeHint(min: 0, pref: 5, max: 5), fixedHint(1))
    let inp = newHinted(grow, fixedHint(1))
    f.add lab; f.add inp
    f.arrange(rect(0, 0, 30, 6))
    check lab.bounds == rect(0, 0, 5, 1)   # label column = its pref (5)
    check inp.bounds == rect(6, 0, 24, 1)  # col1x = 5 + spacing 1; width = rest
  test "two rows: widest label sets the column, rows stack":
    let f = newFormLayout(0)
    let l1 = newHinted(SizeHint(min: 0, pref: 3, max: 3), fixedHint(1))
    let i1 = newHinted(grow, fixedHint(1))
    let l2 = newHinted(SizeHint(min: 0, pref: 7, max: 7), fixedHint(1))
    let i2 = newHinted(grow, fixedHint(1))
    f.add l1; f.add i1; f.add l2; f.add i2
    f.arrange(rect(0, 0, 30, 6))
    check l1.bounds == rect(0, 0, 3, 1)    # its own pref, left in the 7-col
    check i1.bounds == rect(7, 0, 23, 1)   # col0 = widest label (7)
    check l2.bounds == rect(0, 1, 7, 1)
    check i2.bounds == rect(7, 1, 23, 1)
