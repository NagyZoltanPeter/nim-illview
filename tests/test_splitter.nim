## Phase 20 exit criteria (plan-4): a Splitter lays out two panes around a
## 1-cell handle; the handle drags (absolute, mouse-capture) and nudges with
## Alt+arrows when focused; pane minimums (child hints) clamp the divider.
## No terminal.

import std/unittest
import ../src/illview/core/[geometry, view, events, routing]
import ../src/illview/widgets/splitter

type Box = ref object of View
proc newBox(minMain: int): Box =
  ## A pane with a minimum size on both axes so clamping is observable.
  result = Box()
  initView(result)
  result.hint = (SizeHint(min: minMain, max: high(int)),
                 SizeHint(min: minMain, max: high(int)))

proc mount(axis: Axis, mf, ms, pos, w, h: int): tuple[root: Group, s: Splitter] =
  let root = newGroup()
  root.bounds = rect(0, 0, w, h)
  let s = newSplitter(axis, newBox(mf), newBox(ms), pos = pos)
  s.dock = dkFill
  root.add s
  root.arrangeChildren()
  (root, s)

suite "Splitter layout":
  test "axH places first | handle | second across the width":
    let (_, s) = mount(axH, 5, 5, 8, 20, 10)
    check s.first.bounds == rect(0, 0, 8, 10)
    check s.divider.bounds == rect(8, 0, 1, 10)
    check s.second.bounds == rect(9, 0, 11, 10) # 20 - 8 - 1
  test "axV stacks first / handle / second down the height":
    let (_, s) = mount(axV, 2, 2, 4, 12, 10)
    check s.first.bounds == rect(0, 0, 12, 4)
    check s.divider.bounds == rect(0, 4, 12, 1)
    check s.second.bounds == rect(0, 5, 12, 5) # 10 - 4 - 1
  test "pos 0 centres the divider on first arrange":
    let (_, s) = mount(axH, 0, 0, 0, 21, 10) # avail 20 -> pos 10
    check s.pos == 10

suite "Splitter drag (absolute, mouse-capture)":
  test "dragging the handle moves the divider under the mouse":
    let (root, s) = mount(axH, 5, 5, 8, 20, 10)
    dispatchMouse(root, mouseEvent(maPress, mbLeft, 8, 0)) # grab the handle
    dispatchMouse(root, mouseEvent(maMove, mbLeft, 13, 0))
    check s.pos == 13
    dispatchMouse(root, mouseEvent(maRelease, mbLeft, 13, 0))
  test "drag clamps at both pane minimums":
    let (root, s) = mount(axH, 5, 5, 8, 20, 10) # avail 19, so pos in [5, 14]
    dispatchMouse(root, mouseEvent(maPress, mbLeft, 8, 0))
    dispatchMouse(root, mouseEvent(maMove, mbLeft, 99, 0)) # far right
    check s.pos == 14 # 19 - minSecond(5)
    dispatchMouse(root, mouseEvent(maMove, mbLeft, -99, 0)) # far left
    check s.pos == 5  # minFirst(5)

suite "Splitter keyboard nudge":
  test "Alt+Right / Alt+Left nudge when the divider is focused (axH)":
    let (root, s) = mount(axH, 5, 5, 8, 20, 10)
    setFocus(root, s.divider)
    check dispatchKey(root, keyEvent(Key.Right, mods = {modAlt}))
    check s.pos == 9
    check dispatchKey(root, keyEvent(Key.Left, mods = {modAlt}))
    check s.pos == 8
  test "Alt+Down / Alt+Up nudge on an axV splitter":
    let (root, s) = mount(axV, 2, 2, 4, 12, 10)
    setFocus(root, s.divider)
    check dispatchKey(root, keyEvent(Key.Down, mods = {modAlt}))
    check s.pos == 5
    check dispatchKey(root, keyEvent(Key.Up, mods = {modAlt}))
    check s.pos == 4
  test "wrong-axis Alt-arrow is not consumed by the handle":
    let (root, s) = mount(axH, 5, 5, 8, 20, 10)
    setFocus(root, s.divider)
    check not dispatchKey(root, keyEvent(Key.Up, mods = {modAlt}))
    check s.pos == 8 # unchanged
