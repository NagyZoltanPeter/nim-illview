## StatusBar (Phase 4.5): docked one-line bar with clickable hotkey items
## (each publishes its `command`) plus a free-text area.

import std/unicode
import ../core/[geometry, theme, view, drawcontext, events, bus]

type
  StatusItem* = object
    label*: string # e.g. "F10 Menu"
    command*: Command

  StatusBar* = ref object of View
    items*: seq[StatusItem]
    text*: string

proc statusItem*(label: string, command: Command): StatusItem =
  StatusItem(label: label, command: command)

proc newStatusBar*(items: seq[StatusItem] = @[]): StatusBar =
  result = StatusBar(items: items)
  initView(result)
  result.dock = dkBottom
  result.hint = (prefHint(0, stretch = 1), fixedHint(1))

proc setText*(sb: StatusBar, s: string) =
  sb.text = s
  sb.invalidate()

func itemSpan(sb: StatusBar, i: int): tuple[x, w: int] =
  var x = 1
  for k in 0 ..< i:
    x += sb.items[k].label.runeLen + 3
  (x, sb.items[i].label.runeLen + 2)

method draw*(sb: StatusBar, dc: DrawContext) {.gcsafe, raises: [].} =
  let st = sb.styleOf(tkStatusBar)
  let hot = sb.styleOf(tkStatusBarHotkey)
  dc.fill(rect(0, 0, sb.bounds.w, 1), " ", st)
  for i, item in sb.items:
    let (x, _) = sb.itemSpan(i)
    dc.write(x, 0, " " & item.label & " ", hot)
  if sb.text.len > 0:
    let x = sb.bounds.w - sb.text.runeLen - 1
    dc.write(max(x, 0), 0, sb.text, st)

method handleEvent*(sb: StatusBar, ev: Event): bool {.gcsafe, raises: [].} =
  if ev.kind == evMouse and ev.imouse.action == maPress:
    for i, item in sb.items:
      let (x, w) = sb.itemSpan(i)
      if ev.imouse.mx >= x and ev.imouse.mx < x + w:
        sb.publish(item.command)
        return true
    return true # consume clicks on the bar background
  false
