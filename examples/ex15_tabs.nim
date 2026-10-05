## Deviation #39 demo: a TabView holding three windows. Each window is
## embedded frameless (its title is the tab label); inactive pages keep their
## state and remembered focus. Switch with Ctrl+PgUp / Ctrl+PgDn, a click on
## a tab, or Tab to the strip and Left / Right. The Log tab is closable (×)
## and uses the blue window palette. ESC quits.

import std/strformat
import chronos
import illview

proc main() {.async.} =
  let app = newApp()
  let status = newStatusBar(@[statusItem("Ctrl+PgUp/PgDn Switch", cmdNone),
                              statusItem("Esc Quit", cmdNone)])
  app.desktop.add status

  let win = newWindow("tabs", rect(0, 0, 0, 0))
  win.dock = dkFill
  let tabs = newTabView()
  tabs.dock = dkFill

  # page 1: a small form
  let form = newWindow("Form", rect(0, 0, 0, 0))
  form.closable = false
  let fl = newFormLayout(spacing = 1)
  fl.dock = dkFill
  fl.padding = 1
  fl.add newLabel("Name")
  let nameIn = newInput("nim-illview")
  fl.add nameIn
  fl.add newLabel("Port")
  fl.add newInput("8000")
  fl.add newLabel("TLS")
  fl.add newCheckbox("enabled", checked = true)
  form.add fl

  # page 2: a list
  let lst = newWindow("List", rect(0, 0, 0, 0))
  lst.closable = false
  var items: seq[string]
  for i in 1 .. 40:
    items.add &"peer {i:02}"
  let lv = newListView(items)
  lv.dock = dkFill
  lv.showScrollbar = true
  lst.add lv

  # page 3: a log, blue palette, closable from its tab
  let logw = newWindow("Log", rect(0, 0, 0, 0))
  logw.palette = pBlue
  let log = newTextView(maxLines = 200)
  log.dock = dkFill
  logw.add log
  log.addLine "tab switches are logged here"

  tabs.addPage(form)
  tabs.addPage(lst)
  tabs.addPage(logw)
  tabs.onSelect = proc(t: TabView) {.gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      log.addLine &"selected tab {t.selected}"
      status.setText &"tab {t.selected + 1}/{t.pages.len}"
  win.add tabs
  app.desktop.add win
  setFocus(app.desktop, nameIn) # keys reach the TabView through the focus

  app.onInput = proc(ev: InputEvent) {.gcsafe, raises: [].} =
    if ev.kind == ikKey and ev.key == Key.Escape:
      app.stop()

  await app.run()

waitFor main()
