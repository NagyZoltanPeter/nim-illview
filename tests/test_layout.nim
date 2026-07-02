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
