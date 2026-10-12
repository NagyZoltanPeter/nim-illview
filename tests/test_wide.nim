## Wide (CJK, emoji) and zero-width characters (deviation #45): widths, the
## cell model, widgets measuring in columns, and the diff renderer's output
## replayed through a minimal terminal emulator.

import std/[unittest, unicode, strutils, os, sequtils]
import ../src/illview/backend/illwill_vendored except Style
import ../src/illview/core/[geometry, theme, drawcontext, textwidth, view, events]
import ../src/illview/widgets/[table, input, editor]
import ../src/illview/backend/probe_posix

proc rowText(tb: TerminalBuffer, y: int): string =
  ## The row as a terminal shows it: continuation cells contribute nothing.
  for x in 0 ..< tb.width:
    let c = tb[x, y]
    if c.ch != Rune(0):
      result.add $c.ch & c.extra

proc keyEv(k: Key, r = Rune(0)): Event =
  Event(kind: evKey, ikey: keyEvent(k, r))

suite "widths":
  test "rune widths":
    check:
      "a".runeAt(0).runeWidth == 1
      "é".runeAt(0).runeWidth == 1
      "日".runeAt(0).runeWidth == 2
      "🙂".runeAt(0).runeWidth == 2
      "👋".runeAt(0).runeWidth == 2
      Rune(0x0301).runeWidth == 0 # combining acute
      Rune(0x200D).runeWidth == 0 # zero-width joiner
      Rune(0xFE0F).runeWidth == 0 # variation selector

  test "text width, clipping never splits a wide character":
    check:
      "Bye 👋 日本語".textWidth == 4 + 2 + 1 + 6
      "日本語".clipWidth(3) == "日"
      "日本語".clipWidth(4) == "日本"
      "éx".clipWidth(1) == "é" # the mark stays with its base
      "日a".padWidth(5) == "日a  "
      "日本".padWidth(3) == "日 "

  test "column <-> index":
    let rs = "a日b".toRunes
    check:
      rs.colOf(0) == 0
      rs.colOf(2) == 3
      rs.indexAtCol(1) == 1
      rs.indexAtCol(2) == 1 # right half of 日
      rs.indexAtCol(3) == 2
      rs.indexAtCol(9) == 3

suite "cell model":
  let st = Style(fg: fgWhite, bg: bgBlue)

  test "a wide character takes two cells":
    let tb = newTerminalBuffer(6, 1)
    let dc = initDrawContext(tb)
    dc.write(0, 0, "a日b", st)
    check:
      tb[1, 0].ch == "日".runeAt(0)
      tb[2, 0].ch == Rune(0)
      tb[3, 0].ch == "b".runeAt(0)
      tb.rowText(0) == "a日b  "

  test "overwriting either half blanks the other":
    let tb = newTerminalBuffer(5, 1)
    let dc = initDrawContext(tb)
    dc.write(0, 0, "a日b", st)
    dc.putCell(2, 0, "x".runeAt(0), st) # right half
    check tb.rowText(0) == "a xb "
    dc.write(0, 0, "a日b", st)
    dc.putCell(1, 0, "y".runeAt(0), st) # left half
    check tb.rowText(0) == "ay b "

  test "a wide character that does not fit the clip is a space":
    let tb = newTerminalBuffer(5, 1)
    let dc = initDrawContext(tb).sub(rect(0, 0, 2, 1))
    dc.write(0, 0, "a日", st)
    check tb.rowText(0) == "a    "

  test "zero-width characters join the cell before them":
    let tb = newTerminalBuffer(4, 1)
    let dc = initDrawContext(tb)
    dc.write(0, 0, "éx", st)
    check:
      tb[0, 0].extra == "́"
      tb[1, 0].ch == "x".runeAt(0)
      tb.rowText(0) == "éx  "

suite "widgets measure in columns":
  test "table columns stay aligned after wide text":
    let t = newTable(@[tableColumn("payload", fixedHint(10)),
                       tableColumn("status", fixedHint(6))])
    t.setRows(@[@["plain", "ok"], @["日本語もOK", "ok"], @["Bye 👋", "ok"]])
    let tb = newTerminalBuffer(17, 4)
    t.arrange(rect(0, 0, 17, 4))
    t.draw(initDrawContext(tb))
    for y in 1 .. 3: # every status cell starts at column 11
      check tb[11, y].ch == "o".runeAt(0)

  test "editor cursor and scroll follow display columns":
    let e = newEditor("日本語")
    e.curCol = 2
    let tb = newTerminalBuffer(10, 1)
    e.arrange(rect(0, 0, 10, 1))
    e.theme = defaultTheme()
    e.draw(initDrawContext(tb))
    check tb[4, 0].ch == "語".runeAt(0) # the cursor cell, after two wide runes
    let narrow = newEditor("日本語もOK")
    discard narrow.handleEvent(keyEv(Key.End))
    narrow.arrange(rect(0, 0, 4, 1))
    narrow.draw(initDrawContext(newTerminalBuffer(4, 1)))
    check narrow.scrollX == 10 - 4 + 1 # end column 10, cursor cell visible

  test "input click lands on the rune under the mouse":
    let i = newInput("a日b")
    i.arrange(rect(0, 0, 10, 1))
    discard i.handleEvent(Event(kind: evMouse,
      imouse: mouseEvent(maPress, mbLeft, 2, 0)))
    check i.cursor == 1 # column 2 is 日's right half

suite "renderer output":
  proc replay(path: string, screen: var seq[string], w: int) =
    ## Minimal VT: CSI row;col f/H and col G move, SGR ignored, text
    ## advances by display width (continuation of a wide glyph left as "").
    let s = readFile(path)
    var x, y = 0
    var i = 0
    while i < s.len:
      if s[i] == '\e' and i + 1 < s.len and s[i + 1] == '[':
        var j = i + 2
        while j < s.len and s[j] notin {'A'..'Z', 'a'..'z'}:
          inc j
        let params = s[i + 2 ..< j]
        case s[j]
        of 'f', 'H':
          let p = params.split(';')
          y = parseInt(p[0]) - 1
          x = parseInt(p[1]) - 1
        of 'G':
          x = parseInt(params) - 1
        else: discard
        i = j + 1
      else:
        let r = s.runeAt(i)
        let rw = r.runeWidth
        if rw == 0:
          if x > 0: screen[y * w + x - 1].add $r
        else:
          screen[y * w + x] = $r
          if rw == 2: screen[y * w + x + 1] = ""
          x += rw
        i += s.runeLenAt(i)

  proc frame(text: string, w: int): TerminalBuffer =
    result = newTerminalBuffer(w, 1)
    initDrawContext(result).write(0, 0, text, Style(fg: fgWhite, bg: bgBlue))

  proc shown(screen: seq[string]): string =
    screen.join("")

  test "a diff after wide characters lands in the right columns":
    let w = 24
    let path = getTempDir() / "illview_wide_out.txt"
    for (before, after) in [
      ("Bye 👋 日本語も propagated", "Bye 👋 日本語も sent ✓✓"),
      ("日本語 abc", "日本語 abX"),
      ("ab日cd", "abXYcd"), # a wide character replaced by two narrow ones
      ("abXYcd", "ab日cd"),
    ]:
      let prev = frame(before, w)
      let cur = frame(after, w)
      var screen = newSeqWith(w, " ")
      block: # the terminal shows `prev` first
        let f = open(path, fmWrite)
        setOutput(f)
        displayDiffForTest(newTerminalBuffer(w, 1), prev)
        f.close()
        replay(path, screen, w)
      block: # then the diff to `cur`
        let f = open(path, fmWrite)
        setOutput(f)
        displayDiffForTest(prev, cur)
        f.close()
        replay(path, screen, w)
      setOutput(stdout)
      check screen.shown == cur.rowText(0)

suite "emoji width (deviation #46)":
  test "the terminal's cursor report gives the column":
    check:
      parseCursorCol("\e[12;3R") == 3
      parseCursorCol("junk\e[1;2R") == 2
      parseCursorCol("\e[1;") == 0 # incomplete
      parseCursorCol("") == 0

  test "a measured width of 1 applies to emoji, not to CJK":
    setEmojiWidth(1)
    check:
      "🙂".runeAt(0).runeWidth == 1
      "Bye 👋 日本".textWidth == 4 + 1 + 1 + 4
      "日".runeAt(0).runeWidth == 2
    setEmojiWidth(2)
    check "🙂".runeAt(0).runeWidth == 2
