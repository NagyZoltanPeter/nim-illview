## Backend input event types (§3.1 of docs/BUILD-PLAN.md).
##
## `Key` is reused from the vendored illwill. The framework-level `Event`
## (§3.5) lives in core/view.nim because it references `View` (sender) —
## see docs/DESIGN-DEVIATIONS.md.

import std/unicode

from ../backend/illwill_vendored import Key
export Key
export unicode.Rune

type
  InputKind* = enum
    ikKey, ikMouse, ikResize, ikPaste

  Modifier* = enum
    modShift, modAlt, modCtrl

  MouseAction* = enum
    maPress, maRelease, maMove, maWheelUp, maWheelDown

  MouseButton* = enum
    mbNone, mbLeft, mbMiddle, mbRight

  InputEvent* = object
    case kind*: InputKind
    of ikKey:
      key*: Key
      rune*: Rune
      keyMods*: set[Modifier]
    of ikMouse:
      action*: MouseAction
      button*: MouseButton
      mx*, my*: int
      mouseMods*: set[Modifier]
    of ikResize:
      discard
    of ikPaste:
      text*: string

proc `==`*(a, b: InputEvent): bool =
  ## Variant objects have no safe structural equality; needed by tests.
  if a.kind != b.kind:
    return false
  case a.kind
  of ikKey:
    a.key == b.key and a.rune == b.rune and a.keyMods == b.keyMods
  of ikMouse:
    a.action == b.action and a.button == b.button and
      a.mx == b.mx and a.my == b.my and a.mouseMods == b.mouseMods
  of ikResize:
    true
  of ikPaste:
    a.text == b.text

proc keyEvent*(key: Key, rune = Rune(0), mods: set[Modifier] = {}): InputEvent =
  InputEvent(kind: ikKey, key: key, rune: rune, keyMods: mods)

func isTabSwitch*(k: InputEvent): bool =
  ## Ctrl+PgUp / Ctrl+PgDn: reserved for switching tabs (TabView, deviation
  ## #39) — paging widgets let it bubble instead of treating it as PgUp/PgDn.
  k.kind == ikKey and modCtrl in k.keyMods and k.key in {Key.PageUp, Key.PageDown}

proc mouseEvent*(action: MouseAction, button: MouseButton, x, y: int,
                 mods: set[Modifier] = {}): InputEvent =
  InputEvent(kind: ikMouse, action: action, button: button,
             mx: x, my: y, mouseMods: mods)
