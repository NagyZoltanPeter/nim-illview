## Phase 22 exit criteria (plan-4 P22/D19): tilde hotkey parsing, Alt+letter
## routing, Label.linkTo focus, and command enable/disable gating activation.
## No terminal.

import std/[unittest, unicode]
import ../src/illview/core/[geometry, view, events, bus, routing, hotkey]
import ../src/illview/widgets/[button, checkbox, label, input, statusbar, tristate]

const cmd = Command(7)

suite "parseHotkey":
  test "tilde markup extracts key, column and clean text":
    let h = parseHotkey("~F~ile")
    check h.text == "File"
    check h.key == "F".runeAt(0)
    check h.col == 0
  test "accelerator mid-word":
    let h = parseHotkey("E~x~it")
    check h.text == "Exit"
    check h.key == "x".runeAt(0)
    check h.col == 1
  test "single leading tilde also works":
    let h = parseHotkey("~Save")
    check h.text == "Save"
    check h.col == 0
  test "no tilde: whole string, no accelerator":
    let h = parseHotkey("Plain")
    check h.text == "Plain"
    check h.key == Rune(0)
    check h.col == -1
  test "case-insensitive matching":
    check hotkeyMatches("F".runeAt(0), "f".runeAt(0))
    check not hotkeyMatches(Rune(0), "f".runeAt(0)) # no accelerator

suite "command enable/disable (D19)":
  test "disabled command blocks button activation and greys it":
    let root = newGroup()
    root.bounds = rect(0, 0, 40, 4)
    var off: seq[Command]
    root.commandEnabledCb = proc(c: Command): bool {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: c notin off
    let btn = newButton("Go", cmd)
    var clicks = 0
    btn.onClick = proc(s: Button) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: inc clicks
    root.add btn
    root.arrangeChildren()
    setFocus(root, btn)
    discard dispatchKey(root, keyEvent(Key.Enter))
    check clicks == 1              # enabled: fires
    off.add cmd                    # disable it
    discard dispatchKey(root, keyEvent(Key.Enter))
    check clicks == 1              # disabled: blocked

  test "disabled status item does not publish":
    let root = newGroup()
    root.bounds = rect(0, 0, 40, 2)
    var off = @[cmd]
    var published: seq[int]
    root.commandEnabledCb = proc(c: Command): bool {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: c notin off
    root.publishCb = proc(a: UiAction) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: published.add a.senderId
    let sb = newStatusBar(@[statusItem("Menu", cmd)])
    root.add sb
    root.arrangeChildren()
    # click the item span (x starts at 1)
    dispatchMouse(root, mouseEvent(maPress, mbLeft, 3, 1))
    check published.len == 0 # disabled -> consumed but not published

suite "Alt+letter hotkey routing":
  test "Alt+accelerator triggers the matching button anywhere in scope":
    let root = newGroup()
    root.bounds = rect(0, 0, 40, 6)
    let btn = newButton("~R~un")
    var clicks = 0
    btn.onClick = proc(s: Button) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: inc clicks
    root.add btn
    root.arrangeChildren()
    check dispatchKey(root, keyEvent(Key.None, "r".runeAt(0), {modAlt}))
    check clicks == 1

  test "checkbox accelerator toggles it":
    let root = newGroup()
    root.bounds = rect(0, 0, 40, 6)
    let cb = newCheckbox("~A~ccept")
    root.add cb
    root.arrangeChildren()
    check dispatchKey(root, keyEvent(Key.None, "a".runeAt(0), {modAlt}))
    check cb.checked

  test "tri-state accelerator cycles it":
    let root = newGroup()
    root.bounds = rect(0, 0, 40, 6)
    let tc = newTriStateCheckBox("~S~elect all")
    root.add tc
    root.arrangeChildren()
    check dispatchKey(root, keyEvent(Key.None, "s".runeAt(0), {modAlt}))
    check tc.state == csChecked

  test "label accelerator focuses its linked control":
    let root = newGroup()
    root.bounds = rect(0, 0, 40, 6)
    let inp = newInput()
    let lbl = newLabel("~N~ame")
    lbl.linkTo = inp
    root.add lbl
    root.add inp
    root.arrangeChildren()
    check dispatchKey(root, keyEvent(Key.None, "n".runeAt(0), {modAlt}))
    check root.focusedLeaf == View(inp)

  test "no match: Alt+letter is not consumed":
    let root = newGroup()
    root.bounds = rect(0, 0, 40, 6)
    root.add newButton("~R~un")
    root.arrangeChildren()
    check not dispatchKey(root, keyEvent(Key.None, "z".runeAt(0), {modAlt}))
