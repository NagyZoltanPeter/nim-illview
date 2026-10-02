## TriStateCheckBox (deviation #32): `[ ]` / `[x]` / `[?]` checkbox whose user
## path cycles unchecked → checked → intermediate. The mark character and its
## colour are configurable per state; `Checkbox` stays the two-state widget.

import std/unicode
import ../core/[geometry, theme, view, drawcontext, events, bus, hotkey]
import ../vocab

export CheckState

type
  TriStateCheckBox* = ref object of View
    caption*: string
    hlCol*: int # hotkey highlight column, -1 = none
    state*: CheckState
    marks*: array[CheckState, Rune] # the one cell between the brackets
    markStyle*: array[CheckState, StyleOverride] # mark cell only; zero = inherit
    command*: Command
    onChange*: proc(sender: TriStateCheckBox) {.gcsafe, raises: [].}

proc applyCaption*(c: TriStateCheckBox, s: string) =
  let hk = parseHotkey(s)
  c.caption = hk.text
  c.hotkey = hk.key
  c.hlCol = hk.col
  c.hint = (fixedHint(hk.text.runeLen + 4), fixedHint(1))
  c.invalidate()

proc newTriStateCheckBox*(caption: string, state = csUnchecked,
                          command = cmdNone): TriStateCheckBox =
  result = TriStateCheckBox(state: state, command: command, hlCol: -1,
                            marks: [Rune(' '), Rune('x'), Rune('?')])
  initView(result)
  result.focusable = true
  result.applyCaption(caption)
  let c = result
  c.installSignal(SetCheckState):
    # programmatic apply: no slot, no publish, no re-emit (plan-3 D8)
    c.state = sig.state
    c.invalidate()
  c.installFocusMe()

proc setState*(c: TriStateCheckBox, s: CheckState) =
  ## Programmatic: never fires `onChange` nor emits (deviation #15).
  c.state = s
  c.invalidate()

proc setMarks*(c: TriStateCheckBox, unchecked, checked, intermediate: Rune) =
  c.marks = [unchecked, checked, intermediate]
  c.invalidate()

proc setMarkStyle*(c: TriStateCheckBox, s: CheckState, o: StyleOverride) =
  c.markStyle[s] = o
  c.invalidate()

proc disabled(c: TriStateCheckBox): bool =
  c.command != cmdNone and not c.commandEnabled(c.command)

proc cycle*(c: TriStateCheckBox) =
  ## User path: unchecked → checked → intermediate → unchecked.
  if not c.enabled or c.disabled:
    return
  c.state = if c.state == CheckState.high: CheckState.low else: succ(c.state)
  if c.onChange != nil:
    c.onChange(c)
  c.publish(c.command)
  if c.hasBrokerCtx: StateChanged.emit(c.brokerCtx, StateChanged(state: c.state))
  c.invalidate()

method triggerHotkey*(c: TriStateCheckBox, scope: Group) {.gcsafe, raises: [].} =
  c.cycle()

func merged(st: Style, o: StyleOverride, focused: bool): Style =
  ## Same merge rule as `styleOf`'s per-view override, applied to one cell.
  result = st
  if o.fg != fgNone:
    result.fg = o.fg
    result.bright = o.bright
  if o.bg != bgNone:
    result.bg = o.bg
  if focused:
    if o.focusFg != fgNone:
      result.fg = o.focusFg
    if o.focusBg != bgNone:
      result.bg = o.focusBg

method draw*(c: TriStateCheckBox, dc: DrawContext) {.gcsafe, raises: [].} =
  let dis = c.disabled
  let st = if dis: c.styleOf(tkTextDisabled)
           else: c.styleOf(if c.isFocused: tkCheckboxFocused else: tkCheckbox)
  let mark = $c.marks[c.state]
  dc.fill(rect(0, 0, c.contentW, c.contentH), " ", st) # cluster surface
  dc.write(0, 0, "[" & mark & "] " & c.caption, st)
  if not dis:
    dc.write(1, 0, mark, merged(st, c.markStyle[c.state], c.isFocused))
    if c.hlCol >= 0: # box prefix "[x] " is 4 cells wide
      dc.write(4 + c.hlCol, 0, $c.caption.runeAtPos(c.hlCol), c.hotkeyStyle(st))

method handleEvent*(c: TriStateCheckBox, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    if ev.ikey.key == Key.Space: # Enter goes to the default button (TV)
      c.cycle()
      return true
  of evMouse:
    if ev.imouse.action == maPress:
      c.cycle()
      return true
  of evFocusGained, evFocusLost:
    c.invalidate()
  else:
    discard
  false
