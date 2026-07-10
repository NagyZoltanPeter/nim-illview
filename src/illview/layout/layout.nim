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

func alignSpan*(a: Align, avail: int, h: SizeHint): tuple[off, size: int] =
  ## Place a child of hint `h` within `avail` cells per `a` (plan-4 D14).
  ## alStretch fills the span (clamped to max) at offset 0 — the historical
  ## behavior; the others size to pref and offset start/center/end.
  if a == alStretch:
    return (0, clamp(avail, h.min, h.max))
  let size = clamp(h.pref, h.min, min(h.max, avail))
  let off = case a
    of alStart, alStretch: 0
    of alCenter: max((avail - size) div 2, 0)
    of alEnd: max(avail - size, 0)
  (off, size)

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
    let m = c.outerHints()
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
    let m = c.outerHints()
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
    # alStretch keeps the historical cross clamp-to-max; other aligns size to
    # pref and offset within the cross span (plan-4 D14).
    let (coff, csize) =
      if c.align == alStretch:
        (0, clamp(crossTotal, cross[i].min, cross[i].max))
      else:
        alignSpan(c.align, crossTotal, cross[i])
    if b.axis == axH:
      c.arrange(rect(pos, coff, sizes[i], csize))
    else:
      c.arrange(rect(coff, pos, csize, sizes[i]))
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
    let m = c.outerHints()
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
    if c.align == alStretch:
      # historical grid behavior: fill the whole cell (ignores child max)
      c.arrange(rect(xs[col], ys[row], widths[col], heights[row]))
    else:
      let m = c.outerHints()
      let (xo, ws) = alignSpan(c.align, widths[col], m.w)
      let (yo, hs) = alignSpan(c.align, heights[row], m.h)
      c.arrange(rect(xs[col] + xo, ys[row] + yo, ws, hs))

# --- FormLayout --------------------------------------------------------------

type
  FormLayout* = ref object of Group
    ## Two-column form (plan-4 D14): children are (label, control) pairs in
    ## order. Column 0 auto-sizes to the widest label's pref; column 1 takes
    ## the rest and stretches. A trailing unpaired child gets its own row's
    ## label column. Per-child `align` still applies within each cell.
    spacing*: int

proc newFormLayout*(spacing = 0): FormLayout =
  result = FormLayout(spacing: spacing)
  initView(result)

proc formDims(f: FormLayout): tuple[labelW, ctrlW: int, rows: seq[SizeHint]] =
  ## Column-0 (label) and column-1 (control) pref widths and per-row height
  ## hints, aggregated over the (label, control) pairs.
  let kids = f.visibleChildren
  var i = 0
  while i < kids.len:
    let lw = kids[i].outerHints().w
    result.labelW = max(result.labelW, clamp(lw.pref, lw.min, lw.max))
    var rh = kids[i].outerHints().h
    if i + 1 < kids.len:
      let cm = kids[i + 1].outerHints()
      result.ctrlW = max(result.ctrlW, clamp(cm.w.pref, cm.w.min, cm.w.max))
      rh.min = max(rh.min, cm.h.min)
      rh.pref = max(rh.pref, clamp(cm.h.pref, cm.h.min, cm.h.max))
      rh.max = max(rh.max, cm.h.max)
    result.rows.add rh
    i += 2

method measure*(f: FormLayout): tuple[w, h: SizeHint] {.gcsafe, raises: [].} =
  let (labelW, ctrlW, rows) = f.formDims()
  let base = labelW + f.spacing
  result.w = SizeHint(min: base, pref: base + ctrlW, max: high(int),
                      stretch: max(f.hint.w.stretch, 1))
  result.h = combineMain(rows, f.spacing)
  result.h.stretch = f.hint.h.stretch

method arrange*(f: FormLayout, r: Rect) {.gcsafe, raises: [].} =
  f.bounds = r
  let kids = f.visibleChildren
  if kids.len == 0:
    return
  let (labelW, _, rows) = f.formDims()
  let cr = f.clientRect
  let heights = distribute(cr.h, rows, f.spacing)
  let col0 = min(labelW, cr.w)
  let col1x = col0 + f.spacing
  let col1w = max(cr.w - col1x, 0)
  var y = 0
  var i = 0
  var rowIdx = 0
  while i < kids.len:
    let rh = heights[rowIdx]
    let lm = kids[i].outerHints()
    let (lxo, lws) = alignSpan(kids[i].align, col0, lm.w)
    let (lyo, lhs) = alignSpan(kids[i].align, rh, lm.h)
    kids[i].arrange(rect(lxo, y + lyo, lws, lhs))
    if i + 1 < kids.len:
      let cm = kids[i + 1].outerHints()
      let (cxo, cws) = alignSpan(kids[i + 1].align, col1w, cm.w)
      let (cyo, chs) = alignSpan(kids[i + 1].align, rh, cm.h)
      kids[i + 1].arrange(rect(col1x + cxo, y + cyo, cws, chs))
    y += rh + f.spacing
    i += 2
    inc rowIdx
