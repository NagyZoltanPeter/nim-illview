## Menu (Phase 4.5): menu bar + dropdown as a transient modal group. Each
## item carries a broker `command`; activating an item publishes it and
## closes the menu. The dropdown runs through the App's modal loop via the
## root closures (view.runModal / view.endModal), so input routing is
## automatically confined to it.
##
## Keyboard: focus the bar (Tab), Left/Right to pick a menu, Enter/Down to
## open; inside a dropdown Up/Down/Enter/Escape. A global open key (e.g.
## F10) is wired at app level — see the gallery example.

import std/unicode
import ../core/[geometry, theme, view, drawcontext, events, bus]

type
  MenuItem* = object
    label*: string
    command*: Command

  Menu* = object
    title*: string
    items*: seq[MenuItem]

  MenuBar* = ref object of View
    menus*: seq[Menu]
    barSel: int # highlighted title while the bar is focused

  MenuPopup* = ref object of Group
    items: seq[MenuItem]
    selected: int
    owner: MenuBar

proc menuItem*(label: string, command: Command): MenuItem =
  MenuItem(label: label, command: command)

proc menu*(title: string, items: seq[MenuItem]): Menu =
  Menu(title: title, items: items)

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

proc activateItem(p: MenuPopup) =
  let cmd = p.items[p.selected].command
  p.endModal(cmdNone) # remove popup first; publish reaches the bus either way
  p.owner.publish(cmd)

method draw*(p: MenuPopup, dc: DrawContext) {.gcsafe, raises: [].} =
  let st = p.styleOf(tkMenu)
  let sel = p.styleOf(tkMenuSelected)
  dc.fill(rect(0, 0, p.contentW, p.contentH), " ", st)
  dc.box(rect(0, 0, p.contentW, p.contentH), st)
  for i, item in p.items:
    let s = if i == p.selected: sel else: st
    if i == p.selected:
      dc.fill(rect(1, 1 + i, p.contentW - 2, 1), " ", s)
    dc.write(2, 1 + i, item.label, s)

method handleEvent*(p: MenuPopup, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    case ev.ikey.key
    of Key.Up:
      p.selected = (p.selected - 1 + p.items.len) mod p.items.len
      p.invalidate()
    of Key.Down:
      p.selected = (p.selected + 1) mod p.items.len
      p.invalidate()
    of Key.Enter:
      p.activateItem()
    of Key.Escape:
      p.endModal(cmdNone)
    else:
      discard
    return true # modal: swallow all keys
  of evMouse:
    let m = ev.imouse
    if m.action == maPress:
      if not rect(0, 0, p.contentW, p.contentH).contains(point(m.mx, m.my)):
        p.endModal(cmdNone) # click outside closes the menu
      else:
        let idx = m.my - 1
        if idx >= 0 and idx < p.items.len:
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
    w = max(w, item.label.runeLen)
  let o = mb.absOrigin
  let popup = MenuPopup(items: mb.menus[i].items, owner: mb)
  initView(popup)
  popup.bounds = rect(o.x + mb.titleX(i) - 1, o.y + 1, w + 4,
                      mb.menus[i].items.len + 2)
  mb.runModal(popup)

# --- bar ---------------------------------------------------------------------

method draw*(mb: MenuBar, dc: DrawContext) {.gcsafe, raises: [].} =
  let st = mb.styleOf(tkMenu)
  let sel = mb.styleOf(tkMenuSelected)
  dc.fill(rect(0, 0, mb.contentW, 1), " ", st)
  for i, m in mb.menus:
    let s = if mb.isFocused and i == mb.barSel: sel else: st
    dc.write(mb.titleX(i), 0, " " & m.title & " ", s)

method handleEvent*(mb: MenuBar, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
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
