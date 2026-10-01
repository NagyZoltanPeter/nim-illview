## Menu (Phase 4.5 + plan-4 P23 + iteration-5): menu bar, dropdowns and
## context menus as PERSISTENT views with transient tree membership. A popup
## is built ONCE (cached on the bar / parent popup / held by the caller),
## added on open and removed on close — never rebuilt, never leaking an
## instanceCtx (see deviation #21). Items carry a broker `command`, an
## `onActivate` closure (e.g. emit an EventBroker event), and/or a `submenu`.
##
## Declarative surface (iteration-5): `menuBar(menu("~F~ile", @[
##   item("~O~pen", OpenRequested), sep(), submenu("~R~ecent", @[...]),
##   item("~Q~uit", cmQuit)]))` — `item(label, EventType)` auto-emits the
## EventBroker type on activation (the type IS the semantic) on the host view's
## session ctx, `senderId = host.id` when the type has one (deviation #27).
##
## Keyboard — bar: Left/Right pick, Enter/Down open. Popup: Up/Down (skips
## separators + disabled), Enter/Right open-or-activate, Left/Escape close.

import std/unicode
import ../core/[geometry, theme, view, drawcontext, events, bus, hotkey]

type
  MenuAction* = proc() {.gcsafe, raises: [].}
    ## Runs on item activation (after the menu closes). Typically emits an
    ## EventBroker event; may open a dialog, mutate state, etc.

  MenuItem* = object
    label*: string        # tilde-stripped
    hlCol*: int
    accel*: Rune
    command*: Command     # tier-2 publish on activation (cmdNone = none)
    onActivate*: MenuAction
    onActivateFrom*: proc(host: View) {.gcsafe, raises: [].}
      ## Like onActivate but receives the popup's host (menu bar / context-menu
      ## opener), the still-attached view whose session ctx and id identify
      ## the source. `item(label, EventType)` emits through this.
    separator*: bool      # a non-selectable divider line
    submenu*: seq[MenuItem]

  Menu* = object
    title*: string
    hlCol*: int
    accel*: Rune
    items*: seq[MenuItem]

  MenuBar* = ref object of View
    menus*: seq[Menu]
    popups: seq[MenuPopup] # persistent dropdown per menu (lazily built)
    barSel: int
    hotMenu: int

  MenuPopup* = ref object of Group
    items: seq[MenuItem]
    selected: int
    host: View            # stable view for publish (survives closeAll): bar/opener
    parentPopup: MenuPopup
    subCache: seq[MenuPopup] # persistent child popup per submenu item

  ContextMenu* = ref object of MenuPopup
    source*: View         # the widget this menu was opened on (right-click)

# --- constructors ------------------------------------------------------------

proc menuItem*(label: string, command: Command): MenuItem =
  let hk = parseHotkey(label)
  MenuItem(label: hk.text, hlCol: hk.col, accel: hk.key, command: command)

proc submenuItem*(label: string, items: seq[MenuItem]): MenuItem =
  let hk = parseHotkey(label)
  MenuItem(label: hk.text, hlCol: hk.col, accel: hk.key, submenu: items)

proc menu*(title: string, items: seq[MenuItem]): Menu =
  let hk = parseHotkey(title)
  Menu(title: hk.text, hlCol: hk.col, accel: hk.key, items: items)

proc newMenuBar*(menus: seq[Menu]): MenuBar =
  result = MenuBar(menus: menus, popups: newSeq[MenuPopup](menus.len))
  initView(result)
  result.focusable = true
  result.dock = dkTop
  result.hint = (prefHint(0, stretch = 1), fixedHint(1))

# --- declarative sugar (iteration-5, 2b) -------------------------------------

proc item*(label: string, command: Command): MenuItem = menuItem(label, command)

proc item*(label: string, act: MenuAction): MenuItem =
  let hk = parseHotkey(label)
  MenuItem(label: hk.text, hlCol: hk.col, accel: hk.key, onActivate: act)

proc itemFrom*(label: string,
               act: proc(host: View) {.gcsafe, raises: [].}): MenuItem =
  let hk = parseHotkey(label)
  MenuItem(label: hk.text, hlCol: hk.col, accel: hk.key, onActivateFrom: act)

template item*(label: string, EventType: typedesc): MenuItem =
  ## Activation emits `EventType` on the host view's session ctx (the menu
  ## bar's / context-menu opener's `sessionCtx`), with `senderId = host.id`
  ## when the type declares that field (uiEvents-style) and default-constructed
  ## otherwise. Never the ambient default ctx (deviation #27).
  mixin emit
  itemFrom(label, proc(host: View) {.gcsafe, raises: [].} =
    when compiles(EventType(senderId: host.id)):
      emit(EventType, host.sessionCtx, EventType(senderId: host.id))
    else:
      emit(EventType, host.sessionCtx, EventType()))

proc sep*(): MenuItem = MenuItem(separator: true, hlCol: -1)

proc submenu*(label: string, items: seq[MenuItem]): MenuItem =
  submenuItem(label, items)

proc menuBar*(menus: varargs[Menu]): MenuBar = newMenuBar(@menus)

# --- shared helpers ----------------------------------------------------------

func titleX(mb: MenuBar, i: int): int =
  var x = 1
  for k in 0 ..< i:
    x += mb.menus[k].title.runeLen + 3
  x

proc itemDisabled(p: MenuPopup, i: int): bool =
  let it = p.items[i]
  it.submenu.len == 0 and it.command != cmdNone and
    not p.commandEnabled(it.command)

proc skippable(p: MenuPopup, i: int): bool =
  p.items[i].separator or p.itemDisabled(i)

proc firstEnabled(p: MenuPopup): int =
  for i in 0 ..< p.items.len:
    if not p.skippable(i):
      return i
  0

func popupWidth(items: seq[MenuItem]): int =
  var w = 0
  for it in items:
    w = max(w, it.label.runeLen + (if it.submenu.len > 0: 2 else: 0))
  w + 4

proc buildPopup(items: seq[MenuItem], parent: MenuPopup, host: View): MenuPopup =
  result = MenuPopup(items: items, parentPopup: parent, host: host,
                     subCache: newSeq[MenuPopup](items.len))
  initView(result)

# --- popup behavior ----------------------------------------------------------

proc closeAll(p: MenuPopup) =
  ## Detach this popup and every ancestor (deepest first: each is the current
  ## modal top). Does NOT dispose — the popups are reused on the next open.
  var cur: MenuPopup = p
  while cur != nil:
    let par = cur.parentPopup
    cur.endModal(cmdNone)
    cur = par

proc openSubmenu(p: MenuPopup, idx: int) =
  let item = p.items[idx]
  if item.submenu.len == 0:
    return
  if p.subCache[idx] == nil: # build once, reuse thereafter
    p.subCache[idx] = buildPopup(item.submenu, p, p.host)
  let child = p.subCache[idx]
  let cw = popupWidth(item.submenu)
  var x = p.bounds.x + p.bounds.w - 1 # right, overlapping the border
  let deskW = if p.parent != nil: p.parent.contentW else: x + cw
  if x + cw > deskW: # no room right: flip to the left
    x = p.bounds.x - cw + 1
  child.selected = child.firstEnabled()
  child.bounds = rect(max(x, 0), p.bounds.y + 1 + idx, cw, item.submenu.len + 2)
  p.runModal(child)

proc activateItem(p: MenuPopup) =
  let item = p.items[p.selected]
  if item.submenu.len > 0:
    p.openSubmenu(p.selected)
    return
  if p.skippable(p.selected):
    return
  let host = p.host
  p.closeAll()                 # menu gone first (action may open a dialog)
  if item.onActivate != nil:
    item.onActivate()          # free closure — safe after detach
  if item.onActivateFrom != nil:
    item.onActivateFrom(if host != nil: host else: View(p))
  if item.command != cmdNone and host != nil:
    host.publish(item.command) # via the still-attached host, not the detached popup

proc moveSel(p: MenuPopup, dir: int) =
  let n = p.items.len
  if n == 0:
    return
  var i = p.selected
  for _ in 0 ..< n:
    i = (i + dir + n) mod n
    if not p.skippable(i):
      p.selected = i
      p.invalidate()
      return

method draw*(p: MenuPopup, dc: DrawContext) {.gcsafe, raises: [].} =
  let st = p.styleOf(tkMenu)
  let sel = p.styleOf(tkMenuSelected)
  let off = p.styleOf(tkTextDisabled)
  dc.fill(rect(0, 0, p.contentW, p.contentH), " ", st)
  dc.box(rect(0, 0, p.contentW, p.contentH), st)
  for i, item in p.items:
    if item.separator:
      for x in 1 ..< p.contentW - 1:
        dc.write(x, 1 + i, "─", st)
      continue
    let dis = p.itemDisabled(i)
    let s = if i == p.selected: sel elif dis: off else: st
    if i == p.selected:
      dc.fill(rect(1, 1 + i, p.contentW - 2, 1), " ", s)
    dc.write(2, 1 + i, item.label, s)
    if item.hlCol >= 0 and not dis and i != p.selected:
      dc.write(2 + item.hlCol, 1 + i, $item.label.runeAtPos(item.hlCol),
               p.styleOf(tkStatusBarHotkey))
    if item.submenu.len > 0:
      dc.write(p.contentW - 2, 1 + i, "▶", s)

method handleEvent*(p: MenuPopup, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    case ev.ikey.key
    of Key.Up: p.moveSel(-1)
    of Key.Down: p.moveSel(1)
    of Key.Enter: p.activateItem()
    of Key.Right:
      if p.items[p.selected].submenu.len > 0:
        p.openSubmenu(p.selected)
    of Key.Left, Key.Escape:
      p.endModal(cmdNone) # close this level
    else:
      let r = ev.ikey.rune
      if int(r) != 0:
        for i, item in p.items:
          if hotkeyMatches(item.accel, r) and not p.skippable(i):
            p.selected = i
            p.activateItem()
            break
    return true
  of evMouse:
    let m = ev.imouse
    if m.action == maPress:
      if not rect(0, 0, p.contentW, p.contentH).contains(point(m.mx, m.my)):
        p.endModal(cmdNone)
      else:
        let idx = m.my - 1
        if idx >= 0 and idx < p.items.len and not p.skippable(idx):
          p.selected = idx
          p.activateItem()
    return true
  else:
    discard
  false

# --- menu bar ----------------------------------------------------------------

proc openMenu*(mb: MenuBar, i: int) =
  ## Open dropdown i (persistent popup, reused) under its bar title.
  if i < 0 or i >= mb.menus.len or mb.menus[i].items.len == 0:
    return
  mb.barSel = i
  if mb.popups[i] == nil: # build once
    mb.popups[i] = buildPopup(mb.menus[i].items, nil, mb)
  let popup = mb.popups[i]
  popup.selected = popup.firstEnabled()
  let o = mb.absOrigin
  popup.bounds = rect(o.x + mb.titleX(i) - 1, o.y + 1,
                      popupWidth(mb.menus[i].items), mb.menus[i].items.len + 2)
  mb.runModal(popup)

# --- context menu (iteration-5, item 2) --------------------------------------

proc newContextMenu*(items: seq[MenuItem]): ContextMenu =
  ## Build once, hold the reference, and open()/reuse on every right-click.
  result = ContextMenu(items: items, subCache: newSeq[MenuPopup](items.len))
  initView(result)

proc openAt*(cm: ContextMenu, opener: View, at: Point) =
  ## Show the (persistent) context menu at absolute point `at`, remembering the
  ## `source` widget it was opened on. `opener` supplies the modal wiring.
  cm.source = opener
  cm.host = opener
  cm.selected = cm.firstEnabled()
  cm.bounds = rect(at.x, at.y, popupWidth(cm.items), cm.items.len + 2)
  opener.runModal(cm)

method handlesHotkey*(mb: MenuBar, key: Rune): bool {.gcsafe, raises: [].} =
  for i, m in mb.menus:
    if hotkeyMatches(m.accel, key):
      mb.hotMenu = i
      return true
  false

method triggerHotkey*(mb: MenuBar, scope: Group) {.gcsafe, raises: [].} =
  mb.openMenu(mb.hotMenu)

method draw*(mb: MenuBar, dc: DrawContext) {.gcsafe, raises: [].} =
  let st = mb.styleOf(tkMenu)
  let sel = mb.styleOf(tkMenuSelected)
  let hot = mb.styleOf(tkStatusBarHotkey)
  dc.fill(rect(0, 0, mb.contentW, 1), " ", st)
  for i, m in mb.menus:
    let s = if mb.isFocused and i == mb.barSel: sel else: st
    dc.write(mb.titleX(i), 0, " " & m.title & " ", s)
    if m.hlCol >= 0 and not (mb.isFocused and i == mb.barSel):
      dc.write(mb.titleX(i) + 1 + m.hlCol, 0, $m.title.runeAtPos(m.hlCol), hot)

method handleEvent*(mb: MenuBar, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    if modAlt in ev.ikey.keyMods:
      return false
    case ev.ikey.key
    of Key.Left:
      mb.barSel = (mb.barSel - 1 + mb.menus.len) mod mb.menus.len
      mb.invalidate()
      return true
    of Key.Right:
      mb.barSel = (mb.barSel + 1) mod mb.menus.len
      mb.invalidate()
      return true
    of Key.Enter, Key.Down:
      mb.openMenu(mb.barSel)
      return true
    else:
      discard
  of evMouse:
    if ev.imouse.action == maPress:
      for i, m in mb.menus:
        let x = mb.titleX(i)
        if ev.imouse.mx >= x and ev.imouse.mx < x + m.title.runeLen + 2:
          mb.openMenu(i)
          return true
      return true
  of evFocusGained, evFocusLost:
    mb.invalidate()
  else:
    discard
  false
