## TreeView (Phase 26, plan-4): a collapsible outline. ▸/▾ mark branches;
## Up/Down navigate the flattened visible rows, Right expands (or descends),
## Left collapses (or ascends to the parent), Enter toggles a branch or
## activates a leaf. Children may be supplied up front or via a lazy `loader`
## fired on first expand. Slots: onSelect (row moved), onActivate (leaf Enter).

import ../core/[geometry, theme, view, drawcontext, events]

type
  TreeNode* = ref object
    label*: string
    children*: seq[TreeNode]
    expanded*: bool
    loader*: proc(n: TreeNode): seq[TreeNode] {.gcsafe, raises: [].}
    loaded*: bool

  TreeView* = ref object of View
    roots*: seq[TreeNode]
    selected*: int # index into the flattened visible list
    top*: int      # first visible row
    onSelect*: proc(sender: TreeView) {.gcsafe, raises: [].}
    onActivate*: proc(sender: TreeView) {.gcsafe, raises: [].}

  VisRow = tuple[node: TreeNode, depth: int]

proc treeNode*(label: string, children: seq[TreeNode] = @[]): TreeNode =
  TreeNode(label: label, children: children)

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
  let normal = t.styleOf(tkText)
  let sel = t.styleOf(if t.isFocused: tkSelectionFocused else: tkSelection)
  for y in 0 ..< max(t.contentH, 0):
    let idx = t.top + y
    if idx >= v.len: break
    let (node, depth) = v[idx]
    let st = if idx == t.selected: sel else: normal
    if idx == t.selected:
      dc.fill(rect(0, y, t.contentW, 1), " ", st)
    let marker = if node.hasKids: (if node.expanded: "▾ " else: "▸ ") else: "  "
    dc.write(depth * 2, y, marker & node.label, st)

method handleEvent*(t: TreeView, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    if modAlt in ev.ikey.keyMods:
      return false
    let n = t.selectedNode
    case ev.ikey.key
    of Key.Up: t.selectRow(t.selected - 1)
    of Key.Down: t.selectRow(t.selected + 1)
    of Key.Home: t.selectRow(0)
    of Key.End: t.selectRow(t.visibleRows.len - 1)
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
    if ev.imouse.action == maPress:
      let v = t.visibleRows
      let idx = t.top + ev.imouse.my
      if idx >= 0 and idx < v.len:
        t.selected = idx
        let (node, depth) = v[idx]
        # a click on the ▸/▾ marker toggles; elsewhere just selects
        if node.hasKids and ev.imouse.mx >= depth * 2 and
           ev.imouse.mx <= depth * 2 + 1:
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
