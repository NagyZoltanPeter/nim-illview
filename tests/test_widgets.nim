## Phase 4 exit criteria: snapshot tests for list scroll, input horizontal
## scroll, textview viewport, editor cursor/edit; closure slots fire inside
## dispatch; command-bearing widgets publish to the StubBus. No terminal.

import std/[unittest, strformat, unicode, strutils]
import chronos
import ../src/illview/backend/illwill_vendored
import ../src/illview/vocab
import ../src/illview/core/[geometry, theme, drawcontext, events, bus, view, routing]
import ../src/illview/widgets/[button, checkbox, radio, list, input, textview,
                               editor, statusbar, menu, groupbox, table,
                               progress, label, sparkline, tristate,
                               controlbar, scrollbar, window]
import ../src/illview/layout/layout

proc rowStr(tb: TerminalBuffer, y, w: int): string =
  for x in 0 ..< w:
    result.add $tb[x, y].ch

proc renderInto(v: View, w, h: int): TerminalBuffer =
  ## Arrange + draw a single widget at (0,0,w,h) into a fresh buffer.
  result = newTerminalBuffer(w, h)
  v.arrange(rect(0, 0, w, h))
  v.draw(initDrawContext(result))

proc keyEv(k: Key, r = Rune(0)): Event =
  Event(kind: evKey, ikey: keyEvent(k, r))

suite "slots + stub bus":
  setup:
    let root = newGroup()
    root.bounds = rect(0, 0, 40, 10)
    let stub = newStubBus()
    root.publishCb = proc(a: UiAction) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: # single-threaded test; suite vars are globals
        stub.publish(a)

  test "button: onClick fires inside dispatch, command publishes":
    var clicked = 0
    let b = newButton("Run", command = Command(42))
    b.onClick = proc(sender: Button) {.gcsafe, raises: [].} = inc clicked
    root.add b
    b.arrange(rect(0, 0, 9, 1)) # give it bounds so the mouse can hit it
    setFocus(root, b)
    check dispatchKey(root, keyEvent(Key.Enter))
    check clicked == 1
    check stub.actions.len == 1
    check stub.actions[0].cmd == Command(42)
    check stub.actions[0].senderId == b.id
    # mouse activation too
    dispatchMouse(root, mouseEvent(maPress, mbLeft, 1, 0))
    check clicked == 2
    check stub.actions.len == 2

  test "checkbox: onToggle + state":
    var toggles: seq[bool]
    let c = newCheckbox("opt")
    c.onToggle = proc(sender: Checkbox) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        toggles.add sender.checked
    root.add c
    setFocus(root, c)
    discard dispatchKey(root, keyEvent(Key.Space))
    discard dispatchKey(root, keyEvent(Key.Space))
    check toggles == @[true, false]

  test "radio: exclusive selection via keys, onSelect":
    var sels: seq[int]
    let r = newRadio(@["a", "b", "c"])
    r.onSelect = proc(sender: Radio) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        sels.add sender.selected
    root.add r
    setFocus(root, r)
    discard dispatchKey(root, keyEvent(Key.Down))
    discard dispatchKey(root, keyEvent(Key.Down))
    discard dispatchKey(root, keyEvent(Key.Up))
    check sels == @[1, 2, 1]
    check r.selected == 1

  test "input: onChange/onSubmit/onFocus/onBlur are distinct":
    var log: seq[string]
    let inp = newInput()
    inp.onChange = proc(s: Input) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: log.add "change:" & s.text
    inp.onSubmit = proc(s: Input) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: log.add "submit:" & s.text
    inp.onFocus = proc(s: Input) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: log.add "focus"
    inp.onBlur = proc(s: Input) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: log.add "blur"
    let other = newButton("x")
    root.add inp
    root.add other
    setFocus(root, inp)
    discard dispatchKey(root, keyEvent(Key.H, Rune('h')))
    discard dispatchKey(root, keyEvent(Key.I, Rune('i')))
    discard dispatchKey(root, keyEvent(Key.Enter))
    setFocus(root, other)
    check log == @["focus", "change:h", "change:hi", "submit:hi", "blur"]

  test "menu popup: item publishes command through the bar's root":
    var modalOpened: Group
    root.runModalCb = proc(g: Group) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        modalOpened = g
        root.add g
    root.endModalCb = proc(cmd: Command) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        root.remove modalOpened
    let mb = newMenuBar(@[
      menu("File", @[menuItem("Open", Command(1)), menuItem("Quit", Command(2))])])
    mb.bounds = rect(0, 0, 40, 1)
    root.add mb
    mb.openMenu(0)
    check modalOpened != nil
    discard modalOpened.handleEvent(keyEv(Key.Down))
    discard modalOpened.handleEvent(keyEv(Key.Enter))
    check stub.actions.len == 1
    check stub.actions[0].cmd == Command(2) # "Quit"
    check modalOpened.parent == nil # popup removed on activation

  test "statusbar: clicking an item publishes its command":
    let sb = newStatusBar(@[statusItem("F10 Menu", Command(7)),
                            statusItem("Esc Quit", Command(8))])
    root.add sb
    sb.arrange(rect(0, 9, 40, 1))
    # second item starts after " F10 Menu " + gap
    let ev = Event(kind: evMouse,
                   imouse: mouseEvent(maPress, mbLeft, 13, 0))
    check sb.handleEvent(ev)
    check stub.actions.len == 1
    check stub.actions[0].cmd == Command(8)

suite "list viewport (snapshot)":
  test "selection past the bottom scrolls the viewport":
    var items: seq[string]
    for i in 1 .. 10:
      items.add &"item{i:02}"
    let l = newListView(items)
    var tb = renderInto(l, 8, 3)
    check rowStr(tb, 0, 6) == "item01"
    check rowStr(tb, 2, 6) == "item03"
    for _ in 1 .. 4: # select down to item05: viewport must follow
      discard l.handleEvent(keyEv(Key.Down))
    tb = renderInto(l, 8, 3)
    check rowStr(tb, 0, 6) == "item03"
    check rowStr(tb, 2, 6) == "item05"
    check l.selected == 4
    # End jumps to the last item
    discard l.handleEvent(keyEv(Key.End))
    tb = renderInto(l, 8, 3)
    check rowStr(tb, 2, 6) == "item10"

  test "wheel scrolls without moving the selection":
    var items: seq[string]
    for i in 1 .. 10:
      items.add &"item{i:02}"
    let l = newListView(items)
    discard l.renderInto(8, 3)
    let wheel = Event(kind: evMouse,
                      imouse: mouseEvent(maWheelDown, mbNone, 0, 0))
    check l.handleEvent(wheel)
    check l.top == 1
    check l.selected == 0

suite "input horizontal scroll (snapshot)":
  test "typing past the width keeps the cursor visible":
    let inp = newInput("abcdefghij") # cursor at end (10)
    let tb = renderInto(inp, 5, 1)
    # window of width 5 ending at the cursor cell: shows "ghij" + cursor
    check rowStr(tb, 0, 5) == "ghij "
    check inp.scrollX == 6
    # jump home: viewport snaps back
    discard inp.handleEvent(keyEv(Key.Home))
    let tb2 = renderInto(inp, 5, 1)
    check rowStr(tb2, 0, 5) == "abcde"

suite "textview viewport (snapshot)":
  test "follow pins to bottom; cap drops oldest":
    let tv = newTextView(maxLines = 5)
    for i in 1 .. 7:
      tv.addLine &"line{i}"
    check tv.lines.len == 5 # 3..7 kept
    let tb = renderInto(tv, 8, 3)
    check rowStr(tb, 0, 5) == "line5"
    check rowStr(tb, 2, 5) == "line7"

  test "scrolling up unpins; End re-pins":
    let tv = newTextView()
    for i in 1 .. 9:
      tv.addLine &"line{i}"
    discard tv.renderInto(8, 3) # arrange first
    discard tv.handleEvent(keyEv(Key.PageUp))
    check not tv.follow
    let tb = renderInto(tv, 8, 3)
    check rowStr(tb, 0, 5) == "line4"
    discard tv.handleEvent(keyEv(Key.End))
    check tv.follow

suite "editor (snapshot)":
  test "cursor movement, insert, newline split, join":
    let e = newEditor("hello\nworld")
    discard e.renderInto(10, 4)
    check e.text == "hello\nworld"
    # move to end of "hello", split there -> no change in text w/ newline?
    discard e.handleEvent(keyEv(Key.End))
    discard e.handleEvent(keyEv(Key.X, Rune('!')))
    check e.text == "hello!\nworld"
    discard e.handleEvent(keyEv(Key.Enter))
    check e.text == "hello!\n\nworld"
    discard e.handleEvent(keyEv(Key.Backspace)) # join back
    check e.text == "hello!\nworld"
    # go to start of "world"; Left wraps to previous line end
    discard e.handleEvent(keyEv(Key.Down))
    discard e.handleEvent(keyEv(Key.Home))
    discard e.handleEvent(keyEv(Key.Left))
    check e.curLine == 0
    check e.curCol == 6

  test "two-axis scrolling keeps the cursor visible":
    var text = ""
    for i in 1 .. 8:
      text.add &"row{i}-abcdefghijklmnop\n"
    let e = newEditor(text)
    e.curLine = 0
    e.curCol = 0
    # jump to line 7, column end
    for _ in 1 .. 7:
      discard e.handleEvent(keyEv(Key.Down))
    discard e.handleEvent(keyEv(Key.End))
    let tb = renderInto(e, 6, 3)
    check e.scrollY == 5 # line 7 visible in a 3-row viewport
    check e.scrollX > 0  # horizontally scrolled to the line end

  test "onChange fires for edits only":
    var changes = 0
    let e = newEditor("ab")
    e.onChange = proc(s: Editor) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: inc changes
    discard e.handleEvent(keyEv(Key.Right))
    check changes == 0
    discard e.handleEvent(keyEv(Key.X, Rune('x')))
    discard e.handleEvent(keyEv(Key.Backspace))
    check changes == 2

suite "groupbox (iteration 2)":
  test "border + title + inset children, drawn by the parent":
    let root = newGroup()
    root.bounds = rect(0, 0, 20, 8)
    let gb = newGroupBox("opts")
    gb.border = bkSingle # optional frame (deviation #34: borderless default)
    gb.bounds = rect(1, 1, 14, 5)
    gb.add newLabel("inside")
    gb.children[0].bounds = rect(0, 0, 6, 1)
    root.add gb
    let tb = newTerminalBuffer(20, 8)
    root.draw(initDrawContext(tb))
    check rowStr(tb, 1, 16).contains(" opts ")
    check $tb[1, 1].ch == "┌"
    check $tb[14, 1].ch == "┐"
    # label content starts at gb content origin abs (2,2)
    check rowStr(tb, 2, 16).contains("inside")
    check $tb[2, 2].ch == "i"

  test "borderless default: heading row above a cluster-filled block":
    let root = newGroup()
    root.theme = defaultTheme()
    root.bounds = rect(0, 0, 20, 8)
    let gb = newGroupBox("opts")
    gb.hint = (fixedHint(10), fixedHint(2))
    check gb.border == bkNone
    check gb.measure().h == fixedHint(3) # heading + 2 content rows
    gb.bounds = rect(1, 1, 10, 3)
    gb.add newLabel("in")
    gb.children[0].bounds = rect(0, 0, 2, 1)
    root.add gb
    let tb = newTerminalBuffer(20, 8)
    root.draw(initDrawContext(tb))
    check rowStr(tb, 1, 6) == " opts "  # heading at the group's top row
    check rowStr(tb, 2, 4) == " in "    # content starts one row lower
    let cluster = defaultTheme().style(tkCluster).bg
    check tb[5, 3].bg == cluster         # empty content cell: cluster fill
    check tb[5, 1].bg != cluster         # heading row: not the block
suite "table (iteration 2)":
  setup:
    var rows: seq[seq[string]]
    for i in 1 .. 10:
      rows.add @[&"row{i:02}", &"val{i:02}"]
    let t = newTable(@[
      tableColumn("id", fixedHint(6)),
      tableColumn("value", prefHint(0, stretch = 1))], rows)

  test "header + column widths via distribute":
    let tb = renderInto(t, 16, 4)
    check rowStr(tb, 0, 6) == "id    "
    check rowStr(tb, 0, 12).contains("value")
    check rowStr(tb, 1, 6) == "row01 "
    # second column starts after fixed 6 + 1 spacing
    check rowStr(tb, 1, 13).contains("val01")

  test "selection scrolls the viewport (header stays)":
    discard renderInto(t, 16, 4) # 3 data rows visible
    for _ in 1 .. 5:
      discard t.handleEvent(keyEv(Key.Down))
    check t.selected == 5
    let tb = renderInto(t, 16, 4)
    check rowStr(tb, 0, 2) == "id" # header pinned
    check rowStr(tb, 1, 6).contains("row04")
    check rowStr(tb, 3, 6).contains("row06")

  test "mouse: click selects (header ignored), re-click activates":
    var acts: seq[int]
    t.onActivate = proc(s: Table) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: acts.add s.selected
    discard renderInto(t, 16, 4)
    let press1 = Event(kind: evMouse, imouse: mouseEvent(maPress, mbLeft, 2, 2))
    check t.handleEvent(press1)
    check t.selected == 1 # data row under y=2
    check t.handleEvent(press1) # same row again -> activate
    check acts == @[1]
    let hdr = Event(kind: evMouse, imouse: mouseEvent(maPress, mbLeft, 2, 0))
    check t.handleEvent(hdr)
    check t.selected == 1 # header click changes nothing

suite "progressbar (iteration 2)":
  test "fill at 0 / 50 / 100 percent":
    let p = newProgressBar(maxValue = 100, showPercent = false)
    p.setValue(0)
    var tb = renderInto(p, 10, 1)
    check rowStr(tb, 0, 10) == repeat("░", 10)
    p.setValue(50)
    tb = renderInto(p, 10, 1)
    check rowStr(tb, 0, 10) == repeat("█", 5) & repeat("░", 5)
    p.setValue(100)
    tb = renderInto(p, 10, 1)
    check rowStr(tb, 0, 10) == repeat("█", 10)

  test "percent label centered":
    let p = newProgressBar(maxValue = 100)
    p.setValue(40)
    let tb = renderInto(p, 12, 1)
    check rowStr(tb, 0, 12).contains(" 40% ")
    check p.value == 40

# --- console widgets (deviation #30) -----------------------------------------------

suite "live-data widgets (deviation #30)":
  test "Table.setRows keeps the selection and viewport; clamps when shorter":
    var rows: seq[seq[string]]
    for i in 1 .. 10:
      rows.add @[&"row{i:02}", &"val{i:02}"]
    let t = newTable(@[tableColumn("id", fixedHint(6)),
                       tableColumn("value", prefHint(0, stretch = 1))], rows)
    discard renderInto(t, 16, 4) # 3 data rows visible
    for _ in 1 .. 5:
      discard t.handleEvent(keyEv(Key.Down))
    check t.selected == 5
    check t.top == 3
    var fresh: seq[seq[string]]
    for i in 1 .. 10:
      fresh.add @[&"new{i:02}", "x"]
    t.setRows(fresh)              # a refresh must not jump to the top
    check t.selected == 5
    check t.top == 3
    t.setRows(fresh[0 .. 1])      # shorter data: clamped, still visible
    check t.selected == 1
    check t.top == 0

  test "TextView ring buffer keeps the cap; lineStyle colors a line":
    let tv = newTextView(maxLines = 3)
    for i in 1 .. 1000:
      tv.addLine &"line{i}"
    check tv.lines.len == 3
    check tv.lines[0] == "line998"
    var styled: seq[string]
    tv.lineStyle = proc(line: string): ThemeToken {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: styled.add line
      if line.endsWith("999"): tkSelection else: tkText
    let tb = renderInto(tv, 8, 3)
    check rowStr(tb, 1, 7) == "line999"
    check styled == @["line998", "line999", "line1000"] # consulted per drawn line

  test "Sparkline: right-aligned window, ceiling scale, SetProgress drives it":
    let s = newSparkline(capacity = 5)
    for v in 1 .. 10:
      s.push(v)
    check s.len == 5 and s.last == 10
    var tb = renderInto(s, 5, 1)
    check rowStr(tb, 0, 5) == "▆▆▇██" # window 6..10 scaled to 10
    let s2 = newSparkline(capacity = 5, maxValue = 10)
    s2.push(10)
    tb = renderInto(s2, 5, 1)
    check rowStr(tb, 0, 5) == "    █" # fewer samples than cells: right-aligned
    check SetProgress.signal(s2.brokerCtx, SetProgress(value: 5)).isOk
    waitFor sleepAsync(5.milliseconds)
    check s2.last == 5

suite "TriStateCheckBox (deviation #32)":
  test "user path cycles unchecked -> checked -> intermediate -> unchecked":
    let root = newGroup()
    root.bounds = rect(0, 0, 40, 4)
    let stub = newStubBus()
    root.publishCb = proc(a: UiAction) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: stub.publish(a)
    var seen: seq[CheckState]
    let c = newTriStateCheckBox("all", command = Command(9))
    c.onChange = proc(sender: TriStateCheckBox) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: seen.add sender.state
    root.add c
    c.arrange(rect(0, 0, 7, 1))
    setFocus(root, c)
    discard dispatchKey(root, keyEvent(Key.Space))
    discard dispatchKey(root, keyEvent(Key.Space))
    dispatchMouse(root, mouseEvent(maPress, mbLeft, 1, 0))
    check seen == @[csChecked, csIntermediate, csUnchecked]
    check stub.actions.len == 3
    check stub.actions[0].cmd == Command(9)

  test "setState is programmatic: no slot":
    var fired = 0
    let c = newTriStateCheckBox("x")
    c.onChange = proc(sender: TriStateCheckBox) {.gcsafe, raises: [].} = inc fired
    c.setState(csIntermediate)
    check c.state == csIntermediate
    check fired == 0

  test "disabled widget does not cycle":
    let c = newTriStateCheckBox("x")
    c.enabled = false
    c.cycle()
    check c.state == csUnchecked

  test "default marks [ ] / [x] / [?]":
    let c = newTriStateCheckBox("all")
    check rowStr(renderInto(c, 7, 1), 0, 7) == "[ ] all"
    c.setState(csChecked)
    check rowStr(renderInto(c, 7, 1), 0, 7) == "[x] all"
    c.setState(csIntermediate)
    check rowStr(renderInto(c, 7, 1), 0, 7) == "[?] all"

  test "custom marks and per-state mark colour (mark cell only)":
    let c = newTriStateCheckBox("all", state = csIntermediate)
    c.setMarks(Rune(' '), "✓".runeAt(0), Rune('~'))
    c.setMarkStyle(csIntermediate, StyleOverride(fg: fgRed, bg: bgYellow))
    var tb = renderInto(c, 7, 1)
    check rowStr(tb, 0, 7) == "[~] all"
    check tb[1, 0].fg == fgRed
    check tb[1, 0].bg == bgYellow
    check tb[0, 0].fg != fgRed # bracket keeps the widget style
    check tb[4, 0].fg != fgRed # caption too
    c.setState(csChecked) # no override for checked: inherits
    tb = renderInto(c, 7, 1)
    check rowStr(tb, 0, 7) == "[✓] all"
    check tb[1, 0].fg != fgRed

  test "mark focus colour applies while focused":
    let root = newGroup()
    root.bounds = rect(0, 0, 20, 2)
    let c = newTriStateCheckBox("all", state = csChecked)
    c.setMarkStyle(csChecked, StyleOverride(fg: fgGreen, focusFg: fgMagenta))
    root.add c
    var tb = renderInto(c, 7, 1)
    check tb[1, 0].fg == fgGreen
    setFocus(root, c)
    tb = renderInto(c, 7, 1)
    check tb[1, 0].fg == fgMagenta

suite "ControlBar (deviation #32)":
  test "height: lines clamped to 1..3, zero-init means 1":
    check newControlBar(lines = 0).measure().h == fixedHint(1)
    check newControlBar(lines = 2).measure().h == fixedHint(2)
    check newControlBar(lines = 7).measure().h == fixedHint(3)
    let cb = newControlBar()
    cb.setLines(3)
    check cb.measure().h == fixedHint(3)

  test "left group fills, right group flush right, spacing between":
    let cb = newControlBar(lines = 2)
    let run = newButton("Run")             # fixed 8 x 2 (face 7 + shadow)
    let log = newTextView()                # pref 0, stretch
    let sb = newScrollBar(axH)             # min 2, pref 8, stretch
    let r = newRadio(@["a", "b", "c", "d"]) # fixed 5 x 4
    let ok = newButton("OK")               # fixed 7 x 2
    cb.add run
    cb.add log
    cb.add sb
    cb.add r
    cb.addRight ok
    cb.arrange(rect(0, 0, 40, 2))
    check ok.bounds == rect(33, 0, 7, 2)
    # 32 cells for the left group: 8+0+8+5 pref + 3 gaps, 8 leftover split
    check run.bounds == rect(0, 0, 8, 2)
    check log.bounds == rect(9, 0, 4, 2)
    check sb.bounds == rect(14, 0, 12, 1)
    check r.bounds == rect(27, 0, 5, 2)    # 4 rows wanted, bar has 2

  test "right group keeps declaration order":
    let cb = newControlBar()
    let a = newButton("A")
    let b = newButton("B")
    cb.addRight a
    cb.addRight b
    cb.arrange(rect(0, 0, 20, 1))
    check a.bounds.x == 7 and b.bounds.x == 14 # 6 + 1 + 6, flush right

  test "narrow bar: right group wins, left never overlaps it":
    let cb = newControlBar()
    let l1 = newButton("Left")
    let l2 = newButton("More")
    let ok = newButton("OK")
    cb.add l1
    cb.add l2
    cb.addRight ok
    cb.arrange(rect(0, 0, 10, 1))
    check ok.bounds.x == 3
    for c in [View(l1), l2]:
      check c.bounds.x + c.bounds.w <= 2
    cb.arrange(rect(0, 0, 4, 1)) # narrower than the right group
    check l1.bounds.w == 0 and l2.bounds.w == 0
    check ok.bounds.x == 0

  test "alignRight moves an already-added child":
    let cb = newControlBar()
    let a = newButton("A")
    cb.add a
    cb.arrange(rect(0, 0, 20, 1))
    check a.bounds.x == 0
    cb.alignRight(a)
    cb.arrange(rect(0, 0, 20, 1))
    check a.bounds.x == 14

  test "children are clipped to the bar (no cells drawn below it)":
    let root = newGroup()
    root.bounds = rect(0, 0, 20, 5)
    let cb = newControlBar(lines = 2)
    cb.dock = dkTop
    cb.add newRadio(@["a", "b", "c", "d"])
    root.add cb
    root.theme = defaultTheme()
    let tb = renderInto(root, 20, 5)
    check tb[10, 1].bg == defaultTheme().style(tkControlBar).bg # bar fill
    check rowStr(tb, 0, 5) == "(•) a"
    check rowStr(tb, 1, 5) == "( ) b"
    check rowStr(tb, 2, 5) == "     "
    check rowStr(tb, 3, 5) == "     "

  test "docked bottom: fill sibling shrinks by the bar height":
    let root = newGroup()
    root.bounds = rect(0, 0, 40, 10)
    let cb = newControlBar(lines = 3)
    let body = newGroup()
    body.dock = dkFill
    root.add cb
    root.add body
    root.arrange(rect(0, 0, 40, 10))
    check cb.bounds == rect(0, 7, 40, 3)
    check body.bounds == rect(0, 0, 40, 7)

  test "focus traversal and mouse reach bar children":
    let root = newGroup()
    root.bounds = rect(0, 0, 40, 5)
    let cb = newControlBar()
    var clicks = 0
    let a = newButton("A")
    let b = newButton("B")
    b.onClick = proc(sender: Button) {.gcsafe, raises: [].} = inc clicks
    cb.add a
    cb.addRight b
    root.add cb
    root.arrange(rect(0, 0, 40, 5))
    focusNext(root)
    check root.focusedLeaf == View(a)
    focusNext(root)
    check root.focusedLeaf == View(b)
    dispatchMouse(root, mouseEvent(maPress, mbLeft, 36, 4))
    check clicks == 1

suite "surfaces (deviation #34)":
  setup:
    let th = defaultTheme()
    let root = newGroup()
    root.theme = th
    root.bounds = rect(0, 0, 30, 10)

  test "checkbox / radio fill their whole arranged width with the cluster bg":
    let c = newCheckbox("ab")
    let r = newRadio(@["x", "y"])
    root.add c
    root.add r
    var tb = renderInto(c, 12, 1)
    check tb[11, 0].bg == th.style(tkCheckbox).bg
    tb = renderInto(r, 12, 2)
    check tb[11, 1].bg == th.style(tkCheckbox).bg

  test "list rows and empty space use the list surface; editor the field":
    let l = newListView(@["a"])
    let e = newEditor("x")
    root.add l
    root.add e
    var tb = renderInto(l, 6, 3)
    check tb[5, 2].bg == th.style(tkList).bg
    tb = renderInto(e, 6, 3)
    check tb[5, 2].bg == th.style(tkInput).bg

  test "control hotkey keeps the control bg, bars keep the red hotkey":
    let b = newButton("~R~un")
    root.add b
    let tb = renderInto(b, 8, 2) # face 7: "Run" centred at x 2
    check tb[2, 0].bg == th.style(tkButton).bg
    check tb[2, 0].fg == th.style(tkHotkey).fg

  test "label lights up while its linked control has focus":
    let inp = newInput()
    let lbl = newLabel("~N~ame")
    lbl.linkTo = inp
    root.add lbl
    root.add inp
    var tb = renderInto(lbl, 4, 1)
    check tb[1, 0].fg == th.style(tkText).fg
    setFocus(root, inp)
    tb = renderInto(lbl, 4, 1)
    check tb[1, 0].fg == th.style(tkLabelFocused).fg

suite "TV buttons (deviation #34)":
  test "half-block shadow keeps the surface underneath (cluster block)":
    let root = newGroup()
    root.theme = defaultTheme()
    root.bounds = rect(0, 0, 20, 6)
    let gb = newGroupBox("")
    gb.bounds = rect(0, 0, 20, 4)
    let b = newButton("OK")              # face 6 + shadow column, 2 rows
    b.bounds = rect(1, 1, 7, 2)
    gb.add b
    root.add gb
    let tb = newTerminalBuffer(20, 6)
    root.draw(initDrawContext(tb))
    let cluster = defaultTheme().style(tkCluster).bg
    check rowStr(tb, 1, 8) == "   OK  ▄" # cluster cell, face "  OK  ", ▄
    check $tb[7, 1].ch == "▄" and tb[7, 1].bg == cluster
    check $tb[2, 2].ch == "▀" and tb[2, 2].bg == cluster
    check $tb[1, 2].ch != "▀"               # shadow starts one cell in
    check tb[3, 1].bg == defaultTheme().style(tkButton).bg

  test "clicks on the shadow do not activate; setShadowed(false) is 1 row":
    let root = newGroup()
    root.bounds = rect(0, 0, 20, 4)
    var clicks = 0
    let b = newButton("OK")
    b.onClick = proc(s: Button) {.gcsafe, raises: [].} = inc clicks
    root.add b
    b.arrange(rect(0, 0, 7, 2))
    dispatchMouse(root, mouseEvent(maPress, mbLeft, 6, 0)) # ▄ column
    dispatchMouse(root, mouseEvent(maPress, mbLeft, 3, 1)) # ▀ row
    check clicks == 0
    dispatchMouse(root, mouseEvent(maPress, mbLeft, 3, 0)) # face
    check clicks == 1
    b.setShadowed(false)
    check b.hint == (fixedHint(6), fixedHint(1))

  test "default button: bright caption; Enter not consumed fires it":
    let win = newWindow("w", rect(0, 0, 30, 10))
    let box = newVBox()
    box.dock = dkFill
    let plain = newInput()              # nobody listens: passes Enter on
    let wired = newInput()
    var submitted = 0
    wired.onSubmit = proc(s: Input) {.gcsafe, raises: [].} = inc submitted
    let chk = newCheckbox("c")
    let ok = newButton("OK")
    ok.isDefault = true
    var fired = 0
    ok.onClick = proc(s: Button) {.gcsafe, raises: [].} = inc fired
    box.add plain
    box.add wired
    box.add chk
    box.add ok
    win.add box
    let root = newGroup()
    root.theme = defaultTheme()
    root.bounds = rect(0, 0, 40, 12)
    root.add win
    root.arrange(rect(0, 0, 40, 12))
    setFocus(root, plain)
    check dispatchKey(root, keyEvent(Key.Enter))
    check fired == 1
    setFocus(root, chk)
    check dispatchKey(root, keyEvent(Key.Enter))
    check fired == 2 and not chk.checked  # Enter no longer toggles (TV)
    discard dispatchKey(root, keyEvent(Key.Space))
    check chk.checked
    setFocus(root, wired)
    check dispatchKey(root, keyEvent(Key.Enter))
    check submitted == 1 and fired == 2   # a listened input keeps Enter
    let tb = renderInto(ok, 7, 2)
    check tb[2, 0].fg == defaultTheme().style(tkButtonDefault).fg
