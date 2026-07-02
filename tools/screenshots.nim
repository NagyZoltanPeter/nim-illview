## Renders documentation "screenshots": builds real widget scenes, draws
## them through the actual framework into an offscreen TerminalBuffer and
## emits SVG files under docs/assets/. No terminal involved — the output is
## exactly what the renderer produces, cell for cell.
##
## Regenerate with: nimble screenshots

import std/[strformat, strutils, unicode]
from std/terminal import styleBright
import ../src/illview
import ../src/illview/backend/illwill_vendored except Style

const
  CellW = 9
  CellH = 18
  FontSize = 14

func fgHex(c: ForegroundColor, bright: bool): string =
  case c
  of fgNone: (if bright: "#ffffff" else: "#d8d8d8")
  of fgBlack: (if bright: "#7a7a7a" else: "#30302c")
  of fgRed: (if bright: "#ff6e67" else: "#cc4444")
  of fgGreen: (if bright: "#8ae234" else: "#4e9a06")
  of fgYellow: (if bright: "#fce94f" else: "#c4a000")
  of fgBlue: (if bright: "#729fcf" else: "#3465a4")
  of fgMagenta: (if bright: "#d38be8" else: "#a45bb8")
  of fgCyan: (if bright: "#34e2e2" else: "#06989a")
  of fgWhite: (if bright: "#ffffff" else: "#d3d7cf")

func bgHex(c: BackgroundColor): string =
  case c
  of bgNone: "#1c1c1c"
  of bgBlack: "#262626"
  of bgRed: "#a02020"
  of bgGreen: "#3f7d16"
  of bgYellow: "#b08800"
  of bgBlue: "#20409a"
  of bgMagenta: "#7c3b96"
  of bgCyan: "#178b8d"
  of bgWhite: "#d0d0c8"

func esc(s: string): string =
  s.multiReplace(("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"))

proc toSvg(tb: TerminalBuffer): string =
  let w = tb.width * CellW
  let h = tb.height * CellH
  result = &"""<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">
<rect width="{w}" height="{h}" fill="#1c1c1c"/>
<g font-family="Menlo, Consolas, 'DejaVu Sans Mono', monospace" font-size="{FontSize}">
"""
  for y in 0 ..< tb.height:
    # background runs
    var x = 0
    while x < tb.width:
      let bg = tb[x, y].bg
      var rx = x
      while rx < tb.width and tb[rx, y].bg == bg:
        inc rx
      if bg != bgNone:
        result.add &"""<rect x="{x * CellW}" y="{y * CellH}" width="{(rx - x) * CellW}" height="{CellH}" fill="{bgHex(bg)}"/>""" & "\n"
      x = rx
    # text runs (same fg + brightness)
    x = 0
    while x < tb.width:
      let c = tb[x, y]
      let bright = styleBright in c.style
      var rx = x
      var text = ""
      while rx < tb.width and tb[rx, y].fg == c.fg and
            (styleBright in tb[rx, y].style) == bright:
        text.add $tb[rx, y].ch
        inc rx
      if text.strip.len > 0:
        let tl = (rx - x) * CellW
        result.add &"""<text x="{x * CellW}" y="{y * CellH + FontSize}" textLength="{tl}" lengthAdjust="spacingAndGlyphs" xml:space="preserve" fill="{fgHex(c.fg, bright)}">{esc(text)}</text>""" & "\n"
      x = rx
  result.add "</g>\n</svg>\n"

proc shoot(name: string, w, h: int, build: proc(d: Desktop)) =
  let d = newDesktop()
  build(d)
  d.arrange(rect(0, 0, w, h))
  let tb = newTerminalBuffer(w, h)
  d.draw(initDrawContext(tb))
  writeFile("docs/assets/" & name & ".svg", toSvg(tb))
  echo "wrote docs/assets/", name, ".svg"

# --- scene 1: the widget gallery ----------------------------------------------

proc galleryScene(d: Desktop) =
  d.add newMenuBar(@[
    menu("File", @[menuItem("Run", Command(1)), menuItem("Quit", Command(2))]),
    menu("Help", @[menuItem("About", Command(3))])])
  d.add newStatusBar(@[statusItem("F10 Menu", Command(4)),
                       statusItem("Esc Quit", Command(5))])

  let win = newWindow("widget gallery", rect(0, 0, 0, 0))
  win.dock = dkFill
  let rows = newVBox(spacing = 1)
  rows.dock = dkFill
  let cols = newHBox(spacing = 2)
  cols.hint = (prefHint(0, stretch = 1), prefHint(0, stretch = 3))

  let form = newVBox(spacing = 1)
  form.hint = (prefHint(28, stretch = 1), prefHint(0, stretch = 1))
  form.add newLabel("Name:")
  form.add newInput("nim-illview")
  let opts = newGroupBox("options")
  opts.hint = (prefHint(0, stretch = 1), fixedHint(4))
  let optsBox = newVBox()
  optsBox.dock = dkFill
  optsBox.add newCheckbox("enable feature", checked = true)
  optsBox.add newRadio(@["refc", "orc", "arc"], selected = 1)
  opts.add optsBox
  form.add opts
  let pb = newProgressBar()
  pb.setValue(62)
  form.add pb
  form.add newButton("Run")

  let right = newVBox(spacing = 1)
  right.hint = (prefHint(0, stretch = 2), prefHint(0, stretch = 1))
  var items: seq[string]
  for i in 1 .. 12:
    items.add &"list item {i:02}"
  let lst = newListView(items)
  right.add lst
  let tbl = newTable(
    @[tableColumn("proto", fixedHint(10)),
      tableColumn("status", prefHint(0, stretch = 1))],
    @[@["relay", "up"], @["store", "syncing"], @["filter", "off"]])
  tbl.hint = (prefHint(0, stretch = 1), fixedHint(4))
  right.add tbl

  cols.add form
  cols.add right
  let log = newTextView()
  log.hint = (prefHint(0, stretch = 1), prefHint(4, stretch = 1))
  log.addLine "checkbox: true"
  log.addLine "radio: orc"
  log.addLine "list select: list item 04"
  log.addLine "bus: UiAction(cmd: 120, sender: 7)"
  rows.add cols
  rows.add log
  win.add rows
  d.add win
  d.arrange(rect(0, 0, 80, 24))
  lst.select(3) # after arrange: the viewport geometry is known
  setFocus(d, lst)

# --- scene 2: windows, styling, shadows ----------------------------------------

proc windowsScene(d: Desktop) =
  let back = newWindow("logs", rect(3, 2, 42, 13))
  back.shadow = true
  let tv = newTextView()
  tv.dock = dkFill
  for line in ["[peer]  connected 16Uiu2HAm...",
               "[relay] push 1.2 kB msgHash=0xa1f3...",
               "[store] query served (12 msgs)",
               "[peer]  score +1"]:
    tv.addLine line
  back.add tv
  d.add back

  let front = newWindow("settings", rect(30, 7, 36, 13))
  front.shadow = true
  let form = newVBox(spacing = 1)
  form.dock = dkFill
  let inp = newInput("wss://node.example:8000")
  inp.border = bkSingle
  inp.borderTitle = "endpoint"
  form.add inp
  let mm = newGroupBox("memory model")
  mm.hint = (prefHint(0, stretch = 1), fixedHint(3))
  let mmBox = newVBox()
  mmBox.dock = dkFill
  mmBox.add newRadio(@["refc", "orc", "arc"], selected = 1)
  mm.add mmBox
  form.add mm
  let ok = newButton("Apply")
  ok.styleOv.focusBg = bgCyan
  form.add ok
  front.add form
  d.add front
  d.arrange(rect(0, 0, 70, 21))
  setFocus(d, ok)

# --- scene 3: live network-event visualizer -------------------------------------

proc netvizScene(d: Desktop) =
  d.add newStatusBar(@[statusItem("Esc Quit", Command(1))])
  let win = newWindow("network events - nim-brokers live", rect(0, 0, 0, 0))
  win.dock = dkFill
  let nv = newNetVizWidget()
  nv.dock = dkFill
  for (t, p) in [("peer", "connected 16Uiu2HAm...  #1"),
                 ("relay", "subscribed /waku/2/rs/0/1  #2"),
                 ("relay", "push 1.2 kB msgHash=0xa1f3...  #3"),
                 ("store", "archive insert ok  #4"),
                 ("peer", "score +1  #5"),
                 ("relay", "duplicate ignored  #6"),
                 ("store", "query served (12 msgs)  #7"),
                 ("peer", "disconnected 16Uiu2HAk...  #8")]:
    nv.addEvent(t, p)
  win.add nv
  d.add win
  d.arrange(rect(0, 0, 80, 15))
  setFocus(d, nv)

when isMainModule:
  shoot("gallery", 80, 24, galleryScene)
  shoot("windows", 70, 21, windowsScene)
  shoot("netviz", 80, 15, netvizScene)
