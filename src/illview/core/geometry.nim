## Geometry primitives and layout size hints (§3.2).

type
  Point* = object
    x*, y*: int

  Rect* = object
    x*, y*, w*, h*: int

  Dock* = enum
    dkNone, dkTop, dkBottom, dkLeft, dkRight, dkFill

  Axis* = enum
    axH, axV

  Align* = enum
    ## Cross-axis (box) / in-cell (grid) placement of a child within the
    ## space allotted to it. alStretch (default) fills the span — the
    ## pre-iteration-4 behavior; the others size the child to its pref hint
    ## and position it at the start / center / end of the span.
    alStretch, alStart, alCenter, alEnd

  Anchor* = enum
    ## Edge-anchor mode for a dkNone child (plan-4 D14): each set edge keeps
    ## a constant offset from the parent's matching content edge as the
    ## parent resizes. Both edges of an axis => the child stretches on that
    ## axis; one edge => it slides; neither => it stays put (top-left).
    aLeft, aTop, aRight, aBottom

  SizeHint* = object
    min*: int
    pref*: int
    max*: int = high(int) # high(int) = unbounded
    stretch*: int         # 0 = fixed at pref; >0 = share of leftover space

func point*(x, y: int): Point =
  Point(x: x, y: y)

func rect*(x, y, w, h: int): Rect =
  Rect(x: x, y: y, w: w, h: h)

func contains*(r: Rect, p: Point): bool =
  p.x >= r.x and p.x < r.x + r.w and p.y >= r.y and p.y < r.y + r.h

func intersect*(a, b: Rect): Rect =
  let
    x1 = max(a.x, b.x)
    y1 = max(a.y, b.y)
    x2 = min(a.x + a.w, b.x + b.w)
    y2 = min(a.y + a.h, b.y + b.h)
  rect(x1, y1, max(x2 - x1, 0), max(y2 - y1, 0))

func isEmpty*(r: Rect): bool =
  r.w <= 0 or r.h <= 0

func fixedHint*(n: int): SizeHint =
  SizeHint(min: n, pref: n, max: n)

func prefHint*(n: int, stretch = 0): SizeHint =
  SizeHint(min: 0, pref: n, stretch: stretch)

# --- scroll geometry (plan-4 D15): pure int math shared by the ScrollBar -----
# widget and the list/table/textview indicator columns so they agree exactly.

func scrollMax*(total, page: int): int = max(total - page, 0)

func arrowCells*(track: int): int =
  ## TV scrollbars put an arrow at each end once the rail has room for them.
  if track >= 3: 1 else: 0

func thumbCell*(track, total, page, pos: int): int =
  ## Single-cell TV thumb (`■`): its index within the rail between the arrows.
  let inner = track - 2 * arrowCells(track)
  let sm = max(total - page, 0)
  if inner <= 1 or sm == 0: 0 else: (inner - 1) * min(pos, sm) div sm

func scrollGlyphs*(track, total, page, pos: int, axis: Axis): seq[string] =
  ## TV scrollbar cells (deviation #35): `▲`/`▼` (`◄`/`►` horizontal) at the
  ## ends, `▒` rail, one `■` thumb.
  if track <= 0:
    return @[]
  let a = arrowCells(track)
  result = newSeq[string](track)
  for i in 0 ..< track:
    result[i] = "▒"
  if a == 1:
    result[0] = if axis == axV: "▲" else: "◄"
    result[^1] = if axis == axV: "▼" else: "►"
  result[a + thumbCell(track, total, page, pos)] = "■"

func thumbGeom*(track, total, page, pos: int): tuple[start, len: int] =
  ## Thumb start-cell and length within a `track`-cell rail for a viewport of
  ## `page` over `total` at offset `pos`.
  if track <= 0 or total <= 0 or page >= total:
    return (0, max(track, 0))          # nothing to scroll: rail is all thumb
  let len = max(track * page div total, 1)
  let sm = scrollMax(total, page)
  let start = if sm == 0: 0 else: (track - len) * pos div sm
  (min(start, track - len), len)
