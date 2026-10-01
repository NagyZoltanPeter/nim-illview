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

  Theme* = ref object
    styles*: array[ThemeToken, Style]

func style*(fg: ForegroundColor, bg: BackgroundColor, bright = false): Style =
  Style(fg: fg, bg: bg, bright: bright)

func style*(t: Theme, tok: ThemeToken): Style =
  t.styles[tok]

proc defaultTheme*(): Theme =
  ## Classic TurboVision-ish palette on illwill's 8+bright colors.
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
