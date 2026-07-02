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
