## TabView (deviation #39): a tab container. Every child except the private
## tab strip is a page; the strip is one row on top, the selected page fills
## the rest, the other pages are `visible = false` (so focus traversal,
## hit-testing and hotkeys skip them while their state survives). A `Window`
## page is embedded frameless (`framed = false`); its title is the tab label.
##
## Switching: click a tab; Ctrl+PgUp / Ctrl+PgDn anywhere inside; or focus the
## strip (Tab) and use Left / Right / Home / End. A closable Window page shows
## `×` on its tab: a click calls `close()`. `removePage` detaches without
## disposing. Zero-init safe for `mount(T)`: the strip is created lazily and
## `{.child.}` fields become pages in declaration order.

import std/unicode
import ../core/[geometry, theme, view, drawcontext, events, routing]
import ../vocab
import ./window

type
  TabView* = ref object of Group
    selected*: int
    onSelect*: proc(sender: TabView) {.gcsafe, raises: [].}
    titles: seq[(int, string)] # (page view id, explicit title)
    selView: View              # selected page by identity (survives removals)
    first: int                 # first tab shown when the strip overflows
    strip: TabStrip

  TabStrip = ref object of View
    owner: TabView
    fallback: bool # focus parked here because the page had nothing focusable

  TabSpan = object
    page, x, w: int
    closeX: int # column of `×`, -1 = none

# --- pages --------------------------------------------------------------------

proc ensureStrip(t: TabView) =
  if t.strip == nil:
    let s = TabStrip(owner: t)
    initView(s)
    s.focusable = true
    s.parent = t
    t.children.insert(s, 0)
    t.strip = s

proc pages*(t: TabView): seq[View] =
  for c in t.children:
    if c != View(t.strip):
      result.add c

proc page*(t: TabView): View =
  ## The selected page, nil when there is none.
  let ps = t.pages
  if t.selected >= 0 and t.selected < ps.len: ps[t.selected] else: nil

proc title(t: TabView, p: View, i: int): string =
  for (id, s) in t.titles:
    if id == p.id:
      return s
  if p of Window and Window(p).title.len > 0: Window(p).title
  else: "Page " & $(i + 1)

func closable(p: View): bool =
  p of Window and Window(p).closable

proc isInside(v, g: View): bool =
  var cur = v
  while cur != nil:
    if cur == g:
      return true
    cur = cur.parent
  false

proc focusPage(t: TabView) =
  ## Move focus to the selected page when the focus was inside the TabView
  ## (never steal it from elsewhere; keep it on the strip if it is there).
  let r = t.root
  if not (r of Group):
    return
  let scope = Group(r)
  let leaf = scope.focusedLeaf
  if leaf == nil or not leaf.isInside(t):
    return
  if leaf == View(t.strip) and not t.strip.fallback:
    return # the user put focus on the strip: it stays
  let p = t.page
  if p != nil and p of Group:
    focusInto(scope, Group(p))
  elif p != nil and canFocus(p):
    setFocus(scope, p)
  let now = scope.focusedLeaf
  if now == nil or not canFocus(now) or now == View(t.strip):
    t.strip.fallback = true # page without focusable content: park on the strip
    setFocus(scope, t.strip)
  else:
    t.strip.fallback = false

proc syncPages(t: TabView) =
  ## Reconcile after adds/removals (a page Window's default close() detaches
  ## it behind our back): frameless windows, selection by identity,
  ## visibility, focus repair.
  t.ensureStrip()
  let ps = t.pages
  for p in ps:
    if p of Window:
      Window(p).framed = false
  if ps.len == 0:
    t.selected = 0
    t.selView = nil
    return
  let idx = if t.selView != nil: ps.find(t.selView) else: -1
  if idx >= 0:
    t.selected = idx
  else: # selected page gone: its neighbour takes over
    t.selected = clamp(t.selected, 0, ps.high)
    t.selView = ps[t.selected]
  for i, p in ps:
    p.visible = i == t.selected
  let r = t.root
  if r of Group and Group(r).focusedLeaf == View(t): # focused page was removed
    t.focusPage()

proc addPage*(t: TabView, page: View, title = "") =
  ## Append a page; `title` overrides a Window's own title on the tab.
  t.ensureStrip()
  t.add page
  if title.len > 0:
    t.titles.add (page.id, title)
  if page of Window:
    Window(page).framed = false
  if t.selView == nil:
    t.selView = page
  page.visible = page == t.selView
  t.invalidate()

proc removePage*(t: TabView, page: View) =
  ## Detach a page WITHOUT disposing it (re-add it, or float it as a window).
  if page.parent != t or page == View(t.strip):
    return
  if page of Window:
    Window(page).framed = true
  page.visible = true
  t.remove(page)
  for i in countdown(t.titles.high, 0):
    if t.titles[i][0] == page.id:
      t.titles.delete(i)
  t.syncPages()
  t.invalidate()

proc select*(t: TabView, i: int) =
  ## Programmatic: no slot, no event (deviation #15).
  let ps = t.pages
  if ps.len == 0:
    return
  let n = clamp(i, 0, ps.high)
  if n == t.selected and t.selView == ps[n]:
    return
  t.selected = n
  t.selView = ps[n]
  for k, p in ps:
    p.visible = k == n
  t.focusPage()
  t.invalidate()

proc userSelect(t: TabView, i: int) =
  let before = t.selView
  t.select(i)
  if t.selView != before:
    if t.onSelect != nil:
      t.onSelect(t)
    if t.hasBrokerCtx:
      SelectionChanged.emit(t.brokerCtx, SelectionChanged(selected: t.selected))

proc step(t: TabView, d: int) =
  let n = t.pages.len
  if n > 0:
    t.userSelect((t.selected + d + n) mod n)

proc newTabView*(): TabView =
  result = TabView()
  initView(result)
  result.hint = (prefHint(0, stretch = 1), prefHint(0, stretch = 1))
  result.ensureStrip()
  let t = result
  t.installSignal(SetSelected):
    t.select(sig.selected) # programmatic: no slot, no re-emit (plan-3 D8)

# --- strip geometry -----------------------------------------------------------

proc label(t: TabView, p: View, i: int): string =
  " " & t.title(p, i) & (if p.closable: " × " else: " ")

proc spans(t: TabView, width: int): tuple[tabs: seq[TabSpan], left, right: bool] =
  ## Tabs that fit in `width`, scrolled so the selected one is visible;
  ## `left`/`right` = more tabs hidden on that side (◄ / ►).
  let ps = t.pages
  var ws: seq[int]
  for i, p in ps:
    ws.add t.label(p, i).runeLen
  var total = max(ws.len - 1, 0) # one rule cell between tabs
  for w in ws:
    total += w
  let overflow = total > width
  let x0 = if overflow: 1 else: 0
  let avail = if overflow: width - 2 else: width
  t.first = if overflow: clamp(t.first, 0, max(ps.high, 0)) else: 0
  if t.selected < t.first:
    t.first = t.selected
  proc used(a, b: int): int =
    for k in a .. b:
      result += ws[k] + (if k > a: 1 else: 0)
  while t.first < t.selected and used(t.first, t.selected) > avail:
    inc t.first
  var x = x0
  var last = t.first - 1
  for i in t.first ..< ps.len:
    if x + ws[i] > x0 + avail:
      break
    let cx = if ps[i].closable: x + ws[i] - 2 else: -1
    result.tabs.add TabSpan(page: i, x: x, w: ws[i], closeX: cx)
    x += ws[i] + 1
    last = i
  result.left = overflow and t.first > 0
  result.right = overflow and last < ps.high

# --- layout / draw ------------------------------------------------------------

method keepsChildOrder*(t: TabView): bool {.gcsafe, raises: [].} =
  ## child order = tab order (deviation #33)
  true

method arrange*(t: TabView, r: Rect) {.gcsafe, raises: [].} =
  t.bounds = r
  t.syncPages()
  let cr = t.clientRect
  t.strip.arrange(rect(0, 0, cr.w, min(1, cr.h)))
  let p = t.page
  if p != nil:
    p.arrange(rect(0, 1, cr.w, max(cr.h - 1, 0)))

method draw*(s: TabStrip, dc: DrawContext) {.gcsafe, raises: [].} =
  let t = s.owner
  let w = s.contentW
  let rule = t.styleOf(tkWindowFrame)
  dc.fill(rect(0, 0, w, 1), "─", rule)
  let (tabs, left, right) = t.spans(w)
  let ps = t.pages
  for sp in tabs:
    let p = ps[sp.page]
    let st = if sp.page != t.selected: t.styleOf(tkCluster)
             elif s.isFocused: t.styleOf(tkSelectionFocused)
             else: p.styleOf(tkWindowTitle) # flush with the page: a folder tab
    dc.write(sp.x, 0, t.label(p, sp.page), st)
  if left: dc.write(0, 0, "◄", rule)
  if right: dc.write(w - 1, 0, "►", rule)

# --- input --------------------------------------------------------------------

method handleEvent*(s: TabStrip, ev: Event): bool {.gcsafe, raises: [].} =
  let t = s.owner
  case ev.kind
  of evKey:
    let k = ev.ikey
    if modAlt in k.keyMods:
      return false
    if k.key notin {Key.Left, Key.Right, Key.Home, Key.End}:
      return false # e.g. Ctrl+PgUp/PgDn bubble on to the TabView
    s.fallback = false # interacting with the strip: focus stays here
    case k.key
    of Key.Left: t.step(-1)
    of Key.Right: t.step(1)
    of Key.Home: t.userSelect(0)
    else: t.userSelect(t.pages.high)
    return true
  of evMouse:
    let m = ev.imouse
    if m.action != maPress or m.my != 0:
      return m.action == maPress
    s.fallback = false
    let (tabs, left, right) = t.spans(s.contentW)
    if left and m.mx == 0:
      dec t.first
      t.invalidate()
      return true
    if right and m.mx == s.contentW - 1:
      inc t.first
      t.invalidate()
      return true
    for sp in tabs:
      if m.mx >= sp.x and m.mx < sp.x + sp.w:
        let p = t.pages[sp.page]
        if sp.closeX >= 0 and m.mx == sp.closeX:
          Window(p).close() # default: detach + dispose; syncPages picks a neighbour
          t.syncPages()
          t.invalidate()
        else:
          t.userSelect(sp.page)
        return true
    return true
  of evFocusLost:
    s.fallback = false
    s.invalidate()
  of evFocusGained:
    s.invalidate()
  else:
    discard
  false

method handleEvent*(t: TabView, ev: Event): bool {.gcsafe, raises: [].} =
  ## Ctrl+PgUp / Ctrl+PgDn bubble here from anywhere inside the TabView.
  if ev.kind == evKey and modCtrl in ev.ikey.keyMods:
    case ev.ikey.key
    of Key.PageUp:
      t.step(-1)
      return true
    of Key.PageDown:
      t.step(1)
      return true
    else:
      discard
  false
