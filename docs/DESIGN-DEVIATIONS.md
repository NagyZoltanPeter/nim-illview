# Design deviations & gap analysis

Deviations from [BUILD-PLAN.md](BUILD-PLAN.md), found while executing. The plan
remains authoritative for everything not listed here. Numbering is stable so
commits can reference "deviation #N".

## 1. Decoder is a rewrite, not a lift (Phase 0)

The plan assumes the escape-sequence parser can be "lifted out" of illwill's
`getKey()`. It cannot: illwill's POSIX `parseStdin` issues multiple blocking
`read()` calls *mid-sequence*, keeps no partial-sequence state, and does not
handle Alt-combos, UTF-8 runes, CSI modifier parameters, or bracketed paste.

What was ported verbatim: the `Key` mapping tables (`KEYS_D/E/F/G`) and the
SGR mouse bit layout from `fillGlobalMouseInfo`. The incremental state machine
in `backend/decoder.nim` is new. Additions beyond the plan's §3.1:

- `flush()` — resolves the bare-ESC ambiguity. A lone `0x1B` may be the ESC
  key or the head of a sequence whose tail hasn't arrived. `feed()` keeps it
  pending; the driver calls `flush()` after draining the fd, which converts a
  pending lone ESC into `Key.Escape`. Without this, ESC-the-key is
  undecodable in an incremental parser.
- CSI modifier params (`\e[1;5C` → Right+Ctrl), `\e[Z` → Shift-Tab.
- Bracketed paste (`ikPaste` is declared in the plan's §3.1 but no phase task
  implements it; the framework will enable mode 2004 in the driver).
- Key aliasing follows upstream illwill: bytes 10 and 13 → `Key.Enter`,
  8 and 127 → `Key.Backspace`. `Key.CtrlH` / `Key.CtrlJ` are therefore
  unreachable, exactly as in illwill.

## 2. `DrawContext.tb` is `TerminalBuffer`, not `ptr TerminalBuffer` (§3.3)

illwill's `TerminalBuffer` is a `ref object`; a `ptr` to it would be a pointer
to a managed ref cell. The field holds the ref directly.

## 3. `Style` is an illview type (§3.3)

illwill has no single `Style` value — drawing state is
`ForegroundColor` + `BackgroundColor` + `set[terminal.Style]`. `core/theme.nim`
defines `Style* = object; fg, bg, styles` and the theme tokens map to it.

## 4. Widget access to `App`/bus (§3.9)

The plan's activation pseudocode references `app.bus` inside
`Button.handleEvent` but never defines how a widget reaches the `App`.
Decision: `Desktop` (the root `Group`) holds an `App` backref; `View.app()`
walks `parent` to the root. Views detached from a desktop get `nil` — slots
still fire, broker publish is skipped.

## 5. `Group.focused` vs `App.focus` (§3.4/§3.7)

Two sources of truth in the plan. Decision: `App.focus` is authoritative for
key delivery; `Group.focused` only remembers the group's last-focused child so
window activation can restore it. Invariant: `App.focus` is always reachable
from `App.desktop` or is `nil`.

## 6. Modal loop is Future-based (§ Phase 2)

A TurboVision-style nested poll loop conflicts with a single chronos loop.
`execView(v): Future[Command]` inserts the modal view, marks it modal (routing
refuses to deliver outside it), and returns a future completed by
`endModal(cmd)`. No nested event loop, no reentrancy.

## 7. Framework `Event` lives next to `View`, not in `core/events.nim` (§3.5)

`Event` carries `sender*: View`; defining it in `events.nim` would create an
import cycle (`events → view → events`). `core/events.nim` holds the backend
input types; `Event`/`EventKind` are defined in `core/view.nim` and re-exported
by the umbrella module, so user code sees no difference.

## 8. Dependency handling

- `chronos` — normal nimble requirement.
- `nim-brokers` — IS in the nimble registry as `brokers`
  (github.com/NagyZoltanPeter/nim-brokers), contrary to the initial
  assumption. Phases 1–5 code against the `EventBus` abstraction + `StubBus`
  only (per plan §3.8); Phase 6 adds `requires "brokers >= 3.1.0"` and
  implements `BrokersBus` in `illview/bus_brokers.nim`. That module is
  deliberately NOT re-exported by the umbrella so the broker macro expansion
  stays out of the default import graph — import it explicitly.

## 9. Phase 6 scope split

Wiring `enableTui`/`disableTui` into the LogosDelivery daemon happens in the
`logos-delivery` repository, not here. This repo delivers: the real
nim-brokers `EventBus` implementation, `NetVizWidget`, and
`examples/06_netviz.nim` driving it with synthetic domain events.

## 10. `enableTui`/`disableTui` re-entrancy vs `illwillInit`

`illwillInit` raises `IllwillError` on double-init and `illwillDeinit` on
double-deinit; the vendored file stays verbatim, so `App` tracks its own
`tuiActive` state and additionally saves/restores `O_NONBLOCK` on stdin
(illwill only toggles termios ICANON/ECHO; the chronos driver needs
non-blocking reads).

## 11. Resize delivery (Phase 1)

`SIGWINCH` handlers can't safely touch the chronos loop. The POSIX driver uses
the self-pipe trick: the signal handler write()s one byte to a pipe registered
with `addReader`; the read side emits `ikResize` on the loop thread. (chronos'
signal support is platform-uneven; the self-pipe is dependency-free and
single-threaded.)

## 12. Example file names carry an `ex` prefix (§2)

The plan's `00_echo.nim` is not a valid Nim module name (identifiers cannot
start with a digit — the compiler rejects the file). Examples are
`ex00_echo.nim`, `ex01_loop.nim`, … instead.

## 13. Demand-scheduled frames instead of a permanent ticker (§3.7, Phase 1)

The plan describes "a capped ticker [that] renders one frame when dirty". A
permanently-running 30 Hz ticker wakes the loop 30×/s even when idle. Instead,
`requestRedraw` arms a *one-shot* frame task that waits out the remainder of
the fps period and then renders once. Same observable behavior (dirty-driven,
fps-capped), but an idle app has **zero** pending timers — which is what the
Phase 1 exit criterion ("idle CPU ≈ 0") actually demands. Verified: 4 s
mostly-idle run = 0.00 user + 0.00 sys.

## 14. Input reads its own tty fd, never O_NONBLOCK on stdin (Phase 6 fix)

The Phase-1 driver set `O_NONBLOCK` on fd 0. On a terminal, fd 0/1/2
normally share ONE open file description, so the flag also made **stdout**
non-blocking — large frames then failed mid-write with `EAGAIN` (observed as
`IOError: errno 35` on quit, and silently dropped frames elsewhere). The
driver now opens the terminal's real device (`ttyname(0|1|2)`) as a
dedicated O_NONBLOCK read fd; termios raw mode set by illwill on fd 0 still
applies because termios state is per-device. Note: `/dev/tty` (the alias
device) is NOT usable here — macOS kqueue refuses to watch it. Fallback when
no fd is a tty: the old stdin+O_NONBLOCK path (flags restored on stop).

## 15. No echo-guard flag for signal application (plan-3 D8, Phase 12)

Plan-3 D8 called for an `applying: bool` guard so inbound Set-signals don't
re-emit outbound vocab events. Unnecessary: illview's programmatic setters
(`setText`, direct field application in the signal handlers) have NEVER fired
change slots — only user-driven edit paths call `changed()`/`onToggle`/etc.,
and those are the only places the vocab emits live. Signal application
therefore bypasses slots and emission by construction; no guard flag exists.
Consequence (documented in vocab.nim): tier-1 slots do NOT observe
signal-applied changes — same semantics programmatic setters always had.

## 16. dispose() is explicit; remove()/close do NOT auto-dispose (plan-3 D11)

Plan-3 wired dispose into `Desktop.remove`/`Window.close`. There is no
`Window.close`, and `Group.remove` is used for transient reparenting (menu
popups, window re-adds) where broker wiring must survive. Auto-dispose there
would silently strip signal handlers from a view the app intends to re-add.
`dispose(v)` is therefore an explicit lifecycle call: exactly once, when a
subtree is permanently done. The strong-ref note stands: broker registrations
keep undisposed views alive (registry global → plain leak under refc AND ORC,
no cycle involved).

## 17. core/view depends on brokers/broker_context (plan-3 D7, Phase 12)

`bus.nim`/`view.nim` were the dependency-free bottom. `View.brokerCtx`
requires `brokers/broker_context` — a leaf module (chronos-only) of
nim-brokers; the broker MACHINERY (EventBroker/SignalBroker expansion) stays
out of core and lives in `vocab.nim`. vocab also deliberately does not
`export brokers`: event_broker re-exports std/tables, whose `Table` collides
with the Table widget in the umbrella module.

## 18. Windows input driver deferred by decision (plan-4 D13, Phase 16)

The original plan scoped Windows *async* input out; iteration 4 makes the
deferral explicit and documented. illview is POSIX-only (macOS/Linux/WSL)
until a native-Windows consumer exists. The full design — INPUT_RECORD
translation, `RegisterWaitForSingleObject` → chronos `ThreadSignalPtr`
wake-up (the kernel thread-pool callback only signals; it bends the
single-thread directive in letter, not in spirit), `WINDOW_BUFFER_SIZE_EVENT`
resize — lives in [WINDOWS-DRIVER.md](WINDOWS-DRIVER.md), including cost/risk
and the testing blocker (no pty equivalent on Windows).

## 19. The child-alignment pragma is `alignSelf`, not `align` (plan-4 D14, Phase 17)

BUILD-PLAN-4 D14 names the DSL pragma `align(a)`. Nim reserves `{.align: N.}`
as a built-in field-alignment pragma taking a power-of-two integer, and it
wins name resolution in field-pragma position — `align: alEnd` fails with
"power of two expected" at type-definition time, before the mount macro ever
runs. The pragma is therefore `alignSelf` (after CSS `align-self`); the
`View.align` field and the `Align`/`al*` enum keep their names. `padding` and
`anchors` do not collide with any built-in pragma.

## 20. Command gating reuses `tkTextDisabled`; menu gating lands in P23 (plan-4 D19, Phase 22)

D19 calls for a new `tkDisabled` theme token; `tkTextDisabled` already exists
with identical semantics (dim, non-interactive), so greyed command items reuse
it rather than add a redundant token. Command enable/disable is wired through
Button, Checkbox and StatusBar in Phase 22; **menu** item greying/gating is
deferred to Phase 23, where the menu is already being reworked for submenus —
doing both in one pass avoids touching menu.nim twice. Alt+letter hotkeys cover
Button/Checkbox/Label in P22; **menubar** top-level accelerators also land with
the P23 menu rework.

## 21. instanceCtx recycling dropped; back to nim-brokers 3.2.0 (iteration 5)

Iteration 3 (deviation #16) had `dispose()` call `releaseInstanceCtx` to recycle
a View's broker instanceCtx id, needing a local nim-brokers 3.3.0. That whole
mechanism is **reverted**: `requires "brokers >= 3.2.0"` at the time (now
`>= 3.4.0`, still without `releaseInstanceCtx`), `dispose()` no longer
recycles (it drops listeners via the recorded disposers and marks the ctx
inert), and the one `hasListeners` test assertion became a behavioral check
(activate a disposed widget → reaches nobody).

Rationale: recycling was needed only because transient views (menus, dialogs)
were **created fresh on every open** and never returned their id — churn against
a 16-bit, monotonic instanceCtx counter. The framework already separates object
lifetime from tree membership (`remove()` keeps wiring; `dispose()` is the
explicit teardown, deviation #16). Adopting **persistent-object /
transient-membership** — build a popup/dialog/context-menu once, `add`/`remove`
it on show/hide, `dispose` only at app teardown — allocates one instanceCtx per
object for its whole life, so there is no churn and nothing to recycle. The
persistent MenuBar popups + ContextMenu widget realize this.

## 22. Mouse-capture release under 1003, ORC churn crash, crash-time restore

Three related runtime bugs found stress-testing the showcase (ex13):

- **Drag "holds tight".** illwill enables 1003 *any-event* mouse tracking; real
  terminals often report a button-up as a no-button motion (`maMove`, `mbNone`)
  rather than a distinct `maRelease`. Capture only cleared on `maRelease`, so a
  splitter/window-resize grab stuck forever. Fix: `dispatchMouse` also ends a
  capture on a no-button move (normalizing it to `maRelease` for the captor).

- **SIGSEGV under --mm:orc when churning app-capturing closures.** Repeatedly
  building + freeing views whose closures capture `app` (forming
  app→tree→closure→app cycles) trips the ORC cycle collector (deterministic
  crash under orc, none under refc). This is why the showcase now uses
  persistent, cached example windows (deviation #21) — build once, add/remove,
  never free — rather than rebuild-on-select. A splitter/grid/form also needs a
  stretchy hint or it collapses to 0 inside a box (`newSplitter` now sets one).

- **Terminal wrecked after any crash.** Nim runs `addExitProc` only on
  `quit()`, NOT on an unhandled exception or a signal, so a crash left the
  terminal in raw + mouse mode ("trash on mouse move"). Fix: `enableTui`
  installs POSIX signal handlers (SIGSEGV/ABRT/BUS/ILL/FPE) that reset the
  terminal with async-signal-safe `write(2)`/`tcsetattr` before the default
  action. Normal exit still restores via `run()`'s `finally: disableTui`.

Standalone reproducer: [repro/orc_churn_crash.nim](../repro/orc_churn_crash.nim)
— SIGSEGVs under `--mm:orc`, clean under `--mm:refc`. The crash resisted
minimization below the full-app graph (pure-stdlib closure churn and several
smaller illview subsets did not reproduce it), so the reproducer is the
showcase with caching disabled.

## 23. Docked-child raise flip; async-closure ORC churn; MDI tile (showcase)

More showcase issues found in a second pass:

- **Menu/title bar "flip" on click.** `dispatchMouse` raised the scope's clicked
  direct child for window z-order — but that also reordered *docked* children
  (menu/title/status bars), and since dock arrangement follows child order they
  visibly swapped. Fix: only raise `dkNone` (floating) children.

- **Dialog examples still SIGSEGV'd.** The prior fix cached example windows, but
  the Confirm/Input-box buttons still built an `app`-capturing *async* onClick
  closure — and *building* that under the churn (or even in a startup bulk
  build) trips the ORC collector (deviation #22). Fix: the buttons emit a plain
  broker event that captures nothing; a single persistent listener (wired once)
  opens the dialog. Example windows are also pre-built once at startup, not
  during the poll loop.

- **File > Tile did nothing.** The ground showed one example at a time, so there
  was nothing to tile. Reworked to MDI: Enter opens a leaf as a floating window
  in the ground (several coexist, movable/resizable/closable), and Tile
  arranges them in a grid. `-d:noCrashRestore` added to `enableTui` to opt out
  of the crash-restore signal handlers (for getting clean tracebacks).

## 24. Modal focus restore; nested-window raise; window move clamp

MDI follow-ups (nested floating windows in a sub-group):

- **Focus lost after a modal closed.** `execView` focus-into'd the modal but
  never saved the prior focus, and `endModal` never restored it — so after a
  menu/dialog closed, keys went to the detached modal (e.g. Tile a window, then
  the tree stopped responding to Enter). `execView` now records the pre-modal
  `focusedLeaf`; `endModal` restores it in the layer below.

- **Nested windows never raised.** The raise-on-press only reordered the
  *scope's* direct children, so a floating window inside a sub-group (the MDI
  ground) never came to front (a maximized one hid behind its neighbours). Now
  `dispatchMouse` raises every floating view on the target→scope path, each
  within its own parent.

- **A dragged window could be lost.** A parent group clips its children, so a
  window dragged out was unreachable. `Window.moveTo` now clamps the window to
  the parent's content area.

## 25. Showcase MDI ground is a nested Desktop; click activates content-less windows

Iterations 4–5 repeatedly hit rough edges putting the ex13 example windows in a
plain `Group` "ground": no `tile`/`cascade`, subtly different z-order and
activation than the desktop. Root cause: the ground was an *untested* window
container. Fix (deviation #25, driven by the user's redesign call):

- **The example ground is now a nested `Desktop`** — the framework's primary,
  tested window surface. `Desktop.tile`/`cascade`/`selectWindow`/
  `floatingWindows` operate on `d.clientRect`/`d.children` and never required
  the desktop to be the app root, so a `Desktop` nested as the splitter's right
  pane gives real MDI (tile, cascade, raise, move, resize) for free. The tree +
  splitter stay docked on the left, as required. `tileGround` (a hand-rolled
  copy of `Desktop.tile`) was deleted; `File > Tile` calls `ground.tile()`.

- **A floating window with no focusable content couldn't be activated.**
  `dispatchMouse`'s frame-click path only did `focusInto`, which is a no-op when
  the window has no focusable descendant (e.g. the label-only "Box / grid"
  pane) — so clicking it never made it the active window, so no double border,
  no ◢ grip, no keyboard move/resize. Now, when no focusable widget is hit,
  routing walks up to the nearest floating (`dock == dkNone`) view and selects
  the window itself if its content took no focus. `focusInto`-into-remembered-
  child is preserved for windows that *do* have focusable content. This is a
  general framework fix, not showcase-specific.

Interaction note (not a bug): after `Tile`, focus is on the tree, so no example
window is active. Click a window to activate it (double border + ◢), then drag
◢ or Alt+Shift+Arrows to resize. Regression test: "nested Desktop as MDI ground:
tile, click-activate, then resize" in `tests/test_routing.nim`.

## 26. uiEvents `emits:` fire on a session ctx, not DefaultBrokerContext

Generated `emits:` events (`uiEmit`) used to `emit(Ev(…))` on the global
`DefaultBrokerContext`, colliding with every other broker user in the process and
offering no way to sandbox two UIs. They now fire on the sender's **session
ctx** — the shared classCtx common to all views, per-instance high-16 stripped —
via `emit(Ev, sender.sessionCtx, Ev(…))`. Listeners subscribe with
`Ev.listen(view.sessionCtx, …)` (or `app.sessionCtx`), never the bare default.

The session ctx is resolved at view construction by `viewSessionParent()`:

- No thread broker context installed → the process-wide `gAppClassCtx` (still off
  the global default). Preserves prior behavior for standalone widgets/tests.
- `newApp` installs its own session ctx (`app.sessionCtx`, a fresh
  `NewBrokerContext()` unless one is passed) as the thread global BEFORE building
  the desktop, so every app view adopts it — each App is its own sandbox.
- A user can install their own: `setThreadBrokerContext(myCtx)` before building,
  then `Ev.listen(myCtx, …)`. The broker-context API is re-exported from illview.

`emits:` uses the **session** part deliberately (common to all widgets, keyed by
`ev.senderId`); instance-ctx vocab events (`Clicked`/`TextChanged`, the `on: {}`
path) still route on the full per-widget `brokerCtx` and are unchanged. The
opened-bus `UiAction`/domain events stay on `DefaultBrokerContext` by design.
Regression tests in `tests/test_bindings.nim`: emits land on the session ctx (not
the default), and a `setThreadBrokerContext` sandbox routes to the saved ctx.

**Superseded in part by #27**: the "each App is its own sandbox by default"
resolution (fresh `NewBrokerContext()` + `setThreadBrokerContext`) is gone.

## 27. The session ctx IS the thread's global broker context

Deviation #26 made `newApp` allocate a fresh session ctx and **install it as
the thread's global broker context**. An external audit flagged this as the
main obstacle to embedding illview in a host that keys its own brokers on
`globalBrokerContext()` (logos-delivery captures it at construction in ~20
places): depending on whether the node or the TUI was built first, the node
silently adopted illview's private scope or the two never met.

New resolution, `core/app.nim` `newApp` + `core/view.nim` `viewSessionParent`:

- No argument → **adopt `globalBrokerContext()` as-is**, `DefaultBrokerContext`
  included. `app.sessionCtx == globalBrokerContext()`, and every view built on
  the thread derives its instance ctx from the same class. `newApp` never
  calls `setThreadBrokerContext`.
- Host-installed scope (`setThreadBrokerContext(myCtx)` before building) →
  adopted, exactly as before. This remains the sandbox path.
- Explicit `newApp(sessionCtx = x)` → `x` is bound through an illview-private
  `{.threadvar.}` (`bindSessionCtx`) so views built afterwards land on it
  without touching the brokers threadvar. A later plain `newApp()` clears the
  binding. `gAppClassCtx` is deleted.

Consequence: on a bare thread, `emits:` events now fire on
`DefaultBrokerContext` — by decision: the UI shares the scope its host process
already uses, and isolation is opt-in (install or pass a ctx). Two UIs in one
process each pass their own `sessionCtx`.

Same phase: menu `item(label, EventType)` no longer emits on the ambient
default ctx. It emits on the popup **host's** `sessionCtx` (menu bar /
context-menu opener) with `senderId = host.id` when the type declares that
field (default-constructed otherwise), via a new `MenuItem.onActivateFrom`
slot. Closes the open item noted under #26.

Tests: `tests/test_bindings.nim` "session ctx resolution (deviation #27)" (adopt
host ctx + thread ctx untouched; bare thread → default; explicit binding), and
`tests/test_menu.nim` "emits on the host's session ctx with senderId".

## 28. Instance ctx materialized on first use

`initView` allocated `newInstanceCtx` for **every** view — each Label, each
layout box — from nim-brokers' process-wide, monotonic, 16-bit instanceCtx
counter (`doAssert` at 65 535), the same counter a host's own broker
sub-instances draw from. Persistent-object/transient-membership (#21) keeps
the churn down but not the base cost: a 300-widget screen was 300 ids at
construction, most of them never listened to or signalled.

Now `View.brokerCtx` is an accessor (`core/view.nim`): the id is allocated
the first time anyone asks for the route — a listener, a `SetText.signal`, a
`bindValue` writer, an `on:` lowering. `initView` only captures the session
classCtx. Widget constructors still declare their signal handlers, but
`installSignal`/`installFocusMe` (`vocab.nim`) now go through
`deferWiring`, which runs the install at materialization (or immediately if
the ctx already exists). Widgets emit vocab events only `if w.hasBrokerCtx`
— nobody can be listening on a route that was never handed out. `dispose`
marks the view so the accessor stays inert (`BrokerContext(0)`) afterwards.

Source-compatible: `x.brokerCtx` reads unchanged; only `view.nim` ever
assigned the field. refc notes: (1) a deferred wiring closure captures its
own view (view → closure → view cycle) until materialization or `dispose`
clears it; the eager install held the same view alive through the broker
registry, so the "dispose exactly once" contract (#16) is unchanged. (2) The
accessor takes the pending list with `swap`, not `let pending = v.wiring`:
under `--mm:refc` that `let` aliases the seq field, so the following
`setLen 0` emptied both and no wiring ever ran — every Set-signal returned
`err` under refc while ORC (which copies) was green. Caught by the refc CI
leg (deviation #31) the first time it ran.

Test: `tests/test_ctx_vocab.nim` "lazy instance ctx" — 1 000 Labels
allocate nothing; ids are handed out in use order, not construction order;
deferred wiring is live after materialization; a never-materialized widget
activates without emitting and without crashing.

## 29. The DSL fails loudly, and third-party widgets are first-class

Four silent failure modes in `dsl/mount.nim` / `dsl/uievents.nim`, all found
by the audit, all now compile errors:

1. **Misplaced pragmas.** A known DSL pragma in the wrong position
   (`{.caption.}` on a type, `{.vbox.}` on a field) or any DSL pragma on a
   field without `{.child.}` compiled and did nothing. `rejectMisplaced`
   checks type-level and field-level names against explicit tables. Typos
   were never silent — every DSL pragma is a `{.pragma.}` template — so only
   known names are checked.
2. **Generic `createView[T]` fallback.** A `{.child.}` field of a type that
   is neither `{.view.}` nor covered by a `createView` overload fell to
   `mount(T)`, i.e. `T()` + `initView` — the widget's own constructor never
   ran. Now `when T.hasCustomPragma(view): mount(T) else: {.error.}`.
   COOKBOOK §15 shows the one-line overload.
3. **`payloadKind` by type NAME.** `uiEvents` chose the `emits:` payload and
   the `set<Field>` writer by string-matching `"Input"`, `"Checkbox"`, …: a
   user type named `Input` was misclassified, and a third-party widget could
   never take part. Replaced by an overload hook resolved at the expansion
   site: `template uiValueKind*(t: typedesc[W]): UiPayloadKind` (stock
   overloads in `mount.nim`, generic fallback `upNone`). `uiEvents(T)` now
   expands to `uiEventsImpl(T, @[uiValueKind(F1), uiValueKind(F2), …])` with
   a `static seq` parameter, so the kinds are known at macro time exactly as
   before. The payload snapshot goes through `widgetValue(sender)` instead of
   `sender.text`/`.checked`/`.selected`, the same overload `bindValue` uses.
   `chain` is exported so custom `bindSlot`/`bindValueSlot` overloads append
   like the stock ones.
4. **`on:` handler fallback.** `when compiles(handler(self, ev)) … else
   handler(self)` turned a handler-signature typo into a confusing type
   mismatch at the generated call. Both arities stay accepted; anything else
   hits `{.error: "on: handler 'x' must be proc(self: T) or proc(self: T,
   ev: E)".}`.

Tests: `tests/test_mount.nim` "mount(T) fail-fast" (positive `createView`
overload; `not compiles` for the bad child, three misplacements, and the bad
handler) and `tests/test_bindings.nim` "third-party widget joins
bindValue/emits" (a `Dialish` widget with `uiValueKind = upSelected` gets a
typed `DialTurned.selected` payload, a store, and a `setDialVal` writer that
drives it through `SetSelected`). The full contract: `docs/EXTENDING.md`.

## 30. Model binding, console widgets, examples hygiene

**`bindValue` stores on a model.** `bindValue: "model.field"` targets
a field of a `ref` object the view holds (`storeTarget` in `dsl/mount.nim`
builds `self.model.field`); the generated writer is still `set<Field>` (last
path segment), and a new `notify<Field>(self)` pushes the store's current
value to the widget after the model was mutated behind the framework's back.
The view keeps only a pointer to the model — the audit's "domain state lives
inside the widget tree" finding. `examples/ex09_bindings.nim` now binds to a
`FormState` ref; DESIGN.md gained a dataflow section. Test:
`tests/test_bindings.nim` "bindValue on an external model".

**Widgets a status console needs.**
- `Scroller` gets the same stretchy default hint `Splitter` got in #22, so a
  scroller in a box no longer collapses to nothing (COOKBOOK §17 relied on
  the hand-set hint it did not show).
- `Table.setRows` keeps `selected` and `top` (clamped) instead of jumping to
  the top on every refresh.
- `TextView.lines` is a `std/deques.Deque[string]`: O(1) eviction at the
  cap instead of `delete(0)`; `len`/`[]` unchanged, `.high` callers
  (`netviz.nim`) use `len - 1`. New optional `lineStyle: proc(line):
  ThemeToken` for per-line coloring (log levels).
- New `widgets/sparkline.nim`: fixed-capacity ring of samples, block glyphs,
  auto or fixed scale, right-aligned, `SetProgress`-drivable like a
  ProgressBar. `examples/ex06_netviz.nim` shows events/second with it.
Tests: `tests/test_widgets.nim` "live-data widgets".

**Hygiene.** `examples/nim.cfg` adds `--path:"../src"` so every
example imports `illview` exactly as a downstream project does (no more
`../src/illview/...` teaching internal paths; the redundant `ivlayout`
aliases are gone). `newNetVizWidget` → `newNetViz` (the one `…Widget`
constructor). Nim floor reconciled to `>= 2.2.4` at all five sites; README
build section documents `testRefc`/`testAsan`, the lockfile, and links
`EMBEDDING.md`; `EXTENDING.md` documents the widget/DSL extension contract.

## 31. Embedding hygiene: NullBus default, chained crash handlers, refc/ASAN CI

Three changes so illview behaves inside a long-running host process
(`docs/EMBEDDING.md`):

- **`NullBus` is the default `app.bus`** (`core/bus.nim`). `StubBus`
  appended every `UiAction` and domain event to a seq forever — fine for
  tests, an unbounded history in a daemon. `NullBus` dispatches domain
  subscriptions synchronously and records nothing. `StubBus` stays for tests;
  `newBrokersBus()` is still the real routing.
- **Crash-restore handlers chain** (`core/app.nim` `installCrashRestore`).
  `posix.signal(s, restoreOnSignal)` replaced whatever the host had for
  SIGSEGV/ABRT/BUS/ILL/FPE. Now `sigaction` with `SA_SIGINFO` saves the
  previous action per signal; after restoring the terminal the handler
  re-installs that action and invokes it (`SA_SIGINFO` or plain handler), or
  returns to re-fault under the default when it was `SIG_DFL`/`SIG_IGN`.
  `CrashSignals` is a `let`, not a `const`: Nim's posix signal numbers are
  importc vars. `-d:noCrashRestore` still opts out.
- **refc and ASAN are gated**, not claimed. `nimble test` reads
  `ILLVIEW_MM` (default orc), plus `testRefc` and `testAsan` (orc +
  `-d:useMalloc`, `-fsanitize=address`); `ci/nimble-strict.sh` fails a step
  whenever a task raised even if nimble exited 0; `.github/workflows/ci.yml`
  runs {orc, refc} × {ubuntu, macos} × Nim {2.2.4, 2.2.12} and one ASAN job.
  The refc leg caught the aliasing bug recorded in #28 on its first run.

Tests: `tests/test_app.nim` (NullBus records nothing; a SIGSEGV raised after
`installCrashRestore` reaches the previously installed handler, which is then
the current action again).

## 32. New widgets instead of widening `Checkbox` / `StatusBar`

A third checkbox state and a widget-hosting status bar were added as **new
widgets**, `TriStateCheckBox` (`widgets/tristate.nim`) and `ControlBar`
(`widgets/controlbar.nim`). `Checkbox` and `StatusBar` are unchanged. A
widened `Checkbox` would have had to change `checked: bool`, `Toggled` and
`SetChecked` — every listener and every generated `set<Field>` writer — or
grow a second value field next to the first. Two names also make the choice
obvious at the call site.

- **`CheckState`** (`csUnchecked`, `csChecked`, `csIntermediate`) lives in
  `vocab.nim`, next to the new `StateChanged{state}` event and
  `SetCheckState{state}` signal. User input always cycles in enum order. The
  mark cell is configurable per state (`marks`, `markStyle`); the brackets
  stay fixed so the widget stays 4 + caption cells wide.
- **DSL**: `UiPayloadKind` gains `upCheckState` (appended — existing ordinals
  unchanged). The three exhaustive `case kind` sites in `dsl/uievents.nim`
  (`valueTypeIdent`, the `emits:` payload, the `set<Field>` writer) handle it;
  `CheckState` and `SetCheckState` resolve at the expansion site like the
  other vocab names.
- **`ControlBar` is a `Group` with its own `arrange`**, not a `BoxLayout`
  subclass: `BoxLayout.arrange` has no notion of a right-aligned group.
  `View.align` already means vertical placement inside the bar, so right-group
  membership is a set of view ids on the bar (`addRight` / `alignRight`).
  Left children that overflow collapse at the left group's boundary instead of
  overlapping the right group.
- **`mount(T)` never calls `newX()`** (`dsl/mount.nim` constructs `T()` +
  `initView`), so a `{.view.}` subtype of `ControlBar` starts zero-initialised:
  `lines = 0` is treated as 1, `spacing` is 0, the dock must come from
  `{.dock: dkBottom.}`, and a layout pragma would insert a nested box (the
  bar would then see one child). `{.child.}: ControlBar` goes through
  `createView` and gets `newControlBar()` defaults.

Tests: `tests/test_widgets.nim` (cycle order, marks and mark colours, bar
layout, narrow-bar overflow, clipping, docking, focus/mouse),
`tests/test_ctx_vocab.nim` (`StateChanged` / `SetCheckState`),
`tests/test_hotkey.nim`, `tests/test_bindings.nim` (bindValue / bindTo /
emits on a `TriStateCheckBox`), `tests/test_mount.nim` (zero-init
`ControlBar` subtype).

## 33. Clicks raise floating views only outside layout containers

A mouse press raises every `dkNone` view on the path from the hit target to
the scope (`core/routing.nim` `dispatchMouse`), so nested MDI windows come to
the front. `dkNone` is also the default dock of every child of a `BoxLayout`,
`Grid`, `FormLayout` or `ControlBar`, where `children` order is the layout
order, not z-order. Clicking such a child moved it, and each container above
it, to the end of its parent. The next frame then laid everything out in the
new order: a clicked list jumped below its siblings, a ControlBar's right
group swapped places. The bug has been there since the nested-window raise
was added; it shows wherever a non-last child of a box is clicked.

`Group` now has a base method `keepsChildOrder(g): bool` (default `false`).
The layout containers return `true`, and the raise loop skips any view whose
parent keeps child order. Desktops, windows, plain groups, popups, `Splitter`
and `Scroller` keep raising (the last two find their children through fields,
so raising only changes draw order). A third-party layout container overrides
`keepsChildOrder` (`docs/EXTENDING.md`). Rejected: raising only `Window`s
(core routing would import a widget module, and non-Window floating panes
would stop raising) and opt-in raising (every existing floating container
would have to declare it).

Tests: `tests/test_routing.nim` (box, grid and ControlBar children keep their
order on press; the enclosing floating window still raises).

## 34. Turbo Vision's visual language: surfaces, palettes, shadowed buttons

The default look takes Turbo Vision's *visual representation*, not its exact
palette: every control sits on a **surface** whose background differs from the
surface around it. Groups pop out of the window by colour (no frame needed),
input fields are always distinguishable, buttons read as pressable blocks.
`tests/test_theme.nim` enforces it for every palette of the default theme:
field, cluster, list and button backgrounds never equal the window background,
and a field never equals a cluster.

- **Themes**: `defaultTheme()` is now `tvTheme()` (lightgray desktop `░` and
  bars, blue windows, gray dialogs, cyan clusters and lists, green buttons).
  The previous table is `classicBlueTheme()`; it does not satisfy the surface
  rule and has no variants. Seven tokens were added (`tkHotkey`,
  `tkLabelFocused`, `tkCluster`, `tkList`, `tkButtonDefault`,
  `tkButtonShadow`, `tkWindowCloseBox`); no token was removed or renamed.
  Fields reuse `tkInput*`, cluster items `tkCheckbox*`, list selection
  `tkSelection*`.
- **Palettes**: `View.palette` + `Theme.variants` give TV's per-window colour
  sets (blue, cyan, gray) without a second theme object per window.
  `effectiveTheme` takes the nearest explicit theme and switches it to the
  variant named by the nearest palette at or below it. `newWindow` sets
  `pBlue`, stock dialogs `pGray`. In the blue palette a field is black on
  lightgray (a cyan field would match the clusters and lists).
- **fg-only tokens**: `tkHotkey` replaces the controls' use of
  `tkStatusBarHotkey`, whose white background showed through inside green
  buttons and blue windows; `hotkeyStyle(v, host)` keeps the host's bg.
  `tkButtonShadow` is drawn with the new `dc.overlay`, which keeps the cell's
  bg, so a shadow is correct on a window, a cluster block or a ControlBar
  without knowing which.
- **Widgets fill their surface**: Checkbox, Radio, TriStateCheckBox fill their
  arranged width; ListView, Table, TreeView, Editor, TextView fill their
  content. GroupBox fills its content with `tkCluster` and is **borderless by
  default**, its title a heading row above the block (`clientRect` and
  `measure` account for the row); `border = bkSingle` restores the frame.
- **Buttons**: caption centred, no `[ ]`/`▶ ◀`, focus shown by a bright
  caption, half-block shadow (`▄` right, `▀` below) — **+1 column and +1 row**
  per button (`shadowed`, `setShadowed(false)` for the flat 1-row button; no
  shadow is drawn when the button is arranged 1 row tall). Shadow cells don't
  activate. `isDefault`: bright cyan caption, and an Enter that reaches the
  enclosing `Window` unconsumed fires it (`Window.defaultButton`).
- **Enter follows TV** so the default button is reachable: Checkbox and
  TriStateCheckBox toggle on Space only; Input consumes Enter only when
  something may listen for submit — `onSubmit`, a `command`, or a
  materialised instance route (`hasBrokerCtx`; brokers 3.4.0 has no listener
  query, so "someone asked for the route" is the conservative stand-in).
  Lists and Editor keep Enter.

Tests: `tests/test_theme.nim` (invariants, palette resolution, hotkey style),
`tests/test_widgets.nim` (surface fills, label focus, borderless GroupBox,
button shadow / inert shadow / default-button Enter paths),
`tests/test_render_snapshot.nim` (close box, window vs dialog palette).

## 35. Lightgray windows, dark ControlBar, TV scrollbars

Deviation #34 kept TV's blue windows and gray dialogs. For more contrast every
window now uses the gray palette: the base table of `tvTheme()` is the gray
variant, `newWindow` no longer forces `pBlue` (palette `pDefault` = base), and
blue / cyan are opt-in variants (`win.palette = pBlue`). With a lightgray
window two widgets would have merged into it:

- **TextView** draws on the list surface (`tkList`, black on cyan) — a
  read-only data pane, like ListView/Table; `lineStyle` colours still apply.
- **ControlBar** is lightgray on black (`tkControlBar`, palette-independent),
  so it stands apart from windows, clusters, fields and buttons wherever it is
  docked. The button shadow keeps TV's black ink and is therefore invisible on
  the bar itself.

The desktop and the window share TV's lightgray; the blue `░` pattern, the
window frame and its shadow separate them (the invariant test checks the
pattern ink differs from window text instead of the background).

**Scrollbars** take TV's shape: an arrow at each end once the rail has three
cells (`▲`/`▼`, `◄`/`►` horizontal; a click steps by one), a `▒` rail (a click
pages) and a single-cell `■` thumb (drag maps the thumb cell linearly onto
`0..scrollMax`). The proportional thumb is gone; `thumbGeom` stays as pure
math. The glyph logic is one pure helper (`scrollGlyphs` / `thumbCell` /
`arrowCells` in `core/geometry.nim`) shared by ScrollBar and the ListView,
Table and TextView indicator column.

Tests: `tests/test_theme.nim` (ControlBar ≠ window in every palette, gray
base, blue variant), `tests/test_scrollbar.nim` (glyph rows incl. short rails,
arrow steps, single-cell drag, indicator columns),
`tests/test_render_snapshot.nim` (windows gray by default, `pBlue` opt-in).

## 36. Flat buttons with `> <` focus and a pressed shift (supersedes #34's shadow)

The half-block shadow from #34 is gone (author's call): a button is one row,
a flat green face with the caption centred, `> caption <` while focused. The
button is one cell wider than its face (`caption + 5`); the face rests one
cell in and shifts into that cell while `pressed`, so a press reads as the
button moving. `tkButtonShadow` and `dc.overlay` (which existed only for the
shadow) were removed.

Activation follows Turbo Vision: the **mouse fires on release** over the
button — a press only shifts the face and captures the mouse, dragging off
un-presses, releasing elsewhere cancels. **Keys** (Enter, Space, hotkey)
fire at once, as TV does, and flash the pressed face for 100 ms (a chronos
timer clears `pressed`). Delaying key activation was rejected: slots fire
synchronously inside dispatch — DSL `emits:`, the stock dialogs and the tests
rely on it.

Tests: `tests/test_widgets.nim` (face layout and `> <` focus, press shift,
fire on release, drag-off cancel, key flash); tests that clicked a button with
a bare press now send the release too (`test_widgets`, `test_routing`).

## 37. A real TV gray: `bgGray`, a 256-colour background

illwill emits ANSI 47 for `bgWhite`; the terminal palette decides what that
looks like, and many render it near-white — lightgray windows turned white and
their bright-white double frame disappeared. TV's lightgray is CGA #AAAAAA.

The vendored illwill carries one local patch (noted in its provenance
header): `BackgroundColor.bgGray = 100`, outside the SGR 40..47 range so it
can never be cast to a `std/terminal` colour by accident. `setAttribs` routes
backgrounds through `emitBg`, which writes `ESC[48;5;248m` (#a8a8a8, the
nearest xterm-256 entry) for `bgGray` and uses `std/terminal` for the rest.
Whether 256 colours are allowed is decided once, lazily, by the pure
`wants256Colors(TERM, COLORTERM, ILLVIEW_COLORS)`: `ILLVIEW_COLORS=16|256`
overrides; else `COLORTERM` set, or a `TERM` containing `256color`, `direct`,
`ghostty`, `kitty`, `alacritty` or `wezterm`. Otherwise — and on the Windows
console — `bgGray` falls back to ANSI 47, today's behaviour. No general
256/truecolor API was added.

Every lightgray in `tvTheme()` (desktop, menu/status bars, gray windows and
dialogs, the cyan palette's clusters/lists, the blue palette's fields) is now
`bgGray`; `classicBlueTheme()` keeps `bgWhite`. The screenshot renderer maps
`bgGray` to #a8a8a8 and `bgWhite` to a near-white, so a stray `bgWhite` would
show in the docs.

Tests: `tests/test_theme.nim` (capability parsing, both escapes, no TV token
uses `bgWhite`). Verified on a real pty: ex04 emits `ESC[48;5;248m` with
`ILLVIEW_COLORS=256` and `ESC[47m` with `16`, never both.

## 38. Cyan ControlBar; focusable ScrollBar

The dark ControlBar from #35 read badly in practice: a bar full of widgets
showed its black background only as slivers next to buttons and under the
scrollbar, which looked like stray shadows. `tkControlBar` now takes the
palette's **cluster** colour — black on cyan on gray and blue windows (and at
desktop level), lightgray in the cyan palette — so it still never equals the
window background (`tests/test_theme.nim`). Accepted trade-off: a cyan Radio
or TextView inside the bar blends with it.

`ScrollBar` was mouse-only (`focusable = false`, keys ignored). It is now
focusable and handles the arrow keys along its axis (±1), PgUp/PgDn (±page)
and Home/End; cross-axis keys and Alt-chords bubble on. The `■` thumb is
bright while focused. It joins the Tab order wherever it is used (ex04's
ControlBar, ex11's scroller bar).

Tests: `tests/test_scrollbar.nim` (vertical/horizontal keys, Alt pass-through,
Tab focus + routed keys), `tests/test_theme.nim` invariants.

## 39. TabView: windows as tabs

`TabView` (`widgets/tabview.nim`) is a `Group` whose children are its pages,
plus one private, focusable `TabStrip` child created lazily (so a `mount`
zero-initialised subtype works and its `{.child.}` fields become pages in
declaration order). The strip is one row on top; the selected page fills the
rest; every other page is `visible = false`. That reuses what routing already
does for hidden views — Tab traversal, hit-testing and hotkey lookup skip
them — while their state, broker wiring and focus memory (`Group.focused`)
survive. `keepsChildOrder = true`: child order is tab order (deviation #33).

- **Embedded windows** get the new `Window.framed = false`: no border (so
  `clientRect` is the whole page), no `[■]`/`[↑]`, no `◢`. The title is the
  tab label (re-read each draw); the window keeps its palette, so a `pBlue`
  window gives a blue page. `removePage` restores the frame and detaches
  without disposing.
- **Selection by identity**: a page removed behind the TabView's back (a
  Window's default `close()` detaches and disposes it) is reconciled on the
  next arrange; removing an earlier page keeps the selected page selected,
  removing the selected one hands over to its neighbour.
- **Focus**: switching moves focus into the new page — its remembered widget,
  else its first focusable — but only when focus was inside the TabView. A
  page with nothing focusable parks focus on the strip; that fallback does
  not stick (switching to a page with controls moves focus into it), while a
  strip the user focused (Tab, click, strip keys) keeps focus.
- **`canFocus` now requires every ancestor to be visible** (`routing.nim`).
  Before, a `FocusMe` signal could focus a widget on a hidden page. Existing
  focus paths only ever target visible subtrees, so their behaviour is
  unchanged (full suite green before TabView was added).
- **Keys**: Ctrl+PgUp/PgDn bubble to the TabView from anywhere inside; the
  strip takes Left/Right/Home/End. The paging widgets (ListView, Table,
  TextView, Editor, Scroller, ScrollBar) used to treat Ctrl+PgUp/PgDn as
  plain PgUp/PgDn and swallow it — found driving ex15 in a real pty with a
  focused list — so they now let it bubble (`events.isTabSwitch`); plain
  PgUp/PgDn still page. Alt+1..9 stays
  the Desktop's. Events: `onSelect` + `SelectionChanged` on the user path;
  `select(i)` and `SetSelected` are programmatic (deviation #15). DSL:
  `upSelected`, `bindSlot`/`bindValueSlot` → `onSelect`.

Out of scope: dragging a tab out into a floating window, reordering tabs by
drag, a strip anywhere but on top.

Tests: `tests/test_tabview.nim` (pages, hidden-page reachability, focus memory
and fallback, Ctrl+PgUp/PgDn wrap, strip keys and clicks, `×` close,
`removePage`, selection by identity, overflow, events, no reorder),
`tests/test_mount.nim` (`{.view.}` subtype).
