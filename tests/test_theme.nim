## Deviation #34: TV visual language. The shipped default theme keeps every
## control surface (field, cluster, list, button) distinct from the window
## surface it sits on, in every window palette; palettes resolve per subtree.

import std/unittest
import ../src/illview/core/[geometry, theme, view]
import ../src/illview/backend/illwill_vendored

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
      check v.style(tkControlBar).bg != win # bars stand out (deviation #35)

  test "default theme is the TV theme; desktop differs from windows":
    let d = defaultTheme()
    check d.style(tkDesktop) == tvTheme().style(tkDesktop)
    # same lightgray as TV: the blue ░ pattern (plus frame and shadow) separates them
    check d.style(tkDesktop).fg != d.style(tkWindowBg).fg
    check d.style(tkWindowBg).bg == bgGray # windows are lightgray (#35), TV gray (#37)
    check d.variant(pGray) == d             # gray IS the base table
    check d.variant(pBlue).style(tkWindowBg).bg == bgBlue

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

suite "TV gray background (deviation #37)":
  test "256-colour capability: override, COLORTERM, known TERMs, fallback":
    check wants256Colors("xterm", "", "256")
    check not wants256Colors("xterm-256color", "truecolor", "16")
    check wants256Colors("xterm", "truecolor", "")
    check wants256Colors("xterm-256color", "", "")
    check wants256Colors("tmux-256color", "", "")
    check wants256Colors("xterm-ghostty", "", "")
    check wants256Colors("xterm-kitty", "", "")
    check not wants256Colors("linux", "", "")
    check not wants256Colors("xterm", "", "")

  test "bgGray escape: 256-colour 248, else ANSI 47":
    check bgGrayEscape(true) == "\e[48;5;248m"
    check bgGrayEscape(false) == "\e[47m"

  test "every TV lightgray is bgGray; the classic theme keeps bgWhite":
    let t = tvTheme()
    check t.style(tkDesktop).bg == bgGray
    check t.style(tkMenu).bg == bgGray
    check t.style(tkStatusBar).bg == bgGray
    check t.variant(pCyan).style(tkList).bg == bgGray
    check t.variant(pBlue).style(tkInput).bg == bgGray
    for tok in ThemeToken:
      for p in [pBlue, pCyan, pGray]:
        check t.variant(p).style(tok).bg != bgWhite
    check classicBlueTheme().style(tkMenu).bg == bgWhite
