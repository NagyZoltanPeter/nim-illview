## Phase 26 exit criteria (plan-4): TreeView expand/collapse/navigation +
## lazy loading + activation, and Input history (recency, Enter records, Down
## opens a picker that sets the text). No terminal.

import std/unittest
import ../src/illview/core/[geometry, view, events, routing]
import ../src/illview/widgets/[treeview, input]

proc key(k: Key): Event = Event(kind: evKey, ikey: keyEvent(k))

proc sampleTree(): TreeView =
  let a = treeNode("a", @[treeNode("a1"), treeNode("a2")])
  let b = treeNode("b")
  result = newTreeView(@[a, b])
  result.bounds = rect(0, 0, 20, 10)

suite "TreeView expand / collapse / navigate":
  test "collapsed shows only roots; expand reveals children":
    let tv = sampleTree()
    check tv.visibleRows.len == 2
    discard tv.handleEvent(key(Key.Right)) # expand 'a' (selected 0)
    check tv.roots[0].expanded
    check tv.visibleRows.len == 4          # a, a1, a2, b

  test "Left on a leaf jumps to the parent; Left on a branch collapses":
    let tv = sampleTree()
    discard tv.handleEvent(key(Key.Right)) # expand a
    discard tv.handleEvent(key(Key.Down))  # select a1
    check tv.selectedNode.label == "a1"
    discard tv.handleEvent(key(Key.Left))  # leaf -> parent a
    check tv.selectedNode.label == "a"
    discard tv.handleEvent(key(Key.Left))  # branch -> collapse
    check not tv.roots[0].expanded
    check tv.visibleRows.len == 2

  test "clicking the marker toggles the branch":
    let tv = sampleTree()
    discard tv.handleEvent(Event(kind: evMouse,
      imouse: mouseEvent(maPress, mbLeft, 0, 0))) # marker of row 0
    check tv.roots[0].expanded

suite "TreeView lazy loading + activation":
  test "loader fires on first expand only":
    var loads = 0
    let lazy = treeNode("lazy")
    lazy.loader = proc(n: TreeNode): seq[TreeNode] {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: inc loads
      @[treeNode("child")]
    let tv = newTreeView(@[lazy]); tv.bounds = rect(0, 0, 20, 10)
    check lazy.hasKids # loader present => looks expandable
    check loads == 0
    discard tv.handleEvent(key(Key.Right)) # expand -> load
    check loads == 1
    check tv.visibleRows.len == 2
    discard tv.handleEvent(key(Key.Left))  # collapse
    discard tv.handleEvent(key(Key.Right)) # re-expand: no reload
    check loads == 1

  test "Enter on a leaf activates":
    var got = ""
    let tv = newTreeView(@[treeNode("leaf")]); tv.bounds = rect(0, 0, 20, 10)
    tv.onActivate = proc(s: TreeView) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: got = s.selectedNode.label
    discard tv.handleEvent(key(Key.Enter))
    check got == "leaf"

suite "Input history (plan-4 P26)":
  test "addHistory de-duplicates, bumps recency, and caps":
    let i = newInput(); i.historyMax = 3
    i.addHistory("a"); i.addHistory("b"); i.addHistory("a")
    check i.history == @["a", "b"] # 'a' moved to front
    i.addHistory("c"); i.addHistory("d")
    check i.history == @["d", "c", "a"] # capped at 3, 'b' evicted

  test "Enter records the current text":
    let i = newInput("hello")
    discard i.handleEvent(key(Key.Enter))
    check i.history == @["hello"]

  test "Down opens the picker; Enter sets the text and bumps recency":
    var modals: seq[Group]
    let root = newGroup(); root.bounds = rect(0, 0, 40, 14)
    root.runModalCb = proc(g: Group) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: (root.add g; modals.add g)
    root.endModalCb = proc(cmd: Command) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: (if modals.len > 0: root.remove modals.pop())
    let i = newInput("current")
    i.history = @["old1", "old2"]
    root.add i
    root.arrangeChildren()
    setFocus(root, i)
    discard dispatchKey(root, key(Key.Down).ikey)
    check modals.len == 1
    discard dispatchKey(modals[^1], key(Key.Enter).ikey)
    check modals.len == 0
    check i.text == "old1"
    check i.history[0] == "old1"
