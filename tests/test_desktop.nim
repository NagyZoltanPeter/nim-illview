## Phase 21 exit criteria (plan-4): window title-row chrome (close/zoom) with
## hit regions, zoom save/restore, onClose override, and desktop management
## (Alt+N select, tile, cascade). No terminal.

import std/[unittest, unicode]
import ../src/illview/backend/illwill_vendored
import ../src/illview/core/[geometry, view, events, drawcontext, routing]
import ../src/illview/widgets/[desktop, window, button]

proc pressAt(d: Desktop, x, y: int) =
  dispatchMouse(Group(d), mouseEvent(maPress, mbLeft, x, y))

suite "Window title-row chrome":
  test "zoom() fills the parent content, then restores":
    let d = newDesktop(); d.bounds = rect(0, 0, 40, 14)
    let w = newWindow("w", rect(2, 1, 20, 8)); d.add w
    d.arrangeChildren()
    w.zoom()
    check w.bounds == rect(0, 0, 40, 14) # parent clientRect (no desktop border)
    w.zoom()
    check w.bounds == rect(2, 1, 20, 8)  # restored

  test "close() default detaches the window from its parent":
    let d = newDesktop(); d.bounds = rect(0, 0, 40, 14)
    let w = newWindow("w", rect(2, 1, 20, 8)); d.add w
    check d.children.len == 1
    w.close()
    check d.children.len == 0
    check w.parent == nil

  test "onClose override runs instead of the default detach":
    let d = newDesktop(); d.bounds = rect(0, 0, 40, 14)
    let w = newWindow("w", rect(2, 1, 20, 8)); d.add w
    var fired = false
    w.onClose = proc(win: Window) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: fired = true
    w.close()
    check fired
    check d.children.len == 1 # override did not detach

  test "clicking the close box closes the window":
    let d = newDesktop(); d.bounds = rect(0, 0, 40, 14)
    let w = newWindow("w", rect(2, 1, 20, 8)); d.add w
    d.arrangeChildren()
    # close box: content mx 0..2 on the title row (my == -1). Window content
    # origin abs = (3,2); title row abs y = 1; close box abs x = 3..5.
    pressAt(d, 4, 1)
    check d.children.len == 0

  test "clicking the zoom box toggles zoom":
    let d = newDesktop(); d.bounds = rect(0, 0, 40, 14)
    let w = newWindow("w", rect(2, 1, 20, 8)); d.add w
    d.arrangeChildren()
    # zoom box: content mx contentW-3..contentW-1 (18-wide content => 15..17);
    # abs x = 3 + 16 = 19, abs y = 1.
    pressAt(d, 19, 1)
    check w.bounds == rect(0, 0, 40, 14)

  test "chrome glyphs render on the title row":
    let d = newDesktop(); d.bounds = rect(0, 0, 30, 10)
    let w = newWindow("t", rect(0, 0, 20, 6)); d.add w
    d.arrange(rect(0, 0, 30, 10))
    let tb = newTerminalBuffer(30, 10)
    d.draw(initDrawContext(tb))
    check $tb[1, 0].ch & $tb[2, 0].ch & $tb[3, 0].ch == "[■]"    # close box, left
    check $tb[16, 0].ch & $tb[17, 0].ch & $tb[18, 0].ch == "[↑]" # zoom box, right

suite "Desktop window management":
  proc threeWindows(): Desktop =
    result = newDesktop(); result.bounds = rect(0, 0, 40, 14)
    for i in 1 .. 3:
      let w = newWindow("w" & $i, rect(0, 0, 10, 5))
      w.add newButton("ok") # a focusable child so selection can focus in
      result.add w
    result.arrangeChildren()

  test "selectWindow raises and activates":
    let d = threeWindows()
    let target = d.children[0] # bottom of the z-order
    d.selectWindow(0)
    check d.children[^1] == target # raised to the top
    check d.focused == target      # activated

  test "Alt+2 selects the second window":
    let d = threeWindows()
    let second = d.children[1]
    check dispatchKey(Group(d), keyEvent(Key.None, Rune(ord('2')), {modAlt}))
    check d.focused == second

  test "tile lays a non-overlapping grid":
    let d = threeWindows()
    d.tile()
    let ws = d.floatingWindows
    # 3 windows => 2 cols x 2 rows, cell 20x7
    check ws[0].bounds == rect(0, 0, 20, 7)
    check ws[1].bounds == rect(20, 0, 20, 7)
    check ws[2].bounds == rect(0, 7, 20, 7)

  test "cascade offsets the windows diagonally":
    let d = threeWindows()
    d.cascade()
    let ws = d.floatingWindows
    # ww = 26, wh = 9; each offset by (2,1)
    check ws[0].bounds == rect(0, 0, 26, 9)
    check ws[1].bounds == rect(2, 1, 26, 9)
    check ws[2].bounds == rect(4, 2, 26, 9)
