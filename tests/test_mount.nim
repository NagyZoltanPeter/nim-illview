## Phase 5 exit criteria: a declaratively-defined screen produces a tree
## structurally identical to a hand-built equivalent; `action:` sets the
## right command; `bindTo:` wires the right method. No terminal.
## Phase 13 (plan-3 D9): `on:` installs ctx-scoped listeners per instance.

import std/unittest
import chronos
import ../src/illview/core/[geometry, events, bus, view, routing]
import ../src/illview/layout/layout
import ../src/illview/widgets/[window, label, button, checkbox, input, textview]
import ../src/illview/dsl/pragmas
import ../src/illview/dsl/mount
import ../src/illview/vocab

const cmdRun = Command(42)

var evLog: seq[string] # handler evidence (module-global on purpose)

type
  FormBox {.view, vbox, spacing: 1.} = ref object of Group
    heading {.child, caption: "Form".}: Label
    name {.child.}: Input
    accept {.child, caption: "accept", bindTo: "onAccept".}: Checkbox
    run {.child, caption: "Run", action: cmdRun, bindTo: "onRun".}: Button

  Screen {.view, title: "Declarative", hbox.} = ref object of Window
    form {.child, stretch: 1.}: FormBox
    log {.child, stretch: 2.}: TextView

proc onAccept(self: FormBox, sender: Checkbox) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    evLog.add "accept:" & $sender.checked

proc onRun(self: FormBox, sender: Button) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    evLog.add "run"

proc sameShape(a, b: View): bool =
  ## Structural comparison: group-ness and child counts, recursively.
  if (a of Group) != (b of Group):
    return false
  if a of Group:
    let ga = Group(a)
    let gb = Group(b)
    if ga.children.len != gb.children.len:
      return false
    for i in 0 ..< ga.children.len:
      if not sameShape(ga.children[i], gb.children[i]):
        return false
  true

suite "mount(T)":
  setup:
    evLog.setLen(0)

  test "tree structure matches a hand-built equivalent":
    let scr = mount(Screen)
    # hand-built equivalent of the declared screen
    let hwin = newWindow("Declarative", rect(0, 0, 0, 0))
    let hcols = newHBox()
    hcols.dock = dkFill
    hwin.add hcols
    let hform = newGroup() # component root, its own vbox inside
    let hformBox = newVBox(spacing = 1)
    hformBox.dock = dkFill
    hform.add hformBox
    hformBox.add newLabel("Form")
    hformBox.add newInput()
    hformBox.add newCheckbox("accept")
    hformBox.add newButton("Run")
    let hlog = newTextView()
    hcols.add hform
    hcols.add hlog
    check sameShape(scr, hwin)
    check scr.title == "Declarative"

  test "fields are constructed, ordered and configured":
    let scr = mount(Screen)
    check scr.form != nil
    check scr.log != nil
    let inner = Group(scr.children[0]) # the hbox container
    check inner of BoxLayout
    check BoxLayout(inner).axis == axH
    check inner.children.len == 2
    check inner.children[0] == View(scr.form)
    check inner.children[1] == View(scr.log)
    check scr.form.hint.w.stretch == 1
    check scr.log.hint.w.stretch == 2
    # nested component: vbox with 4 children in declaration order
    let formInner = Group(scr.form.children[0])
    check formInner of BoxLayout
    check BoxLayout(formInner).axis == axV
    check BoxLayout(formInner).spacing == 1
    check formInner.children.len == 4
    check scr.form.heading.text == "Form"
    check scr.form.run.caption == "Run"

  test "action: sets the command; activation publishes to the bus":
    let scr = mount(Screen)
    check scr.form.run.command == cmdRun
    let root = newGroup()
    root.bounds = rect(0, 0, 80, 24)
    let stub = newStubBus()
    root.publishCb = proc(a: UiAction) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        stub.publish(a)
    root.add scr
    setFocus(root, scr.form.run)
    check dispatchKey(root, keyEvent(Key.Enter))
    check stub.actions.len == 1
    check stub.actions[0].cmd == cmdRun
    check stub.actions[0].senderId == scr.form.run.id

  test "bindTo: wires the named handler to the primary slot":
    let scr = mount(Screen)
    let root = newGroup()
    root.bounds = rect(0, 0, 80, 24)
    root.add scr
    setFocus(root, scr.form.accept)
    discard dispatchKey(root, keyEvent(Key.Space))
    setFocus(root, scr.form.run)
    discard dispatchKey(root, keyEvent(Key.Enter))
    check evLog == @["accept:true", "run"]

  test "ui: block escape hatch for dynamic content":
    let g = newGroup()
    ui(g):
      for i in 1 .. 3:
        it.add newLabel("row " & $i)
    check g.children.len == 3
    check Label(g.children[1]).text == "row 2"

# --- on: pragma (plan-3 D9) ----------------------------------------------------

type
  CtxForm {.view, vbox.} = ref object of Group
    run {.child, caption: "Run", on: {Clicked: "onCtxRun"}.}: Button
    cancel {.child, caption: "Cancel", on: {Clicked: "onCtxCancel"},
             bindTo: "onCancelSlot".}: Button
    host {.child, on: {TextChanged: "onHostEdit"}.}: Input

proc onCtxRun(self: CtxForm) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    evLog.add "ctx:run"

proc onCtxCancel(self: CtxForm) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    evLog.add "ctx:cancel"

proc onCancelSlot(self: CtxForm, sender: Button) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    evLog.add "slot:cancel"

proc onHostEdit(self: CtxForm, ev: TextChanged) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    evLog.add "host:" & ev.text

template pump() =
  waitFor sleepAsync(5.milliseconds)

suite "mount(T) on: pragma (plan-3 D9)":
  setup:
    evLog.setLen(0)

  test "same event type, two buttons, no cross-talk; bindTo coexists":
    let f = mount(CtxForm)
    f.run.activate()
    f.cancel.activate()
    pump()
    # suspension-free listener tasks run eagerly inside emit (asyncSpawn
    # executes to the first await), so broker handlers land in call order
    check evLog == @["ctx:run", "slot:cancel", "ctx:cancel"]
    dispose(f)

  test "payload arity: handler receives the typed event":
    let f = mount(CtxForm)
    f.host.insertText("ab") # one changed() for the whole insert
    pump()
    check evLog == @["host:ab"]
    dispose(f)

  test "two instances of the same form type are isolated":
    let a = mount(CtxForm)
    let b = mount(CtxForm)
    a.run.activate()
    pump()
    check evLog == @["ctx:run"] # exactly one hit: a's listener only
    b.cancel.activate()
    pump()
    check evLog == @["ctx:run", "slot:cancel", "ctx:cancel"]
    dispose(a)
    dispose(b)

  test "dispose(form) tears down everything mount installed":
    let f = mount(CtxForm)
    dispose(f)
    pump() # let asyncSpawn'd drops settle
    # behavioral check (3.2.0 has no hasListeners): the ctx is inert, so
    # activating the disposed widget reaches nobody.
    f.run.activate()
    pump()
    check evLog.len == 0

# --- plan-4 D14: form container + align/anchors/padding field pragmas ---------

type
  FormScreen {.view, form, spacing: 1.} = ref object of Group
    nameLbl {.child, caption: "Name".}: Label
    name {.child.}: Input
    noteLbl {.child, caption: "Note", alignSelf: alEnd.}: Label
    note {.child, padding: 1.}: Input

  AnchoredScreen {.view.} = ref object of Group
    body {.child, anchors: {aLeft, aTop, aRight, aBottom}.}: TextView

suite "mount(T) plan-4 layout pragmas":
  test "form: container is a FormLayout and lays out label/control pairs":
    let f = mount(FormScreen)
    f.bounds = rect(0, 0, 30, 6)
    check f.children.len == 1
    check f.children[0] of FormLayout      # form pragma selected the container
    f.arrange(rect(0, 0, 30, 6))
    # label column auto-sizes to widest label ("Name"/"Note" => 4); col1 fills
    check f.name.bounds.x == 5             # 4-wide label col + spacing 1
    check f.note.bounds.x == 5

  test "align + padding pragmas reach the widgets":
    let f = mount(FormScreen)
    check f.noteLbl.align == alEnd
    check f.note.padding == 1

  test "anchors pragma sets the edge set; child stretches with the parent":
    let s = mount(AnchoredScreen)
    check s.body.anchor.edges == {aLeft, aTop, aRight, aBottom}
    s.body.bounds = rect(1, 1, 8, 4)
    s.bounds = rect(0, 0, 10, 6)
    s.arrangeChildren()                    # capture at 10x6
    s.bounds = rect(0, 0, 20, 10)          # dw=10, dh=4
    s.arrangeChildren()
    check s.body.bounds == rect(1, 1, 18, 8)

# --- fail-fast (deviation #29) ----------------------------------------------------

type
  Plain = ref object of View # not {.view.}, no createView overload
  BadChild {.view.} = ref object of Group
    p {.child.}: Plain
  Dialish = ref object of View
    built: bool
  GoodChild {.view.} = ref object of Group
    d {.child.}: Dialish
  MisplacedOnType {.view, caption: "x".} = ref object of Group
    l {.child.}: Label
  MisplacedOnField {.view.} = ref object of Group
    b {.child, vbox.}: Button
  NoChild {.view.} = ref object of Group
    l {.caption: "x".}: Label
  BadHandler {.view.} = ref object of Group
    host {.child, on: {TextChanged: "onBadEdit"}.}: Input

proc newDialish(): Dialish =
  result = Dialish(built: true)
  initView(result)

proc createView(t: typedesc[Dialish]): Dialish = newDialish()

proc onBadEdit(self: BadHandler, n: int) {.gcsafe, raises: [].} = discard

suite "mount(T) fail-fast (deviation #29)":
  test "a createView overload makes a custom child first-class":
    let g = mount(GoodChild)
    check g.d.built # the widget's own constructor ran, not a bare Dialish()

  test "a non-{.view.} child without createView is a compile error":
    check not compiles(mount(BadChild))

  test "misplaced DSL pragmas are compile errors":
    check not compiles(mount(MisplacedOnType))
    check not compiles(mount(MisplacedOnField))
    check not compiles(mount(NoChild))

  test "an on: handler with neither accepted shape is a compile error":
    check not compiles(mount(BadHandler))
