## Two-pass layout engine (Phase 3): measure bottom-up aggregates child
## SizeHints per axis; arrange top-down distributes space — satisfy min,
## aim pref, share leftover by stretch, clamp to max. No constraint solver.
## `distribute()` is pure so the whole engine is unit-testable without a
## terminal. Dock anchoring lives in Group.arrangeChildren (core/view.nim)
## so every Group — including Window — reflows on resize.

import ../core/[geometry, view]

func satAdd(a, b: int): int =
  ## Saturating add for max-hints (high(int) = unbounded).
  if a == high(int) or b == high(int) or a > high(int) - b: high(int)
  else: a + b

proc distribute*(total: int, hints: seq[SizeHint], spacing = 0): seq[int] =
  ## Sizes along one axis for children with `hints` in `total` cells
  ## (minus spacing between items). Deterministic; rounding remainders are
  ## swept in child order.
  let n = hints.len
  if n == 0:
    return @[]
  result = newSeq[int](n)
  let avail = total - spacing * (n - 1)
  var sumPref = 0
  for i, h in hints:
    result[i] = clamp(h.pref, h.min, h.max)
    sumPref += result[i]

  if avail > sumPref:
    var leftover = avail - sumPref
    while leftover > 0:
      var totalStretch = 0
      for i, h in hints:
        if h.stretch > 0 and result[i] < h.max:
          totalStretch += h.stretch
      if totalStretch == 0:
        break # nothing stretchy left; leftover stays empty
      var grewAny = false
      let pool = leftover
      for i, h in hints:
        if h.stretch > 0 and result[i] < h.max:
          let share = pool * h.stretch div totalStretch
          let grow = min(share, h.max - result[i])
          if grow > 0:
            result[i] += grow
            leftover -= grow
            grewAny = true
      if not grewAny:
        # flooring gave everyone 0: hand out single cells in order
        for i, h in hints:
          if leftover == 0:
            break
          if h.stretch > 0 and result[i] < h.max:
            inc result[i]
            dec leftover
  elif avail < sumPref:
    let deficit = sumPref - avail
    var shrinkable = 0
    for i, h in hints:
      shrinkable += result[i] - h.min
    if shrinkable <= deficit:
      for i, h in hints:
        result[i] = h.min # may overflow the container; clipping handles it
    else:
      var remaining = deficit
      for i, h in hints:
        let cap = result[i] - h.min
        let cut = deficit * cap div shrinkable
        result[i] -= cut
        remaining -= cut
      while remaining > 0: # sweep rounding remainder
        for i, h in hints:
          if remaining == 0:
            break
          if result[i] > h.min:
            dec result[i]
            dec remaining

func combineMain(hints: seq[SizeHint], spacing: int): SizeHint =
  let pad = spacing * max(hints.len - 1, 0)
  result = SizeHint(min: pad, pref: pad, max: pad)
  for h in hints:
    result.min += h.min
    result.pref += clamp(h.pref, h.min, h.max)
    result.max = satAdd(result.max, h.max)

func combineCross(hints: seq[SizeHint]): SizeHint =
  result = SizeHint(max: 0)
  for h in hints:
    result.min = max(result.min, h.min)
    result.pref = max(result.pref, clamp(h.pref, h.min, h.max))
    result.max = max(result.max, h.max)
  if hints.len == 0:
    result.max = high(int)

# --- HBox / VBox -------------------------------------------------------------

type
  BoxLayout* = ref object of Group
    axis*: Axis
    spacing*: int

proc newBox(axis: Axis, spacing: int): BoxLayout =
  result = BoxLayout(axis: axis, spacing: spacing)
  initView(result)

proc newHBox*(spacing = 0): BoxLayout =
  newBox(axH, spacing)

proc newVBox*(spacing = 0): BoxLayout =
  newBox(axV, spacing)

proc visibleChildren(g: Group): seq[View] =
  for c in g.children:
    if c.visible:
      result.add c

method measure*(b: BoxLayout): tuple[w, h: SizeHint] {.gcsafe, raises: [].} =
  var wHints, hHints: seq[SizeHint]
  for c in b.visibleChildren:
    let m = c.measure()
    wHints.add m.w
    hHints.add m.h
  if b.axis == axH:
    result = (combineMain(wHints, b.spacing), combineCross(hHints))
  else:
    result = (combineCross(wHints), combineMain(hHints, b.spacing))
  # container-level stretch comes from the box's own hint
  result.w.stretch = b.hint.w.stretch
  result.h.stretch = b.hint.h.stretch

method arrange*(b: BoxLayout, r: Rect) {.gcsafe, raises: [].} =
  b.bounds = r
  let kids = b.visibleChildren
  var main, cross: seq[SizeHint]
  for c in kids:
    let m = c.measure()
    if b.axis == axH:
      main.add m.w
      cross.add m.h
    else:
      main.add m.h
      cross.add m.w
  let cr = b.clientRect
  let mainTotal = if b.axis == axH: cr.w else: cr.h
  let crossTotal = if b.axis == axH: cr.h else: cr.w
  let sizes = distribute(mainTotal, main, b.spacing)
  var pos = 0
  for i, c in kids:
    let crossSize = clamp(crossTotal, cross[i].min, cross[i].max)
    if b.axis == axH:
      c.arrange(rect(pos, 0, sizes[i], crossSize))
    else:
      c.arrange(rect(0, pos, crossSize, sizes[i]))
    pos += sizes[i] + b.spacing

# --- Grid --------------------------------------------------------------------

type
  Grid* = ref object of Group
    cols*: int
    spacing*: int

proc newGrid*(cols: int, spacing = 0): Grid =
  result = Grid(cols: max(cols, 1), spacing: spacing)
  initView(result)

proc gridHints(g: Grid): tuple[colH, rowH: seq[SizeHint]] =
  ## Column hint = loosest combination over the column's cells; same for rows.
  let kids = g.visibleChildren
  if kids.len == 0:
    return
  let rows = (kids.len + g.cols - 1) div g.cols
  result.colH = newSeq[SizeHint](g.cols)
  result.rowH = newSeq[SizeHint](rows)
  for i in 0 ..< g.cols:
    result.colH[i] = SizeHint(max: 0)
  for i in 0 ..< rows:
    result.rowH[i] = SizeHint(max: 0)
  for i, c in kids:
    let m = c.measure()
    let col = i mod g.cols
    let row = i div g.cols
    template mergeInto(dst: SizeHint, src: SizeHint) =
      dst.min = max(dst.min, src.min)
      dst.pref = max(dst.pref, clamp(src.pref, src.min, src.max))
      dst.max = max(dst.max, src.max)
      dst.stretch = max(dst.stretch, src.stretch)
    mergeInto(result.colH[col], m.w)
    mergeInto(result.rowH[row], m.h)

method measure*(g: Grid): tuple[w, h: SizeHint] {.gcsafe, raises: [].} =
  let (colH, rowH) = g.gridHints()
  result = (combineMain(colH, g.spacing), combineMain(rowH, g.spacing))
  result.w.stretch = g.hint.w.stretch
  result.h.stretch = g.hint.h.stretch

method arrange*(g: Grid, r: Rect) {.gcsafe, raises: [].} =
  g.bounds = r
  let kids = g.visibleChildren
  if kids.len == 0:
    return
  let (colH, rowH) = g.gridHints()
  let cr = g.clientRect
  let widths = distribute(cr.w, colH, g.spacing)
  let heights = distribute(cr.h, rowH, g.spacing)
  var ys = newSeq[int](heights.len)
  var acc = 0
  for i, h in heights:
    ys[i] = acc
    acc += h + g.spacing
  var xs = newSeq[int](widths.len)
  acc = 0
  for i, w in widths:
    xs[i] = acc
    acc += w + g.spacing
  for i, c in kids:
    let col = i mod g.cols
    let row = i div g.cols
    c.arrange(rect(xs[col], ys[row], widths[col], heights[row]))
