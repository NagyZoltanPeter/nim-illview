## Phase 2 exit criteria: synthetic mouse coords hit the correct topmost
## view; Tab order is correct; unhandled keys bubble to the scope root.
## Pure view-tree logic — no terminal, no chronos.

import std/unittest
import ../src/illview/core/[geometry, events, view, routing]
import ../src/illview/widgets/[desktop, window]

type
  Probe = ref object of View
    ## Focusable test widget recording every event it receives.
    name: string
    got: seq[Event]
    consumeKeys: seq[Key] # which keys it consumes

  RecordingRoot = ref object of Group
    got: seq[Event]

proc newProbe(name: string, bounds: Rect): Probe =
  result = Probe(name: name)
  initView(result)
  result.bounds = bounds
  result.focusable = true

method handleEvent(p: Probe, ev: Event): bool =
  p.got.add ev
  case ev.kind
  of evMouse:
    ev.imouse.action == maPress # consume presses, let moves bubble
  of evKey:
    ev.ikey.key in p.consumeKeys
  else:
    false

method handleEvent(r: RecordingRoot, ev: Event): bool =
  r.got.add ev
  false

proc newRecordingRoot(w, h: int): RecordingRoot =
  result = RecordingRoot()
  initView(result)
  result.bounds = rect(0, 0, w, h)

proc press(x, y: int): InputEvent =
  mouseEvent(maPress, mbLeft, x, y)

proc mouseGot(p: Probe): seq[Event] =
  ## Probes also record focus events; keep only the mouse ones.
  for ev in p.got:
    if ev.kind == evMouse:
      result.add ev

proc key(k: Key, mods: set[Modifier] = {}): InputEvent =
  keyEvent(k, mods = mods)

suite "routing: mouse hit-testing":
  # layout used below:
  #   root 80x24
  #     winA (5,5,30,10)   content origin abs (6,6)
  #       a1 (2,1,10,1) -> abs x 8..17, y 7
  #       a2 (2,3,10,1) -> abs x 8..17, y 9
  #     winB (20,10,30,10) content origin abs (21,11), overlaps winA
  #       b1 (2,1,10,1) -> abs x 23..32, y 12
  setup:
    let root = newRecordingRoot(80, 24)
    let winA = newWindow("A", rect(5, 5, 30, 10))
    let a1 = newProbe("a1", rect(2, 1, 10, 1))
    let a2 = newProbe("a2", rect(2, 3, 10, 1))
    winA.add a1
    winA.add a2
    let winB = newWindow("B", rect(20, 10, 30, 10))
    let b1 = newProbe("b1", rect(2, 1, 10, 1))
    winB.add b1
    root.add winA
    root.add winB

  test "click hits the widget, coords are target-local":
    dispatchMouse(root, press(10, 7)) # inside a1
    check a1.mouseGot.len == 1
    check a1.mouseGot[0].imouse.mx == 2 # 10 - abs origin 8
    check a1.mouseGot[0].imouse.my == 0

  test "click sets focus and raises the window":
    dispatchMouse(root, press(10, 7))
    check root.focusedLeaf == View(a1)
    check root.children[^1] == View(winA) # raised above winB

  test "topmost window wins in the overlap":
    # (23,12) is inside b1 and also within winA's rect (x 5..34, y 5..14).
    # winB is topmost -> b1 must get it, winA's children must not.
    dispatchMouse(root, press(23, 12))
    check b1.mouseGot.len == 1
    check a1.mouseGot.len == 0
    check a2.mouseGot.len == 0

  test "frame click focuses into the window (remembered child)":
    dispatchMouse(root, press(10, 9)) # focus a2 first (raises winA)
    check root.focusedLeaf == View(a2)
    # winB content background, outside the (now covered) overlap: no widget
    # there and winB itself is not focusable -> focus falls into b1
    dispatchMouse(root, press(40, 12))
    check root.focusedLeaf == View(b1)
    dispatchMouse(root, press(11, 5)) # winA title bar, clear of close/zoom boxes
    check root.focusedLeaf == View(a2) # remembered, not a1

  test "window consumes mouse; nothing reaches the root":
    dispatchMouse(root, press(11, 5)) # title bar, clear of the close/zoom boxes
    check root.got.len == 0

  test "click on empty desktop reaches the root":
    dispatchMouse(root, press(70, 2))
    check root.got.len == 1
    check root.got[0].kind == evMouse

suite "routing: keys, focus traversal, bubbling":
  setup:
    let root = newRecordingRoot(80, 24)
    let winA = newWindow("A", rect(5, 5, 30, 10))
    let a1 = newProbe("a1", rect(2, 1, 10, 1))
    let a2 = newProbe("a2", rect(2, 3, 10, 1))
    winA.add a1
    winA.add a2
    let winB = newWindow("B", rect(20, 10, 30, 10))
    let b1 = newProbe("b1", rect(2, 1, 10, 1))
    winB.add b1
    root.add winA
    root.add winB

  test "Tab cycles focusable views in tree order, wraps":
    check dispatchKey(root, key(Key.Tab)) # nothing focused -> first
    check root.focusedLeaf == View(a1)
    check dispatchKey(root, key(Key.Tab))
    check root.focusedLeaf == View(a2)
    check dispatchKey(root, key(Key.Tab))
    check root.focusedLeaf == View(b1)
    check dispatchKey(root, key(Key.Tab)) # wrap
    check root.focusedLeaf == View(a1)

  test "Shift-Tab goes backwards, wraps":
    setFocus(root, a1)
    check dispatchKey(root, key(Key.Tab, {modShift}))
    check root.focusedLeaf == View(b1)
    check dispatchKey(root, key(Key.Tab, {modShift}))
    check root.focusedLeaf == View(a2)

  test "disabled and invisible views are skipped":
    a2.enabled = false
    setFocus(root, a1)
    discard dispatchKey(root, key(Key.Tab))
    check root.focusedLeaf == View(b1)
    b1.visible = false
    discard dispatchKey(root, key(Key.Tab))
    check root.focusedLeaf == View(a1)

  test "consumed key stops at the focused view":
    a1.consumeKeys = @[Key.Enter]
    setFocus(root, a1)
    check dispatchKey(root, key(Key.Enter))
    check root.got.len == 0

  test "unhandled key bubbles to the scope root":
    setFocus(root, a1)
    check not dispatchKey(root, key(Key.Q))
    check root.got.len == 1
    check root.got[0].kind == evKey
    check root.got[0].ikey.key == Key.Q

  test "focus change fires evFocusLost / evFocusGained":
    setFocus(root, a1)
    setFocus(root, a2)
    check a1.got[^1].kind == evFocusLost
    check a2.got[^1].kind == evFocusGained

suite "routing: border-inset coordinates (iteration 2)":
  test "bordered group: content clicks are content-local, frame clicks hit the group":
    let root = newRecordingRoot(40, 20)
    let box = newGroup()
    box.border = bkSingle
    box.bounds = rect(10, 10, 10, 4)
    let p1 = newProbe("p1", rect(0, 0, 5, 1)) # content abs (11,11)
    box.add p1
    root.add box
    var (target, local) = hitTest(root, point(11, 11))
    check target == View(p1)
    check local == point(0, 0)
    (target, local) = hitTest(root, point(13, 11))
    check local == point(2, 0)
    # top border cell: no child there; the group gets it with y == -1
    (target, local) = hitTest(root, point(12, 10))
    check target == View(box)
    check local == point(1, -1)

  test "mouse capture routes moves/release to the captor, then auto-clears":
    let root = newRecordingRoot(40, 20)
    let p = newProbe("p", rect(5, 5, 5, 1))
    root.add p
    p.captureMouse()
    check root.mouseCapture == View(p)
    # a held-button move (real drag) far outside p still reaches p
    dispatchMouse(root, mouseEvent(maMove, mbLeft, 30, 15))
    check p.mouseGot.len == 1
    check p.mouseGot[0].imouse.mx == 25
    check p.mouseGot[0].imouse.my == 10
    dispatchMouse(root, mouseEvent(maRelease, mbLeft, 30, 15))
    check root.mouseCapture == nil

  test "clicking a docked child does not reorder it (bars stay put)":
    let root = newRecordingRoot(40, 20)
    let bar1 = newProbe("bar1", rect(0, 0, 40, 1)); bar1.dock = dkTop
    let bar2 = newProbe("bar2", rect(0, 1, 40, 1)); bar2.dock = dkTop
    root.add bar1
    root.add bar2
    dispatchMouse(root, press(5, 0)) # click the top (menu-bar-like) docked child
    check root.children[0] == View(bar1) # NOT raised to the end -> no visual swap
    check root.children[1] == View(bar2)

  test "a no-button move ends the drag (1003 implicit release)":
    let root = newRecordingRoot(40, 20)
    let p = newProbe("p", rect(5, 5, 5, 1))
    root.add p
    p.captureMouse()
    dispatchMouse(root, mouseEvent(maMove, mbLeft, 20, 10)) # held: continues
    check root.mouseCapture == View(p)
    dispatchMouse(root, mouseEvent(maMove, mbNone, 22, 10)) # button up => ends
    check root.mouseCapture == nil
    # after release, normal routing resumes
    dispatchMouse(root, press(30, 15))
    check p.mouseGot.len == 2 # only the capture move + release... press missed p
    check root.got.len == 1   # press went to the root background

suite "window move/resize (phase 10)":
  setup:
    let root = newRecordingRoot(80, 24)
    let win = newWindow("W", rect(5, 5, 20, 10))
    let p = newProbe("p", rect(0, 0, 5, 1))
    win.add p
    root.add win

  test "Alt+Arrows move; Alt+Shift+Arrows resize; min size clamps":
    setFocus(root, p)
    check dispatchKey(root, keyEvent(Key.Right, mods = {modAlt}))
    check win.bounds == rect(6, 5, 20, 10)
    check dispatchKey(root, keyEvent(Key.Down, mods = {modAlt}))
    check win.bounds.y == 6
    check dispatchKey(root, keyEvent(Key.Right, mods = {modAlt, modShift}))
    check win.bounds.w == 21
    for _ in 1 .. 30:
      discard dispatchKey(root, keyEvent(Key.Left, mods = {modAlt, modShift}))
      discard dispatchKey(root, keyEvent(Key.Up, mods = {modAlt, modShift}))
    check win.bounds.w == 8 # MinW
    check win.bounds.h == 3 # MinH

  test "docked windows are layout-owned: move/resize ignored":
    win.dock = dkFill
    setFocus(root, p)
    check not dispatchKey(root, keyEvent(Key.Right, mods = {modAlt}))
    check win.bounds == rect(5, 5, 20, 10)

  test "title drag moves the window; capture ends on release":
    dispatchMouse(root, press(10, 5)) # top border row: content-local y == -1
    check root.mouseCapture == View(win)
    dispatchMouse(root, mouseEvent(maMove, mbLeft, 15, 8)) # +5, +3
    check win.bounds.x == 10
    check win.bounds.y == 8
    dispatchMouse(root, mouseEvent(maRelease, mbLeft, 15, 8))
    check root.mouseCapture == nil

  test "corner drag resizes; clamps at minimum":
    dispatchMouse(root, press(24, 14)) # bottom-right corner cell
    check root.mouseCapture == View(win)
    dispatchMouse(root, mouseEvent(maMove, mbLeft, 30, 18))
    check win.bounds.w == 26
    check win.bounds.h == 14
    dispatchMouse(root, mouseEvent(maMove, mbLeft, 2, 2))
    check win.bounds.w == 8
    check win.bounds.h == 3
    dispatchMouse(root, mouseEvent(maRelease, mbLeft, 2, 2))
    check root.mouseCapture == nil

  test "content clicks do not start a drag":
    dispatchMouse(root, press(12, 12)) # inside the content area
    check root.mouseCapture == nil
