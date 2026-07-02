## Phase 5 exit criteria: a declaratively-defined screen produces a tree
## structurally identical to a hand-built equivalent; `action:` sets the
## right command; `bindTo:` wires the right method. No terminal.

import std/unittest
import ../src/illview/core/[geometry, events, bus, view, routing]
import ../src/illview/layout/layout
import ../src/illview/widgets/[window, label, button, checkbox, input, textview]
import ../src/illview/dsl/pragmas
import ../src/illview/dsl/mount

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
