## illview — retained-mode, TurboVision-inspired TUI widget framework.
## Umbrella module: re-exports the public API.

import illview/core/[events, geometry, theme, drawcontext, bus, view, routing, app]
import illview/backend/decoder
import illview/layout/layout
import illview/widgets/[desktop, window, label, button, checkbox, radio,
                        list, input, textview, statusbar, menu, editor, netviz,
                        groupbox, table, progress, scrollbar]
import illview/dsl/[pragmas, mount]
import illview/vocab
# The real nim-brokers bus lives in illview/bus_brokers — import explicitly
# to keep the broker macro expansion out of the default import graph.
# (vocab is different: the widgets themselves emit its events, so it is
# part of the default graph since Phase 12.)

export events, geometry, theme, drawcontext, bus, view, routing, app
export decoder
export layout
export desktop, window, label, button, checkbox, radio, groupbox, table, progress,
       list, input, textview, statusbar, menu, editor, netviz, scrollbar
export pragmas, mount
export vocab
