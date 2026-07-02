## Phase 4 demo: a dialog hand-assembled from every widget, closure slots
## wired (tier 1), command-bearing widgets publishing to the bus (tier 2).
## Try: Tab/Shift-Tab, mouse, F10 or click for the menu, type in the input
## and editor, scroll the list/log, ESC quits.

import std/strformat
import chronos
import ../src/illview
import ../src/illview/layout/layout as ivlayout

const
  cmdQuit = Command(101)
  cmdAbout = Command(102)
  cmdMenu = Command(110)
  cmdRun = Command(120)

# tier-2 demo: a bus that logs every UiAction and reacts to commands
type GalleryBus = ref object of EventBus
  app: App
  log: TextView
  mb: MenuBar

method publish(bus: GalleryBus, a: UiAction) {.gcsafe, raises: [].} =
  bus.log.addLine &"bus: UiAction(cmd: {int(a.cmd)}, sender: {a.senderId})"
  if a.cmd == cmdQuit:
    bus.app.stop()
  elif a.cmd == cmdMenu:
    bus.mb.openMenu(0)
  elif a.cmd == cmdAbout:
    bus.log.addLine "bus: illview widget gallery (Phase 4)"

proc main() {.async.} =
  let app = newApp()
  let log = newTextView(maxLines = 200)

  let mb = newMenuBar(@[
    menu("File", @[menuItem("Run", cmdRun), menuItem("Quit", cmdQuit)]),
    menu("Help", @[menuItem("About", cmdAbout)])])
  app.bus = GalleryBus(app: app, log: log, mb: mb)
  app.desktop.add mb
  app.desktop.add newStatusBar(@[
    statusItem("F10 Menu", cmdMenu), statusItem("Esc Quit", cmdQuit)])

  let win = newWindow("widget gallery", rect(0, 0, 0, 0))
  win.dock = dkFill
  let cols = newHBox(spacing = 2)
  cols.dock = dkFill

  # left column: form widgets
  let form = newVBox(spacing = 1)
  form.hint = (prefHint(28, stretch = 1), prefHint(0, stretch = 1))
  form.add newLabel("Name:")
  let inp = newInput("type here")
  inp.onChange = proc(s: Input) {.gcsafe, raises: [].} =
    {.cast(gcsafe).}: log.addLine "input change: " & s.text
  inp.onSubmit = proc(s: Input) {.gcsafe, raises: [].} =
    {.cast(gcsafe).}: log.addLine "input SUBMIT: " & s.text
  form.add inp
  let chk = newCheckbox("enable feature")
  chk.onToggle = proc(s: Checkbox) {.gcsafe, raises: [].} =
    {.cast(gcsafe).}: log.addLine &"checkbox: {s.checked}"
  form.add chk
  let rad = newRadio(@["refc", "orc", "arc"], selected = 1)
  rad.onSelect = proc(s: Radio) {.gcsafe, raises: [].} =
    {.cast(gcsafe).}: log.addLine &"radio: {s.items[s.selected]}"
  form.add rad
  let btn = newButton("Run", command = cmdRun)
  btn.onClick = proc(s: Button) {.gcsafe, raises: [].} =
    {.cast(gcsafe).}: log.addLine "button: onClick (before publish)"
  form.add btn

  # right column: list + editor
  let right = newVBox(spacing = 1)
  right.hint = (prefHint(0, stretch = 2), prefHint(0, stretch = 1))
  var items: seq[string]
  for i in 1 .. 30:
    items.add &"list item {i:02}"
  let lst = newListView(items)
  lst.onSelect = proc(s: ListView) {.gcsafe, raises: [].} =
    {.cast(gcsafe).}: log.addLine "list select: " & s.items[s.selected]
  lst.onActivate = proc(s: ListView) {.gcsafe, raises: [].} =
    {.cast(gcsafe).}: log.addLine "list ACTIVATE: " & s.items[s.selected]
  right.add lst
  let ed = newEditor("multiline editor\nno wrap, no undo (v1)\nend.")
  ed.onChange = proc(s: Editor) {.gcsafe, raises: [].} =
    {.cast(gcsafe).}: log.addLine "editor changed"
  right.add ed

  cols.add form
  cols.add right

  let rows = newVBox(spacing = 1)
  rows.dock = dkFill
  cols.hint = (prefHint(0, stretch = 1), prefHint(0, stretch = 3))
  log.hint = (prefHint(0, stretch = 1), prefHint(5, stretch = 1))
  rows.add cols
  rows.add log
  win.add rows
  app.desktop.add win

  log.addLine "gallery ready - interact away"

  app.onInput = proc(ev: InputEvent) {.gcsafe, raises: [].} =
    if ev.kind == ikKey:
      case ev.key
      of Key.Escape: app.stop()
      of Key.F10: mb.openMenu(0)
      else: discard

  await app.run()

waitFor main()
