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
| `bindValue` | `"fieldName"` or `"model.fieldName"` | widget → field store on every value change (the store may live on a `ref` model object held by the view, deviation #30); `uiEvents(T)` also generates the inverse `set<Field>` writer and a `notify<Field>` re-sync (§4) | value type by `uiValueKind`: Input/Editor (`string`), Checkbox (`bool`), Radio/ListView/Table (`int`), custom widgets via their overload |
| `bindRequest` | `"ReqName"` | routes the value through a sync RequestBroker provider before storing (validation/normalization; provider replaceable) | same as bindValue |
| `emits` | `"EventName"` | activation emits the uiEvents-generated SEMANTIC event `EventName{senderId, payload}` on the sender's session ctx (deviation #27) | payload by `uiValueKind(FieldType)` (deviation #29): Button none, Input/Editor `text`, Checkbox `checked`, Radio/ListView/Table `selected`; custom widgets declare their own (`docs/EXTENDING.md`) |
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
| `TriStateCheckBox` | `newTriStateCheckBox(caption, state = csUnchecked, command)` | `state: CheckState` | `onChange` | `StateChanged{state}` | `SetCheckState`, `FocusMe` | on cycle |
| `Radio` | `newRadio(items, selected = 0, command)` | `selected: int` | `onSelect` | `SelectionChanged{selected}` | `SetSelected`, `FocusMe` | on select |
| `Input` | `newInput(text = "", command)` | `text: string` | `onChange`, `onSubmit`, `onFocus`, `onBlur` | `TextChanged{text}` (edits), `Submitted{text}` (Enter) | `SetText`, `FocusMe` | on Enter |
| `Editor` | `newEditor(text = "")` | `text: string` | `onChange` | `TextChanged{text}` | `SetText`, `FocusMe` | — |
| `ListView` | `newListView(items = @[], command)` | `selected: int` | `onSelect`, `onActivate` | `SelectionChanged`, `Activated` | `SetSelected`, `FocusMe` | on activate |
| `Table` | `newTable(columns, rows, command)` | `selected: int` | `onSelect`, `onActivate` | `SelectionChanged`, `Activated` | `SetSelected`, `FocusMe` | on activate |
| `Label` | `newLabel(text)` | — | — | — | `SetText` | — |
| `ProgressBar` | `newProgressBar(maxValue = 100, showPercent = true)` | — | — | — | `SetProgress` | — |
| `TextView` | `newTextView(maxLines = 1000)` | — | — | — | — | — |
| `NetVizWidget` | `newNetViz(maxLines = 500)` | — | — | — | — | — |
| `Sparkline` | `newSparkline(capacity = 40, maxValue = 0)` | — | — | — | `SetProgress` (pushes a sample) | — |
| `StatusBar` | `newStatusBar(items)` | — | — | — | — | per-item on click |
| `ControlBar` | `newControlBar(lines = 1, spacing = 1)` | — | — | — | — | — (children publish their own) |
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
- **TriStateCheckBox**: user path cycles `csUnchecked → csChecked → csIntermediate → csUnchecked`; `setState(s)` (programmatic); `setMarks(unchecked, checked, intermediate: Rune)` — the one cell between the brackets, default `' '`/`'x'`/`'?'`; `setMarkStyle(state, StyleOverride)` — fg/bg/bright and focusFg/focusBg on the mark cell only (zero = inherit); `~tilde~` accelerator cycles
- **StatusBar**: `statusItem(label, command)`, `setText(s)`
- **ControlBar**: a `Group`, docked `dkBottom`, height `clamp(lines, 1, 3)` (`setLines(n)`). Children in one row: left group (`add`) gets the remaining width via `distribute`; right group (`addRight(v)`, or `alignRight(v)` for an existing child) is packed at preferred widths against the right edge and wins when space is short. Children are clipped to the bar height; `View.align` places them vertically. Background `tkControlBar`. As a `{.view.}` base type: zero-init (`lines = 0` = 1), set `{.dock: dkBottom.}`, no layout pragma, call `alignRight` after `mount` (deviation #32)
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
| `StateChanged` | `state: CheckState` | TriStateCheckBox | cycle |
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
| `SetCheckState` | `state: CheckState` | TriStateCheckBox | set + invalidate |
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
| `emits: "Name"` | `EventBroker` type `Name = object senderId: int; <payload>` + `uiEmit(sender, Name)`; payload by `uiValueKind(FieldType)`, snapshot via `widgetValue(sender)`: Input/Editor `text`, Checkbox `checked`, TriStateCheckBox `state`, Radio/ListView/Table `selected`, Button none |
| `bindRequest: "Name"` | sync `RequestBroker` `proc Name(value: VT): Result[VT, string]` with a default identity provider; swap via `Name.replaceProvider(DefaultBrokerContext, p)`, remove via `Name.clearProvider()`; `err` from the provider VETOES the store |
| `bindValue: "field"` / `"model.field"` | `proc set<Field>*(self: T, v: VT)` — writes the store field (on `self` or on `self.model`) AND signals the bound widget (`SetText`/`SetChecked`/`SetCheckState`/`SetSelected`) on its ctx. Authoritative: bypasses any `bindRequest` provider; fires no slots; loop-free by construction. Plus `proc notify<Field>*(self: T)` — pushes the store's current value to the widget after the model was mutated directly (deviation #30) |

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
| 3b | semantic `uiEvents` events (§4) | typed intent, `app.sessionCtx` (= the thread's global ctx unless one is installed/passed, deviation #27) |

`app.bus` is a `NullBus` (domain topics dispatch synchronously, `UiAction`s go
nowhere, nothing is recorded) until you set `app.bus = newBrokersBus()`.
`StubBus` (records everything) is for tests.

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
`tkGroupBox`, `tkProgress`, `tkBorder`, `tkShadow`, `tkScrollBar`, `tkControlBar`.

---

## 9. App

`newApp(fpsCap = 30, theme = nil, sessionCtx = BrokerContext(0))` → `App`
(session ctx = the thread's `globalBrokerContext()` unless one is passed,
deviation #27) with `desktop`, `bus`, `running`,
`onInput` hook; `await app.run()`, `app.stop()`, `app.requestRedraw()`,
`app.execView(g)` (modal, returns the closing `Command`),
`app.endModal(cmd)`, `app.focus`, `app.tuiActive`. Frames are dirty-driven
and fps-capped; an idle app has zero pending timers. Everything runs on ONE
chronos thread — no marshaling; `--mm:refc` and `--mm:orc` are both CI-gated
(`nimble test` / `nimble testRefc`, see `docs/EMBEDDING.md §6`).

Command gating (P22/D19): `app.disableCommand(cmd)` / `app.enableCommand(cmd)`
/ `app.isCommandEnabled(cmd)`. A disabled command greys and blocks any
Button/Checkbox/StatusBar/menu item that carries it.

---

## 10. Iteration 4 additions (plan-4)

### 10.1 Layout (P17, D14)

- Field pragmas: `alignSelf(Align)` — `alStretch` (default) / `alStart` /
  `alCenter` / `alEnd`, cross-axis in a box, in-cell for grid/form;
  `anchors({aLeft,aTop,aRight,aBottom})` — edge-anchor a `dkNone` child (both
  edges of an axis stretch, one slides); `padding(int)` — content inset,
  composes with the border. (Named `alignSelf`, not `align` — Nim reserves
  `{.align.}`; deviation #19.)
- Type pragma `form` → `FormLayout`: two columns, (label, control) pairs;
  col 0 auto-sizes to the widest label, col 1 stretches. `newFormLayout(spacing)`.
- Imperative: `View.align`, `View.anchor.edges`, `View.padding`.

### 10.2 New widgets

| Widget | Constructor | Notes |
|--------|-------------|-------|
| `ScrollBar` | `newScrollBar(axis = axV)` | passive track/thumb; `setRange(total, page, pos)`, `setPos`, `onScroll`; wheel / click-page / drag |
| `Scroller` | `newScroller(content)` | viewport over an over-sized child; wheel + PageUp/Dn; `scrollTo`/`scrollBy`/`ensureVisible`; focus auto-scroll; `onScroll` for bar sync |
| `Splitter` | `newSplitter(axis, first, second, pos = 0)` | two panes + draggable focusable divider (`divider()`); Alt+arrows nudge; mins from child hints |
| `TreeView` | `newTreeView(roots = @[])` | `TreeNode{label, children, expanded, loader}`; ▸/▾, Left/Right, Enter; `onSelect`/`onActivate`; `visibleRows`, `selectedNode` |

`ListView`/`Table`/`TextView` gain `showScrollbar` (indicator column). Double-
clicks arrive as `Event.clicks == 2` (synthesized by the App; 300 ms window).

### 10.3 Window chrome & desktop (P21)

- `Window`: `close()` (fires `onClose` or detach+dispose), `zoom()` (toggle
  maximize), `closable`/`zoomable` flags, title-row `[■]`/`[↑]` boxes.
- `Desktop`: `selectWindow(i)`, `tile()`, `cascade()`, `floatingWindows`;
  Alt+1..9 selects the Nth window.

### 10.4 Hotkeys & validators

- `~tilde~` accelerators in Button/Checkbox/Label/menu captions; Alt+letter
  routes via `dispatchHotkey`. `Label.linkTo` focuses a control. Menu titles
  open with Alt+letter; item letters activate inside an open popup.
- `Input.filter: KeyFilter` (`proc(r, text): bool`) with shipped
  `digitsOnly()`, `charSet(s)`, `maxLen(n)`, `allOf(...)`; `intRange(lo, hi)`
  is a value-level `bindRequest` provider. `Input.history` + Down-arrow picker.

### 10.5 Stock dialogs (P25, D20)

`messageBox(app, title, text, buttons, cancel = cmCancel): Future[Command]`,
`confirm(app, text): Future[bool]`, `inputBox(app, title, prompt, initial,
filter): Future[Option[string]]`. Standard commands `cmOk`/`cmCancel`/`cmYes`/
`cmNo` (negative, collision-free). Esc cancels, Enter fires the default button,
`~tilde~` accelerators pick any button.

Windows input driver is **deferred** (documented in
[WINDOWS-DRIVER.md](WINDOWS-DRIVER.md), deviation #18): POSIX only for now.
