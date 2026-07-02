# nim-illview — Iteration 2 plan (Phases 7–10)

Follow-up to [BUILD-PLAN.md](BUILD-PLAN.md). Same rules: phase by phase, each
phase compiles + tests green + demoable, commit per phase. Deviations get
recorded in [DESIGN-DEVIATIONS.md](DESIGN-DEVIATIONS.md) with continued
numbering.

Scope requested:
1. Declarative styling — border, fg/bg colors, focus style, shadow.
2. Widgets: group-box (border + title container), table, progress bar.
3. Ergonomics: declarative widget-state binding (widget → field), declarative
   typed event emission on action, a less restrictive bus.
4. Bonus: key/mouse driven window move & resize.

---

## 0. Design decisions (CONFIRMED 2026-07-02)

Sanity-check answers: (1) widget→field OK, add a RequestBroker-mediated
update path for decoupling; (2) auto-generate event types; (3) no CBOR,
string payloads, start simple; (4) Alt+key variant; (5) Phase-2 snapshot
tests may be refactored.

### D1. Decoration is a View-level concern, drawn by the parent

Every `View` gains:

```nim
border*: BorderKind          # bkNone / bkSingle / bkDouble
borderTitle*: string         # drawn on the top border when border != bkNone
shadow*: bool                # 1-cell offset shadow (TV style), dimmed cells
```

`Group.draw` renders, per visible child: shadow (before the child, onto
whatever is beneath), then border + title, then the child clipped to its
border-inset content area. The BASE `View.clientRect` insets by the border,
so **routing and drawing stay geometrically consistent for free** (hit-test
already honors clientRect).

Coordinate-space convention change (the one real refactor): the DrawContext
a view receives in `draw()` and the mouse coords a view receives in
`handleEvent` are relative to its CONTENT area (clientRect), for leaves and
groups alike; `child.bounds` stays relative to the parent's content area.
Border cells of a view are addressable as -1 / contentW in its own local
space (used by Window title-drag / resize-corner hits). Widgets switch from
`bounds.w/h` to `contentW/contentH` in draw/scroll math. Phase-2/4 tests
adjust accordingly (approved).

Consequences:

- `Window` is refactored onto this mechanism (its hand-rolled frame/title
  becomes `border = bkSingle/bkDouble(active) + borderTitle`), keeping only
  raise/consume/active behavior. Snapshot tests must stay byte-identical or
  be consciously updated.
- **GroupBox falls out almost for free**: `Group` + border + title.

### D2. Per-view style overrides, merged over theme tokens

```nim
StyleOverride* = object      # on View, all optional
  fg*: ForegroundColor       # fgNone = inherit from theme token
  bg*: BackgroundColor       # bgNone = inherit
  bright*: Option-like flag
  focusFg*, focusBg*         # applied when isFocused
```

`styleOf(v, tok)` resolution order: theme token → per-view override →
focus override (when focused). Widgets keep calling `styleOf`; zero widget
changes. Subtree theming (`View.theme`) stays as-is. NOT in scope: full
CSS-like stylesheets/selectors.

### D3. Styling pragmas (Phase 7) — field-level and type-level

`border(bk)`, `boxTitle(s)` (name avoids clashing with `title`), `shadow`,
`fg(c)`, `bg(c)`, `focusFg(c)`, `focusBg(c)`. Applied by `mount`; matching
imperative setters exported for hand-built UIs.

### D4. Value binding is ONE-WAY, widget → enclosing view field

```nim
type MyForm {.view, vbox.} = ref object of Group
  name {.child, bindValue: "nameVal".}: Input
  nameVal*: string      # plain state field, kept current on every change
```

`mount` composes the value-store into the widget's change slot; a `bindTo:`
handler on the same field still fires (store happens first). Bindings:
Input→string, Editor→string, Checkbox→bool, Radio→int, ListView→int,
Table→int (selected row). Field→widget direction is explicitly out of scope
(no observable vars in v1).

**RequestBroker-mediated variant (confirmed amendment):** an additional
`bindRequest: "SetName"` pragma routes the update through nim-brokers'
sync RequestBroker instead of a direct store. `uiEvents(T)` generates
`RequestBroker(sync): proc SetName*(value: VT): Result[VT, string]`;
`mount` registers a default identity provider (`ok(value)`) and wires the
widget's change slot to `SetName.request(v)` — the field stores whatever
the provider RETURNS (isErr → field unchanged). Replacing the provider
(`SetName.replaceProvider`) gives external validation/normalization/veto
with the widget fully decoupled from the storage. `bindRequest` without
`bindValue` just issues the request (caller owns the provider).

Slot composition rule: all mount-generated consumers of one slot (value
store → `bindTo:` handler → `emits:` emit) are CHAINED, not assigned, in
that order.

### D5. Typed event emission: `emits:` pragma + `uiEvents(T)` macro

```nim
type MyForm {.view, vbox.} = ref object of Group
  run  {.child, caption: "Run", emits: "RunClicked".}: Button
  name {.child, emits: "NameSubmitted".}: Input

uiEvents(MyForm)   # top-level: generates the broker event types + emitters
```

`uiEvents(T)` scans the same pragmas `mount` sees and generates one
`EventBroker:` block per `emits:` name with a standard per-widget payload
(`senderId` + Button: nothing / Input,Editor: `text` / Checkbox: `checked` /
Radio,ListView,Table: `selected` + item text where meaningful). `mount`
wires activation → `emit(RunClicked(...))`. Subscribers use the generated
`RunClicked.listen(...)` — fully typed, no illview coupling. (Type
generation must be top-level in Nim, hence the separate macro; `mount`
alone cannot declare types.)

### D6. Bus opened up (the "restrictive bus" complaint)

The abstraction gains subscription and topic routing:

```nim
method subscribeDomain*(bus, topic: string,
                        handler: proc(topic, payload: string)): SubId {.base.}
method unsubscribe*(bus, id: SubId) {.base.}
```

- topic matching: exact + `"prefix/*"` wildcard.
- `StubBus` implements it synchronously (tests); `BrokersBus` implements it
  over `IvDomainEvent.listen` with topic filtering illview-side.
- The heavy-duty typed path is D5 (direct EventBroker types) — the string
  bus stays for loosely-coupled/domain traffic. UiAction/`command` tier
  unchanged.

### D7. Window move/resize

- **Mouse capture** added to routing: on `maPress` the pressed view may
  capture the mouse (`scope.mouseCapture`); `maMove`/`maRelease` then route
  to the captured view with translated coords until release. Needed for any
  dragging; done once in routing, reusable.
- Window: drag title row = move; drag the bottom-right corner cell (drawn
  `◢` when active) = resize. Minimum size clamped (8x3).
- Keyboard (on the active window, resolved in Window.handleEvent when the
  event bubbles to it): **Alt+Arrows = move, Alt+Shift+Arrows = resize**
  (Ctrl+arrows are commonly eaten by terminals/tmux; decoder already parses
  CSI modifier params).
- Only `dock == dkNone` windows are movable/resizable (docked windows are
  layout-owned); attempts on docked windows are ignored.

---

## Phase 7 — Styling & decoration

Tasks: BorderKind/StyleOverride on View; parent-drawn shadow/border/title;
base clientRect inset; Window refactor onto decoration; styleOf merge; the
D3 pragmas + setters; theme token additions (tkShadow, tkGroupBox…).

Exit criteria:
- Snapshot tests: border inset clipping (child cannot paint over its own
  border), shadow cells over desktop pattern, fg/bg/focus overrides reach
  the buffer, Window renders identically (or updated tests reviewed).
- Routing test: click inside a bordered widget lands with border-inset
  local coords.
- ex07_styling demo: same widget with different borders/colors/shadow.

Guardrails: no stylesheet engine; overrides only; widgets keep drawing via
styleOf, no per-widget style code.

## Phase 8 — GroupBox, Table, ProgressBar

- GroupBox: Group + border + title; works as `{.view, vbox.}` base type in
  mount (inner container lands in the inset clientRect).
- Table: `columns: seq[TableColumn]` (title + SizeHint), `rows:
  seq[seq[string]]`; header row; row selection; vertical scroll; column
  widths via the existing layout `distribute()`; slots onSelect/onActivate;
  key/wheel/click nav. NOT in v1: sorting, cell editing, horizontal scroll.
- ProgressBar: `value`, `maxValue`, optional percent text; determinate only
  (indeterminate animation would need a ticker — deliberately out).

Exit criteria: snapshot tests (table header/selection/scroll + column
distribution, progressbar fill at 0/50/100%, groupbox border+title+inset);
gallery example extended with all three.

## Phase 9 — Value binding, typed events, open bus

Tasks: D4 `bindValue:` in mount (+ composition with bindTo), D5 `uiEvents`
macro + `emits:` wiring, D6 subscribe/unsubscribe + wildcard topics on
EventBus/StubBus/BrokersBus.

Exit criteria:
- test_mount: typing into a mounted Input updates the bound field; bindTo
  and bindValue coexist on one field.
- test_events: uiEvents-generated type carries the right payload; widget
  activation emits it; listener receives typed data (real broker).
- test_bus: wildcard subscription on StubBus + BrokersBus.
- ex09 demo: form whose state fields render live + typed events feeding a
  NetViz-style log.

## Phase 10 — Window move/resize (bonus)

Tasks: mouse capture in routing; Window drag-move/drag-resize; Alt+Arrows /
Alt+Shift+Arrows; `◢` resize handle on active windows; min-size clamp;
dkNone-only guard.

Exit criteria: routing tests for capture (move events keep flowing to the
captured view outside its bounds, release ends capture); window
move/resize unit tests via synthetic events; ex02_windows demo gains
dragging; all prior suites green.
