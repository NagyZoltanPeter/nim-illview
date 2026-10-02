## Phase 2 exit criteria: render scenes into an off-screen TerminalBuffer and
## assert cells — clipping correctness is the highest-risk item in the
## project (plan §3.3). No terminal required (display() is never called).

import std/[unittest, unicode, strutils]
import ../src/illview/backend/illwill_vendored
import ../src/illview/core/[geometry, theme, drawcontext, view, routing]
import ../src/illview/widgets/[desktop, window]

type
  TextView = ref object of View
    ## Minimal drawing widget for tests: writes `text` at its local origin,
    ## deliberately allowed to be wider than its bounds.
    text: string

proc newTextView(text: string, bounds: Rect, focusable = false): TextView =
  result = TextView(text: text)
  initView(result)
  result.bounds = bounds
  result.focusable = focusable

method draw(v: TextView, dc: DrawContext) =
  dc.write(0, 0, v.text, v.styleOf(tkText))

proc rowStr(tb: TerminalBuffer, y: int): string =
  for x in 0 ..< tb.width:
    result.add $tb[x, y].ch

proc cellStr(tb: TerminalBuffer, x, y: int): string =
  $tb[x, y].ch

proc render(d: Desktop, w, h: int): TerminalBuffer =
  result = newTerminalBuffer(w, h)
  d.bounds = rect(0, 0, w, h)
  d.draw(initDrawContext(result))

suite "render snapshots":
  test "desktop fill + window frame + title":
    let d = newDesktop()
    d.add newWindow("Log", rect(2, 1, 20, 5))
    let tb = render(d, 26, 8)
    check rowStr(tb, 0) == repeat("░", 26)
    # frame row: corners at abs x=2 / x=21, title " Log " centered
    check cellStr(tb, 2, 1) == "┌"
    check cellStr(tb, 21, 1) == "┐"
    check " Log " in rowStr(tb, 1)
    # content row: frame, blank interior, frame, desktop pattern outside
    check cellStr(tb, 2, 2) == "│"
    for x in 3 .. 20:
      check cellStr(tb, x, 2) == " "
    check cellStr(tb, 21, 2) == "│"
    check cellStr(tb, 22, 2) == "░"
    # bottom frame row and untouched desktop below
    check cellStr(tb, 2, 5) == "└"
    check cellStr(tb, 21, 5) == "┘"
    check rowStr(tb, 6) == repeat("░", 26)

  test "child drawing outside the content rect is clipped (no bleed)":
    let d = newDesktop()
    let win = newWindow("W", rect(2, 1, 12, 5))
    # 20 'X' runes at content row 0: content width is only 10
    win.add newTextView(repeat("X", 20), rect(0, 0, 20, 1))
    # a child positioned below the content area: must not appear at all
    win.add newTextView("YYY", rect(0, 10, 3, 1))
    d.add win
    let tb = render(d, 20, 8)
    check rowStr(tb, 2) == "░░│XXXXXXXXXX│░░░░░░"
    for y in 0 ..< 8:
      check "Y" notin rowStr(tb, y)

  test "overlapping windows: topmost covers, clipped correctly":
    let d = newDesktop()
    let winA = newWindow("A", rect(0, 0, 14, 6))
    winA.add newTextView(repeat("a", 12), rect(0, 0, 12, 1))
    let winB = newWindow("B", rect(6, 2, 14, 6))
    winB.add newTextView(repeat("b", 12), rect(0, 0, 12, 1))
    d.add winA
    d.add winB # z-order: B on top
    let tb = render(d, 24, 10)
    # winA content row (y=1) is fully visible (winB starts at y=2)
    check rowStr(tb, 1) == "│aaaaaaaaaaaa│" & repeat("░", 10)
    # winB's top frame (y=2) covers winA from x=6 on
    check cellStr(tb, 6, 2) == "┌"
    # winB content row (y=3): winA frame + interior left of x=6, then winB
    check rowStr(tb, 3) == "│     │bbbbbbbbbbbb│" & repeat("░", 4)

  test "raiseToTop changes which window covers":
    let d = newDesktop()
    let winA = newWindow("A", rect(0, 0, 14, 6))
    let winB = newWindow("B", rect(6, 2, 14, 6))
    d.add winA
    d.add winB
    raiseToTop(d, winA)
    let tb = render(d, 24, 10)
    # winA's bottom frame row (y=5) now covers winB in the overlap
    check cellStr(tb, 0, 5) == "└"
    check cellStr(tb, 13, 5) == "┘"

  test "active window renders a double frame":
    let d = newDesktop()
    let win = newWindow("W", rect(0, 0, 12, 4))
    let btn = newTextView("ok", rect(0, 0, 2, 1), focusable = true)
    win.add btn
    d.add win
    var tb = render(d, 16, 6)
    check cellStr(tb, 0, 0) == "┌"
    setFocus(d, btn)
    tb = render(d, 16, 6)
    check cellStr(tb, 0, 0) == "╔"

  test "styles reach the buffer (theme token -> cell attrs)":
    let d = newDesktop()
    let tb = render(d, 4, 2)
    let cell = tb[0, 0]
    let st = defaultTheme().style(tkDesktop)
    check cell.fg == st.fg
    check cell.bg == st.bg

suite "decoration (iteration 2)":
  test "border insets the content and clips it":
    let d = newDesktop()
    let win = newWindow("W", rect(0, 0, 20, 7))
    let t = newTextView(repeat("X", 16), rect(1, 1, 10, 3))
    t.border = bkSingle
    d.add win
    win.add t
    let tb = render(d, 24, 9)
    # t's full rect abs = win content (1,1) + bounds (1,1) => (2,2,10,3)
    check cellStr(tb, 2, 2) == "┌"
    check cellStr(tb, 11, 2) == "┐"
    check cellStr(tb, 2, 3) == "│"
    # content row: 8 cells of X, clipped at the border
    for x in 3 .. 10:
      check cellStr(tb, x, 3) == "X"
    check cellStr(tb, 11, 3) == "│"
    check cellStr(tb, 12, 3) == " " # window bg, no bleed

  test "border title is centered on the top border":
    let d = newDesktop()
    let box = newGroup()
    box.border = bkSingle
    box.borderTitle = "opts"
    box.bounds = rect(1, 1, 12, 4)
    d.add box
    let tb2 = render(d, 16, 7)
    check " opts " in rowStr(tb2, 1)
    check cellStr(tb2, 1, 1) == "┌"

  test "shadow recolors cells but keeps the runes":
    let d = newDesktop()
    let win = newWindow("S", rect(1, 1, 10, 4))
    win.shadow = true
    d.add win
    let tb = render(d, 20, 10)
    # bottom shadow row: y = 1 + 4 = 5, x from 3; right shadow: x = 11..12
    let sh = defaultTheme().style(tkShadow)
    check cellStr(tb, 3, 5) == "░" # rune preserved from the desktop pattern
    check tb[3, 5].fg == sh.fg
    check tb[3, 5].bg == sh.bg
    check tb[11, 2].fg == sh.fg
    # untouched desktop cell keeps its own colors
    check tb[0, 0].fg == defaultTheme().style(tkDesktop).fg

  test "fg/bg override merges over the theme token":
    let d = newDesktop()
    let t = newTextView("hi", rect(0, 0, 4, 1))
    t.styleOv.fg = fgRed
    t.styleOv.bg = bgGreen
    d.add t
    let tb = render(d, 6, 2)
    check cellStr(tb, 0, 0) == "h"
    check tb[0, 0].fg == fgRed
    check tb[0, 0].bg == bgGreen

  test "focus override applies only while focused":
    let d = newDesktop()
    let t = newTextView("hi", rect(0, 0, 4, 1), focusable = true)
    t.styleOv.focusFg = fgYellow
    d.add t
    var tb = render(d, 6, 2)
    check tb[0, 0].fg == defaultTheme().style(tkText).fg
    setFocus(d, t)
    tb = render(d, 6, 2)
    check tb[0, 0].fg == fgYellow

  test "outerHints adds the border cells for layout":
    let t = newTextView("x", rect(0, 0, 0, 0))
    t.hint = (fixedHint(5), fixedHint(1))
    check t.outerHints().w.pref == 5
    t.border = bkSingle
    check t.outerHints().w.pref == 7
    check t.outerHints().h.min == 3

suite "TV chrome (deviation #34)":
  test "close box ■ in its own colour; windows gray, blue is opt-in (deviation #35)":
    let d = newDesktop()
    let win = newWindow("W", rect(0, 0, 12, 4))
    d.add win
    let tb = render(d, 14, 6)
    check cellStr(tb, 2, 0) == "■"
    check tb[2, 0].fg == defaultTheme().style(tkWindowCloseBox).fg
    check tb[1, 0].fg != defaultTheme().style(tkWindowCloseBox).fg # bracket
    check win.palette == pDefault
    check tb[3, 2].bg == bgGray # lightgray: the base (gray) palette
    win.palette = pBlue
    let tb2 = render(d, 14, 6)
    check tb2[3, 2].bg == defaultTheme().variant(pBlue).style(tkWindowBg).bg
    check tb2[3, 2].bg == bgBlue
