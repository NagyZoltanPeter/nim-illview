## Phase 3 demo: size-hint-driven auto-arrange. A status bar docked at the
## bottom of the desktop, a window auto-filling the rest, nested HBox/VBox
## with fixed + stretchy panes. Resize the terminal: everything reflows.
## ESC quits.

import std/strformat
import chronos
import ../src/illview
import ../src/illview/layout/layout

type
  Pane = ref object of View
    label: string
    fg: ForegroundColor
    bg: BackgroundColor

proc newPane(label: string, fg: ForegroundColor, bg: BackgroundColor,
             w, h: SizeHint): Pane =
  result = Pane(label: label, fg: fg, bg: bg)
  initView(result)
  result.hint = (w, h)

method draw(p: Pane, dc: DrawContext) =
  let st = style(p.fg, p.bg)
  dc.fill(rect(0, 0, p.bounds.w, p.bounds.h), " ", st)
  dc.write(1, 0, p.label, st)
  dc.write(1, 1, &"{p.bounds.w}x{p.bounds.h} @ {p.bounds.x},{p.bounds.y}", st)

type
  StatusPane = ref object of View

proc newStatusPane(): StatusPane =
  result = StatusPane()
  initView(result)
  result.hint = (prefHint(0, stretch = 1), fixedHint(1))
  result.dock = dkBottom

method draw(s: StatusPane, dc: DrawContext) =
  let st = s.styleOf(tkStatusBar)
  dc.fill(rect(0, 0, s.bounds.w, 1), " ", st)
  dc.write(1, 0, " resize the terminal to reflow - ESC quits ", st)

proc main() {.async.} =
  let app = newApp()

  let win = newWindow("layout", rect(0, 0, 0, 0))
  win.dock = dkFill

  let rows = newVBox(spacing = 1)
  rows.dock = dkFill

  let topRow = newHBox(spacing = 1)
  topRow.hint = (prefHint(0, stretch = 1), prefHint(0, stretch = 3))
  topRow.add newPane("sidebar (fixed 16)", fgBlack, bgCyan,
                     fixedHint(16), prefHint(0, stretch = 1))
  topRow.add newPane("main (stretch 2)", fgWhite, bgGreen,
                     prefHint(0, stretch = 2), prefHint(0, stretch = 1))
  topRow.add newPane("aux (stretch 1)", fgBlack, bgYellow,
                     prefHint(0, stretch = 1), prefHint(0, stretch = 1))

  let bottomRow = newGrid(cols = 3, spacing = 1)
  bottomRow.hint = (prefHint(0, stretch = 1), prefHint(0, stretch = 1))
  for i in 1 .. 6:
    bottomRow.add newPane(&"grid cell {i}", fgWhite, bgMagenta,
                          prefHint(0, stretch = 1), prefHint(0, stretch = 1))

  rows.add topRow
  rows.add bottomRow
  win.add rows

  app.desktop.add newStatusPane() # docked first: consumes the bottom line
  app.desktop.add win             # then the window fills the rest

  app.onInput = proc(ev: InputEvent) {.gcsafe, raises: [].} =
    if ev.kind == ikKey and ev.key == Key.Escape:
      app.stop()

  await app.run()

waitFor main()
