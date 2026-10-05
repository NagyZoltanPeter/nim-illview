## Deviation #39: TabView — pages are children, the strip is drawn on top,
## hidden pages are unreachable by focus / mouse / hotkeys, focus is
## remembered per page, Window pages are embedded frameless.

import std/[unittest, unicode, strutils]
import chronos
import ../src/illview/backend/illwill_vendored
import ../src/illview/core/[geometry, theme, view, drawcontext, events, routing]
import ../src/illview/widgets/[tabview, window, button, input, label, list]
import ../src/illview/layout/layout
import ../src/illview/vocab

proc rowStr(tb: TerminalBuffer, y, w: int): string =
  for x in 0 ..< w: result.add $tb[x, y].ch

proc pageWin(title: string, a, b: View): Window =
  result = newWindow(title, rect(0, 0, 0, 0))
  let box = newVBox()
  box.dock = dkFill
  box.add a
  box.add b
  result.add box

proc setup3(): tuple[root: Group, tv: TabView, a1, a2, b1, b2: Button, c: Window] =
  let root = newGroup()
  root.theme = defaultTheme()
  root.bounds = rect(0, 0, 40, 10)
  let tv = newTabView()
  tv.dock = dkFill
  let a1 = newButton("~A~1")
  let a2 = newButton("A2")
  let b1 = newButton("~B~1")
  let b2 = newButton("B2")
  let c = newWindow("Log", rect(0, 0, 0, 0))
  c.add newLabel("only a label")
  tv.addPage(pageWin("Alpha", a1, a2))
  tv.addPage(pageWin("Beta", b1, b2))
  tv.addPage(c)
  root.add tv
  root.arrange(rect(0, 0, 40, 10))
  (root, tv, a1, a2, b1, b2, c)

proc render(root: Group, w, h: int): TerminalBuffer =
  result = newTerminalBuffer(w, h)
  root.arrange(rect(0, 0, w, h))
  root.draw(initDrawContext(result))

suite "TabView (deviation #39)":
  test "pages, selection, frameless windows, strip labels":
    let (root, tv, a1, _, _, _, _) = setup3()
    check tv.pages.len == 3
    check tv.selected == 0
    for p in tv.pages:
      check not Window(p).framed
      check p.visible == (p == tv.page)
    let tb = render(root, 40, 10)
    check rowStr(tb, 0, 40) == " Alpha × ─ Beta × ─ Log × ──────────────"
    check a1.bounds.y == 0 and tv.page.bounds.y == 1 # page below the strip

  test "hidden pages: unreachable by Tab, mouse and hotkeys":
    let (root, tv, a1, a2, b1, _, _) = setup3()
    var seen: seq[View]
    for _ in 0 .. 5:
      focusNext(root)
      seen.add root.focusedLeaf
    check View(b1) notin seen
    check View(a1) in seen and View(a2) in seen
    check not dispatchHotkey(root, "b".runeAt(0)) # B1 is on a hidden page
    check not canFocus(b1)

  test "Ctrl+PgDn / Ctrl+PgUp switch (wrap) and carry focus per page":
    let (root, tv, a1, a2, b1, b2, _) = setup3()
    setFocus(root, a2)
    check dispatchKey(root, keyEvent(Key.PageDown, mods = {modCtrl}))
    check tv.selected == 1
    check root.focusedLeaf == View(b1)  # first focusable on a fresh page
    setFocus(root, b2)
    check dispatchKey(root, keyEvent(Key.PageUp, mods = {modCtrl}))
    check tv.selected == 0
    check root.focusedLeaf == View(a2)  # remembered
    check dispatchKey(root, keyEvent(Key.PageUp, mods = {modCtrl}))
    check tv.selected == 2              # wraps to the last
    check dispatchKey(root, keyEvent(Key.PageDown, mods = {modCtrl}))
    check tv.selected == 0
    check root.focusedLeaf == View(a2)  # fallback on the empty page didn't stick

  test "a page without focusable content leaves focus on the strip":
    let (root, tv, a1, _, _, _, _) = setup3()
    setFocus(root, a1)
    tv.select(2)
    check canFocus(root.focusedLeaf)
    check not root.focusedLeaf.isNil

  test "strip: focusable, Left/Right/Home/End; click selects":
    let (root, tv, _, _, _, _, _) = setup3()
    var focusedStrip = false
    for _ in 0 .. 6:
      focusNext(root)
      if not (root.focusedLeaf of Button): focusedStrip = true; break
    check focusedStrip
    check dispatchKey(root, keyEvent(Key.Right)) and tv.selected == 1
    check dispatchKey(root, keyEvent(Key.End)) and tv.selected == 2
    check dispatchKey(root, keyEvent(Key.Home)) and tv.selected == 0
    check dispatchKey(root, keyEvent(Key.Left)) and tv.selected == 2
    discard render(root, 40, 10)
    dispatchMouse(root, mouseEvent(maPress, mbLeft, 13, 0)) # " Beta × " at x 10..17
    dispatchMouse(root, mouseEvent(maRelease, mbLeft, 13, 0))
    check tv.selected == 1

  test "× closes the page window; a neighbour takes over":
    let (root, tv, _, _, _, _, c) = setup3()
    tv.select(2)
    discard render(root, 40, 10)
    dispatchMouse(root, mouseEvent(maPress, mbLeft, 24, 0)) # × of " Log × " (x 19..25)
    check tv.pages.len == 2
    check c.parent == nil
    check tv.selected == 1 and tv.page.visible

  test "removePage detaches without disposing; the window gets its frame back":
    let (root, tv, _, _, _, _, c) = setup3()
    let beta = tv.pages[1]
    tv.select(1)
    tv.removePage(beta)
    check beta.parent == nil
    check Window(beta).framed and beta.visible
    check tv.pages.len == 2
    check tv.page == View(c) or tv.selected in 0 .. 1
    tv.addPage(beta, "Beta again")       # can be re-added
    check tv.pages.len == 3

  test "removing an earlier page keeps the selected page by identity":
    let (root, tv, _, _, _, _, c) = setup3()
    tv.select(2)                         # Log
    tv.removePage(tv.pages[0])
    check tv.page == View(c)
    check tv.selected == 1

  test "overflow: ◄ ► markers and the selected tab kept visible":
    let root = newGroup()
    root.theme = defaultTheme()
    let tv = newTabView()
    tv.dock = dkFill
    for i in 0 .. 7:
      tv.addPage(newLabel("p" & $i), "Tab" & $i)
    root.add tv
    tv.select(7)
    let tb = render(root, 24, 4)
    let row = rowStr(tb, 0, 24)
    check row.runeAtPos(0) == "◄".runeAt(0)
    check " Tab7 " in row

  test "user switch fires onSelect + SelectionChanged; select() and SetSelected don't":
    let (root, tv, a1, _, _, _, _) = setup3()
    var slot: seq[int]
    var evs: seq[int]
    setFocus(root, a1) # keys route through the focus
    tv.onSelect = proc(s: TabView) {.gcsafe, raises: [].} =
      {.cast(gcsafe).}: slot.add s.selected
    check SelectionChanged.listen(tv.brokerCtx,
      proc(e: SelectionChanged): Future[void] {.async: (raises: []), gcsafe.} =
        {.cast(gcsafe).}: evs.add e.selected).isOk
    discard dispatchKey(root, keyEvent(Key.PageDown, mods = {modCtrl}))
    tv.select(0)
    check SetSelected.signal(tv.brokerCtx, SetSelected(selected: 2)).isOk
    waitFor sleepAsync(5.milliseconds)
    check tv.selected == 2
    check slot == @[1]
    check evs == @[1]
    waitFor SelectionChanged.dropAllListeners(tv.brokerCtx)
    dispose(tv)

  test "clicks don't reorder pages (keepsChildOrder)":
    let (root, tv, a1, _, _, _, _) = setup3()
    let before = tv.pages
    let o = a1.absOrigin
    dispatchMouse(root, mouseEvent(maPress, mbLeft, o.x + 2, o.y))
    dispatchMouse(root, mouseEvent(maRelease, mbLeft, o.x + 2, o.y))
    check tv.pages == before

  test "Ctrl+PgDn switches even when a paging widget (ListView) has focus":
    let root = newGroup()
    root.bounds = rect(0, 0, 40, 10)
    let tv = newTabView()
    tv.dock = dkFill
    var items: seq[string]
    for i in 0 .. 30: items.add "item" & $i
    let lv = newListView(items)
    let lw = newWindow("List", rect(0, 0, 0, 0))
    lv.dock = dkFill
    lw.add lv
    tv.addPage(lw)
    tv.addPage(newWindow("Other", rect(0, 0, 0, 0)))
    root.add tv
    root.arrange(rect(0, 0, 40, 10))
    setFocus(root, lv)
    check dispatchKey(root, keyEvent(Key.PageDown, mods = {modCtrl}))
    check tv.selected == 1
    check lv.selected == 0             # the list did not page
    check isTabSwitch(keyEvent(Key.PageUp, mods = {modCtrl}))
    check not isTabSwitch(keyEvent(Key.PageUp))
