## Phase 26 exit criteria (plan-4): TreeView expand/collapse/navigation +
## lazy loading + activation, and Input history (recency, Enter records, Down
## opens a picker that sets the text). No terminal.

import std/[strutils, unittest]
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

suite "TreeView scrolling + live refresh (deviation #43)":
  proc shiftKey(k: Key): Event = Event(kind: evKey, ikey: keyEvent(k, mods = {modShift}))
  proc wheel(a: MouseAction, mods: set[Modifier] = {}): Event =
    Event(kind: evMouse, imouse: mouseEvent(a, mbNone, 0, 0, mods))

  test "Shift+Left/Right/Home/End scroll horizontally, clamped":
    let tv = newTreeView(@[treeNode("x".repeat(30))]) # row width 32
    tv.bounds = rect(0, 0, 10, 5)
    check tv.scrollMaxX == 22
    check tv.handleEvent(shiftKey(Key.Right))
    check tv.scrollX == 4
    discard tv.handleEvent(shiftKey(Key.End))
    check tv.scrollX == 22
    discard tv.handleEvent(shiftKey(Key.Right)) # clamped at the edge
    check tv.scrollX == 22
    discard tv.handleEvent(shiftKey(Key.Left))
    check tv.scrollX == 18
    discard tv.handleEvent(shiftKey(Key.Home))
    check tv.scrollX == 0
    check not tv.roots[0].expanded # plain Left/Right meaning untouched

  test "no horizontal scroll when everything fits":
    let tv = sampleTree()
    check tv.scrollMaxX == 0
    discard tv.handleEvent(shiftKey(Key.Right))
    check tv.scrollX == 0

  test "wheel moves the viewport, not the selection; Shift+wheel is horizontal":
    var roots: seq[TreeNode]
    for i in 0 ..< 20: roots.add treeNode("row " & $i & " " & "y".repeat(20))
    let tv = newTreeView(roots)
    tv.bounds = rect(0, 0, 10, 5)
    check tv.handleEvent(wheel(maWheelDown))
    check tv.top == 1
    check tv.selected == 0
    for _ in 0 ..< 30: discard tv.handleEvent(wheel(maWheelDown))
    check tv.top == 15 # 20 rows - 5 visible
    discard tv.handleEvent(wheel(maWheelUp))
    check tv.top == 14
    discard tv.handleEvent(wheel(maWheelDown, {modShift}))
    check tv.scrollX == 4
    check tv.top == 14

  test "PgDn / PgUp page the selection; Ctrl+PgDn bubbles for tab switching":
    var roots: seq[TreeNode]
    for i in 0 ..< 20: roots.add treeNode($i)
    let tv = newTreeView(roots)
    tv.bounds = rect(0, 0, 10, 5)
    discard tv.handleEvent(key(Key.PageDown))
    check tv.selected == 5
    discard tv.handleEvent(key(Key.PageUp))
    check tv.selected == 0
    check not tv.handleEvent(Event(kind: evKey,
      ikey: keyEvent(Key.PageDown, mods = {modCtrl})))

  test "a click on the marker still toggles when scrolled horizontally":
    let tv = newTreeView(@[treeNode("p", @[treeNode("x".repeat(40))])])
    tv.bounds = rect(0, 0, 10, 5)
    tv.roots[0].expanded = true
    tv.scrollToX(2) # row 0 marker now at column -2: off screen
    discard tv.handleEvent(Event(kind: evMouse,
      imouse: mouseEvent(maPress, mbLeft, 0, 0)))
    check tv.roots[0].expanded # column 0 is the label, not the marker
    tv.scrollToX(0)
    discard tv.handleEvent(Event(kind: evMouse,
      imouse: mouseEvent(maPress, mbLeft, 0, 0)))
    check not tv.roots[0].expanded

  proc liveTree(peers: seq[string], extraLabel = ""): seq[TreeNode] =
    ## by-protocol shape: same peer key under several protocols
    for proto in ["relay", "store"]:
      var kids: seq[TreeNode]
      for p in peers:
        kids.add treeNode(p & extraLabel, @[treeNode("addr")], key = p)
      result.add treeNode(proto & " (" & $peers.len & ")", kids, key = proto)

  test "setRoots keeps expansion and selection by key, labels may change":
    let tv = newTreeView(liveTree(@["p1", "p2"]))
    tv.bounds = rect(0, 0, 20, 10)
    tv.roots[1].expanded = true                 # store
    tv.roots[1].children[1].expanded = true     # store/p2
    discard tv.handleEvent(key(Key.Down))       # store
    discard tv.handleEvent(key(Key.Down))       # store/p1
    discard tv.handleEvent(key(Key.Down))       # store/p2
    check tv.selectedNode.key == "p2"
    tv.setRoots(liveTree(@["p0", "p1", "p2"], extraLabel = " *"))
    check not tv.roots[0].expanded              # relay stays collapsed
    check tv.roots[1].expanded                  # store stays open, label "store (3)"
    check tv.roots[1].children[2].expanded      # store/p2 by key
    check not tv.roots[1].children[1].expanded  # store/p1 was collapsed
    check not tv.roots[1].children[0].expanded  # p0 is new: its own default
    check tv.selectedNode.key == "p2"           # followed the node, not the index
    check tv.selectedNode.label == "p2 *"
    # same key under another parent is a different path
    check not tv.roots[0].children[2].expanded

  test "setRoots keeps the state of nodes hidden under a collapsed parent":
    let tv = newTreeView(liveTree(@["p1"]))
    tv.bounds = rect(0, 0, 20, 10)
    tv.roots[0].children[0].expanded = true # relay/p1 open, relay itself closed
    tv.setRoots(liveTree(@["p1"]))
    check not tv.roots[0].expanded
    check tv.roots[0].children[0].expanded

  test "setRoots: removed selection clamps; new nodes keep their own state":
    let tv = newTreeView(@[treeNode("a"), treeNode("b"), treeNode("c")])
    tv.bounds = rect(0, 0, 20, 10)
    discard tv.handleEvent(key(Key.End))
    check tv.selected == 2
    let fresh = treeNode("d", @[treeNode("d1")])
    fresh.expanded = true
    tv.setRoots(@[treeNode("a"), fresh])
    check tv.roots[1].expanded       # "d" never existed before
    check tv.selected == 2           # "c" gone: index kept, clamped to 3 rows
    check tv.selectedNode.label == "d1"

  test "setRoots clamps the horizontal scroll and does not fire onSelect":
    var fired = 0
    let tv = newTreeView(@[treeNode("x".repeat(30))])
    tv.bounds = rect(0, 0, 10, 5)
    tv.onSelect = proc(s: TreeView) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: inc fired
    discard tv.handleEvent(shiftKey(Key.End))
    check tv.scrollX == 22
    tv.setRoots(@[treeNode("x".repeat(12))]) # width 14 -> max 4
    check tv.scrollX == 4
    check fired == 0

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
