## TreeView (Phase 26, plan-4): a collapsible outline. ▸/▾ mark branches;
## Up/Down navigate the flattened visible rows, Right expands (or descends),
## Left collapses (or ascends to the parent), Enter toggles a branch or
## activates a leaf. Children may be supplied up front or via a lazy `loader`
## fired on first expand. Slots: onSelect (row moved), onActivate (leaf Enter).
##
## Scrolling (deviation #43): PgUp/PgDn page the selection; the wheel moves
## the viewport by a row without moving the selection. Rows wider than the
## view scroll horizontally: Shift+Left/Right by `hScrollStep` columns,
## Shift+Home/End to either edge, Shift+wheel; `◀`/`▶` mark a row clipped on
## that side. `setRoots` swaps in a rebuilt tree keeping expansion, selection
## and scroll, matched by node path (`key`, else `label`) — for live trees
## refreshed on a timer.

import std/[sets, unicode]
import ../core/[geometry, theme, view, drawcontext, events]

type
  TreeNode* = ref object
    label*: string
    children*: seq[TreeNode]
    expanded*: bool
    loader*: proc(n: TreeNode): seq[TreeNode] {.gcsafe, raises: [].}
    loaded*: bool
    key*: string ## stable identity for `setRoots`; "" = use `label`

  TreeView* = ref object of View
    roots*: seq[TreeNode]
    selected*: int # index into the flattened visible list
    top*: int      # first visible row
    scrollX*: int  # first visible column (horizontal scroll)
    hScrollStep*: int = 4 # columns per Shift+Left/Right / Shift+wheel notch
    onSelect*: proc(sender: TreeView) {.gcsafe, raises: [].}
    onActivate*: proc(sender: TreeView) {.gcsafe, raises: [].}

  VisRow = tuple[node: TreeNode, depth: int]

proc treeNode*(label: string, children: seq[TreeNode] = @[], key = ""): TreeNode =
  TreeNode(label: label, children: children, key: key)

func id(n: TreeNode): string =
  if n.key.len > 0: n.key else: n.label

proc kids(n: TreeNode): seq[TreeNode] =
  if not n.loaded and n.loader != nil:
    n.children = n.loader(n)
    n.loaded = true
  n.children

proc hasKids*(n: TreeNode): bool =
  n.children.len > 0 or (n.loader != nil and not n.loaded)

proc newTreeView*(roots: seq[TreeNode] = @[]): TreeView =
  result = TreeView(roots: roots)
  initView(result)
  result.focusable = true
  result.hint = (prefHint(20, stretch = 1), prefHint(6, stretch = 1))

proc collect(nodes: seq[TreeNode], depth: int, acc: var seq[VisRow]) =
  for n in nodes:
    acc.add (n, depth)
    if n.expanded:
      collect(n.kids, depth + 1, acc)

proc visibleRows*(t: TreeView): seq[VisRow] =
  collect(t.roots, 0, result)

proc selectedNode*(t: TreeView): TreeNode =
  let v = t.visibleRows
  if t.selected >= 0 and t.selected < v.len: v[t.selected].node else: nil

# --- horizontal scroll --------------------------------------------------------

func rowWidth(n: TreeNode, depth: int): int =
  depth * 2 + 2 + n.label.runeLen # indent + marker + label

proc contentWidth*(t: TreeView): int =
  ## Widest visible row, in cells.
  for (n, d) in t.visibleRows:
    result = max(result, rowWidth(n, d))

proc scrollMaxX*(t: TreeView): int =
  max(t.contentWidth - t.contentW, 0)

proc scrollToX*(t: TreeView, x: int) =
  let nx = clamp(x, 0, t.scrollMaxX)
  if nx != t.scrollX:
    t.scrollX = nx
    t.invalidate()

proc scrollByX*(t: TreeView, dx: int) =
  t.scrollToX(t.scrollX + dx)

proc scrollRows(t: TreeView, dy: int) =
  ## Viewport only; the selection stays where it is (ListView wheel rule).
  let n = t.visibleRows.len
  t.top = clamp(t.top + dy, 0, max(n - max(t.contentH, 1), 0))
  t.invalidate()

proc ensureVis(t: TreeView, count: int) =
  let h = max(t.contentH, 1)
  if t.selected < t.top: t.top = t.selected
  elif t.selected >= t.top + h: t.top = t.selected - h + 1
  t.top = clamp(t.top, 0, max(count - 1, 0))

proc selectRow(t: TreeView, idx: int, fire = true) =
  let v = t.visibleRows
  if v.len == 0: return
  t.selected = clamp(idx, 0, v.len - 1)
  t.ensureVis(v.len)
  if fire and t.onSelect != nil: t.onSelect(t)
  t.invalidate()

proc expand*(t: TreeView) =
  let n = t.selectedNode
  if n != nil and n.hasKids and not n.expanded:
    discard n.kids # trigger the lazy load
    n.expanded = true
    t.invalidate()

proc collapse*(t: TreeView) =
  let n = t.selectedNode
  if n != nil and n.expanded:
    n.expanded = false
    t.invalidate()

# --- live refresh -------------------------------------------------------------

proc collectState(nodes: seq[TreeNode], prefix: string, expanded: var HashSet[string]) =
  for n in nodes:
    let path = prefix & "/" & n.id
    if n.expanded:
      expanded.incl path
    collectState(n.children, path, expanded) # loaded children only, no loader call

proc applyState(nodes: seq[TreeNode], prefix: string,
                oldPaths, expanded: HashSet[string]) =
  for n in nodes:
    let path = prefix & "/" & n.id
    if path in oldPaths: # known node: the user's expand/collapse wins
      n.expanded = path in expanded and n.hasKids
    if n.expanded:
      discard n.kids # lazy branch restored open: load it
    applyState(n.children, path, oldPaths, expanded)

proc collectPaths(nodes: seq[TreeNode], prefix: string, acc: var HashSet[string]) =
  for n in nodes:
    let path = prefix & "/" & n.id
    acc.incl path
    collectPaths(n.children, path, acc)

proc rowPath(v: seq[VisRow], idx: int): string =
  ## "/root/…/node" of visible row `idx` (walks back up the depth chain).
  if idx < 0 or idx >= v.len:
    return ""
  var parts = @[v[idx].node.id]
  var d = v[idx].depth
  var i = idx - 1
  while i >= 0 and d > 0:
    if v[i].depth == d - 1:
      parts.insert(v[i].node.id, 0)
      dec d
    dec i
  for p in parts:
    result.add "/" & p

proc setRoots*(t: TreeView, roots: seq[TreeNode]) =
  ## Replace the tree, keeping what the user did with the old one: nodes whose
  ## path (`key`, else `label`, from the root) existed before keep their
  ## expanded state; new nodes keep their own. The selection follows its node
  ## (else stays at its index, clamped); viewport and horizontal scroll are
  ## kept, clamped. Programmatic: `onSelect` does not fire.
  let oldRows = t.visibleRows
  let selPath = rowPath(oldRows, t.selected)
  var expanded, oldPaths: HashSet[string]
  collectState(t.roots, "", expanded)
  collectPaths(t.roots, "", oldPaths)
  applyState(roots, "", oldPaths, expanded)
  t.roots = roots
  let v = t.visibleRows
  var sel = -1
  if selPath.len > 0:
    for i in 0 ..< v.len:
      if rowPath(v, i) == selPath:
        sel = i
        break
  t.selected = if sel >= 0: sel else: clamp(t.selected, 0, max(v.len - 1, 0))
  t.top = clamp(t.top, 0, max(v.len - max(t.contentH, 1), 0))
  t.ensureVis(v.len)
  t.scrollX = clamp(t.scrollX, 0, t.scrollMaxX)
  t.invalidate()

proc toParent(t: TreeView) =
  let v = t.visibleRows
  if t.selected >= v.len: return
  let d = v[t.selected].depth
  if d == 0: return
  var i = t.selected - 1
  while i >= 0 and v[i].depth >= d:
    dec i
  if i >= 0:
    t.selectRow(i)

method draw*(t: TreeView, dc: DrawContext) {.gcsafe, raises: [].} =
  let v = t.visibleRows
  let normal = t.styleOf(tkList)
  let sel = t.styleOf(if t.isFocused: tkSelectionFocused else: tkSelection)
  dc.fill(rect(0, 0, t.contentW, t.contentH), " ", normal) # list surface
  for y in 0 ..< max(t.contentH, 0):
    let idx = t.top + y
    if idx >= v.len: break
    let (node, depth) = v[idx]
    let st = if idx == t.selected: sel else: normal
    if idx == t.selected:
      dc.fill(rect(0, y, t.contentW, 1), " ", st)
    let marker = if node.hasKids: (if node.expanded: "▾ " else: "▸ ") else: "  "
    let x0 = depth * 2 - t.scrollX
    dc.write(x0, y, marker & node.label, st)
    if x0 < 0 and x0 + rowWidth(node, 0) > 0:
      dc.write(0, y, "◀", st) # clipped on the left
    if x0 + rowWidth(node, 0) > t.contentW and t.contentW > 0:
      dc.write(t.contentW - 1, y, "▶", st) # clipped on the right

method handleEvent*(t: TreeView, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    if modAlt in ev.ikey.keyMods:
      return false
    if ev.ikey.isTabSwitch:
      return false # Ctrl+PgUp/PgDn switch tabs (deviation #39)
    if modShift in ev.ikey.keyMods:
      case ev.ikey.key
      of Key.Left: t.scrollByX(-t.hScrollStep)
      of Key.Right: t.scrollByX(t.hScrollStep)
      of Key.Home: t.scrollToX(0)
      of Key.End: t.scrollToX(t.scrollMaxX)
      else: return false
      return true
    let n = t.selectedNode
    let page = max(t.contentH, 1)
    case ev.ikey.key
    of Key.Up: t.selectRow(t.selected - 1)
    of Key.Down: t.selectRow(t.selected + 1)
    of Key.Home: t.selectRow(0)
    of Key.End: t.selectRow(t.visibleRows.len - 1)
    of Key.PageUp: t.selectRow(max(t.selected - page, 0))
    of Key.PageDown: t.selectRow(t.selected + page)
    of Key.Right:
      if n != nil and n.hasKids and not n.expanded: t.expand()
      elif n != nil and n.expanded: t.selectRow(t.selected + 1) # descend
    of Key.Left:
      if n != nil and n.expanded: t.collapse()
      else: t.toParent()
    of Key.Enter:
      if n != nil and n.hasKids:
        if n.expanded: t.collapse() else: t.expand()
      elif t.onActivate != nil:
        t.onActivate(t)
    else:
      return false
    return true
  of evMouse:
    let shift = modShift in ev.imouse.mouseMods
    case ev.imouse.action
    of maWheelUp:
      if shift: t.scrollByX(-t.hScrollStep) else: t.scrollRows(-1)
      return true
    of maWheelDown:
      if shift: t.scrollByX(t.hScrollStep) else: t.scrollRows(1)
      return true
    else:
      discard
    if ev.imouse.action == maPress:
      let v = t.visibleRows
      let idx = t.top + ev.imouse.my
      if idx >= 0 and idx < v.len:
        t.selected = idx
        let (node, depth) = v[idx]
        # a click on the ▸/▾ marker toggles; elsewhere just selects
        let cx = ev.imouse.mx + t.scrollX # column in content space
        if node.hasKids and cx >= depth * 2 and cx <= depth * 2 + 1:
          if node.expanded: t.collapse() else: t.expand()
        else:
          if t.onSelect != nil: t.onSelect(t)
        t.invalidate()
      return true
  of evFocusGained, evFocusLost:
    t.invalidate()
  else:
    discard
  false
