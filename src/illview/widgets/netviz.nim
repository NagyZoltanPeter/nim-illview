## NetVizWidget (Phase 6): live network/domain event visualizer built on
## TextView — a stats header plus the scrolling event feed. The widget has
## ZERO input plumbing of its own (framework routes input) and no broker
## dependency: subscription glue calls addEvent(), e.g. via
## bus_brokers.onDomainEvent.

import std/[tables, strformat, deques]
import ../core/[geometry, theme, view, drawcontext]
import ./textview

type
  NetVizWidget* = ref object of TextView
    total*: int
    perTopic*: OrderedTable[string, int]

proc newNetViz*(maxLines = 500): NetVizWidget =
  ## (Renamed from newNetVizWidget, deviation #30: the only `…Widget` constructor.)
  result = NetVizWidget(maxLines: maxLines, follow: true)
  initView(result)
  result.focusable = true
  result.hint = (prefHint(0, stretch = 1), prefHint(0, stretch = 1))

proc addEvent*(nv: NetVizWidget, topic, payload: string) =
  inc nv.total
  nv.perTopic.mgetOrPut(topic, 0) += 1
  nv.addLine &"[{topic}] {payload}" # addLine invalidates

method draw*(nv: NetVizWidget, dc: DrawContext) {.gcsafe, raises: [].} =
  let h = max(nv.contentH, 1)
  var header = &" events: {nv.total} "
  for topic, n in nv.perTopic:
    header.add &"| {topic}: {n} "
  dc.fill(rect(0, 0, nv.contentW, 1), " ", nv.styleOf(tkSelection))
  dc.write(0, 0, header, nv.styleOf(tkSelection))
  # feed body below the header (h-1 rows)
  let bodyH = h - 1
  if bodyH <= 0:
    return
  let start =
    if nv.follow: max(nv.lines.len - bodyH, 0)
    else: min(nv.top, max(nv.lines.len - 1, 0))
  let st = nv.styleOf(tkText)
  for y in 0 ..< bodyH:
    let idx = start + y
    if idx >= nv.lines.len:
      break
    dc.write(0, 1 + y, nv.lines[idx], st)
