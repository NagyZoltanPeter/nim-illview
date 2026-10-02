## Phase 18 exit criteria (plan-4 D15 + mouse infra): thumb geometry math,
## ScrollBar wheel/page/drag behavior, list/table/textview indicator columns,
## and the double-click synthesis (nextClicks + routing forwarding). No
## terminal — widgets render into an off-screen TerminalBuffer.

import std/[unittest, unicode]
import chronos
import ../src/illview/backend/illwill_vendored
import ../src/illview/core/[geometry, view, events, drawcontext, routing, app]
import ../src/illview/widgets/[scrollbar, list, textview, table]

proc renderView(v: View, w, h: int): TerminalBuffer =
  result = newTerminalBuffer(w, h)
  v.bounds = rect(0, 0, w, h)
  v.draw(initDrawContext(result))

proc colStr(tb: TerminalBuffer, x, h: int): string =
  for y in 0 ..< h: result.add $tb[x, y].ch

proc cellStr(tb: TerminalBuffer, x, y: int): string = $tb[x, y].ch

proc wheel(a: MouseAction): Event =
  Event(kind: evMouse, imouse: mouseEvent(a, mbNone, 0, 0))

proc at(a: MouseAction, x, y: int): Event =
  Event(kind: evMouse, imouse: mouseEvent(a, mbLeft, x, y))

suite "thumbGeom (pure scroll math)":
  test "no scroll needed => full rail":
    check thumbGeom(10, 5, 10, 0) == (0, 10) # page >= total
    check thumbGeom(0, 100, 10, 0) == (0, 0) # empty track
  test "proportional length and position":
    check thumbGeom(10, 20, 10, 0) == (0, 5)   # len 5, at top
    check thumbGeom(10, 20, 10, 10) == (5, 5)  # scrollMax 10, pos 10 => start 5
    check thumbGeom(10, 20, 10, 5) == (2, 5)   # mid
  test "thumb never shorter than one cell":
    check thumbGeom(4, 100, 4, 0).len == 1

suite "TV scrollbar glyphs (deviation #35)":
  test "arrows at the ends, ▒ rail, one ■ thumb":
    check scrollGlyphs(6, 100, 10, 0, axV) == @["▲", "■", "▒", "▒", "▒", "▼"]
    check scrollGlyphs(6, 100, 10, 90, axV) == @["▲", "▒", "▒", "▒", "■", "▼"]
    check scrollGlyphs(5, 100, 10, 0, axH) == @["◄", "■", "▒", "▒", "►"]
  test "a rail too short for arrows is thumb + rail only":
    check scrollGlyphs(2, 100, 10, 90, axV) == @["▒", "■"]
    check scrollGlyphs(0, 100, 10, 0, axV).len == 0
  test "nothing to scroll: thumb parked at the start":
    check thumbCell(10, 5, 10, 0) == 0

suite "ScrollBar behavior":
  test "setRange clamps pos; setPos fires onScroll once":
    var got: seq[int]
    let sb = newScrollBar(axV)
    sb.onScroll = proc(p: int) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: got.add p
    sb.setRange(total = 100, page = 10) # scrollMax 90
    sb.setPos(200)                       # clamps to 90
    check sb.pos == 90
    check got == @[90]
    sb.setPos(90)                        # unchanged: no re-emit
    check got == @[90]

  test "wheel scrolls by one in each direction":
    let sb = newScrollBar(axV)
    sb.setRange(100, 10, 0)
    check sb.handleEvent(wheel(maWheelDown))
    check sb.pos == 1
    check sb.handleEvent(wheel(maWheelUp))
    check sb.pos == 0

  test "click past the thumb pages toward it":
    let sb = newScrollBar(axV)
    sb.bounds = rect(0, 0, 1, 10)
    sb.setRange(100, 10, 0) # thumb len 1 at top
    check sb.handleEvent(at(maPress, 0, 5)) # below thumb => page down by 10
    check sb.pos == 10

  test "arrows step by one":
    let sb = newScrollBar(axV)
    sb.bounds = rect(0, 0, 1, 10)
    sb.setRange(100, 10, 5)
    check sb.handleEvent(at(maPress, 0, 9)) # ▼
    check sb.pos == 6
    check sb.handleEvent(at(maPress, 0, 0)) # ▲
    check sb.pos == 5

  test "dragging the thumb sets pos proportionally":
    let sb = newScrollBar(axV)
    sb.bounds = rect(0, 0, 1, 10)
    sb.setRange(100, 10, 0) # ■ at cell 1; rail cells 1..8 = 8 positions
    check sb.handleEvent(at(maPress, 0, 1))       # grab the thumb
    check sb.handleEvent(at(maMove, 0, 8))        # drag to the last rail cell
    check sb.pos == 90
    check sb.handleEvent(at(maRelease, 0, 8))

  test "draw renders arrows, rail and thumb":
    let sb = newScrollBar(axV)
    sb.setRange(20, 10, 0)
    let tb = renderView(sb, 1, 10)
    check colStr(tb, 0, 10) == "▲■▒▒▒▒▒▒▒▼"

suite "ScrollBar keyboard (deviation #37 follow-up)":
  proc key(k: Key, mods: set[Modifier] = {}): Event =
    Event(kind: evKey, ikey: keyEvent(k, Rune(0), mods))

  test "vertical: arrows step, PgUp/PgDn page, Home/End jump":
    let sb = newScrollBar(axV)
    sb.setRange(100, 10, 50)
    check sb.handleEvent(key(Key.Down)) and sb.pos == 51
    check sb.handleEvent(key(Key.Up)) and sb.pos == 50
    check sb.handleEvent(key(Key.PageDown)) and sb.pos == 60
    check sb.handleEvent(key(Key.PageUp)) and sb.pos == 50
    check sb.handleEvent(key(Key.End)) and sb.pos == 90
    check sb.handleEvent(key(Key.Home)) and sb.pos == 0
    check not sb.handleEvent(key(Key.Left))   # cross-axis key bubbles on

  test "horizontal uses Left/Right; Alt-chords pass through":
    let sb = newScrollBar(axH)
    sb.setRange(100, 10, 5)
    check sb.handleEvent(key(Key.Right)) and sb.pos == 6
    check sb.handleEvent(key(Key.Left)) and sb.pos == 5
    check not sb.handleEvent(key(Key.Up))
    check not sb.handleEvent(key(Key.Right, {modAlt}))
    check sb.pos == 5

  test "focusable: Tab reaches it and keys route to it":
    let root = newGroup()
    root.bounds = rect(0, 0, 20, 10)
    let sb = newScrollBar(axV)
    sb.bounds = rect(0, 0, 1, 10)
    sb.setRange(100, 10, 0)
    root.add sb
    focusNext(root)
    check root.focusedLeaf == View(sb)
    check dispatchKey(root, keyEvent(Key.Down))
    check sb.pos == 1

suite "widget scrollbar indicators":
  test "ListView draws a thumb in the last column when overflowing":
    let l = newListView()
    l.showScrollbar = true
    var items: seq[string]
    for i in 0 .. 19: items.add "item" & $i
    l.setItems(items)
    let tb = renderView(l, 10, 5) # 20 items, 5 rows => overflow
    check colStr(tb, 9, 5) == "▲■▒▒▼" # top of the list

  test "TextView indicator tracks the viewport":
    let tv = newTextView()
    tv.showScrollbar = true
    for i in 0 .. 19: tv.addLine("line" & $i)
    let tb = renderView(tv, 10, 5) # follow => pinned to bottom
    # follow: start = 20-5 = 15 = scrollMax => thumb on the last rail cell
    check colStr(tb, 9, 5) == "▲▒▒■▼"

  test "Table reserves the last column for the thumb below the header":
    let cols = @[tableColumn("A", prefHint(4)), tableColumn("B", prefHint(4))]
    var rows: seq[seq[string]]
    for i in 0 .. 19: rows.add @["a" & $i, "b" & $i]
    let t = newTable(cols, rows)
    t.showScrollbar = true
    let tb = renderView(t, 12, 5) # viewportRows 4, 20 rows => overflow
    check cellStr(tb, 11, 1) == "▲" # bar starts on the first data row (y1)
    check cellStr(tb, 11, 2) == "■"
    check cellStr(tb, 11, 4) == "▼"

# --- double-click synthesis (plan-4 mouse infra) ------------------------------

type ClickProbe = ref object of View
  lastClicks: int

method handleEvent(p: ClickProbe, ev: Event): bool {.gcsafe, raises: [].} =
  if ev.kind == evMouse and ev.imouse.action == maPress:
    p.lastClicks = ev.clicks
  true

suite "double-click synthesis":
  test "nextClicks: increments within window+cell, resets otherwise":
    let base = Moment.now()
    let last = (t: base, x: 5, y: 5, button: mbLeft, count: 1)
    check nextClicks(last, base + 200.milliseconds, 5, 5, mbLeft) == 2
    check nextClicks(last, base + 400.milliseconds, 5, 5, mbLeft) == 1 # too slow
    check nextClicks(last, base + 100.milliseconds, 9, 9, mbLeft) == 1 # moved
    check nextClicks(last, base + 100.milliseconds, 5, 5, mbRight) == 1 # other btn

  test "routing forwards the click count onto the framework Event":
    let root = newGroup()
    root.bounds = rect(0, 0, 10, 10)
    let probe = ClickProbe()
    initView(probe)
    probe.bounds = rect(0, 0, 10, 10)
    probe.focusable = true
    root.add probe
    dispatchMouse(root, mouseEvent(maPress, mbLeft, 2, 2), clicks = 2)
    check probe.lastClicks == 2
    dispatchMouse(root, mouseEvent(maPress, mbLeft, 2, 2)) # default single
    check probe.lastClicks == 1
