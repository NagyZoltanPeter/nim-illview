## Deviation #34: TV visual language. The shipped default theme keeps every
## control surface (field, cluster, list, button) distinct from the window
## surface it sits on, in every window palette; palettes resolve per subtree.

import std/unittest
import ../src/illview/core/[geometry, theme, view]

suite "surface invariants (deviation #34)":
  test "fields, clusters, lists and buttons never share the window bg":
    let t = tvTheme()
    for p in [pBlue, pCyan, pGray]:
      let v = t.variant(p)
      let win = v.style(tkWindowBg).bg
      checkpoint $p
      check v.style(tkInput).bg != win
      check v.style(tkInputFocused).bg != win
      check v.style(tkCheckbox).bg != win
      check v.style(tkCluster).bg != win
      check v.style(tkList).bg != win
      check v.style(tkButton).bg != win
      check v.style(tkInput).bg != v.style(tkCluster).bg # a field is not a group

  test "default theme is the TV theme; desktop differs from windows":
    let d = defaultTheme()
    check d.style(tkDesktop) == tvTheme().style(tkDesktop)
    check d.style(tkDesktop).bg != d.style(tkWindowBg).bg
    check d.variant(pGray).style(tkWindowBg).bg != d.style(tkWindowBg).bg

  test "a theme without a variant falls back to itself":
    let c = classicBlueTheme()
    check c.variant(pGray) == c
    check c.variant(pDefault) == c

suite "palette resolution (deviation #34)":
  test "a palette switches its subtree to the variant":
    let root = newGroup()
    root.theme = tvTheme()
    let win = newGroup()
    win.palette = pGray
    let leaf = newGroup()
    root.add win
    win.add leaf
    check leaf.styleOf(tkWindowBg) == tvTheme().variant(pGray).style(tkWindowBg)
    check root.styleOf(tkWindowBg) == tvTheme().style(tkWindowBg)

  test "nearest palette wins; an explicit theme below it wins as-is":
    let root = newGroup()
    root.theme = tvTheme()
    let outer = newGroup()
    outer.palette = pGray
    let inner = newGroup()
    inner.palette = pCyan
    let leaf = newGroup()
    root.add outer
    outer.add inner
    inner.add leaf
    check leaf.styleOf(tkWindowBg) == tvTheme().variant(pCyan).style(tkWindowBg)
    let own = newGroup()
    own.theme = classicBlueTheme()
    outer.add own
    check own.styleOf(tkWindowBg) == classicBlueTheme().style(tkWindowBg)

  test "hotkeyStyle keeps the host bg, takes tkHotkey fg":
    let root = newGroup()
    root.theme = tvTheme()
    let host = style(fgBlack, bgGreen)
    let h = root.hotkeyStyle(host)
    check h.bg == bgGreen
    check h.fg == tvTheme().style(tkHotkey).fg
    check h.bright == tvTheme().style(tkHotkey).bright
