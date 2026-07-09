## View / Group — the retained view tree (§3.4) and the framework Event
## (§3.5; defined here rather than events.nim, deviation #7).
##
## Decoration model (iteration 2, plan-2 D1/D2): border, border title and
## shadow are View-level properties drawn by the PARENT group; the base
## clientRect insets by the border. Coordinate convention: the DrawContext a
## view receives in draw() and the mouse coords it receives in handleEvent
## are relative to its CONTENT area (clientRect); child.bounds is relative
## to the parent's content area. A view's own border cells are addressable
## at -1 / contentW in its local space.
##
## Widgets reach the App only through closures installed on the ROOT group
## (deviation #4): invalidate/publish/runModal/endModal. Detached subtrees
## simply no-op.

import std/unicode
import brokers/broker_context
import ./geometry, ./theme, ./events, ./drawcontext, ./bus

export bus.Command, bus.cmdNone, bus.UiAction
export broker_context.BrokerContext

type
  EventKind* = enum
    evKey, evMouse, evFocusGained, evFocusLost, evCommand, evResize, evPaste

  BorderKind* = enum
    bkNone, bkSingle, bkDouble

  StyleOverride* = object
    ## Per-view style overrides merged over the theme token (plan-2 D2).
    ## fgNone/bgNone = inherit from the theme.
    fg*: ForegroundColor
    bg*: BackgroundColor
    bright*: bool # applied together with a fg override
    focusFg*: ForegroundColor
    focusBg*: BackgroundColor

  View* = ref object of RootObj
    id*: int # unique per process; UiAction.senderId
    brokerCtx*: BrokerContext # instance route (plan-3 D7): vocab events out, signals in
    disposers*: seq[proc() {.gcsafe, raises: [].}] # broker teardowns, run by dispose()
    bounds*: Rect # relative to parent's CONTENT area
    parent*: Group
    hint*: tuple[w, h: SizeHint] # content-size hints (border added on top)
    dock*: Dock
    visible*: bool
    enabled*: bool
    focusable*: bool
    theme*: Theme # nil = inherit from parent chain
    border*: BorderKind
    borderTitle*: string
    shadow*: bool
    styleOv*: StyleOverride

  Group* = ref object of View
    children*: seq[View] # z-order: index 0 = bottom, last = topmost
    focused*: View       # focused child; chain root->leaf is the app focus
    mouseCapture*: View  # meaningful on the ROOT group; set via captureMouse
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
      imouse*: InputEvent # coords translated to target-CONTENT-local
    of evCommand:
      cmd*: Command
      sender*: View
    of evPaste:
      pasteText*: string
    of evFocusGained, evFocusLost, evResize:
      discard

var gNextViewId: int # plain int: safe to touch from gcsafe code; single loop thread

let gAppClassCtx = NewBrokerContext()
  ## One classCtx for the whole process; every View gets an instanceCtx under
  ## it (plan-3 D7). Recycled by dispose() via releaseInstanceCtx.

proc initView*(v: View) =
  ## Every widget constructor must call this.
  inc gNextViewId
  v.id = gNextViewId
  v.brokerCtx = newInstanceCtx(gAppClassCtx)
  v.visible = true
  v.enabled = true
  v.hint = (SizeHint(), SizeHint()) # defaults: max unbounded

proc newGroup*(): Group =
  result = Group()
  initView(result)

# --- tree walking (needed by styleOf below) ---------------------------------

proc root*(v: View): View =
  result = v
  while result.parent != nil:
    result = result.parent

func isFocused*(v: View): bool =
  ## True when v is the leaf of the root's focused chain.
  var cur = v
  while cur.parent != nil:
    if cur.parent.focused != cur:
      return false
    cur = cur.parent
  true

func effectiveTheme*(v: View): Theme =
  var cur = v
  while cur != nil:
    if cur.theme != nil:
      return cur.theme
    cur = cur.parent
  nil

proc styleOf*(v: View, tok: ThemeToken): Style =
  ## Theme token -> per-view override -> focus override (plan-2 D2).
  let t = v.effectiveTheme
  result = if t != nil: t.style(tok) else: Style()
  let o = v.styleOv
  if o.fg != fgNone:
    result.fg = o.fg
    result.bright = o.bright
  if o.bg != bgNone:
    result.bg = o.bg
  if (o.focusFg != fgNone or o.focusBg != bgNone) and v.isFocused:
    if o.focusFg != fgNone:
      result.fg = o.focusFg
    if o.focusBg != bgNone:
      result.bg = o.focusBg

# --- base methods ------------------------------------------------------------

method draw*(v: View, dc: DrawContext) {.base, gcsafe, raises: [].} =
  ## dc is the view's CONTENT area (border already handled by the parent).
  discard

method measure*(v: View): tuple[w, h: SizeHint] {.base, gcsafe, raises: [].} =
  ## CONTENT size hints; layout adds the border via outerHints().
  v.hint

method arrange*(v: View, r: Rect) {.base, gcsafe, raises: [].} =
  v.bounds = r

method handleEvent*(v: View, ev: Event): bool {.base, gcsafe, raises: [].} =
  ## true = consumed (stops bubbling)
  false

method borderKind*(v: View): BorderKind {.base, gcsafe, raises: [].} =
  ## Effective border; widgets may compute it (Window: double when active).
  v.border

method clientRect*(v: View): Rect {.base, gcsafe, raises: [].} =
  ## The content area (in full-rect local coords). Drawing, hit-testing and
  ## child placement all honor it, so they can never disagree.
  let i = if v.borderKind == bkNone: 0 else: 1
  rect(i, i, max(v.bounds.w - 2 * i, 0), max(v.bounds.h - 2 * i, 0))

method borderStyle*(v: View): Style {.base, gcsafe, raises: [].} =
  v.styleOf(tkBorder)

method titleStyle*(v: View): Style {.base, gcsafe, raises: [].} =
  v.styleOf(tkBorder)

method drawOverlay*(v: View, dc: DrawContext) {.base, gcsafe, raises: [].} =
  ## Adornments on the FULL rect (dc spans bounds incl. border cells), drawn
  ## by the parent after the border and the content (e.g. resize handle).
  discard

func contentW*(v: View): int = v.clientRect.w
func contentH*(v: View): int = v.clientRect.h

proc outerHints*(v: View): tuple[w, h: SizeHint] =
  ## measure() plus the border cells — what layout must allocate.
  result = v.measure()
  if v.borderKind != bkNone:
    template infl(h: untyped) =
      h.min += 2
      h.pref += 2
      if h.max != high(int):
        h.max += 2
    infl(result.w)
    infl(result.h)

method draw*(g: Group, dc: DrawContext) {.gcsafe, raises: [].} =
  ## Children in z-order, each decorated (shadow, border, title) and then
  ## drawn clipped to its content area.
  for child in g.children:
    if not child.visible:
      continue
    let b = child.bounds
    if child.shadow:
      let sh = child.styleOf(tkShadow)
      dc.shade(rect(b.x + 2, b.y + b.h, b.w, 1), sh)
      dc.shade(rect(b.x + b.w, b.y + 1, 2, b.h), sh)
    let bk = child.borderKind
    if bk != bkNone:
      dc.box(b, child.borderStyle, double = bk == bkDouble)
      if child.borderTitle.len > 0 and b.w >= 4:
        let t = " " & child.borderTitle & " "
        let x = b.x + max((b.w - t.runeLen) div 2, 1)
        dc.write(x, b.y, t, child.titleStyle)
    child.draw(dc.sub(b).sub(child.clientRect))
    child.drawOverlay(dc.sub(b))

# --- app access via root closures --------------------------------------------

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

proc captureMouse*(v: View) {.gcsafe, raises: [].} =
  ## Route all mouse events to v until the next release (drag support).
  let r = v.root
  if r of Group:
    Group(r).mouseCapture = v

proc releaseMouse*(v: View) {.gcsafe, raises: [].} =
  let r = v.root
  if r of Group and Group(r).mouseCapture == v:
    Group(r).mouseCapture = nil

# --- broker teardown (plan-3 D11) ---------------------------------------------

proc dispose*(v: View) {.gcsafe, raises: [].} =
  ## Tear down broker wiring for v's subtree, leaves first: run the recorded
  ## disposers (ctx-scoped listener drops, signal handler removal) and recycle
  ## each view's brokerCtx. Deliberately NOT called by remove(): transient
  ## reparenting (menus, window re-adds) must keep wiring alive — call dispose
  ## exactly once, when a subtree is permanently done. Broker registrations
  ## hold strong refs to the view (closure captures), so an undisposed view is
  ## kept alive by the broker registry under refc and ORC alike.
  if v of Group:
    for c in Group(v).children:
      dispose(c)
  for d in v.disposers:
    d()
  v.disposers.setLen 0
  releaseInstanceCtx(v.brokerCtx)
  v.brokerCtx = BrokerContext(0) # inert: signals err, emits reach nobody

# --- tree mutation ------------------------------------------------------------

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

# --- dock arrangement ----------------------------------------------------------

func stripLen(h: SizeHint, remaining: int): int =
  min(clamp(h.pref, h.min, h.max), remaining)

proc arrangeChildren*(g: Group) {.gcsafe, raises: [].} =
  ## Dock-aware arrangement of direct children inside clientRect (plan §1
  ## "dock anchors"). Docked children consume edge strips sized by their
  ## measured hint (incl. border); dkFill takes what remains; dkNone keeps
  ## manual bounds. Recurses via child.arrange, so a resize reflows the tree.
  let cr = g.clientRect
  var rem = rect(0, 0, cr.w, cr.h)
  for c in g.children:
    if not c.visible:
      continue
    let hints = c.outerHints()
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

func absOrigin*(v: View): Point =
  ## Absolute buffer position of this view's CONTENT (0,0).
  var cur = v
  while cur != nil:
    let cr = cur.clientRect
    result.x += cur.bounds.x + cr.x
    result.y += cur.bounds.y + cr.y
    cur = cur.parent
