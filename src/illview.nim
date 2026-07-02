## illview — retained-mode, TurboVision-inspired TUI widget framework.
## Umbrella module: re-exports the public API.

import illview/core/[events, geometry, theme, drawcontext, bus, view, routing, app]
import illview/backend/decoder
import illview/layout/layout
import illview/widgets/[desktop, window, label, button, checkbox, radio,
                        list, input, textview, statusbar, menu, editor, netviz]
import illview/dsl/[pragmas, mount]
# The real nim-brokers bus lives in illview/bus_brokers — import explicitly
# to keep the broker macro expansion out of the default import graph.

export events, geometry, theme, drawcontext, bus, view, routing, app
export decoder
export layout
export desktop, window, label, button, checkbox, radio,
       list, input, textview, statusbar, menu, editor, netviz
export pragmas, mount
