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
  of bgWhite: "#e5e5e5" # true white-ish: a stray bgWhite shows in the docs
  of bgGray: "#a8a8a8"  # TV lightgray (deviation #37)

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

# --- scene: TV visual language (deviation #34) --------------------------------

proc tvDialogScene(d: Desktop) =
  ## Turbo Vision's demo dialog rebuilt with stock widgets: gray dialog
  ## palette, borderless cyan clusters, blue field, shadowed buttons.
  d.add newMenuBar(@[menu("~F~ile", @[menuItem("Quit", Command(1))]),
                     menu("~W~indow", @[menuItem("Tile", Command(2))])])
  d.add newStatusBar(@[statusItem("Alt-X Exit", Command(1)),
                       statusItem("Alt-F3 Close", Command(2))])
  let dlg = newWindow("Demo Dialog", rect(12, 2, 46, 15))
  dlg.palette = pGray
  dlg.zoomable = false
  dlg.shadow = true
  let body = newVBox(spacing = 1)
  body.dock = dkFill
  body.padding = 1
  let row = newHBox(spacing = 3)
  row.hint = (prefHint(0, stretch = 1), fixedHint(4))
  let cheeses = newGroupBox("Cheeses")
  cheeses.hint = (fixedHint(16), fixedHint(3))
  let cb = newVBox()
  cb.dock = dkFill
  cb.add newCheckbox("~H~varti")
  cb.add newCheckbox("~T~ilset")
  cb.add newCheckbox("~J~arlsberg", checked = true)
  cheeses.add cb
  let cons = newGroupBox("Consistency")
  cons.hint = (fixedHint(13), fixedHint(3))
  let rad = newRadio(@["Solid", "Runny", "Melted"], selected = 1)
  rad.dock = dkFill
  cons.add rad
  row.add cheeses
  row.add cons
  body.add row
  let lbl = newLabel("~D~elivery Instructions")
  let inp = newInput("Leave it on the doorstep")
  lbl.linkTo = inp
  body.add lbl
  body.add inp
  let btns = newHBox(spacing = 2)
  btns.hint = (prefHint(0, stretch = 1), fixedHint(1))
  let gap = newLabel("")
  gap.hint = (prefHint(0, stretch = 1), fixedHint(1))
  btns.add gap
  let ok = newButton("O~K~")
  ok.isDefault = true
  btns.add ok
  btns.add newButton("~C~ancel")
  body.add btns
  dlg.add body
  d.add dlg
  setFocus(d, inp)

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
  let nv = newNetViz()
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

# --- scene 4: iteration-4 — tree | list split, submenu bar, scrollbar --------

proc featuresScene(d: Desktop) =
  d.add newMenuBar(@[
    menu("~F~ile", @[menuItem("~O~pen", Command(1)),
                     submenuItem("~R~ecent", @[menuItem("a.nim", Command(2))]),
                     menuItem("~Q~uit", Command(3))]),
    menu("~V~iew", @[menuItem("Refresh", Command(4))])])
  d.add newStatusBar(@[statusItem("Tab move", Command(9)),
                       statusItem("Esc Quit", Command(8))])
  let win = newWindow("iteration 4 — tree | list", rect(0, 0, 0, 0))
  win.dock = dkFill
  let tree = newTreeView(@[
    treeNode("src", @[
      treeNode("core", @[treeNode("view.nim"), treeNode("routing.nim")]),
      treeNode("widgets", @[treeNode("treeview.nim"), treeNode("splitter.nim")])]),
    treeNode("docs", @[treeNode("README.md")])])
  tree.roots[0].expanded = true
  tree.roots[0].children[0].expanded = true
  tree.roots[0].children[1].expanded = true
  var items: seq[string]
  for i in 1 .. 20:
    items.add &"event {i:02}"
  let lst = newListView(items)
  lst.showScrollbar = true
  let split = newSplitter(axH, tree, lst, pos = 28)
  split.dock = dkFill
  win.add split
  d.add win
  d.arrange(rect(0, 0, 80, 22))
  lst.select(2)
  setFocus(d, tree)

# --- scene 5: a stock dialog over a backdrop ---------------------------------

proc dialogScene(d: Desktop) =
  let bg = newWindow("editor", rect(0, 0, 0, 0))
  bg.dock = dkFill
  d.add bg
  let dlg = newWindow("Confirm", rect(10, 3, 30, 7))
  dlg.palette = pGray # what messageBox/confirm build (deviation #34)
  dlg.closable = false
  dlg.zoomable = false
  dlg.shadow = true
  let lbl = newLabel("Save changes before exit?")
  lbl.dock = dkTop
  dlg.add lbl
  let row = newHBox(spacing = 1)
  row.dock = dkBottom
  let yes = newButton("~Y~es")
  yes.isDefault = true
  row.add yes
  row.add newButton("~N~o")
  dlg.add row
  d.add dlg
  d.arrange(rect(0, 0, 50, 12))
  setFocus(d, yes)

# --- scene 6: the iteration-5 showcase app (ex13) ----------------------------

type ShotTitleBar = ref object of View
proc newShotTitleBar(): ShotTitleBar =
  result = ShotTitleBar(); initView(result)
  result.dock = dkTop; result.hint = (prefHint(0, stretch = 1), fixedHint(1))
method draw(t: ShotTitleBar, dc: DrawContext) =
  let st = style(fgWhite, bgMagenta, bright = true)
  dc.fill(rect(0, 0, t.bounds.w, 1), " ", st)
  let cap = "illview — showcase"
  dc.write(max((t.bounds.w - cap.runeLen) div 2, 0), 0, cap, st)

proc showcaseScene(d: Desktop) =
  d.add newMenuBar(@[menu("~F~ile", @[menuItem("~Q~uit", Command(1))]),
                     menu("~H~elp", @[menuItem("~A~bout", Command(2))])])
  d.add newShotTitleBar()
  let sb = newStatusBar(@[statusItem("↑↓ navigate", cmdNone),
                          statusItem("Enter open", cmdNone),
                          statusItem("Esc quit", cmdNone)])
  sb.setText("14:22:07")
  d.add sb
  let win = newWindow("examples", rect(0, 0, 0, 0)); win.dock = dkFill
  let tree = newTreeView(@[
    treeNode("Widgets", @[treeNode("Buttons & choices"),
      treeNode("Input & validation"), treeNode("List & table")]),
    treeNode("Layout", @[treeNode("Form layout"), treeNode("Splitter")]),
    treeNode("Dialogs", @[treeNode("Message box")])])
  tree.roots[0].expanded = true
  let ground = newGroup()
  let ex = newWindow("Form layout", rect(0, 0, 0, 0)); ex.dock = dkFill
  let f = newFormLayout(spacing = 1); f.dock = dkFill
  f.add newLabel("Host"); f.add newInput("node.example")
  f.add newLabel("Port"); f.add newInput("8000")
  f.add newLabel("TLS"); f.add newCheckbox("", checked = true)
  ex.add f
  ground.add ex
  let split = newSplitter(axH, tree, ground, pos = 22)
  split.dock = dkFill
  win.add split
  d.add win
  d.arrange(rect(0, 0, 84, 24))
  tree.selected = 1 # "Buttons & choices"
  setFocus(d, tree)

when isMainModule:
  shoot("gallery", 80, 24, galleryScene)
  shoot("windows", 70, 21, windowsScene)
  shoot("features", 80, 22, featuresScene)
  shoot("dialog", 50, 12, dialogScene)
  shoot("tvdialog", 70, 20, tvDialogScene)
  shoot("netviz", 80, 15, netvizScene)
  shoot("showcase", 84, 24, showcaseScene)
