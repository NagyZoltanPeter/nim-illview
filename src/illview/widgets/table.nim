## Table (Phase 8): header row + row selection + vertical scrolling. Column
## widths are size hints distributed by the layout engine's distribute().
## NOT in v1 (scope-locked by plan-2): sorting, cell editing, horizontal
## scroll.

import std/unicode
import ../core/[geometry, theme, view, drawcontext, events, bus]
import ../layout/layout
import ../vocab

type
  TableColumn* = object
    title*: string
    hint*: SizeHint

  Table* = ref object of View
    columns*: seq[TableColumn]
    rows*: seq[seq[string]]
    selected*: int
    top*: int # first visible data row
    command*: Command
    onSelect*: proc(sender: Table) {.gcsafe, raises: [].}
    onActivate*: proc(sender: Table) {.gcsafe, raises: [].}

proc tableColumn*(title: string, hint: SizeHint): TableColumn =
  TableColumn(title: title, hint: hint)

proc recomputeHint(t: Table) =
  var w = max(t.columns.len - 1, 0) # 1-cell column spacing
  for c in t.columns:
    w += clamp(c.hint.pref, c.hint.min, c.hint.max)
  t.hint = (prefHint(w, stretch = 1), prefHint(t.rows.len + 1, stretch = 1))

func viewportRows(t: Table): int =
  max(t.contentH - 1, 1) # minus the header row

proc ensureVisible*(t: Table) =
  let h = t.viewportRows
  if t.selected < t.top:
    t.top = t.selected
  elif t.selected >= t.top + h:
    t.top = t.selected - h + 1
  t.top = clamp(t.top, 0, max(t.rows.len - 1, 0))

proc newTable*(columns: seq[TableColumn] = @[],
               rows: seq[seq[string]] = @[], command = cmdNone): Table =
  result = Table(columns: columns, rows: rows, command: command)
  initView(result)
  result.focusable = true
  result.recomputeHint()
  let t = result
  t.installSignal(SetSelected):
    # programmatic apply: no slot, no re-emit (plan-3 D8)
    if t.rows.len > 0:
      t.selected = clamp(sig.selected, 0, t.rows.high)
      t.ensureVisible()
      t.invalidate()
  t.installFocusMe()

proc setRows*(t: Table, rows: seq[seq[string]]) =
  t.rows = rows
  t.selected = clamp(t.selected, 0, max(rows.high, 0))
  t.top = 0
  t.recomputeHint()
  t.invalidate()

proc addRow*(t: Table, row: seq[string]) =
  t.rows.add row
  t.recomputeHint()
  t.invalidate()

proc select*(t: Table, i: int) =
  let ni = clamp(i, 0, t.rows.high)
  if t.rows.len == 0 or ni == t.selected:
    return
  t.selected = ni
  t.ensureVisible()
  if t.onSelect != nil:
    t.onSelect(t)
  SelectionChanged.emit(t.brokerCtx, SelectionChanged(selected: t.selected))
  t.invalidate()

proc activate*(t: Table) =
  if t.rows.len == 0:
    return
  if t.onActivate != nil:
    t.onActivate(t)
  t.publish(t.command)
  Activated.emit(t.brokerCtx, Activated(selected: t.selected))

func fit(s: string, w: int): string =
  ## First w runes (draw clipping would bleed into the next column).
  if w <= 0:
    return ""
  var n = 0
  for r in s.runes:
    if n >= w:
      break
    result.add r.toUTF8
    inc n

proc columnWidths(t: Table): seq[int] =
  var hints: seq[SizeHint]
  for c in t.columns:
    hints.add c.hint
  distribute(t.contentW, hints, spacing = 1)

method draw*(t: Table, dc: DrawContext) {.gcsafe, raises: [].} =
  if t.columns.len == 0:
    return
  let widths = t.columnWidths()
  let header = t.styleOf(tkTableHeader)
  let normal = t.styleOf(tkText)
  let sel = t.styleOf(if t.isFocused: tkSelectionFocused else: tkSelection)
  dc.fill(rect(0, 0, t.contentW, 1), " ", header)
  var x = 0
  for i, col in t.columns:
    dc.write(x, 0, fit(col.title, widths[i]), header)
    x += widths[i] + 1
  for y in 1 ..< max(t.contentH, 1):
    let idx = t.top + y - 1
    if idx > t.rows.high:
      break
    let st = if idx == t.selected: sel else: normal
    if idx == t.selected:
      dc.fill(rect(0, y, t.contentW, 1), " ", st)
    x = 0
    for i, _ in t.columns:
      if i < t.rows[idx].len:
        dc.write(x, y, fit(t.rows[idx][i], widths[i]), st)
      x += widths[i] + 1

method handleEvent*(t: Table, ev: Event): bool {.gcsafe, raises: [].} =
  case ev.kind
  of evKey:
    if modAlt in ev.ikey.keyMods:
      return false # Alt-chords are window/app level (move/resize)
    let page = t.viewportRows
    case ev.ikey.key
    of Key.Up: t.select(t.selected - 1)
    of Key.Down: t.select(t.selected + 1)
    of Key.Home: t.select(0)
    of Key.End: t.select(t.rows.high)
    of Key.PageUp: t.select(t.selected - page)
    of Key.PageDown: t.select(t.selected + page)
    of Key.Enter: t.activate()
    else:
      return false
    return true
  of evMouse:
    case ev.imouse.action
    of maWheelUp:
      t.top = max(t.top - 1, 0)
      t.invalidate()
      return true
    of maWheelDown:
      t.top = clamp(t.top + 1, 0, max(t.rows.len - t.viewportRows, 0))
      t.invalidate()
      return true
    of maPress:
      let idx = t.top + ev.imouse.my - 1 # row 0 is the header
      if ev.imouse.my >= 1 and idx >= 0 and idx <= t.rows.high:
        if idx == t.selected:
          t.activate()
        else:
          t.select(idx)
      return true
    else:
      discard
  of evFocusGained, evFocusLost:
    t.invalidate()
  else:
    discard
  false
