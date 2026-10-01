## Phase 5 demo: the Phase-4 gallery rebuilt declaratively — pragma-annotated
## view types + mount(T); `bindTo:` wires handlers, `action:` wires broker
## commands, the `ui:` block covers dynamic content (list items, extra
## buttons). Behaves like ex04: Tab/mouse/F10 menu, ESC quits.

import std/strformat
import chronos
import illview
import illview/dsl/pragmas
import illview/dsl/mount

const
  cmdQuit = Command(101)
  cmdMenu = Command(110)
  cmdRun = Command(120)

var gLog: TextView # handler sink; single loop thread (examples keep it simple)

proc logLine(s: string) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    if gLog != nil:
      gLog.addLine s

# --- declarative screen -------------------------------------------------------

type
  FormPane {.view, vbox, spacing: 1.} = ref object of Group
    heading {.child, caption: "Name:".}: Label
    name {.child, caption: "type here", bindTo: "onSubmitName".}: Input
    feature {.child, caption: "enable feature", bindTo: "onFeature".}: Checkbox
    mm {.child, bindTo: "onMm".}: Radio
    run {.child, caption: "Run", action: cmdRun, bindTo: "onRun".}: Button

  RightPane {.view, vbox, spacing: 1.} = ref object of Group
    lst {.child, bindTo: "onItem".}: ListView
    ed {.child, bindTo: "onEdit".}: Editor

  MainRow {.view, hbox, spacing: 2.} = ref object of Group
    form {.child, stretch: 1.}: FormPane
    right {.child, stretch: 2.}: RightPane

  GalleryWin {.view, title: "declarative gallery", vbox, spacing: 1,
               dock: dkFill.} = ref object of Window
    row {.child, stretch: 3.}: MainRow
    log {.child, stretch: 1.}: TextView

proc onSubmitName(self: FormPane, s: Input) {.gcsafe, raises: [].} =
  logLine "input SUBMIT: " & s.text

proc onFeature(self: FormPane, s: Checkbox) {.gcsafe, raises: [].} =
  logLine &"checkbox: {s.checked}"

proc onMm(self: FormPane, s: Radio) {.gcsafe, raises: [].} =
  logLine "radio: " & s.items[s.selected]

proc onRun(self: FormPane, s: Button) {.gcsafe, raises: [].} =
  logLine "button: onClick (before publish)"

proc onItem(self: RightPane, s: ListView) {.gcsafe, raises: [].} =
  logLine "list ACTIVATE: " & s.items[s.selected]

proc onEdit(self: RightPane, s: Editor) {.gcsafe, raises: [].} =
  logLine "editor changed"

# --- bus (tier 2) --------------------------------------------------------------

type DemoBus = ref object of EventBus
  app: App
  mb: MenuBar

method publish(bus: DemoBus, a: UiAction) {.gcsafe, raises: [].} =
  logLine &"bus: UiAction(cmd: {int(a.cmd)}, sender: {a.senderId})"
  if a.cmd == cmdQuit:
    bus.app.stop()
  elif a.cmd == cmdMenu:
    bus.mb.openMenu(0)

proc main() {.async.} =
  let app = newApp()

  let win = mount(GalleryWin)
  {.cast(gcsafe).}: # module-global sink; single loop thread
    gLog = win.log
  win.row.form.mm.setItems @["refc", "orc", "arc"]

  # dynamic content via the ui: escape hatch
  var items: seq[string]
  for i in 1 .. 30:
    items.add &"list item {i:02}"
  win.row.right.lst.setItems items
  ui(Group(win.row.form.children[0])): # the form's vbox container
    it.add newLabel("(labels added via ui: block)")

  let mb = newMenuBar(@[
    menu("File", @[menuItem("Run", cmdRun), menuItem("Quit", cmdQuit)])])
  app.bus = DemoBus(app: app, mb: mb)
  app.desktop.add mb
  app.desktop.add newStatusBar(@[
    statusItem("F10 Menu", cmdMenu), statusItem("Esc Quit", cmdQuit)])
  app.desktop.add win

  logLine "declarative gallery ready"

  app.onInput = proc(ev: InputEvent) {.gcsafe, raises: [].} =
    if ev.kind == ikKey:
      case ev.key
      of Key.Escape: app.stop()
      of Key.F10: mb.openMenu(0)
      else: discard

  await app.run()

waitFor main()
