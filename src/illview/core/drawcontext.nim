## Offset + clip DrawContext (§3.3) — the ONLY sanctioned way widgets draw.
##
## Coordinates passed to write/fill/box/putCell are VIEW-LOCAL; the context
## translates them to absolute buffer positions and clips per cell against
## `clip` (an absolute rectangle). `sub()` derives a child context whose clip
## can only shrink, so no child can ever draw outside its ancestors.

import std/unicode
from std/terminal import styleBright
import ../backend/illwill_vendored except Style # theme.Style is illview's own
import ./geometry, ./theme

type
  DrawContext* = object
    tb*: TerminalBuffer # ref (deviation #2)
    ox*, oy*: int       # absolute origin of the current view
    clip*: Rect         # absolute clip rectangle

proc initDrawContext*(tb: TerminalBuffer): DrawContext =
  DrawContext(tb: tb, ox: 0, oy: 0, clip: rect(0, 0, tb.width, tb.height))

func sub*(dc: DrawContext, r: Rect): DrawContext =
  ## Push a child: origin shifts by the child's local rect; clip is the
  ## intersection of the parent clip and the child's absolute rect.
  DrawContext(
    tb: dc.tb,
    ox: dc.ox + r.x,
    oy: dc.oy + r.y,
    clip: intersect(dc.clip, rect(dc.ox + r.x, dc.oy + r.y, r.w, r.h)))

proc putCell*(dc: DrawContext, x, y: int, ch: Rune, style: Style) =
  let ax = dc.ox + x
  let ay = dc.oy + y
  if ax < dc.clip.x or ax >= dc.clip.x + dc.clip.w:
    return
  if ay < dc.clip.y or ay >= dc.clip.y + dc.clip.h:
    return
  var tb = dc.tb
  tb[ax, ay] = TerminalChar(
    ch: ch, fg: style.fg, bg: style.bg,
    style: if style.bright: {styleBright} else: {})

proc write*(dc: DrawContext, x, y: int, s: string, style: Style) =
  var ax = x
  for r in s.runes:
    dc.putCell(ax, y, r, style)
    inc ax

proc fill*(dc: DrawContext, r: Rect, ch: Rune, style: Style) =
  for y in r.y ..< r.y + r.h:
    for x in r.x ..< r.x + r.w:
      dc.putCell(x, y, ch, style)

proc fill*(dc: DrawContext, r: Rect, ch: string, style: Style) =
  dc.fill(r, ch.runeAt(0), style)

proc shade*(dc: DrawContext, r: Rect, style: Style) =
  ## Recolor cells keeping their runes — TV-style shadows: the underlying
  ## characters stay visible, only the palette darkens.
  for y in r.y ..< r.y + r.h:
    let ay = dc.oy + y
    if ay < dc.clip.y or ay >= dc.clip.y + dc.clip.h:
      continue
    for x in r.x ..< r.x + r.w:
      let ax = dc.ox + x
      if ax < dc.clip.x or ax >= dc.clip.x + dc.clip.w:
        continue
      var tb = dc.tb
      let old = tb[ax, ay]
      tb[ax, ay] = TerminalChar(
        ch: old.ch, fg: style.fg, bg: style.bg,
        style: if style.bright: {styleBright} else: {})

proc overlay*(dc: DrawContext, x, y: int, ch: Rune, style: Style) =
  ## Put `ch` in style's fg/bright but KEEP the cell's background — glyphs
  ## drawn over whatever surface is underneath (button shadow, deviation #34).
  let ax = dc.ox + x
  let ay = dc.oy + y
  if ax < dc.clip.x or ax >= dc.clip.x + dc.clip.w:
    return
  if ay < dc.clip.y or ay >= dc.clip.y + dc.clip.h:
    return
  var tb = dc.tb
  let old = tb[ax, ay]
  tb[ax, ay] = TerminalChar(
    ch: ch, fg: style.fg, bg: old.bg,
    style: if style.bright: {styleBright} else: {})

proc box*(dc: DrawContext, r: Rect, style: Style, double = false) =
  ## Frame on the edge of `r` (view-local). Cell-clipped like everything else.
  if r.w < 2 or r.h < 2:
    return
  let cs = if double: ["╔", "╗", "╚", "╝", "═", "║"]
           else: ["┌", "┐", "└", "┘", "─", "│"]
  let x2 = r.x + r.w - 1
  let y2 = r.y + r.h - 1
  dc.putCell(r.x, r.y, cs[0].runeAt(0), style)
  dc.putCell(x2, r.y, cs[1].runeAt(0), style)
  dc.putCell(r.x, y2, cs[2].runeAt(0), style)
  dc.putCell(x2, y2, cs[3].runeAt(0), style)
  for x in r.x + 1 ..< x2:
    dc.putCell(x, r.y, cs[4].runeAt(0), style)
    dc.putCell(x, y2, cs[4].runeAt(0), style)
  for y in r.y + 1 ..< y2:
    dc.putCell(r.x, y, cs[5].runeAt(0), style)
    dc.putCell(x2, y, cs[5].runeAt(0), style)
