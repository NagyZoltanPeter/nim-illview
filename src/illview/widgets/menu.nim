## Menu (Phase 4.5 + plan-4 P23): menu bar + dropdowns as transient modals.
## Each item carries a broker `command` OR a `submenu`; activating a command
## item publishes it and closes the whole chain, activating a submenu item
## opens a nested popup. Command-gated items grey out and are skipped by the
## keyboard selection. Menu titles and item labels accept ~tilde~ accelerators:
## Alt+<title-letter> opens a menu from anywhere (via the hotkey router).
##
## Keyboard — bar: Left/Right pick, Enter/Down open. Popup: Up/Down (skips
## disabled), Enter/Right open-or-activate, Left/Escape close the level.

import std/unicode
import ../core/[geometry, theme, view, drawcontext, events, bus, hotkey]

type
  MenuItem* = object
    label*: string        # tilde-stripped
    hlCol*: int
    accel*: Rune
    command*: Command
    submenu*: seq[MenuItem] # non-empty => opens a child popup

  Menu* = object
    title*: string        # tilde-stripped
    hlCol*: int
    accel*: Rune
    items*: seq[MenuItem]

  MenuBar* = ref object of View
    menus*: seq[Menu]
    barSel: int   # highlighted title while the bar is focused
    hotMenu: int  # menu index resolved by the last handlesHotkey (P22/P23)

  MenuPopup* = ref object of Group
    items: seq[MenuItem]
    selected: int
    owner: MenuBar
    parentPopup: MenuPopup # nil for the top-level dropdown

proc menuItem*(label: string, command: Command): MenuItem =
  let hk = parseHotkey(label)
  MenuItem(label: hk.text, hlCol: hk.col, accel: hk.key, command: command)

proc submenuItem*(label: string, items: seq[MenuItem]): MenuItem =
  let hk = parseHotkey(label)
  MenuItem(label: hk.text, hlCol: hk.col, accel: hk.key, submenu: items,
           command: cmdNone)

proc menu*(title: string, items: seq[MenuItem]): Menu =
  let hk = parseHotkey(title)
  Menu(title: hk.text, hlCol: hk.col, accel: hk.key, items: items)

proc newMenuBar*(menus: seq[Menu]): MenuBar =
  result = MenuBar(menus: menus)
  initView(result)
  result.focusable = true
  result.dock = dkTop
  result.hint = (prefHint(0, stretch = 1), fixedHint(1))

func titleX(mb: MenuBar, i: int): int =
  var x = 1
  for k in 0 ..< i:
    x += mb.menus[k].title.runeLen + 3
  x

# --- popup -------------------------------------------------------------------

proc itemDisabled(p: MenuPopup, i: int): bool =
  let it = p.items[i]
  it.submenu.len == 0 and it.command != cmdNone and
    not p.commandEnabled(it.command)

proc firstEnabled(p: MenuPopup): int =
  for i in 0 ..< p.items.len:
    if not p.itemDisabled(i):
      return i
  0

proc closeAll(p: MenuPopup) =
  ## Close this popup and every ancestor popup (deepest first; each is on top
  ## of the modal stack when its turn comes).
  var cur: MenuPopup = p
  while cur != nil:
    let par = cur.parentPopup
    cur.endModal(cmdNone)
    cur = par

proc openSubmenu(p: MenuPopup, idx: int) =
  let item = p.items[idx]
  if item.submenu.len == 0:
    return
  var w = 0
  for s in item.submenu:
    w = max(w, s.label.runeLen + (if s.submenu.len > 0: 2 else: 0))
  let cw = w + 4
  let ch = item.submenu.len + 2
  var x = p.bounds.x + p.bounds.w - 1 # to the right, overlapping the border
  let deskW = if p.parent != nil: p.parent.contentW else: x + cw
  if x + cw > deskW: # no room right: flip to the left of this popup
    x = p.bounds.x - cw + 1
  let child = MenuPopup(items: item.submenu, owner: p.owner, parentPopup: p)
  initView(child)
  child.selected = child.firstEnabled()
  child.bounds = rect(max(x, 0), p.bounds.y + 1 + idx, cw, ch)
  p.runModal(child)

proc activateItem(p: MenuPopup) =
  let item = p.items[p.selected]
  if item.submenu.len > 0:
    p.openSubmenu(p.selected)
    return
  if item.command != cmdNone and not p.commandEnabled(item.command):
    return # disabled: ignore
  p.closeAll()
  p.owner.publish(item.command)

proc moveSel(p: MenuPopup, dir: int) =
  let n = p.items.len
  if n == 0:
    return
  var i = p.selected
  for _ in 0 ..< n:
    i = (i + dir + n) mod n
    if not p.itemDisabled(i):
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
      p.endModal(cmdNone) # close this level, back to the parent (or the bar)
    else:
      # accelerator: activate the item whose letter matches
      let r = ev.ikey.rune
      if int(r) != 0:
        for i, item in p.items:
          if hotkeyMatches(item.accel, r) and not p.itemDisabled(i):
            p.selected = i
            p.activateItem()
            break
    return true # modal: swallow all keys
  of evMouse:
    let m = ev.imouse
    if m.action == maPress:
      if not rect(0, 0, p.contentW, p.contentH).contains(point(m.mx, m.my)):
        p.endModal(cmdNone) # click outside closes this level
      else:
        let idx = m.my - 1
        if idx >= 0 and idx < p.items.len and not p.itemDisabled(idx):
          p.selected = idx
          p.activateItem()
    return true
  else:
    discard
  false

proc openMenu*(mb: MenuBar, i: int) =
  ## Open dropdown i as a transient modal positioned under the bar title.
  if i < 0 or i >= mb.menus.len or mb.menus[i].items.len == 0:
    return
  mb.barSel = i
  var w = 0
  for item in mb.menus[i].items:
    w = max(w, item.label.runeLen + (if item.submenu.len > 0: 2 else: 0))
  let o = mb.absOrigin
  let popup = MenuPopup(items: mb.menus[i].items, owner: mb)
  initView(popup)
  popup.selected = popup.firstEnabled()
  popup.bounds = rect(o.x + mb.titleX(i) - 1, o.y + 1, w + 4,
                      mb.menus[i].items.len + 2)
  mb.runModal(popup)

# --- bar ---------------------------------------------------------------------

method handlesHotkey*(mb: MenuBar, key: Rune): bool {.gcsafe, raises: [].} =
  ## Claim Alt+<menu-accelerator> and remember which menu to open.
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
      return false # menu accelerators arrive via the hotkey router, not here
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
      return true # consume bar background clicks
  of evFocusGained, evFocusLost:
    mb.invalidate()
  else:
    discard
  false
