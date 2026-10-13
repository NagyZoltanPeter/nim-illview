## Horizontal scrolling and the bottom scroll bar in ListView, Table, TreeView
## and TextView (deviation #49).

import std/[unittest, unicode, strutils]
import ../src/illview/backend/illwill_vendored except Style
import ../src/illview/core/[geometry, theme, drawcontext, textwidth, view, events]
import ../src/illview/backend/decoder
import ../src/illview/widgets/[hbar, list, table, treeview, textview]

proc rowText(tb: TerminalBuffer, y: int): string =
  for x in 0 ..< tb.width:
    let c = tb[x, y]
    if c.ch != Rune(0):
      result.add $c.ch & c.extra

proc render(v: View, w, h: int): TerminalBuffer =
  result = newTerminalBuffer(w, h)
  v.theme = defaultTheme()
  v.arrange(rect(0, 0, w, h))
  v.draw(initDrawContext(result))

proc key(k: Key, mods: set[Modifier] = {}): Event =
  Event(kind: evKey, ikey: keyEvent(k, mods = mods))

proc mouse(a: MouseAction, x, y: int, mods: set[Modifier] = {}): Event =
  Event(kind: evMouse, imouse: mouseEvent(a, mbLeft, x, y, mods))

suite "helpers":
  test "sliceCols: columns, wide characters cut at an edge":
    check "abcdef".sliceCols(2, 3) == "cde"
    check "abc".sliceCols(1, 10) == "bc"
    check "a日b".sliceCols(0, 2) == "a " # 日 cut on the right
    check "a日b".sliceCols(2, 2) == " b" # 日 cut on the left
    check "a日b".sliceCols(1, 2) == "日"
    check "éx".sliceCols(0, 1) == "é"
    check ("e" & "́" & "x").sliceCols(0, 1) == "é" # mark stays with e

  test "decoder: SGR 66/67 are the horizontal wheel":
    var d: Decoder
    check d.feed("\e[<66;3;4M") == @[mouseEvent(maWheelLeft, mbNone, 2, 3)]
    check d.feed("\e[<67;3;4M") == @[mouseEvent(maWheelRight, mbNone, 2, 3)]
    check d.feed("\e[<64;1;1M") == @[mouseEvent(maWheelUp, mbNone, 0, 0)]
    check d.feed("\e[<65;1;1M") == @[mouseEvent(maWheelDown, mbNone, 0, 0)]

  test "barLayout settles both bars":
    check barLayout(10, 5, 0, 3, 8, true) == BarLayout(rows: 5, cols: 10)
    check barLayout(10, 5, 0, 3, 20, true) ==
      BarLayout(hbar: true, rows: 4, cols: 10)
    # 5 items fit 5 rows, but the bar row leaves 4: the vertical bar appears
    check barLayout(10, 5, 0, 5, 20, true) ==
      BarLayout(vbar: true, hbar: true, rows: 4, cols: 9)
    # content 10 fits 10 columns until the vertical bar takes one
    check barLayout(10, 5, 0, 9, 10, true) ==
      BarLayout(vbar: true, hbar: true, rows: 4, cols: 9)
    check barLayout(10, 1, 0, 1, 20, false).hbar == false # no row to spare
    check barLayout(10, 2, 1, 1, 20, false).hbar == false # header + 1 row

  test "bar presses: arrows step, rail pages, thumb drags":
    check hbarPress(0, 10, 30, 8, 4) == (4, false)  # ◄
    check hbarPress(9, 10, 30, 8, 4) == (12, false) # ►
    check hbarPress(8, 10, 30, 0, 4) == (10, false) # rail right of the thumb
    check hbarPress(1, 10, 30, 0, 4) == (0, true)   # the thumb at pos 0
    check hbarDrag(8, 10, 30) == 20                 # far right = max
    check hbarDrag(1, 10, 30) == 0

suite "ListView":
  test "a cut item shows the bar; Left/Right scroll; the bar row is not an item":
    let l = newListView(@["short", "a much longer item text"])
    var tb = l.render(10, 4)
    check tb.rowText(3) == "◄■▒▒▒▒▒▒▒►"
    check l.handleEvent(key(Key.Right))
    check l.scrollX == 4
    tb = l.render(10, 4)
    check tb.rowText(1) == "ch longer "
    check l.handleEvent(key(Key.End, {modShift}))
    check l.scrollX == 23 - 10
    check l.handleEvent(key(Key.Home, {modShift}))
    check l.scrollX == 0
    check l.handleEvent(mouse(maWheelRight, 0, 0))
    check l.scrollX == 4
    check l.handleEvent(mouse(maPress, 9, 3)) # ► on the bar
    check l.scrollX == 8
    check l.selected == 0 # the press did not select a row

  test "no bar and no scroll when everything fits":
    let l = newListView(@["a", "b"])
    let tb = l.render(10, 4)
    check tb.rowText(3).strip == ""
    check l.handleEvent(key(Key.Right))
    check l.scrollX == 0

  test "dragging the thumb scrolls":
    let l = newListView(@["x".repeat(40)])
    discard l.render(10, 3)
    check l.handleEvent(mouse(maPress, 1, 2)) # the thumb
    check l.handleEvent(mouse(maMove, 8, 2))
    check l.scrollX == 30
    check l.handleEvent(mouse(maRelease, 8, 2))

suite "Table":
  test "each cut cell scrolls in its column; short cells stay; ◀ / ▶ marks":
    let t = newTable(@[tableColumn("k", fixedHint(4)), tableColumn("v", fixedHint(8))],
                     @[@["id", "0123456789abcdef"], @["n", "short"]])
    var tb = t.render(13, 5)
    check tb.rowText(1) == "id   0123456▶"
    check tb.rowText(2) == "n    short   "
    check tb.rowText(4) == "◄■▒▒▒▒▒▒▒▒▒▒►" # overflow 8: total 13 + 8
    check t.handleEvent(key(Key.Right))
    tb = t.render(13, 5)
    check tb.rowText(1) == "id   ◀56789a▶"
    check tb.rowText(2) == "n    short   "
    discard t.handleEvent(key(Key.End, {modShift}))
    check t.scrollX == 8
    tb = t.render(13, 5)
    check tb.rowText(1) == "id   ◀9abcdef"
    check tb.rowText(0).startsWith("k    v") # the header stays

  test "a click on the bar row does not select; rows still do":
    let t = newTable(@[tableColumn("v", fixedHint(4))],
                     @[@["0123456789"], @["b"]])
    discard t.render(6, 4)
    discard t.handleEvent(mouse(maPress, 2, 2))
    check t.selected == 1
    discard t.handleEvent(mouse(maPress, 5, 3)) # ► on the bar
    check t.selected == 1
    check t.scrollX > 0

suite "TreeView":
  test "the bar sits under the rows while any row is cut":
    let tv = newTreeView(@[treeNode("x".repeat(30)), treeNode("y")])
    let tb = tv.render(10, 4)
    check tb.rowText(3) == "◄■▒▒▒▒▒▒▒►"
    check tb.rowText(0).endsWith("▶")
    discard tv.handleEvent(mouse(maPress, 9, 3)) # ►
    check tv.scrollX == 4
    check tv.isBarRow(3)
    check not tv.isBarRow(2)

suite "TextView":
  test "lines scroll; the widest line is tracked through the cap":
    let tv = newTextView(maxLines = 2)
    tv.addLine "w".repeat(30)
    tv.addLine "ab"
    check tv.contentWidth == 30
    var tb = tv.render(10, 3)
    check tb.rowText(2) == "◄■▒▒▒▒▒▒▒►"
    check tv.handleEvent(key(Key.Right))
    check tv.scrollX == 4
    tv.addLine "cd" # drops the wide line
    check tv.contentWidth == 2
    tb = tv.render(10, 3)
    check tv.scrollX == 0
    check tb.rowText(2).strip == ""

  test "selection maps through the horizontal offset":
    let tv = newTextView()
    tv.addLine "0123456789abcdef"
    discard tv.render(8, 3)
    discard tv.handleEvent(key(Key.Right)) # scrollX 4
    discard tv.handleEvent(mouse(maPress, 0, 0))
    discard tv.handleEvent(mouse(maMove, 3, 0))
    check tv.selectedText == "456"
