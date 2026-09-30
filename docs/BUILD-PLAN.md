# nim-illview — Execution Plan

A retained-mode, TurboVision-inspired TUI widget framework for Nim, built on a vendored
fork of `illwill`, driven by a single-thread `chronos` update loop, with framework-owned
input routing and `nim-brokers` as the domain event bus.

**Repo:** `nim-illview`  **Package:** `illview`  **Nim:** 2.x (`--mm:orc`)

This document is the authoritative brief. Work it **phase by phase, in order**. Each phase must
compile, pass its tests, and produce a runnable demo before the next begins. Commit at each phase
boundary. Do not re-open decisions marked **LOCKED**.

---

## 0. Prime directives (do not violate)

1. **Single thread.** Everything runs on one `chronos` event loop. Do **not** spawn threads,
   use `spawn`, `threadpool`, or `Channel`. No cross-thread marshaling anywhere.
2. **Render is blocking, single-shot, single-owner.** Exactly one synchronous `frame()` walks the
   tree and calls `display()`. No async task ever draws. No partial/interleaved rendering.
3. **Render only when dirty**, fps-capped (~30). Idle app = zero render cost, no busy loop.
4. **Framework owns input distribution.** Widgets never subscribe to input. No per-widget input
   listeners. Mouse = z-order hit-test; keys = focus + bubble. (LOCKED)
5. **Broker carries transport + domain events, not intra-widget input plumbing.** Input reaches a
   single framework entry point; domain/network events fan out via the broker. (LOCKED)
6. **Dependencies stay minimal:** `chronos`, `nim-brokers`, and the vendored illwill file. Nothing else
   heavy. illwill is copied in as a single source file (WTFPL — no attribution obligation, but keep a
   provenance comment).
7. **Windows async input is out of scope for v1.** POSIX (`addReader`) is the real path; leave a
   documented poll-based fallback stub for Windows, do not implement it fully.
8. **No scope creep in the multiline editor** (see Phase 4): `seq[string]` model, no soft-wrap, no
   piece table, no undo stack in v1.
9. Keep each phase **demoable**. A phase that compiles but can't be run/seen is not done.

---

## 1. Locked design decisions (reference, do not redesign)

- **Paradigm:** retained view tree (TurboVision-style `View`/`Group`) over illwill's immediate-mode
  buffer. illwill is the "hardware layer" (buffer + `display()` diff + decoder).
- **Loop model:** game-style update loop. Async producers (input reader, network processing) mutate
  widget state via synchronous handlers and set a dirty flag; a capped ticker renders one frame when
  dirty.
- **Event routing (framework-owned):**
  - Mouse: top-down z-order hit-test; topmost containing view wins; click raises window + sets focus.
  - Key: delivered to focused view; unhandled bubbles parent → window → desktop; global hotkeys
    resolved at desktop. Tab / Shift-Tab traverse the focus chain (skip non-focusable).
- **Action handlers (VCL-style, two tiers):**
  - Tier 1: typed closure slots on widgets (`onClick`, `onChange`, `onSubmit`, `onFocus`, `onBlur`),
    fired synchronously inside dispatch, before render.
  - Tier 2: broker bridge — a widget with a `command` field auto-publishes `UiAction(cmd, sender)`
    on activation; closures may also publish explicitly.
  - Guardrail: closures for local/synchronous logic; broker publish only for domain/async/decoupled
    actions.
- **Declarative UI:** custom pragmas on view types/fields + a `mount(T)` macro that generates
  construction, layout wiring, and action binding. A nested `ui:` macro block is the escape hatch for
  dynamic/loop/conditional content. Pragma `bindTo:` (not `bind` — reserved word) wires a field's
  handler to a method on the enclosing view by name; `action:` wires the broker command.
- **Layout:** size hints (`min`/`pref`/`max` + `stretch`) + `HBox`/`VBox`/`Grid` + dock anchors;
  two-pass measure (bottom-up) / arrange (top-down). No constraint solver.
- **Theming:** named style tokens (a `Theme` table keyed by role, e.g. `tkWindowFrame`,
  `tkButtonFocused`), **not** TurboVision's numeric cascading palette.

---

## 2. Repository layout

```
nim-illview/
  illview.nimble
  src/
    illview.nim                 # umbrella module (re-exports public API)
    illview/
      backend/
        illwill_vendored.nim    # copied illwill, provenance comment at top
        decoder.nim             # extracted incremental input decoder (Phase 0)
        driver_posix.nim        # chronos addReader stdin driver (Phase 1)
        driver_fallback.nim     # poll-based stub (Windows/other) — not fully implemented
      core/
        geometry.nim            # Rect, Point, SizeHint, Dock
        events.nim              # InputEvent (backend) + Event (framework)
        drawcontext.nim         # offset + clip DrawContext (Phase 2)
        view.nim                # View, Group, methods (Phase 2)
        routing.nim             # mouse hit-test, key focus/bubble, Tab (Phase 2)
        app.nim                 # App context, loop, dirty flag, frame() (Phase 1/2)
        theme.nim               # style tokens
        bus.nim                 # EventBus abstraction (wraps nim-brokers; stub for tests)
      layout/
        layout.nim              # measure/arrange engine, HBox/VBox/Grid, dock (Phase 3)
      widgets/
        label.nim button.nim checkbox.nim radio.nim
        list.nim input.nim textview.nim editor.nim
        menu.nim statusbar.nim window.nim desktop.nim
      dsl/
        pragmas.nim             # pragma templates (Phase 5)
        mount.nim               # mount(T) macro + ui: block macro (Phase 5)
  tests/
    test_decoder.nim
    test_layout.nim
    test_routing.nim
    test_render_snapshot.nim    # renders into an off-screen buffer, asserts cells
    test_mount.nim
  examples/
    00_echo.nim 01_loop.nim 02_windows.nim 03_layout.nim
    04_widgets_gallery.nim 05_declarative.nim 06_netviz.nim
```

`illview.nimble`: name `illview`, requires `nim >= 2.2.4` (raised from 2.0 with brokers 3.x), `chronos`,
`nim-brokers`. No illwill dep (it's vendored).

---

## 3. Core type contracts

These signatures are **contracts** — honor the shapes; implementation freedom within. Adjust field
names only if a genuine Nim constraint forces it, and note why.

### 3.1 Input (backend) — `core/events.nim` + `backend/decoder.nim`

```nim
type
  InputKind* = enum ikKey, ikMouse, ikResize, ikPaste
  Modifier*  = enum modShift, modAlt, modCtrl
  MouseAction* = enum maPress, maRelease, maMove, maWheelUp, maWheelDown
  MouseButton* = enum mbNone, mbLeft, mbMiddle, mbRight

  InputEvent* = object
    case kind*: InputKind
    of ikKey:    key*: Key; rune*: Rune; keyMods*: set[Modifier]
    of ikMouse:  action*: MouseAction; button*: MouseButton
                 mx*, my*: int; mouseMods*: set[Modifier]
    of ikResize: discard
    of ikPaste:  text*: string

  Decoder* = object          # holds partial-escape-sequence state across feeds
    # internal buffer + parser state

proc feed*(d: var Decoder, bytes: openArray[byte]): seq[InputEvent]
  ## Incremental: may buffer an incomplete sequence and emit it on a later feed.
  ## Pure and terminal-free — fully unit-testable.
```

`Key` enum is reused/ported from illwill. The whole point of Phase 0 is that `feed()` is the
decoder logic lifted out of illwill's `getKey()`, made incremental and side-effect-free.

### 3.2 Geometry & hints — `core/geometry.nim`

```nim
type
  Point* = object x*, y*: int
  Rect*  = object x*, y*, w*, h*: int
  Dock*  = enum dkNone, dkTop, dkBottom, dkLeft, dkRight, dkFill
  Axis*  = enum axH, axV
  SizeHint* = object
    min*, pref*, max*: int    # max = high(int) means unbounded
    stretch*: int             # 0 = fixed at pref; >0 = share of leftover space

proc contains*(r: Rect, p: Point): bool
proc intersect*(a, b: Rect): Rect
```

### 3.3 DrawContext — `core/drawcontext.nim` (the fiddly core)

```nim
type DrawContext* = object
  tb*:   ptr TerminalBuffer   # vendored illwill buffer
  ox*, oy*: int               # absolute origin of the current view
  clip*: Rect                 # absolute clip rectangle

proc sub*(dc: DrawContext, r: Rect): DrawContext
  ## Push a child: new origin = dc.origin + r.xy; new clip = intersect(dc.clip, child abs rect).

proc write*(dc: DrawContext, x, y: int, s: string, style: Style)
  ## x,y are VIEW-LOCAL. Translate to absolute, clip per-cell against dc.clip,
  ## write only in-clip cells into tb. This is the ONLY sanctioned way widgets draw.

proc fill*(dc: DrawContext, r: Rect, ch: Rune, style: Style)
proc box*(dc: DrawContext, r: Rect, style: Style, double = false)
```

Widgets must draw exclusively through `DrawContext`; they never touch `TerminalBuffer` directly.
Clipping correctness here is the highest-risk item in the project — cover it with snapshot tests.

### 3.4 View / Group — `core/view.nim`

```nim
type
  View* = ref object of RootObj
    bounds*: Rect              # relative to parent
    parent*: Group
    hint*: tuple[w, h: SizeHint]
    dock*: Dock
    visible*, enabled*, focusable*: bool
    theme*: Theme

  Group* = ref object of View
    children*: seq[View]       # z-order: index 0 = bottom, last = topmost
    focused*: View

method draw*(v: View, dc: DrawContext) {.base.}
method measure*(v: View): tuple[w, h: SizeHint] {.base.}
method arrange*(v: View, r: Rect) {.base.}        # set bounds + arrange own children
method handleEvent*(v: View, ev: Event): bool {.base.}
  ## return true = consumed (stops bubbling)

proc add*(g: Group, child: View)
proc raiseToTop*(g: Group, child: View)
```

### 3.5 Framework Event (post-routing) — `core/events.nim`

```nim
type
  EventKind* = enum evKey, evMouse, evFocusGained, evFocusLost, evCommand, evResize
  Command* = distinct int

  Event* = object
    case kind*: EventKind
    of evKey:   ikey*: InputEvent
    of evMouse: imouse*: InputEvent        # coords already translated to target-local in routing
    of evCommand: cmd*: Command; sender*: View
    of evFocusGained, evFocusLost, evResize: discard
```

### 3.6 Routing — `core/routing.nim`

```nim
proc dispatchMouse*(root: Group, ev: InputEvent)
  ## Hit-test top-down by z-order; deliver to topmost containing view; recurse into groups.
  ## On press inside a window: raiseToTop + set focus. Translate coords to target-local.

proc dispatchKey*(app: App, ev: InputEvent)
  ## Deliver to app.focus; if handleEvent returns false, bubble parent-ward to desktop.
  ## Desktop resolves global hotkeys. Tab/Shift-Tab handled at desktop => focusNext/focusPrev.

proc focusNext*(g: Group)
proc focusPrev*(g: Group)
```

### 3.7 App / loop — `core/app.nim`

```nim
type App* = ref object
  desktop*: Group
  focus*: View
  bus*: EventBus
  dirty*: bool
  renderPending*: bool
  fpsCap*: int                 # default 30
  running*: bool

proc requestRedraw*(app: App)          # set dirty
proc frame*(app: App)                  # BLOCKING single-shot: layout-if-needed -> draw -> display()
proc run*(app: App) {.async.}          # start driver + ticker; returns when running=false
proc enableTui*(app: App)              # re-entrant: illwillInit + addReader + start ticker
proc disableTui*(app: App)             # unregister reader, restore termios/altscreen, stop ticker
```

`frame()` sequence: if layout dirty → `measure`/`arrange` from desktop; walk tree `draw()` into a
fresh/cleared `TerminalBuffer` via a root `DrawContext`; `tb.display()`; clear `dirty`.

### 3.8 EventBus — `core/bus.nim`

```nim
type
  UiAction* = object
    cmd*: Command
    senderId*: int
  EventBus* = ref object of RootObj      # abstraction; real impl wraps nim-brokers in Phase 6

method publish*(bus: EventBus, a: UiAction) {.base.}
method publishDomain*(bus: EventBus, topic: string, payload: string) {.base.}
# A StubBus (records published actions) backs unit tests so Phases 1–5 need no real broker.
```

Bind to the actual `nim-brokers` Requests/Events API only in Phase 6; adapt to its real signatures
then. Until then, code against this abstraction and the stub.

### 3.9 Widget action slots (VCL tier) — pattern

```nim
type Button* = ref object of View
  caption*: string
  command*: Command                       # optional; auto-publish on activate (default cmdNone)
  onClick*: proc(sender: Button) {.closure.}

# inside Button.handleEvent, on activation (Enter/Space while focused, or mouse click):
#   if onClick != nil: onClick(self)
#   if command != cmdNone: app.bus.publish(UiAction(cmd: command, senderId: self.id))
```

Every interactive widget exposes its typed slots. Slot firing happens **inside dispatch, before the
next frame**, so a handler mutating state + calling `requestRedraw` renders same-tick.

---

## 4. Phases

Each phase: **Goal → Tasks → Exit criteria → Guardrails.** Do not advance until exit criteria pass.

### Phase 0 — Fork & extract the decoder
**Goal:** vendor illwill; lift its escape-sequence parser into a pure, incremental `feed()`.

Tasks:
- Copy current `illwill.nim` into `backend/illwill_vendored.nim`; add provenance comment. Keep
  `TerminalBuffer`, `display()`, drawing, `Key`, color/style, mouse types **as-is**.
- Create `backend/decoder.nim`. Move the byte→event decoding logic (currently inside `getKey()` /
  mouse parsing) into `Decoder` + `feed(bytes): seq[InputEvent]`. Preserve partial-sequence buffering
  (an escape sequence split across two reads must decode correctly).
- Map illwill's key/mouse decoding onto the `InputEvent` shape in §3.1.

Exit criteria:
- `tests/test_decoder.nim` drives raw byte arrays (arrow keys, function keys, Alt-combos, SGR mouse
  press/release/move/wheel, a UTF-8 rune, an escape sequence split across two `feed()` calls) and
  asserts exact `InputEvent`s. No terminal required. All pass.

Guardrails: don't touch rendering; don't change `TerminalBuffer` semantics; don't add deps.

### Phase 1 — Loop, async input driver, opt-in lifecycle
**Goal:** bytes flow stdin → decoder → (echo) with a dirty-driven capped render; TUI toggles cleanly.

Tasks:
- `backend/driver_posix.nim`: set `O_NONBLOCK` on stdin; `chronos` `addReader(STDIN_FILENO, cb)`;
  in cb read available bytes (handle `EAGAIN`), `feed()`, hand events to a callback. Register a resize
  handler (SIGWINCH → emit `ikResize`).
- `backend/driver_fallback.nim`: documented poll stub for non-POSIX; not fully implemented.
- `core/app.nim`: `App`, dirty flag + `renderPending` coalescing, `fpsCap`, `frame()` (blocking
  single-shot), a `chronos` ticker that calls `frame()` only when `dirty` and no render pending, and
  re-entrant `enableTui`/`disableTui` (restore termios/alt-screen on disable; verify daemon runs
  headless with zero UI cost when off).
- `examples/00_echo.nim` / `01_loop.nim`: echo pressed keys/mouse coords; ESC quits.

Exit criteria:
- Keys & mouse echo via input → decoder → app callback → render.
- Idle CPU ≈ 0 (no render when nothing changes; no poll spin on POSIX).
- `enableTui`/`disableTui` toggle repeatedly without terminal corruption.

Guardrails: no threads; render stays synchronous; don't implement Windows async.

### Phase 2 — View tree, DrawContext clipping, framework routing
**Goal:** overlapping windows, correct clipping, framework-owned mouse + key routing, modal loop.

Tasks:
- `core/view.nim` (`View`/`Group` + base methods), `core/drawcontext.nim` (§3.3), `core/theme.nim`
  (token table + a default theme), `widgets/desktop.nim`, `widgets/window.nim` (frame + title +
  clipped content area + scroll offset).
- `core/routing.nim`: `dispatchMouse` (z-order hit-test, raise + focus on press, coord translation),
  `dispatchKey` (focused + bubble to desktop), `focusNext`/`focusPrev` (Tab traversal), modal loop
  (`execView`-style nested loop running until an `endModal(cmd)`).
- `examples/02_windows.nim`: two overlapping windows, click-to-raise, Tab cycles focus.

Exit criteria:
- `tests/test_render_snapshot.nim`: render a scene into an off-screen `TerminalBuffer`, assert cells —
  including that a child drawing outside its window's content rect is clipped (no bleed).
- `tests/test_routing.nim`: synthetic mouse coords hit the correct topmost view; Tab order correct;
  unhandled key bubbles to desktop.
- Demo behaves: overlapping windows, raise, focus cycle, all clipped.

Guardrails: widgets draw **only** via `DrawContext`; routing lives in the framework, never in widgets.

### Phase 3 — Layout engine
**Goal:** size-hint-driven auto-arrange that reflows on resize.

Tasks:
- `layout/layout.nim`: two-pass engine. `measure` bottom-up aggregates child `SizeHint`s per axis;
  `arrange` top-down distributes: satisfy `min`/`pref`, share leftover by `stretch`, clamp to `max`.
  Implement `HBox`, `VBox`, `Grid`, and `dock` anchoring. Hook resize (`ikResize`) → relayout +
  redraw.
- `examples/03_layout.nim`: nested boxes + a docked status bar; resizing the terminal reflows.

Exit criteria:
- `tests/test_layout.nim` (pure): given a tree of hints + a root rect, assert computed child rects for
  HBox/VBox/Grid, stretch distribution, min/max clamping, and dock placement.
- Demo reflows correctly on live resize.

Guardrails: no constraint solver; layout is pure given hints + rect (keep it unit-testable).

### Phase 4 — Widget set (+ VCL closure slots)
**Goal:** all requested widgets, each with typed action slots. Implement in cost order.

Order & slots:
1. `label` (none), `button` (`onClick` + `command`), `checkbox` (`onToggle`), `radio` (exclusive
   group, `onSelect`).
2. `list` (`onSelect`, `onActivate`) — viewport + selection + key/wheel nav.
3. `input` single-line (`onChange`, `onSubmit`, `onFocus`, `onBlur`) — cursor, edit, horizontal
   scroll on overflow. **Note:** `onSubmit` = Enter; `onFocus`/`onBlur` = focus in/out (do NOT
   collapse into one "enter" event à la VCL).
4. `textview` buffered read-only (ring buffer of lines + viewport + scroll) — the log/output widget.
5. `menu` (menu bar + dropdown as transient modal group; `command` per item), `statusbar`
   (header/footer docked).
6. `editor` multiline **last**: `seq[string]` model, cursor, 2-axis scroll, basic edit
   (`onChange`). No soft-wrap, no piece table, no undo in v1.

Also: `examples/04_widgets_gallery.nim` — a dialog hand-assembled from every widget, closures wired.

Exit criteria:
- Gallery demo: every widget usable; closures fire before render; `command`-bearing widgets publish to
  the stub bus (assert via a test).
- Snapshot tests for list scroll, input horizontal scroll, textview viewport, editor cursor movement.

Guardrails: editor scope stays minimal; every interactive widget wires its slots + optional `command`.

### Phase 5 — Declarative layer (pragmas + macros)
**Goal:** describe a screen with pragma-annotated types; `bindTo`/`action` wire handlers.

Tasks:
- `dsl/pragmas.nim`: `view`, `child`, `title(s)`, `dock(d)`, `stretch(n)`, `hbox`, `vbox`, `grid`,
  `action(c: Command)`, `bindTo(m)` (renamed from `bind` — reserved word). Use
  `{.pragma.}` templates.
- `dsl/mount.nim`: `mount(T)` macro walking fields via `getCustomPragmaVal`/`hasCustomPragma` at
  compile time → emit constructor, parent/child wiring, layout container selection, and action
  binding (`action:` → set `command`; `bindTo:` → assign the named method of the enclosing view to
  the field's closure slot). Add the nested `ui:` block macro escape hatch for dynamic/loop content.
- `examples/05_declarative.nim`: rebuild the Phase-4 gallery declaratively.

Exit criteria:
- `tests/test_mount.nim`: a declaratively-defined screen produces a tree structurally identical to a
  hand-built equivalent; `action:` sets the right `command`; `bindTo:` wires the right method.
- Declarative demo behaves identically to the hand-built one.

Guardrails: pragmas handle the static 90%; anything dynamic goes through the `ui:` block, not by
bending pragmas into control flow.

### Phase 6 — nim-brokers wiring + LogosDelivery integration
**Goal:** real broker behind `EventBus`; a live network-event visualizer inside the daemon; opt-in
toggle.

Tasks:
- Implement `EventBus` over the real `nim-brokers` Requests/Events API (adapt to its actual
  signatures). `UiAction` publishes as a Request/Event; domain events subscribe for widgets.
- A `NetVizWidget` (built on `textview`/custom draw) subscribing to LogosDelivery network/domain
  events → update + `requestRedraw`. This is the "visualize networking event" case; it must work with
  zero per-widget input plumbing (framework routes input; broker fans out domain events).
- Wire `enableTui`/`disableTui` into the LogosDelivery daemon as an opt-in flag; confirm headless
  operation when disabled.
- `examples/06_netviz.nim`: synthetic domain events drive the visualizer live.

Exit criteria:
- Domain events published on the loop render in the visualizer within one frame.
- Daemon runs headless (TUI off) with no measurable UI overhead; toggling on/off is clean.

Guardrails: single thread preserved end-to-end; domain events fan out via broker, input stays
framework-routed.

---

## 5. Testing strategy

- **Pure-logic tests, no terminal:** decoder (`feed`), layout (measure/arrange), routing (hit-test,
  focus order, bubbling), mount (tree shape + bindings). These are the bulk and must stay
  terminal-independent.
- **Snapshot tests:** render a scene into an off-screen `TerminalBuffer`; assert cell contents/styles.
  Use these specifically to lock **clipping** correctness (Phase 2) and widget viewport/scroll
  behavior (Phase 4).
- **Manual demos:** one runnable example per phase, listed above, as the human-visible acceptance gate.
- Run `nimble test` green before each phase commit.

---

## 6. Conventions & invariants

- Nim 2.x, `--mm:orc`. Public API in `illview.nim` re-exports; internal modules under `illview/`.
- `{.base.}` on all base methods; method dispatch is acceptable in the draw path for a TUI.
- Single mutable app context (`App`); avoid other global mutable state.
- No `echo` in library code; a debug log goes to a file, never to the managed terminal.
- Every widget: construct → set hints → wire slots. Interactive widgets consume events by returning
  `true` from `handleEvent`.
- Assert the single-thread invariant in debug builds (e.g. capture the loop thread id at `run`, assert
  equality in `frame()` and driver callbacks).
- Commit per phase with a message naming the phase and its exit criteria.

## 7. Definition of done (whole project)

All six phases pass their exit criteria; `nimble test` green; all `examples/*` run; the LogosDelivery
daemon exposes a working opt-in TUI whose network-event visualizer updates live, on one thread, with
blocking single-shot rendering and zero cost when disabled.
