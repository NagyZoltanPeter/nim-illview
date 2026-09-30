## Phase 12 (plan-3 D7/D8/D11): instance-ctx vocabulary — widgets emit
## framework events on their own BrokerContext and handle Set-signals on it;
## dispose() tears wiring down and recycles the ctx.
##
## Discipline note: listeners registered HERE (playing the "model" role) are
## OURS to drop before dispose() releases a ctx — dispose only runs the
## widget's own disposers (D11/D12 drop-then-release contract). Skipping the
## drop would leak the listener into a recycled id and contaminate later
## tests through ctx reuse.

import std/[unittest, unicode]
import chronos
import results
import ../src/illview/backend/illwill_vendored
import ../src/illview/core/[geometry, events, view, routing]
import ../src/illview/widgets/[button, checkbox, radio, list, input, editor,
                               label, progress, table]
import ../src/illview/layout/layout
import ../src/illview/vocab

template pump() =
  waitFor sleepAsync(5.milliseconds) # let asyncSpawn'd listeners run

suite "instance-ctx vocab":
  test "two Buttons share the Clicked type but never cross-talk":
    let run = newButton("Run")
    let cancel = newButton("Cancel")
    var runHits, cancelHits: int
    check Clicked.listen(run.brokerCtx,
      proc(): Future[void] {.async: (raises: []), gcsafe.} =
        {.cast(gcsafe).}: inc runHits).isOk
    check Clicked.listen(cancel.brokerCtx,
      proc(): Future[void] {.async: (raises: []), gcsafe.} =
        {.cast(gcsafe).}: inc cancelHits).isOk

    run.activate()
    run.activate()
    cancel.activate()
    pump()
    check runHits == 2
    check cancelHits == 1

    waitFor Clicked.dropAllListeners(run.brokerCtx)
    waitFor Clicked.dropAllListeners(cancel.brokerCtx)
    dispose(run)
    dispose(cancel)

  test "SetText.signal drives an Input; no TextChanged echo":
    let inp = newInput()
    var changes: seq[string]
    check TextChanged.listen(inp.brokerCtx,
      proc(e: TextChanged): Future[void] {.async: (raises: []), gcsafe.} =
        {.cast(gcsafe).}: changes.add e.text).isOk

    check SetText.signal(inp.brokerCtx, SetText(text: "hello")).isOk
    pump()
    check inp.text == "hello"
    check changes.len == 0 # programmatic apply must not re-emit (D8)

    # user edit DOES emit
    discard inp.handleEvent(Event(kind: evKey, ikey: keyEvent(Key.A, Rune('a'))))
    pump()
    check changes == @["helloa"]

    waitFor TextChanged.dropAllListeners(inp.brokerCtx)
    dispose(inp)

  test "Submitted emits on Enter with the snapshot text":
    let inp = newInput(text = "cmd")
    var submitted: seq[string]
    check Submitted.listen(inp.brokerCtx,
      proc(e: Submitted): Future[void] {.async: (raises: []), gcsafe.} =
        {.cast(gcsafe).}: submitted.add e.text).isOk
    discard inp.handleEvent(Event(kind: evKey, ikey: keyEvent(Key.Enter)))
    pump()
    check submitted == @["cmd"]

    waitFor Submitted.dropAllListeners(inp.brokerCtx)
    dispose(inp)

  test "Toggled / SetChecked round-trip on a Checkbox":
    let cb = newCheckbox("accept")
    var toggles: seq[bool]
    check Toggled.listen(cb.brokerCtx,
      proc(e: Toggled): Future[void] {.async: (raises: []), gcsafe.} =
        {.cast(gcsafe).}: toggles.add e.checked).isOk

    cb.toggle()
    pump()
    check toggles == @[true]

    check SetChecked.signal(cb.brokerCtx, SetChecked(checked: false)).isOk
    pump()
    check cb.checked == false
    check toggles == @[true] # signal apply did not re-emit

    waitFor Toggled.dropAllListeners(cb.brokerCtx)
    dispose(cb)

  test "SelectionChanged / Activated / SetSelected on ListView":
    let lv = newListView(@["a", "b", "c"])
    var sels, acts: seq[int]
    check SelectionChanged.listen(lv.brokerCtx,
      proc(e: SelectionChanged): Future[void] {.async: (raises: []), gcsafe.} =
        {.cast(gcsafe).}: sels.add e.selected).isOk
    check Activated.listen(lv.brokerCtx,
      proc(e: Activated): Future[void] {.async: (raises: []), gcsafe.} =
        {.cast(gcsafe).}: acts.add e.selected).isOk

    lv.select(2)
    lv.activate()
    pump()
    check sels == @[2]
    check acts == @[2]

    check SetSelected.signal(lv.brokerCtx, SetSelected(selected: 1)).isOk
    pump()
    check lv.selected == 1
    check sels == @[2] # no echo

    waitFor SelectionChanged.dropAllListeners(lv.brokerCtx)
    waitFor Activated.dropAllListeners(lv.brokerCtx)
    dispose(lv)

  test "SetSelected drives Radio and Table; SetProgress drives ProgressBar":
    let r = newRadio(@["x", "y", "z"])
    check SetSelected.signal(r.brokerCtx, SetSelected(selected: 2)).isOk
    let t = newTable(@[tableColumn("c", fixedHint(3))], @[@["1"], @["2"]])
    check SetSelected.signal(t.brokerCtx, SetSelected(selected: 1)).isOk
    let p = newProgressBar()
    check SetProgress.signal(p.brokerCtx, SetProgress(value: 40)).isOk
    pump()
    check r.selected == 2
    check t.selected == 1
    check p.value == 40
    dispose(r)
    dispose(t)
    dispose(p)

  test "SetText drives Editor and Label":
    let ed = newEditor("one")
    let lb = newLabel("old")
    check SetText.signal(ed.brokerCtx, SetText(text: "one\ntwo")).isOk
    check SetText.signal(lb.brokerCtx, SetText(text: "new")).isOk
    pump()
    check ed.lines == @["one", "two"]
    check lb.text == "new"
    dispose(ed)
    dispose(lb)

  test "FocusMe focuses the widget through the root chain":
    let root = newGroup()
    let a = newInput()
    let b = newInput()
    root.add a
    root.add b
    root.setFocus(a)
    check a.isFocused
    check FocusMe.signal(b.brokerCtx).isOk
    pump()
    check b.isFocused
    check not a.isFocused
    dispose(root)

  test "dispose drops wiring: signals err, events reach nobody":
    let btn = newButton("gone")
    let savedCtx = btn.brokerCtx
    var hits: int
    check Clicked.listen(savedCtx,
      proc(): Future[void] {.async: (raises: []), gcsafe.} =
        {.cast(gcsafe).}: inc hits).isOk
    btn.activate()
    pump()
    check hits == 1

    waitFor Clicked.dropAllListeners(savedCtx) # ours to drop (see header)
    dispose(btn)
    pump() # let dropSignalHandler spawns settle
    check btn.brokerCtx == BrokerContext(0)
    check SetText.signal(savedCtx, SetText(text: "x")).isErr
    check FocusMe.signal(savedCtx).isErr # widget's own handler was dropped
    btn.activate() # emits on ctx 0 — reaches nobody, must not crash
    pump()
    check hits == 1

  test "dispose recurses a subtree and is idempotent":
    let root = newGroup()
    let box = newVBox(0)
    let inner = newInput()
    root.add box
    box.add inner
    let innerCtx = inner.brokerCtx
    check SetText.signal(innerCtx, SetText(text: "alive")).isOk
    pump()
    check inner.text == "alive"

    dispose(root)
    pump()
    check SetText.signal(innerCtx, SetText(text: "dead")).isErr
    dispose(root) # second dispose: strict no-op, must not crash
    pump()
    check inner.text == "alive"

suite "lazy instance ctx (plan-5 P33, deviation #28)":
  test "construction allocates no instance ctx; first use does, in use order":
    var labels: seq[Label]
    for i in 0 ..< 1000:
      labels.add newLabel("l" & $i)
    for l in labels:
      check not l.hasBrokerCtx
    let late = newButton("late")
    let lateCtx = late.brokerCtx        # materialized first
    let earlyCtx = labels[0].brokerCtx  # built earlier, materialized second
    check instanceCtx(earlyCtx) > instanceCtx(lateCtx)
    check labels[0].hasBrokerCtx and late.hasBrokerCtx
    check not labels[1].hasBrokerCtx
    # deferred wiring ran on materialization: the Set-signal handler is live
    check SetText.signal(earlyCtx, SetText(text: "hi")).isOk
    pump()
    check labels[0].text == "hi"
    dispose(late)
    dispose(labels[0])

  test "a widget that never handed out its ctx emits to nobody, no crash":
    let b = newButton("quiet")
    b.activate()
    pump()
    check not b.hasBrokerCtx
    dispose(b)
    check not b.hasBrokerCtx
    check b.brokerCtx == BrokerContext(0) # disposed: never materializes
