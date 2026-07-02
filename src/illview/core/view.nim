## View / Group — the retained view tree (§3.4) and the framework Event
## (§3.5; defined here rather than events.nim, deviation #7).
##
## Widgets reach the App only through two closures installed on the ROOT
## group (deviation #4): `invalidateCb` (redraw request) and `publishCb`
## (broker publish). Detached subtrees simply no-op.

import ./geometry, ./theme, ./events, ./drawcontext, ./bus

export bus.Command, bus.cmdNone, bus.UiAction

type
  EventKind* = enum
    evKey, evMouse, evFocusGained, evFocusLost, evCommand, evResize, evPaste

  View* = ref object of RootObj
    id*: int # unique per process; UiAction.senderId
    bounds*: Rect # relative to parent's client area
    parent*: Group
    hint*: tuple[w, h: SizeHint]
    dock*: Dock
    visible*: bool
    enabled*: bool
    focusable*: bool
    theme*: Theme # nil = inherit from parent chain

  Group* = ref object of View
    children*: seq[View] # z-order: index 0 = bottom, last = topmost
    focused*: View       # focused child; chain root->leaf is the app focus
    # Set on the ROOT group by App; reached via invalidate()/publish()/
    # runModal()/endModal(). Widgets never see the App itself (deviation #4).
    invalidateCb*: proc() {.gcsafe, raises: [].}
    publishCb*: proc(a: UiAction) {.gcsafe, raises: [].}
    runModalCb*: proc(g: Group) {.gcsafe, raises: [].}
    endModalCb*: proc(cmd: Command) {.gcsafe, raises: [].}

  Event* = object
    case kind*: EventKind
    of evKey:
      ikey*: InputEvent
    of evMouse:
      imouse*: InputEvent # coords translated to target-local by routing
    of evCommand:
      cmd*: Command
      sender*: View
    of evPaste:
      pasteText*: string
    of evFocusGained, evFocusLost, evResize:
      discard

var gNextViewId: int # plain int: safe to touch from gcsafe code; single loop thread

proc initView*(v: View) =
  ## Every widget constructor must call this.
  inc gNextViewId
  v.id = gNextViewId
  v.visible = true
  v.enabled = true
  v.hint = (SizeHint(), SizeHint()) # defaults: max unbounded

proc newGroup*(): Group =
  result = Group()
  initView(result)

# --- base methods ----------------------------------------------------------

method draw*(v: View, dc: DrawContext) {.base, gcsafe, raises: [].} =
  discard

method measure*(v: View): tuple[w, h: SizeHint] {.base, gcsafe, raises: [].} =
  v.hint

method arrange*(v: View, r: Rect) {.base, gcsafe, raises: [].} =
  v.bounds = r

method handleEvent*(v: View, ev: Event): bool {.base, gcsafe, raises: [].} =
  ## true = consumed (stops bubbling)
  false

method clientRect*(v: View): Rect {.base, gcsafe, raises: [].} =
  ## The area (in local coords) that children live in; Window shrinks it by
  ## its frame. Routing and drawing both honor it, so hit-testing and
  ## rendering can never disagree.
  rect(0, 0, v.bounds.w, v.bounds.h)

method draw*(g: Group, dc: DrawContext) {.gcsafe, raises: [].} =
  let cdc = dc.sub(g.clientRect)
  for child in g.children:
    if child.visible:
      child.draw(cdc.sub(child.bounds))

func stripLen(h: SizeHint, remaining: int): int =
  min(clamp(h.pref, h.min, h.max), remaining)

proc arrangeChildren*(g: Group) {.gcsafe, raises: [].} =
  ## Dock-aware arrangement of direct children inside clientRect (plan §1
  ## "dock anchors"). Docked children consume edge strips sized by their
  ## measured hint; dkFill takes what remains; dkNone keeps manual bounds.
  ## Recurses via child.arrange either way, so a resize reflows the tree.
  let cr = g.clientRect
  var rem = rect(0, 0, cr.w, cr.h)
  for c in g.children:
    if not c.visible:
      continue
    let hints = c.measure()
    case c.dock
    of dkNone:
      c.arrange(c.bounds)
    of dkFill:
      c.arrange(rem)
    of dkTop:
      let h = stripLen(hints.h, rem.h)
      c.arrange(rect(rem.x, rem.y, rem.w, h))
      rem.y += h
      rem.h -= h
    of dkBottom:
      let h = stripLen(hints.h, rem.h)
      c.arrange(rect(rem.x, rem.y + rem.h - h, rem.w, h))
      rem.h -= h
    of dkLeft:
      let w = stripLen(hints.w, rem.w)
      c.arrange(rect(rem.x, rem.y, w, rem.h))
      rem.x += w
      rem.w -= w
    of dkRight:
      let w = stripLen(hints.w, rem.w)
      c.arrange(rect(rem.x + rem.w - w, rem.y, w, rem.h))
      rem.w -= w

method arrange*(g: Group, r: Rect) {.gcsafe, raises: [].} =
  g.bounds = r
  g.arrangeChildren()

# --- tree ------------------------------------------------------------------

proc root*(v: View): View =
  result = v
  while result.parent != nil:
    result = result.parent

proc invalidate*(v: View) {.gcsafe, raises: [].} =
  ## Request a redraw. Widgets call this after mutating visual state.
  let r = v.root
  if r of Group and Group(r).invalidateCb != nil:
    Group(r).invalidateCb()

proc publish*(v: View, cmd: Command) {.gcsafe, raises: [].} =
  ## Publish a UiAction on the app bus (no-op when detached or cmdNone).
  if cmd == cmdNone:
    return
  let r = v.root
  if r of Group and Group(r).publishCb != nil:
    Group(r).publishCb(UiAction(cmd: cmd, senderId: v.id))

proc runModal*(v: View, g: Group) {.gcsafe, raises: [].} =
  ## Open g as a transient modal (menus, dialogs). No-op when detached.
  let r = v.root
  if r of Group and Group(r).runModalCb != nil:
    Group(r).runModalCb(g)

proc endModal*(v: View, cmd: Command) {.gcsafe, raises: [].} =
  ## Close the topmost modal. No-op when detached.
  let r = v.root
  if r of Group and Group(r).endModalCb != nil:
    Group(r).endModalCb(cmd)

func isFocused*(v: View): bool =
  ## True when v is the leaf of the root's focused chain.
  var cur = v
  while cur.parent != nil:
    if cur.parent.focused != cur:
      return false
    cur = cur.parent
  true

proc add*(g: Group, child: View) =
  child.parent = g
  g.children.add child

proc remove*(g: Group, child: View) =
  let idx = g.children.find(child)
  if idx >= 0:
    g.children.delete(idx)
    child.parent = nil
    if g.focused == child:
      g.focused = nil

proc raiseToTop*(g: Group, child: View) =
  let idx = g.children.find(child)
  if idx >= 0 and idx < g.children.high:
    g.children.delete(idx)
    g.children.add child
    child.invalidate()

func effectiveTheme*(v: View): Theme =
  var cur = v
  while cur != nil:
    if cur.theme != nil:
      return cur.theme
    cur = cur.parent
  nil

proc styleOf*(v: View, tok: ThemeToken): Style =
  let t = v.effectiveTheme
  if t != nil:
    t.style(tok)
  else:
    Style() # drawing without a theme: illwill defaults (fgNone/bgNone)

func absOrigin*(v: View): Point =
  ## Absolute buffer position of this view's local (0,0).
  var cur = v
  while cur != nil:
    result.x += cur.bounds.x
    result.y += cur.bounds.y
    if cur.parent != nil:
      let cr = cur.parent.clientRect
      result.x += cr.x
      result.y += cr.y
    cur = cur.parent
