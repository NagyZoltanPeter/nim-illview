## ControlBar (deviation #32): docked bar, 1..3 lines tall, hosting arbitrary
## child widgets in one row — a left group (`add`) filling the remaining width
## and a right group (`addRight` / `alignRight`) packed at preferred widths
## against the right edge. `StatusBar` stays the one-line hotkey-label bar.
##
## Zero-init safe for `mount(T)` (which never calls `newControlBar`):
## `lines = 0` means 1; the dock comes from `{.dock: dkBottom.}`.

import std/sets
import ../core/[geometry, theme, view, drawcontext]
import ../layout/layout

type
  ControlBar* = ref object of Group
    lines*: int   # requested height; effective height is clamp(lines, 1, 3)
    spacing*: int # cells between neighbouring children within a group
    rightIds: HashSet[int] # view ids of right-group children

const maxLines* = 3

func effLines(cb: ControlBar): int =
  clamp(cb.lines, 1, maxLines)

proc newControlBar*(lines = 1, spacing = 1): ControlBar =
  result = ControlBar(lines: lines, spacing: spacing)
  initView(result)
  result.dock = dkBottom
  result.hint = (prefHint(0, stretch = 1), fixedHint(result.effLines))

proc setLines*(cb: ControlBar, n: int) =
  ## Clamped to 1..3 on use; the App re-arranges every frame.
  cb.lines = n
  cb.invalidate()

proc alignRight*(cb: ControlBar, v: View) =
  ## Move an existing child (e.g. one created by `mount`) to the right group.
  cb.rightIds.incl v.id
  cb.invalidate()

proc addRight*(cb: ControlBar, v: View) =
  cb.add v
  cb.alignRight(v)

func isRight(cb: ControlBar, v: View): bool =
  v.id in cb.rightIds

method keepsChildOrder*(cb: ControlBar): bool {.gcsafe, raises: [].} =
  ## right-group order is declaration order (deviation #33)
  true

method measure*(cb: ControlBar): tuple[w, h: SizeHint] {.gcsafe, raises: [].} =
  var w, n = 0
  for c in cb.children:
    if c.visible:
      let h = c.outerHints().w
      w += clamp(h.pref, h.min, h.max)
      inc n
  if n > 1:
    w += cb.spacing * (n - 1)
  (prefHint(w, stretch = 1), fixedHint(cb.effLines))

method arrange*(cb: ControlBar, r: Rect) {.gcsafe, raises: [].} =
  cb.bounds = r
  let cr = cb.clientRect
  let lines = min(cb.effLines, cr.h)
  var left, right: seq[View]
  for c in cb.children:
    if c.visible:
      if cb.isRight(c): right.add c else: left.add c

  proc place(c: View, x, w: int) =
    let (off, h) = alignSpan(c.align, lines, c.outerHints().h)
    c.arrange(rect(x, off, max(w, 0), min(h, lines - off)))

  # right group: preferred widths, flush against the right edge
  var rightW = 0
  for i, c in right:
    let h = c.outerHints().w
    rightW += clamp(h.pref, h.min, h.max) + (if i > 0: cb.spacing else: 0)
  var x = max(cr.w - rightW, 0)
  let rightStart = x
  for c in right:
    let h = c.outerHints().w
    let w = clamp(h.pref, h.min, h.max)
    place(c, x, w)
    x += w + cb.spacing

  # left group: what remains, never overlapping the right group
  let gap = if right.len > 0 and left.len > 0: cb.spacing else: 0
  let avail = rightStart - gap
  var hints: seq[SizeHint]
  for c in left:
    hints.add c.outerHints().w
  let sizes = if avail > 0: distribute(avail, hints, cb.spacing)
              else: newSeq[int](left.len)
  x = 0
  let leftEnd = max(avail, 0)
  for i, c in left:
    let cx = min(x, leftEnd) # overflowed children collapse at the boundary
    place(c, cx, min(sizes[i], leftEnd - cx))
    x += sizes[i] + cb.spacing

method draw*(cb: ControlBar, dc: DrawContext) {.gcsafe, raises: [].} =
  dc.fill(rect(0, 0, cb.contentW, cb.effLines), " ", cb.styleOf(tkControlBar))
  procCall draw(Group(cb), dc)
