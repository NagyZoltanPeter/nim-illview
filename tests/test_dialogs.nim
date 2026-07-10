## Phase 25 exit criteria (plan-4 D20): stock dialogs resolve their modal
## future on Enter (default), Esc (cancel), accelerator and OK; inputBox maps
## OK->some / Cancel->none. Driven without the TUI — execView pushes the modal
## and endModal completes the future. No terminal.

import std/[unittest, unicode, options]
import chronos
import ../src/illview/core/[geometry, bus, view, events, routing, app]
import ../src/illview/widgets/[dialogs, input]

proc newTestApp(): App =
  result = newApp()
  result.desktop.bounds = rect(0, 0, 50, 16)
  result.desktop.arrange(rect(0, 0, 50, 16))

proc modal(app: App): Group = Group(app.desktop.children[^1])

proc pump() = waitFor sleepAsync(2.milliseconds)

suite "messageBox (plan-4 D20)":
  test "Enter fires the default (first, focused) button":
    let app = newTestApp()
    let fut = messageBox(app, "T", "Proceed?", @[("~O~K", cmOk), ("~C~ancel", cmCancel)])
    check not fut.finished
    discard dispatchKey(app.modal, keyEvent(Key.Enter))
    check fut.finished
    check fut.read() == cmOk

  test "Escape resolves to the cancel command":
    let app = newTestApp()
    let fut = messageBox(app, "T", "Proceed?", @[("~O~K", cmOk), ("~C~ancel", cmCancel)])
    discard dispatchKey(app.modal, keyEvent(Key.Escape))
    check fut.read() == cmCancel

  test "accelerator picks a non-default button":
    let app = newTestApp()
    let fut = messageBox(app, "T", "Proceed?", @[("~O~K", cmOk), ("~C~ancel", cmCancel)])
    discard dispatchKey(app.modal, keyEvent(Key.None, "c".runeAt(0), {modAlt}))
    check fut.read() == cmCancel

suite "confirm (plan-4 D20)":
  test "Yes -> true":
    let app = newTestApp()
    let f = confirm(app, "Sure?")
    discard dispatchKey(app.modal, keyEvent(Key.Enter)) # default = Yes
    pump()
    check f.finished
    check f.read() == true

  test "No via accelerator -> false":
    let app = newTestApp()
    let f = confirm(app, "Sure?")
    discard dispatchKey(app.modal, keyEvent(Key.None, "n".runeAt(0), {modAlt}))
    pump()
    check f.read() == false

suite "inputBox (plan-4 D20)":
  test "typing + Enter -> some(text)":
    let app = newTestApp()
    let f = inputBox(app, "Name", "Enter name:", initial = "wa")
    # the field is focused; type "ku" then Enter accepts
    for r in "ku".runes:
      discard dispatchKey(app.modal, keyEvent(Key.None, r))
    discard dispatchKey(app.modal, keyEvent(Key.Enter))
    pump()
    check f.read() == some("waku")

  test "Escape -> none":
    let app = newTestApp()
    let f = inputBox(app, "Name", "Enter name:")
    discard dispatchKey(app.modal, keyEvent(Key.Escape))
    pump()
    check f.read() == none(string)

  test "filter applies to the field":
    let app = newTestApp()
    let f = inputBox(app, "Port", "Port:", filter = digitsOnly())
    for r in "80a80".runes:
      discard dispatchKey(app.modal, keyEvent(Key.None, r))
    discard dispatchKey(app.modal, keyEvent(Key.Enter))
    pump()
    check f.read() == some("8080")
