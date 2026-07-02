## Framework-owned input routing (§3.6, LOCKED): mouse = z-order hit-test,
## keys = focus + bubble, Tab/Shift-Tab at the scope root. Pure view-tree
## logic — no chronos, no terminal — fully unit-testable.
##
## All procs take a `scope` Group: the desktop normally, the top modal view
## when a modal is active (deviation #6). Events never escape the scope.

import ./geometry, ./view, ./events

func canFocus*(v: View): bool =
  v.visible and v.enabled and v.focusable

func focusedLeaf*(g: Group): View =
  ## Follow the focused chain to its end. nil when no focus in this scope.
  var cur: View = g
  while cur of Group and Group(cur).focused != nil:
    cur = Group(cur).focused
  if cur == g: nil else: cur

proc setFocus*(scope: Group, v: View) =
  ## Redirect the focused chain to v (must be inside scope; nil clears).
  ## Stale `focused` fields on other branches are kept intentionally: they
  ## are the "last focused child" memory used when a window re-activates.
  let old = scope.focusedLeaf
  if old == v:
    return
  if old != nil:
    discard old.handleEvent(Event(kind: evFocusLost))
  if v == nil:
    scope.focused = nil
  else:
    var cur = v
    while cur != nil and cur.parent != nil:
      cur.parent.focused = cur
      if cur.parent == scope:
        break
      cur = cur.parent
    discard v.handleEvent(Event(kind: evFocusGained))
  scope.invalidate()

proc collectFocusable(g: Group, acc: var seq[View]) =
  for c in g.children:
    if not c.visible or not c.enabled:
      continue
    if c.focusable:
      acc.add c
    if c of Group:
      collectFocusable(Group(c), acc)

proc focusNext*(scope: Group) =
  var acc: seq[View]
  collectFocusable(scope, acc)
  if acc.len == 0:
    return
  let idx = acc.find(scope.focusedLeaf)
  setFocus(scope, acc[(idx + 1) mod acc.len]) # idx == -1 -> first

proc focusPrev*(scope: Group) =
  var acc: seq[View]
  collectFocusable(scope, acc)
  if acc.len == 0:
    return
  let idx = acc.find(scope.focusedLeaf)
  setFocus(scope, if idx <= 0: acc[^1] else: acc[idx - 1])

proc focusInto*(scope: Group, g: Group) =
  ## Focus g's remembered focused child if any, else its first focusable.
  var leaf = g.focusedLeaf
  if leaf == nil or not canFocus(leaf):
    var acc: seq[View]
    collectFocusable(g, acc)
    leaf = if acc.len > 0: acc[0] else: nil
  if leaf != nil:
    setFocus(scope, leaf)

proc hitTest*(g: Group, p: Point): tuple[target: View, local: Point] =
  ## p in g-local coords. Topmost child wins; recurses into groups; falls
  ## back to g itself (frame/background clicks).
  let cr = g.clientRect
  if cr.contains(p):
    let cp = point(p.x - cr.x, p.y - cr.y)
    for i in countdown(g.children.high, 0):
      let c = g.children[i]
      if c.visible and c.bounds.contains(cp):
        let lp = point(cp.x - c.bounds.x, cp.y - c.bounds.y)
        if c of Group:
          return hitTest(Group(c), lp)
        return (c, lp)
  (View(g), p)

proc dispatchMouse*(scope: Group, ev: InputEvent) =
  ## Absolute coords in ev; deliver target-local; bubble unconsumed events
  ## parent-ward (retranslating coords), stopping at scope.
  let so = scope.absOrigin
  let p = point(ev.mx - so.x, ev.my - so.y)

  if ev.action == maPress:
    # raise the scope's direct child (window) under the cursor
    let cr = scope.clientRect
    if cr.contains(p):
      let cp = point(p.x - cr.x, p.y - cr.y)
      for i in countdown(scope.children.high, 0):
        let c = scope.children[i]
        if c.visible and c.bounds.contains(cp):
          raiseToTop(scope, c)
          break

  let (target, local) = hitTest(scope, p)

  if ev.action == maPress:
    var f: View = target
    while f != nil and not canFocus(f):
      if f == scope:
        f = nil
        break
      f = f.parent
    if f != nil:
      setFocus(scope, f)
    elif target != scope and target of Group:
      focusInto(scope, Group(target)) # frame click: focus into the window

  var cur: View = target
  var cp = local
  while cur != nil:
    var mev = ev
    mev.mx = cp.x
    mev.my = cp.y
    if cur.handleEvent(Event(kind: evMouse, imouse: mev)):
      return
    if cur == scope or cur.parent == nil:
      return
    cp.x += cur.bounds.x + cur.parent.clientRect.x
    cp.y += cur.bounds.y + cur.parent.clientRect.y
    cur = cur.parent

proc dispatchKey*(scope: Group, ev: InputEvent): bool =
  ## Deliver to the focused leaf; bubble parent-ward to scope. Unconsumed
  ## Tab / Shift-Tab traverses the focus chain at the scope root.
  var cur: View = scope.focusedLeaf
  if cur == nil:
    cur = scope
  while cur != nil:
    if cur.handleEvent(Event(kind: evKey, ikey: ev)):
      return true
    if cur == scope:
      break
    cur = cur.parent
  if ev.key == Key.Tab:
    if modShift in ev.keyMods:
      focusPrev(scope)
    else:
      focusNext(scope)
    return true
  false

proc dispatchPaste*(scope: Group, text: string): bool =
  var cur: View = scope.focusedLeaf
  if cur == nil:
    return false
  while cur != nil:
    if cur.handleEvent(Event(kind: evPaste, pasteText: text)):
      return true
    if cur == scope:
      break
    cur = cur.parent
  false
