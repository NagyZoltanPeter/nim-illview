## Named style tokens (plan §1 "Theming"): a Theme maps role tokens to
## concrete styles — not TurboVision's numeric cascading palette.
##
## `Style` is an illview type (deviation #3): illwill has no single style
## value. It deliberately carries only fg/bg/bright — the classic text-UI
## palette; other terminal attributes can be added when a widget needs them.

import ../backend/illwill_vendored

export ForegroundColor, BackgroundColor

type
  Style* = object
    fg*: ForegroundColor
    bg*: BackgroundColor
    bright*: bool

  ThemeToken* = enum
    tkDesktop
    tkWindowFrame
    tkWindowFrameActive
    tkWindowTitle
    tkWindowBg
    tkText
    tkTextDisabled
    tkButton
    tkButtonFocused
    tkCheckbox
    tkCheckboxFocused
    tkInput
    tkInputFocused
    tkSelection
    tkSelectionFocused
    tkMenu
    tkMenuSelected
    tkStatusBar
    tkStatusBarHotkey
    tkBorder
    tkShadow
    tkGroupBox
    tkTableHeader
    tkProgress
    tkScrollBar
    tkControlBar
    # surfaces (deviation #34): every surface's bg differs from its parent's
    tkHotkey         # accelerator letter inside controls: ONLY fg/bright apply
    tkLabelFocused   # Label whose `linkTo` control has focus
    tkCluster        # GroupBox content block (Checkbox/Radio use tkCheckbox*)
    tkList           # ListView / Table / TreeView rows (selection: tkSelection*)
    tkButtonDefault  # Button.isDefault caption
    tkButtonShadow   # half-block button shadow, bg = the surface under it
    tkWindowCloseBox # the ■ in a window's [■]

  Palette* = enum
    ## Window colour set (TV blue / cyan / gray). `pDefault` inherits; a view
    ## with another value switches its subtree to that variant of the
    ## inherited theme (`Theme.variants`, deviation #34).
    pDefault, pBlue, pCyan, pGray

  Theme* = ref object
    styles*: array[ThemeToken, Style]
    variants*: array[Palette, Theme] # nil = this theme itself

func style*(fg: ForegroundColor, bg: BackgroundColor, bright = false): Style =
  Style(fg: fg, bg: bg, bright: bright)

func style*(t: Theme, tok: ThemeToken): Style =
  t.styles[tok]

func variant*(t: Theme, p: Palette): Theme =
  ## The theme for palette `p`; the theme itself when it has no such variant.
  if p != pDefault and t.variants[p] != nil: t.variants[p] else: t

# --- TV theme ---------------------------------------------------------------
# Turbo Vision's look on 16 colours: lightgray desktop and bars, blue windows,
# gray dialogs, cyan clusters and lists, green buttons with a half-block
# shadow. illwill: bgWhite = lightgray, fgWhite + bright = white,
# fgBlack + bright = darkgray.

proc tvShared(t: Theme) =
  ## Tokens that do not depend on the window palette.
  t.styles[tkDesktop] = style(fgBlue, bgWhite) # ░ pattern
  t.styles[tkMenu] = style(fgBlack, bgWhite)
  t.styles[tkMenuSelected] = style(fgBlack, bgGreen)
  t.styles[tkStatusBar] = style(fgBlack, bgWhite)
  t.styles[tkStatusBarHotkey] = style(fgRed, bgWhite)
  t.styles[tkControlBar] = style(fgBlack, bgWhite)
  t.styles[tkShadow] = style(fgBlack, bgBlack, bright = true)
  t.styles[tkHotkey] = style(fgYellow, bgBlack, bright = true) # fg only
  t.styles[tkButton] = style(fgBlack, bgGreen)
  t.styles[tkButtonFocused] = style(fgWhite, bgGreen, bright = true)
  t.styles[tkButtonDefault] = style(fgCyan, bgGreen, bright = true)
  t.styles[tkSelectionFocused] = style(fgWhite, bgGreen, bright = true)

proc tvWindow(t: Theme, bg: BackgroundColor, text, frame: ForegroundColor) =
  ## The window surface and everything drawn directly on it.
  t.styles[tkWindowBg] = style(text, bg)
  t.styles[tkText] = style(text, bg)
  t.styles[tkLabelFocused] = style(fgWhite, bg, bright = true)
  t.styles[tkTextDisabled] = style(fgBlack, bg, bright = true)
  t.styles[tkWindowFrame] = style(frame, bg)
  t.styles[tkWindowFrameActive] = style(fgWhite, bg, bright = true)
  t.styles[tkWindowTitle] = style(fgWhite, bg, bright = true)
  t.styles[tkWindowCloseBox] = style(fgGreen, bg, bright = true)
  t.styles[tkBorder] = style(frame, bg)
  t.styles[tkGroupBox] = style(fgWhite, bg, bright = true)
  t.styles[tkButtonShadow] = style(fgBlack, bg)

proc tvControls(t: Theme, cluster, field, list: BackgroundColor,
                fieldFg, ink: ForegroundColor) =
  ## Cluster, field and list surfaces — each must differ from the window bg.
  t.styles[tkCluster] = style(ink, cluster)
  t.styles[tkCheckbox] = style(ink, cluster)
  t.styles[tkCheckboxFocused] = style(fgWhite, cluster, bright = true)
  t.styles[tkInput] = style(fieldFg, field, bright = fieldFg == fgWhite)
  t.styles[tkInputFocused] = style(fieldFg, field, bright = fieldFg == fgWhite)
  t.styles[tkList] = style(ink, list)
  t.styles[tkSelection] = style(fgYellow, list, bright = true)
  t.styles[tkTableHeader] = style(fgWhite, list, bright = true)
  t.styles[tkScrollBar] = style(fgBlue, list)
  t.styles[tkProgress] = style(fgBlue, list)

proc tvVariant(p: Palette): Theme =
  result = Theme()
  result.tvShared()
  case p
  of pDefault, pBlue:
    result.tvWindow(bgBlue, fgYellow, fgWhite)
    result.tvControls(cluster = bgCyan, field = bgWhite, list = bgCyan,
                      fieldFg = fgBlack, ink = fgBlack)
  of pCyan:
    result.tvWindow(bgCyan, fgBlack, fgBlack)
    result.tvControls(cluster = bgWhite, field = bgBlue, list = bgWhite,
                      fieldFg = fgWhite, ink = fgBlack)
  of pGray:
    result.tvWindow(bgWhite, fgBlack, fgBlack)
    result.tvControls(cluster = bgCyan, field = bgBlue, list = bgCyan,
                      fieldFg = fgWhite, ink = fgBlack)

proc tvTheme*(): Theme =
  ## Turbo Vision's visual language (deviation #34): the base table is the
  ## blue window palette; `variants` carry cyan and gray (dialogs).
  result = tvVariant(pBlue)
  result.variants[pCyan] = tvVariant(pCyan)
  result.variants[pGray] = tvVariant(pGray)

proc defaultTheme*(): Theme =
  ## The default look: `tvTheme()`.
  tvTheme()

proc classicBlueTheme*(): Theme =
  ## The pre-deviation-#34 default: everything on blue, no window variants.
  ## Kept for compatibility; it does not separate fields/clusters/lists from
  ## the window background.
  result = Theme()
  result.styles[tkDesktop] = style(fgCyan, bgBlue)
  result.styles[tkWindowFrame] = style(fgWhite, bgBlue)
  result.styles[tkWindowFrameActive] = style(fgWhite, bgBlue, bright = true)
  result.styles[tkWindowTitle] = style(fgWhite, bgBlue, bright = true)
  result.styles[tkWindowBg] = style(fgWhite, bgBlue)
  result.styles[tkText] = style(fgWhite, bgBlue)
  result.styles[tkTextDisabled] = style(fgBlack, bgBlue, bright = true)
  result.styles[tkButton] = style(fgBlack, bgGreen)
  result.styles[tkButtonFocused] = style(fgWhite, bgGreen, bright = true)
  result.styles[tkCheckbox] = style(fgWhite, bgBlue)
  result.styles[tkCheckboxFocused] = style(fgYellow, bgBlue, bright = true)
  result.styles[tkInput] = style(fgYellow, bgBlue)
  result.styles[tkInputFocused] = style(fgYellow, bgBlue, bright = true)
  result.styles[tkSelection] = style(fgBlack, bgCyan)
  result.styles[tkSelectionFocused] = style(fgWhite, bgCyan, bright = true)
  result.styles[tkMenu] = style(fgBlack, bgWhite)
  result.styles[tkMenuSelected] = style(fgWhite, bgGreen, bright = true)
  result.styles[tkStatusBar] = style(fgBlack, bgWhite)
  result.styles[tkStatusBarHotkey] = style(fgRed, bgWhite)
  result.styles[tkBorder] = style(fgWhite, bgBlue)
  result.styles[tkShadow] = style(fgBlack, bgBlack, bright = true)
  result.styles[tkGroupBox] = style(fgWhite, bgBlue, bright = true)
  result.styles[tkTableHeader] = style(fgBlack, bgWhite) # distinct from tkSelection
  result.styles[tkProgress] = style(fgCyan, bgBlue, bright = true)
  result.styles[tkScrollBar] = style(fgCyan, bgBlue)
  result.styles[tkControlBar] = style(fgBlack, bgWhite) # = tkStatusBar
  result.styles[tkHotkey] = style(fgRed, bgWhite)
  result.styles[tkLabelFocused] = style(fgWhite, bgBlue, bright = true)
  result.styles[tkCluster] = style(fgWhite, bgBlue)
  result.styles[tkList] = style(fgWhite, bgBlue)
  result.styles[tkButtonDefault] = style(fgWhite, bgGreen, bright = true)
  result.styles[tkButtonShadow] = style(fgBlack, bgBlue)
  result.styles[tkWindowCloseBox] = style(fgWhite, bgBlue, bright = true)
