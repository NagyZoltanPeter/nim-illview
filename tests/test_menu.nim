## Phase 23 exit criteria (plan-4): nested submenus (open right, navigate,
## close a level), keyboard/accelerator activation that closes the whole
## chain, and command gating (disabled items grey + skip + refuse). Driven
## through a minimal modal harness (root closures stand in for the App). No
## terminal.

import std/[unittest, unicode]
import chronos
import brokers
import ../src/illview/core/[geometry, view, events, bus, routing]
import ../src/illview/widgets/menu

var modals: seq[Group]
var published: seq[Command]
var offCmds: seq[Command]

proc newHarness(): Group =
  modals.setLen(0); published.setLen(0); offCmds.setLen(0)
  let root = newGroup()
  root.bounds = rect(0, 0, 60, 20)
  root.runModalCb = proc(g: Group) {.gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      root.add g # attach so g.root == root and endModal resolves
      modals.add g
  root.endModalCb = proc(cmd: Command) {.gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      if modals.len > 0:
        root.remove modals.pop()
  root.publishCb = proc(a: UiAction) {.gcsafe, raises: [].} =
    {.cast(gcsafe).}: published.add a.cmd
  root.commandEnabledCb = proc(c: Command): bool {.gcsafe, raises: [].} =
    {.cast(gcsafe).}: c notin offCmds
  root

proc fileMenu(): MenuBar =
  result = newMenuBar(@[menu("~F~ile", @[
    menuItem("~O~pen", Command(1)),
    submenuItem("~R~ecent", @[
      menuItem("a.txt", Command(2)),
      menuItem("b.txt", Command(3))]),
    menuItem("~Q~uit", Command(4))])])
  result.dock = dkTop

proc top(): Group = modals[^1]

suite "menu accelerators + submenus (plan-4 P23)":
  test "Alt+F opens the File menu via the hotkey router":
    let root = newHarness()
    let mb = fileMenu(); root.add mb; root.arrangeChildren()
    check dispatchKey(root, keyEvent(Key.None, "f".runeAt(0), {modAlt}))
    check modals.len == 1

  test "submenu opens to the side and Enter activates, closing the chain":
    let root = newHarness()
    let mb = fileMenu(); root.add mb; root.arrangeChildren()
    discard dispatchKey(root, keyEvent(Key.None, "f".runeAt(0), {modAlt}))
    discard dispatchKey(top(), keyEvent(Key.Down))  # Open -> Recent
    discard dispatchKey(top(), keyEvent(Key.Right))  # open Recent submenu
    check modals.len == 2
    discard dispatchKey(top(), keyEvent(Key.Enter))  # a.txt
    check published == @[Command(2)]
    check modals.len == 0 # both popups closed

  test "Escape closes one level at a time":
    let root = newHarness()
    let mb = fileMenu(); root.add mb; root.arrangeChildren()
    discard dispatchKey(root, keyEvent(Key.None, "f".runeAt(0), {modAlt}))
    discard dispatchKey(top(), keyEvent(Key.Down))
    discard dispatchKey(top(), keyEvent(Key.Right))
    check modals.len == 2
    discard dispatchKey(top(), keyEvent(Key.Escape))
    check modals.len == 1 # back to the parent dropdown
    discard dispatchKey(top(), keyEvent(Key.Escape))
    check modals.len == 0

  test "item accelerator activates directly":
    let root = newHarness()
    let mb = fileMenu(); root.add mb; root.arrangeChildren()
    discard dispatchKey(root, keyEvent(Key.None, "f".runeAt(0), {modAlt}))
    discard dispatchKey(top(), keyEvent(Key.None, "q".runeAt(0)))
    check published == @[Command(4)]
    check modals.len == 0

suite "menu command gating (D19, deferred from P22)":
  test "disabled item is skipped by the initial selection and refuses accel":
    let root = newHarness()
    offCmds = @[Command(1)] # Open disabled
    let mb = fileMenu(); root.add mb; root.arrangeChildren()
    discard dispatchKey(root, keyEvent(Key.None, "f".runeAt(0), {modAlt}))
    # 'o' accelerator points at the disabled Open -> nothing happens
    discard dispatchKey(top(), keyEvent(Key.None, "o".runeAt(0)))
    check published.len == 0
    check modals.len == 1 # menu stays open
    # a still-enabled accelerator works
    discard dispatchKey(top(), keyEvent(Key.None, "q".runeAt(0)))
    check published == @[Command(4)]

# --- iteration-5: persistent popups + onActivate + declarative + context -----

var fired: seq[string]

EventBroker:
  type OpenReq = object
    tag*: int

EventBroker:
  type OpenReqFrom = object
    senderId*: int

suite "persistent popups (iteration-5, item 2)":
  test "opening the same menu twice reuses ONE popup object":
    let root = newHarness()
    let mb = fileMenu(); root.add mb; root.arrangeChildren()
    discard dispatchKey(root, keyEvent(Key.None, "f".runeAt(0), {modAlt}))
    let first = top()
    discard dispatchKey(top(), keyEvent(Key.Escape))
    check modals.len == 0
    discard dispatchKey(root, keyEvent(Key.None, "f".runeAt(0), {modAlt}))
    check top() == first # same object — built once, re-added, not rebuilt

suite "onActivate + declarative items (iteration-5, 2b)":
  setup:
    fired.setLen(0)

  test "item(label, closure) runs onActivate and closes the chain":
    let root = newHarness()
    let mb = menuBar(menu("~F~ile", @[
      item("~R~un", proc() {.gcsafe, raises: [].} =
        {.cast(gcsafe).}: fired.add "run"),
      sep(),
      item("~Q~uit", Command(9))]))
    mb.dock = dkTop; root.add mb; root.arrangeChildren()
    discard dispatchKey(root, keyEvent(Key.None, "f".runeAt(0), {modAlt}))
    discard dispatchKey(top(), keyEvent(Key.None, "r".runeAt(0)))
    check fired == @["run"]
    check modals.len == 0

  test "item(label, EventType) auto-emits the broker event":
    var got = 0
    check OpenReq.listen(proc(ev: OpenReq): Future[void] {.async: (raises: []), gcsafe.} =
      {.cast(gcsafe).}: inc got).isOk
    let root = newHarness()
    let mb = menuBar(menu("~F~ile", @[item("~O~pen", OpenReq)]))
    mb.dock = dkTop; root.add mb; root.arrangeChildren()
    discard dispatchKey(root, keyEvent(Key.None, "f".runeAt(0), {modAlt}))
    discard dispatchKey(top(), keyEvent(Key.None, "o".runeAt(0)))
    waitFor sleepAsync(10.milliseconds)
    check got == 1
    waitFor OpenReq.dropAllListeners()

  test "item(label, EventType) emits on the host's session ctx with senderId":
    let uiCtx = NewBrokerContext()
    setThreadBrokerContext(uiCtx)   # a host-installed scope (deviation #27)
    var got: seq[int]
    var gotDefault = 0
    check OpenReqFrom.listen(uiCtx,
      proc(ev: OpenReqFrom): Future[void] {.async: (raises: []), gcsafe.} =
        {.cast(gcsafe).}: got.add ev.senderId).isOk
    check OpenReqFrom.listen(
      proc(ev: OpenReqFrom): Future[void] {.async: (raises: []), gcsafe.} =
        {.cast(gcsafe).}: inc gotDefault).isOk
    let root = newHarness()
    let mb = menuBar(menu("~F~ile", @[item("~O~pen", OpenReqFrom)]))
    mb.dock = dkTop; root.add mb; root.arrangeChildren()
    check mb.sessionCtx == uiCtx
    discard dispatchKey(root, keyEvent(Key.None, "f".runeAt(0), {modAlt}))
    discard dispatchKey(top(), keyEvent(Key.None, "o".runeAt(0)))
    waitFor sleepAsync(10.milliseconds)
    check got == @[mb.id]   # senderId = the popup's host: the menu bar
    check gotDefault == 0   # nothing leaks to the ambient default ctx
    waitFor OpenReqFrom.dropAllListeners(uiCtx)
    waitFor OpenReqFrom.dropAllListeners()
    setThreadBrokerContext(DefaultBrokerContext)

  test "sep() is skipped by keyboard navigation":
    let root = newHarness()
    let mb = menuBar(menu("~F~ile", @[
      item("one", proc() {.gcsafe, raises: [].} = ({.cast(gcsafe).}: fired.add "one")),
      sep(),
      item("two", proc() {.gcsafe, raises: [].} = ({.cast(gcsafe).}: fired.add "two"))]))
    mb.dock = dkTop; root.add mb; root.arrangeChildren()
    discard dispatchKey(root, keyEvent(Key.None, "f".runeAt(0), {modAlt}))
    discard dispatchKey(top(), keyEvent(Key.Down)) # one -> skips sep -> two
    discard dispatchKey(top(), keyEvent(Key.Enter))
    check fired == @["two"]

suite "ContextMenu (iteration-5, item 2)":
  test "openAt remembers the source; reuses one object; action reads it":
    let root = newHarness()
    let target = newGroup()
    target.bounds = rect(0, 0, 4, 1)
    root.add target
    root.arrangeChildren()
    var ctx: ContextMenu
    ctx = newContextMenu(@[
      item("Inspect", proc() {.gcsafe, raises: [].} =
        {.cast(gcsafe).}: fired.add "inspect:" & $ctx.source.id)])
    fired.setLen(0)
    ctx.openAt(target, point(5, 5))
    check modals.len == 1
    check ContextMenu(top()).source == View(target)
    discard dispatchKey(top(), keyEvent(Key.Enter))
    check fired == @["inspect:" & $target.id]
    check modals.len == 0
    # reuse: same object next open
    ctx.openAt(target, point(1, 1))
    check top() == ctx
