## GroupBox (Phase 8, deviation #34): a group of controls that pops out of the
## window by colour — its content is filled with the cluster surface
## (`tkCluster`). Borderless by default: the title is a heading row ABOVE the
## block, drawn on the window surface. `border = bkSingle` restores the framed
## look (title in the frame). Hosts dock/box layouts and works as a
## `{.view, vbox.}` base type in mount().

import ../core/[geometry, theme, view, drawcontext]

type
  GroupBox* = ref object of Group

proc newGroupBox*(title: string): GroupBox =
  result = GroupBox(borderTitle: title)
  initView(result)

func heading(g: GroupBox): bool =
  g.border == bkNone and g.borderTitle.len > 0

method clientRect*(g: GroupBox): Rect {.gcsafe, raises: [].} =
  result = procCall clientRect(View(g))
  if g.heading: # the heading row sits above the content
    result.y += 1
    result.h = max(result.h - 1, 0)

method measure*(g: GroupBox): tuple[w, h: SizeHint] {.gcsafe, raises: [].} =
  result = g.hint
  if g.heading:
    inc result.h.min
    inc result.h.pref
    if result.h.max != high(int):
      inc result.h.max

method titleStyle*(g: GroupBox): Style {.gcsafe, raises: [].} =
  g.styleOf(tkGroupBox)

method draw*(g: GroupBox, dc: DrawContext) {.gcsafe, raises: [].} =
  dc.fill(rect(0, 0, g.contentW, g.contentH), " ", g.styleOf(tkCluster))
  procCall draw(Group(g), dc)

method drawOverlay*(g: GroupBox, dc: DrawContext) {.gcsafe, raises: [].} =
  ## Heading row on the full rect (the window surface under the group).
  if g.heading:
    dc.write(g.padding, 0, g.borderTitle, g.styleOf(tkText))
