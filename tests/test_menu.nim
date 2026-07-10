## Phase 23 exit criteria (plan-4): nested submenus (open right, navigate,
## close a level), keyboard/accelerator activation that closes the whole
## chain, and command gating (disabled items grey + skip + refuse). Driven
## through a minimal modal harness (root closures stand in for the App). No
## terminal.

import std/[unittest, unicode]
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
