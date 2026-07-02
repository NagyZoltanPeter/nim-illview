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
    dispatchMouse(root, press(7, 5)) # winA title bar: no widget there
    check root.focusedLeaf == View(a2) # remembered, not a1

  test "window consumes mouse; nothing reaches the root":
    dispatchMouse(root, press(7, 5))
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
