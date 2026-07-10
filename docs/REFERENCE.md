# illview reference

The complete option surface: every pragma, every widget with its slots /
vocab events / signals, the framework vocabulary, the generated artifacts,
lifecycle rules and the bus tiers. Practical recipes live in
[COOKBOOK.md](COOKBOOK.md); design rationale in [DESIGN.md](DESIGN.md) and
the BUILD-PLAN files.

Module map:

| Import | Gives you |
|--------|-----------|
| `illview` | umbrella: core, layout, all widgets, `mount`/pragmas, vocab |
| `illview/dsl/uievents` | `uiEvents(T)` — semantic events, request providers, `set<Field>` writers |
| `illview/bus_brokers` | `BrokersBus` (real nim-brokers domain/UiAction bus), `onUiAction`, `onDomainEvent` |
| `illview/vocab` | (already in umbrella) framework events/signals + `installSignal`/`installFocusMe` |

---

## 1. Pragmas

### 1.1 Type-level (on the `{.view.}` object)

| Pragma | Arg | Effect |
|--------|-----|--------|
| `view` | — | marks the type mountable; user `{.view.}` field types mount recursively |
| `title` | `string` | window title (via `setCaption`) |
| `vbox` | — | children go into an inner vertical box (`dock = dkFill`) |
| `hbox` | — | children go into an inner horizontal box |
| `grid` | `int` (cols) | children go into an inner grid |
| `spacing` | `int` | spacing for the vbox/hbox/grid container |
| `dock` | `Dock` | dock of the mounted view itself |
| styling set | see 1.3 | applied to the mounted view itself |

### 1.2 Field-level (on `{.child.}` widget fields)

| Pragma | Arg | Effect | Valid on |
|--------|-----|--------|----------|
| `child` | — | mount constructs the widget and adds it to the container | any widget / `{.view.}` type |
| `caption` | `string` | initial text | Button, Checkbox, Label, Input, Window, GroupBox |
| `dock` | `Dock` | dock anchor | any |
| `stretch` | `int` | stretch weight, both axes | any |
| `action` | `Command` | widget publishes `UiAction(cmd, senderId)` on activation (tier-2 bus) | Button, Checkbox, Radio, Input, ListView, Table, StatusBar/Menu items |
| `bindTo` | `"handlerName"` | wires the PRIMARY slot to `proc h(self: T, sender: W)` | Button(onClick), Checkbox(onToggle), Radio(onSelect), ListView(onActivate), Input(onSubmit), Editor(onChange), Table(onActivate) |
| `bindValue` | `"fieldName"` | widget → field store on every value change; `uiEvents(T)` also generates the inverse `set<Field>` writer (§4) | Input/Editor (`string`), Checkbox (`bool`), Radio/ListView/Table (`int`) |
| `bindRequest` | `"ReqName"` | routes the value through a sync RequestBroker provider before storing (validation/normalization; provider replaceable) | same as bindValue |
| `emits` | `"EventName"` | activation emits the uiEvents-generated SEMANTIC event `EventName{senderId, payload}` on the default ctx | Button (no payload), Input/Editor (`text`), Checkbox (`checked`), Radio/ListView/Table (`selected`) |
| `on` | `{EventType: "handler", ...}` | ctx-scoped listeners on THIS widget's brokerCtx (§3); handler arities `proc(self: T)` or `proc(self: T, ev: EventType)` | any widget, any EventBroker type (vocab or uiEvents-generated) |

`bindTo` + `bindValue` + `on:` + `action:` + `emits:` may all coexist on one
field. Firing order on activation: value store → bindTo slot → UiAction
publish → vocab event emit (broker listeners run eagerly to their first
suspension).

### 1.3 Styling pragmas (type-level AND field-level)

| Pragma | Arg | Effect |
|--------|-----|--------|
| `border` | `BorderKind` (`bkNone`/`bkSingle`/`bkDouble`) | parent-drawn border; content insets 1 cell/side |
| `boxTitle` | `string` | title on the top border |
| `shadow` | — | TV-style shadow |
| `fg` / `bg` | `ForegroundColor` / `BackgroundColor` | color override merged over the theme token |
| `focusFg` / `focusBg` | colors | override applied while focused |

Imperative equivalents exist on every View: `border`, `borderTitle`,
`shadow`, `styleOv: StyleOverride`.

---

## 2. Widgets

Common to every View: `id`, `brokerCtx`, `disposers`, `bounds`, `hint`,
`dock`, `visible`, `enabled`, `focusable`, `theme`, `border`, `borderTitle`,
`shadow`, `styleOv`; methods `draw`/`measure`/`arrange`/`handleEvent`
(`{.gcsafe, raises: [].}` contract); helpers `invalidate()`, `publish(cmd)`,
`requestFocus` via `FocusMe`, `dispose()` (§5).

| Widget | Constructor | Value (`bindValue`) | Slots | Emits (vocab, own ctx) | Handles signals (own ctx) | Publishes `command` |
|--------|-------------|--------------------|-------|------------------------|---------------------------|---------------------|
| `Button` | `newButton(caption, command = cmdNone)` | — | `onClick` | `Clicked` | `FocusMe` | on activation |
| `Checkbox` | `newCheckbox(caption, checked = false, command)` | `checked: bool` | `onToggle` | `Toggled{checked}` | `SetChecked`, `FocusMe` | on toggle |
| `Radio` | `newRadio(items, selected = 0, command)` | `selected: int` | `onSelect` | `SelectionChanged{selected}` | `SetSelected`, `FocusMe` | on select |
| `Input` | `newInput(text = "", command)` | `text: string` | `onChange`, `onSubmit`, `onFocus`, `onBlur` | `TextChanged{text}` (edits), `Submitted{text}` (Enter) | `SetText`, `FocusMe` | on Enter |
| `Editor` | `newEditor(text = "")` | `text: string` | `onChange` | `TextChanged{text}` | `SetText`, `FocusMe` | — |
| `ListView` | `newListView(items = @[], command)` | `selected: int` | `onSelect`, `onActivate` | `SelectionChanged`, `Activated` | `SetSelected`, `FocusMe` | on activate |
| `Table` | `newTable(columns, rows, command)` | `selected: int` | `onSelect`, `onActivate` | `SelectionChanged`, `Activated` | `SetSelected`, `FocusMe` | on activate |
| `Label` | `newLabel(text)` | — | — | — | `SetText` | — |
| `ProgressBar` | `newProgressBar(maxValue = 100, showPercent = true)` | — | — | — | `SetProgress` | — |
| `TextView` | `newTextView(maxLines = 1000)` | — | — | — | — | — |
| `NetVizWidget` | `newNetVizWidget(maxLines = 500)` | — | — | — | — | — |
| `StatusBar` | `newStatusBar(items)` | — | — | — | — | per-item on click |
| `MenuBar` | `newMenuBar(menus)` | — | — | — | — | per-item on activate |
| `Window` | `newWindow(title, bounds)` | — | — | — | — | — |
| `GroupBox` | `newGroupBox(title)` | — | — | — | — | — |
| `Desktop` | `newDesktop(theme)` | — | — | — | — | — |

Widget-specific extras:

- **Input**: `text`, `setText(s)`, `insertText(s)`, `cursor`, `scrollX`
- **Editor**: `text`, `setText(s)`, `lines`, `curLine`/`curCol`, `moveCursor`
- **ListView**: `setItems(items)`, `select(i)`, `activate()`, `ensureVisible()`, `top`
- **Table**: `tableColumn(title, hint)`, `setRows`, `addRow`, `select(i)`, `activate()`; column widths distribute via layout hints
- **ProgressBar**: `setValue(v)` (clamped), `value`, `maxValue`
- **TextView**: `addLine(s)`, `clear()`, `scrollBy(delta)`; follows the bottom unless scrolled up (End re-pins)
- **NetVizWidget**: `addEvent(topic, payload)` — per-topic counters + log line
- **StatusBar**: `statusItem(label, command)`, `setText(s)`
- **MenuBar**: `menu(title, items)`, `menuItem(label, command)`, `openMenu(i)`; popups run as modals
- **Window**: `title=`, `isActive`; drag title to move, `◢` corner / Alt+Arrows to move, Alt+Shift+Arrows to resize (dkNone windows only)

Programmatic setters (`setText`, `setValue`, signal application, `set<Field>`
writers) never fire change slots and never emit vocab events — only
user-driven edit paths do (deviation #15).

---

## 3. Framework vocabulary (`illview/vocab`)

Identity lives in the ROUTE: every widget instance owns a `BrokerContext`
(`w.brokerCtx`); payloads carry no `senderId`. Listen on a widget's ctx to
hear exactly that widget; signal a widget's ctx to direct exactly that
widget. A ctx is a plain `uint32` capability handle — passable to model
code, inert after `dispose` (signals return `err`, emits reach nobody).

### 3.1 Events (EventBroker — MANY listeners per (type, ctx))

| Event | Payload | Emitted by | On |
|-------|---------|-----------|----|
| `Clicked` | — (void) | Button | activation |
| `TextChanged` | `text: string` | Input, Editor | user edits (batched per edit op) |
| `Submitted` | `text: string` | Input | Enter |
| `Toggled` | `checked: bool` | Checkbox | toggle |
| `SelectionChanged` | `selected: int` | Radio, ListView, Table | selection moved |
| `Activated` | `selected: int` | ListView, Table | Enter / item re-click |

API per type (generated): `listen(ctx, handler)`, `emit(ctx, ev)` (`emit(ctx)`
for `Clicked`), `dropListener(ctx, handle)`, `dropAllListeners(ctx)`,
`hasListeners(ctx)`. Handler shape:
`proc(ev: T): Future[void] {.async: (raises: []), gcsafe.}`
(no-arg for `Clicked`). Suspension-free handlers run EAGERLY inside `emit`.

### 3.2 Signals (SignalBroker — SINGLE handler per (type, ctx) = the widget)

| Signal | Payload | Handled by | Applies |
|--------|---------|-----------|---------|
| `SetText` | `text: string` | Input, Editor, Label | `setText` + invalidate |
| `SetChecked` | `checked: bool` | Checkbox | set + invalidate |
| `SetSelected` | `selected: int` | Radio, ListView, Table | clamp + scroll-into-view + invalidate |
| `SetProgress` | `value: int` | ProgressBar | `setValue` |
| `FocusMe` | — (void) | any focusable widget | focuses through the root chain |

`SigType.signal(ctx, SigType(field: v))` returns `Result[void, string]`:
`ok()` = accepted (spawned), `err "no signal handler installed"` = widget
gone / never constructed — use it to stop async drivers. `ok()` is NOT
"handled".

Custom widgets: `w.installSignal(SigType): body` (payload injected as
`sig`) and `w.installFocusMe()` register the handler on `w.brokerCtx` and
record teardown in `w.disposers`.

### 3.3 Semantic vs mechanical listening

Models listen SEMANTIC by default — `emits: "RunRequested"` events on the
default ctx survive UI restructuring. Instance-ctx listening is the escape
hatch for genuinely widget-bound concerns (live mirroring, metrics,
autosave). Model-attached instance-ctx listeners are the model's to drop.

---

## 4. `uiEvents(T)` generated artifacts

Call `uiEvents(MyForm)` at top level, right after the type section
(requires `illview/dsl/uievents`; the `set<Field>` writers need
`illview/vocab` in scope — the umbrella gives you both signals and vocab).

| Source pragma | Generates |
|---------------|-----------|
| `emits: "Name"` | `EventBroker` type `Name = object senderId: int; <payload>` + `uiEmit(sender, Name)`; payload per widget: Input/Editor `text`, Checkbox `checked`, Radio/ListView/Table `selected`, Button none |
| `bindRequest: "Name"` | sync `RequestBroker` `proc Name(value: VT): Result[VT, string]` with a default identity provider; swap via `Name.replaceProvider(DefaultBrokerContext, p)`, remove via `Name.clearProvider()`; `err` from the provider VETOES the store |
| `bindValue: "field"` | `proc set<Field>*(self: T, v: VT)` — writes the store field AND signals the bound widget (`SetText`/`SetChecked`/`SetSelected`) on its ctx. Authoritative: bypasses any `bindRequest` provider; fires no slots; loop-free by construction |

---

## 5. Lifecycle: `dispose(v)`

Broker registrations hold STRONG refs to the view (closure captures, global
registry) — an undisposed view leaks under refc and ORC alike. Contract:

- `dispose(v)` recurses leaves-first, runs each view's `disposers`
  (mount-installed `on:` listeners, widget signal handlers), then
  `releaseInstanceCtx(brokerCtx)` and sets the ctx inert (`BrokerContext(0)`).
- Call it EXACTLY ONCE, when a subtree is permanently done. `remove()` /
  re-adding does NOT dispose — transient reparenting (menus, window
  re-adds) keeps wiring alive on purpose (deviation #16).
- Drop-then-release: anything YOU attached to a widget's ctx
  (model listeners) must be dropped by you before/independent of dispose —
  a stale listener survives into the recycled ctx id.
- Idempotent: double dispose is a strict no-op.

---

## 6. Bus tiers (older, still current)

| Tier | Channel | Use |
|------|---------|-----|
| 1 | closure slots (`bindTo`, `onClick`…) | synchronous, inside dispatch, fastest |
| 2 | `UiAction{cmd, senderId}` on `app.bus` (`action:` pragma; menus/statusbar) | command palette semantics; `BrokersBus` bridges to `IvUiAction` EventBroker (`onUiAction`) |
| 2b | string domain bus: `publishDomain(topic, payload)` / `subscribeDomain("net/*", h)` | observability feeds (NetViz); exact or `prefix/*` wildcard topics; `BrokersBus` rides `IvDomainEvent` |
| 3 | instance-ctx vocab events/signals (§3) | typed, per-widget routing |
| 3b | semantic `uiEvents` events (§4) | typed intent, default ctx |

`app.bus` is a `StubBus` (records + sync dispatch, for tests) until you set
`app.bus = newBrokersBus()`.

---

## 7. Layout & sizing

- `Dock`: `dkNone` (manual bounds), `dkTop/dkBottom/dkLeft/dkRight` (edge
  strips), `dkFill` (remainder).
- `SizeHint` helpers: `fixedHint(n)`, `prefHint(n, stretch = 0)`; stretch
  weights share leftover space in boxes/grids.
- Containers: `newVBox(spacing)`, `newHBox(spacing)`, `newGrid(cols, spacing)`;
  in mount via the `vbox`/`hbox`/`grid` type pragmas.
- Coordinates: `draw()`/mouse coords are CONTENT-local (border handled by
  the parent); a view's own border cells address as -1/`contentW`.

---

## 8. Styling & themes

Resolution order: theme token → per-view `styleOv` → focus override
(plan-2 D2). Subtree theming via `View.theme`.

Theme tokens: `tkDesktop`, `tkWindowFrame`, `tkWindowFrameActive`,
`tkWindowTitle`, `tkWindowBg`, `tkText`, `tkTextDisabled`, `tkButton`,
`tkButtonFocused`, `tkCheckbox`, `tkCheckboxFocused`, `tkInput`,
`tkInputFocused`, `tkSelection`, `tkSelectionFocused`, `tkMenu`,
`tkMenuSelected`, `tkStatusBar`, `tkStatusBarHotkey`, `tkTableHeader`,
`tkGroupBox`, `tkProgress`, `tkBorder`, `tkShadow`.

---

## 9. App

`newApp(fpsCap = 30, theme = nil)` → `App` with `desktop`, `bus`, `running`,
`onInput` hook; `await app.run()`, `app.stop()`, `app.requestRedraw()`,
`app.execView(g)` (modal, returns the closing `Command`),
`app.endModal(cmd)`, `app.focus`, `app.tuiActive`. Frames are dirty-driven
and fps-capped; an idle app has zero pending timers. Everything runs on ONE
chronos thread — no marshaling, identical under `--mm:refc` and `--mm:orc`.
