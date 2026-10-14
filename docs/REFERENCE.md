# illview reference

The complete option surface: every pragma, every widget with its slots /
vocab events / signals, the framework vocabulary, the generated artifacts,
lifecycle rules and the bus tiers. Practical recipes live in
[COOKBOOK.md](COOKBOOK.md); architecture and rationale in
[DESIGN.md](DESIGN.md); the numbered `deviation #N` notes cited below are in
[design-notes/DESIGN-DEVIATIONS.md](design-notes/DESIGN-DEVIATIONS.md).

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
| `form` | — | children go into an inner `FormLayout` — two columns of (label, control) pairs (§7.1) |
| `spacing` | `int` | spacing for the vbox/hbox/grid/form container |
| `dock` | `Dock` | dock of the mounted view itself |
| styling set | see 1.3 | applied to the mounted view itself |

### 1.2 Field-level (on `{.child.}` widget fields)

| Pragma | Arg | Effect | Valid on |
|--------|-----|--------|----------|
| `child` | — | mount constructs the widget and adds it to the container | any widget / `{.view.}` type |
| `caption` | `string` | initial text | Button, Checkbox, Label, Input, Window, GroupBox |
| `dock` | `Dock` | dock anchor | any |
| `stretch` | `int` | stretch weight, both axes | any |
| `alignSelf` | `Align` | `alStretch` (default) / `alStart` / `alCenter` / `alEnd` — cross-axis in a box, in-cell for grid/form. Named `alignSelf`, not `align`: Nim reserves `{.align.}` ([deviation #19](design-notes/DESIGN-DEVIATIONS.md)) | any |
| `anchors` | `{aLeft, aTop, aRight, aBottom}` | edge-anchor a `dkNone` child: both edges of an axis stretch, one slides | `dkNone` children |
| `padding` | `int` | content inset; composes with the border | any |
| `action` | `Command` | widget publishes `UiAction(cmd, senderId)` on activation (tier-2 bus) | Button, Checkbox, Radio, Input, ListView, Table, StatusBar/Menu items |
| `bindTo` | `"handlerName"` | wires the PRIMARY slot to `proc h(self: T, sender: W)` | Button(onClick), Checkbox(onToggle), Radio(onSelect), ListView(onActivate), Input(onSubmit), Editor(onChange), Table(onActivate) |
| `bindValue` | `"fieldName"` or `"model.fieldName"` | widget → field store on every value change (the store may live on a `ref` model object held by the view, deviation #30); `uiEvents(T)` also generates the inverse `set<Field>` writer and a `notify<Field>` re-sync (§4) | value type by `uiValueKind`: Input/Editor (`string`), Checkbox (`bool`), Radio/ListView/Table (`int`), custom widgets via their overload |
| `bindRequest` | `"ReqName"` | routes the value through a sync RequestBroker provider before storing (validation/normalization; provider replaceable) | same as bindValue |
| `emits` | `"EventName"` | activation emits the uiEvents-generated SEMANTIC event `EventName{senderId, payload}` on the sender's session ctx (deviation #27) | payload by `uiValueKind(FieldType)` (deviation #29): Button none, Input/Editor `text`, Checkbox `checked`, Radio/ListView/Table `selected`; custom widgets declare their own ([DESIGN.md §9](DESIGN.md#9-extending-illview)) |
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

Common to every View: `id`, `brokerCtx`, `sessionCtx`, `disposers`, `bounds`,
`hint`, `dock`, `visible`, `enabled`, `focusable`, `theme`, `palette`,
`border`, `borderTitle`, `shadow`, `styleOv`, `align`, `anchor.edges`,
`padding`; methods `draw`/`measure`/`arrange`/`handleEvent`
(`{.gcsafe, raises: [].}` contract); helpers `invalidate()`, `publish(cmd)`,
`dispose()` (§6). Focus by signal: `FocusMe.signal(w.brokerCtx)` — handled by
every focusable widget that called `installFocusMe()` (§3.2). Modal and
mouse helpers (`core/view`): `v.runModal(g)` opens `g` as a transient modal
(menus, dialogs), `v.endModal(cmd)` closes the topmost one,
`v.captureMouse()` / `v.releaseMouse()` route every mouse event to `v` until
release (drag support); all are no-ops on a detached view.

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
| `TreeView` | `newTreeView(roots = @[])` | — | `onSelect`, `onActivate` | — | — | — |
| `Label` | `newLabel(text)` | — | — | — | `SetText` | — |
| `ProgressBar` | `newProgressBar(maxValue = 100, showPercent = true)` | — | — | — | `SetProgress` | — |
| `TextView` | `newTextView(maxLines = 1000)` | — | — | — | — | — |
| `NetVizWidget` | `newNetViz(maxLines = 500)` | — | — | — | — | — |
| `Sparkline` | `newSparkline(capacity = 40, maxValue = 0)` | — | — | — | `SetProgress` (pushes a sample) | — |
| `ScrollBar` | `newScrollBar(axis = axV)` | — | `onScroll` | — | — | — |
| `Scroller` | `newScroller(content)` | — | `onScroll` | — | — | — |
| `Splitter` | `newSplitter(axis, first, second, pos = 0)` | — | — | — | — | — |
| `StatusBar` | `newStatusBar(items)` | — | — | — | — | per-item on click |
| `ControlBar` | `newControlBar(lines = 1, spacing = 1)` | — | — | — | — | — (children publish their own) |
| `TabView` | `newTabView()` | `selected: int` | `onSelect` | `SelectionChanged` | `SetSelected` | — |
| `MenuBar` | `newMenuBar(menus)` / `menuBar(menus...)` | — | — | — | — | per-item on activate |
| `ContextMenu` | `newContextMenu(items)` | — | — | — | — | per-item on activate |
| `Window` | `newWindow(title, bounds)` | — | `onClose` | — | — | — |
| `GroupBox` | `newGroupBox(title)` | — | — | — | — | — |
| `Desktop` | `newDesktop(theme)` | — | — | — | — | — |

Widget-specific extras:

- **Input**: `text`, `setText(s)`, `insertText(s)`, `cursor`, `scrollX`, `readOnly`, selection (§2.2); `filter` and `history` (§2.4); Enter is consumed only when something may listen for submit (`onSubmit`, a `command`, or an instance route anyone asked for), else it reaches the window's default button ([deviation #34](design-notes/DESIGN-DEVIATIONS.md))
- **Button**: flat green face, caption centred, `> caption <` while focused; width = caption + 5 (the face sits one cell in and shifts into that cell while `pressed`); mouse fires on release over the button (drag off cancels), Enter/Space/hotkey fire at once and flash the pressed face; `isDefault` = bright caption + fired by an unconsumed Enter in its Window (deviations #34, #36)
- **Checkbox / TriStateCheckBox**: toggle on Space (and mouse / hotkey); Enter goes to the default button (deviation #34)
- **TriStateCheckBox**: user path cycles `csUnchecked → csChecked → csIntermediate → csUnchecked`; `setState(s)` (programmatic); `setMarks(unchecked, checked, intermediate: Rune)` — the one cell between the brackets, default `' '`/`'x'`/`'?'`; `setMarkStyle(state, StyleOverride)` — fg/bg/bright and focusFg/focusBg on the mark cell only (zero = inherit); `~tilde~` accelerator cycles
- **GroupBox**: borderless by default — title as a heading row above a `tkCluster` block; `border = bkSingle` puts the title back in a frame (deviation #34)
- **Label**: drawn with `tkLabelFocused` while its `linkTo` control has focus
- **Editor**: `text`, `setText(s)`, `lines`, `curLine`/`curCol`, `moveCursor`, `readOnly`, selection (§2.2)
- **ListView**: `setItems(items)`, `select(i)`, `activate()`, `ensureVisible()`, `top`, `showScrollbar` (indicator column); horizontal scroll (§2.1)
- **Table**: `tableColumn(title, hint)`, `setRows`, `addRow`, `select(i)`, `activate()`, `showScrollbar`; column widths distribute via layout hints; cut cells scroll inside their column, marked `◀`/`▶` (§2.1)
- **TreeView**: `TreeNode{label, children, expanded, loader, key}` (`treeNode(label, children, key = "")`; `loader` fills children lazily on first expand); ▸/▾, Left/Right expand/collapse, Enter, PgUp/PgDn, wheel; `setRoots` (live refresh keeping expansion / selection / scroll by `key`-or-`label` path); `visibleRows`, `selectedNode`; horizontal scroll (§2.1) with `scrollByX`/`scrollMaxX` too
- **ProgressBar**: `setValue(v)` (clamped), `value`, `maxValue`
- **TextView**: `addLine(s)`, `clear()`, `scrollBy(delta)`, `showScrollbar`; follows the bottom unless scrolled up (End re-pins) or while text is selected; selection (§2.2)
- **NetVizWidget**: `addEvent(topic, payload)` — per-topic counters + log line
- **ScrollBar**: focusable — arrows along its axis step, PgUp/PgDn page, Home/End jump, bright `■` while focused (deviation #38); TV look (deviation #35): `▲`/`▼` (`◄`/`►`) arrows step by one, `▒` rail pages, one `■` thumb drags; `setRange(total, page, pos)`, `setPos`, `onScroll`; wheel. Pure helpers `scrollGlyphs` / `thumbCell` / `arrowCells` in `core/geometry`, also used by the ListView/Table/TextView indicator column
- **Scroller**: viewport over an over-sized child; wheel + PgUp/PgDn; `scrollTo`/`scrollBy`/`ensureVisible`; auto-scrolls to reveal the focused widget; `onScroll` for bar sync; `virtualSize`, `contentH`, `offY`
- **Splitter**: two panes + draggable focusable divider (`divider()`); Alt+arrows nudge; pane minimums from child hints
- **StatusBar**: `statusItem(label, command)`, `setText(s)`
- **ControlBar**: a `Group`, docked `dkBottom`, height `clamp(lines, 1, 3)` (`setLines(n)`). Children in one row: left group (`add`) gets the remaining width via `distribute`; right group (`addRight(v)`, or `alignRight(v)` for an existing child) is packed at preferred widths against the right edge and wins when space is short. Children are clipped to the bar height; `View.align` places them vertically. Background `tkControlBar`. As a `{.view.}` base type: zero-init (`lines = 0` = 1), set `{.dock: dkBottom.}`, no layout pragma, call `alignRight` after `mount` (deviation #32)
- **TabView**: tab container (deviation #39). Every child except its private strip is a page (`addPage(v, title = "")`, `removePage(v)` detaches without disposing, `select(i)`, `pages`, `page`); a `Window` page is embedded frameless (`Window.framed = false`) and its title is the tab label. One-row strip on top: inactive tabs cyan, the active tab in the page's colours; `◄`/`►` when tabs overflow, the active tab kept visible. Switch by clicking a tab, Ctrl+PgUp/PgDn anywhere inside (paging widgets let it bubble: `isTabSwitch`), or focusing the strip (Tab) and Left/Right/Home/End. A closable page Window shows `×`: a click calls its `close()` and a neighbour takes over. Hidden pages are unreachable by focus, mouse and hotkeys (`canFocus` requires visible ancestors); each page remembers its focused widget. As a `{.view.}` base type, `{.child.}` fields become pages in declaration order
- **MenuBar / ContextMenu**: see §2.3
- **Window**: `title=`, `isActive`, `palette` (gray by default, `pBlue`/`pCyan` opt in — §8), `defaultButton()`; `close()` (fires `onClose`, else detach + dispose), `zoom()` (toggle maximize), `closable`/`zoomable` flags with title-row `[■]`/`[↑]` boxes; drag title to move, `◢` corner / Alt+Arrows to move, Alt+Shift+Arrows to resize (`dkNone` windows only)
- **Desktop**: `selectWindow(i)`, `tile()`, `cascade()`, `floatingWindows`; Alt+1..9 selects the Nth window; nests (a Desktop inside a pane hosts its own floating windows)

Double-clicks arrive as `Event.clicks == 2` (synthesized by the App; 300 ms
window).

Programmatic setters (`setText`, `setValue`, signal application, `set<Field>`
writers) never fire change slots and never emit vocab events — only
user-driven edit paths do ([deviation #15](design-notes/DESIGN-DEVIATIONS.md)).

### 2.1 Horizontal scrolling

On ListView, Table, TreeView and TextView
([deviation #49](design-notes/DESIGN-DEVIATIONS.md)): a one-row scroll bar
(`◄ ▒ ■ ►`) along the bottom, only while something is cut; it takes a row
from the items and settles with the vertical bar (the corner stays blank).
Keys: Shift+Left/Right by `hScrollStep` (4) — plain Left/Right too, except in
TreeView (expand / collapse) — and Shift+Home/End to either edge; Shift+wheel
and the horizontal wheel / trackpad (`maWheelLeft` / `maWheelRight`); on the
bar, the arrows step, the rail pages and the thumb drags. API: `scrollX`,
`hScrollStep`, `scrollToX(x)`, `contentWidth` (ListView, TreeView, TextView);
`TreeView.isBarRow(y)` for subclasses that handle presses. Table keeps its
column widths: every cut cell scrolls by `scrollX` clamped to its own overflow
(short cells stay), with `◀` / `▶` in the cell's edge where text continues;
the header stays.

### 2.2 Text selection and the clipboard

On Input, Editor and TextView
([deviation #47](design-notes/DESIGN-DEVIATIONS.md)). Keys follow Midnight
Commander (F5 copy, F6 move) and Turbo Vision (Ctrl+Insert, Shift+Delete);
paste is the terminal's own (bracketed paste):

| Action | Input / Editor | TextView | `readOnly` Input / Editor |
|---|---|---|---|
| Select | Shift + arrows / Home / End (Editor also PgUp / PgDn), mouse drag, Shift+click | mouse drag, Shift+click | same |
| Select all | Ctrl+A | Ctrl+A | Ctrl+A |
| Copy | F5, Ctrl+Insert | F5, Ctrl+Insert | same |
| Cut | F6, Shift+Delete | — | bubbles |
| Type, Enter, Backspace, Delete, paste | replace the selection | — | bubble |

API: `hasSelection`, `selectedText`, `selectAll()`, `clearSelection()`,
`copySelection(): bool` (false, and the key bubbles, when nothing is
selected); Input / Editor also `deleteSelection(): bool`, `cutSelection(): bool`. Selected cells use
`tkTextSelection`. `core/clipboard.copyToClipboard(s)` writes OSC 52 to the
renderer's output and pipes `s` to `pbcopy` / `wl-copy` / `xclip` / `xsel`
when found; set `clipboard.copyHook` to replace both.

### 2.3 Menus

Constructors (`widgets/menu`); `~X~` in any label marks the accelerator:

| Proc | Builds |
|------|--------|
| `menuBar(menus: varargs[Menu])` / `newMenuBar(menus: seq[Menu])` | the bar (docks `dkTop`) |
| `menu(title, items)` | one drop-down |
| `item(label, cmd: Command)` (= `menuItem`) | publishes `UiAction(cmd)` on activation |
| `item(label, act: MenuAction)` | calls `act()` (`proc() {.gcsafe, raises: [].}`) |
| `item(label, EventType)` | emits `EventType` on the host view's `sessionCtx` — the bar's, or the context menu's opener — with `senderId = host.id` when the type has that field (deviation #27) |
| `itemFrom(label, proc(host: View))` | calls the proc with the host view |
| `sep()` | separator row |
| `submenu(label, items)` (= `submenuItem`) | nested popup |

`MenuBar.openMenu(i)`; menu titles open with Alt+letter, item letters
activate inside an open popup; popups run as modals. Items carrying a
disabled command grey out (§9).

`ContextMenu`: `newContextMenu(items)` builds it once — hold the reference
and reuse it; `cm.openAt(opener, at: Point)` shows it at absolute point `at`
(e.g. on a right-click) and records `cm.source = opener`, the widget it was
opened on.

### 2.4 Hotkeys & input filters

- `~tilde~` accelerators in Button/Checkbox/Label/menu captions; Alt+letter
  routes via `dispatchHotkey(scope, key)`. `Label.linkTo` focuses a control.
- `Input.filter: KeyFilter` (`proc(r, text): bool`) rejects keystrokes live,
  with shipped `digitsOnly()`, `charSet(s)`, `maxLen(n)`, `allOf(...)`;
  `intRange(lo, hi)` is a value-level `bindRequest` provider.
- `Input.history` + Down-arrow opens a recency picker; `input.addHistory(s)`
  records `s` as most recent (de-duplicated, capped).

### 2.5 Dialogs

`messageBox(app, title, text, buttons, cancel = cmCancel): Future[Command]`,
`confirm(app, text, title = "Confirm"): Future[bool]`, `inputBox(app, title,
prompt, initial = "", filter): Future[Option[string]]`. Standard commands
`cmOk`/`cmCancel`/`cmYes`/`cmNo` (negative, collision-free). Esc cancels,
Enter fires the default button, `~tilde~` accelerators pick any button.

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
| `SelectionChanged` | `selected: int` | Radio, ListView, Table, TabView | selection moved |
| `Activated` | `selected: int` | ListView, Table | Enter / item re-click |

API per type (generated): `listen(ctx, handler)`, `emit(ctx, ev)` (`emit(ctx)`
for `Clicked`), `dropListener(ctx, handle)`, `dropAllListeners(ctx)`.
Handler shape:
`proc(ev: T): Future[void] {.async: (raises: []), gcsafe.}`
(no-arg for `Clicked`). Suspension-free handlers run EAGERLY inside `emit`.

### 3.2 Signals (SignalBroker — SINGLE handler per (type, ctx) = the widget)

| Signal | Payload | Handled by | Applies |
|--------|---------|-----------|---------|
| `SetText` | `text: string` | Input, Editor, Label | `setText` + invalidate |
| `SetChecked` | `checked: bool` | Checkbox | set + invalidate |
| `SetCheckState` | `state: CheckState` | TriStateCheckBox | set + invalidate |
| `SetSelected` | `selected: int` | Radio, ListView, Table, TabView | clamp + scroll-into-view + invalidate |
| `SetProgress` | `value: int` | ProgressBar, Sparkline | `setValue` / push a sample |
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
session ctx survive UI restructuring. Instance-ctx listening is the escape
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
| `bindValue: "field"` / `"model.field"` | `proc set<Field>*(self: T, v: VT)` — writes the store field (on `self` or on `self.model`) AND signals the bound widget (`SetText`/`SetChecked`/`SetCheckState`/`SetSelected`) on its ctx. Authoritative: bypasses any `bindRequest` provider; fires no slots; loop-free by construction. Plus `proc notify<Field>*(self: T)` — pushes the store's current value to the widget after the model was mutated directly ([deviation #30](design-notes/DESIGN-DEVIATIONS.md)) |

---

## 5. Bus tiers

| Tier | Channel | Use |
|------|---------|-----|
| 1 | closure slots (`bindTo`, `onClick`…) | synchronous, inside dispatch, fastest |
| 2 | `UiAction{cmd, senderId}` on `app.bus` (`action:` pragma; menus/statusbar) | command palette semantics; `BrokersBus` bridges to `IvUiAction` EventBroker (`onUiAction`) |
| 2b | string domain bus: `publishDomain(topic, payload)` / `subscribeDomain("net/*", h)` → `SubId`, `unsubscribe(id)` | observability feeds (NetViz); exact or `prefix/*` wildcard topics; `BrokersBus` rides `IvDomainEvent` (`onDomainEvent`) |
| 3 | instance-ctx vocab events/signals (§3) | typed, per-widget routing |
| 3b | semantic `uiEvents` events (§4) | typed intent, `app.sessionCtx` (= the thread's global ctx unless one is installed/passed, [deviation #27](design-notes/DESIGN-DEVIATIONS.md)) |

Bus implementations (`core/bus`, `bus_brokers`):

| Bus | Constructor | Behaviour |
|-----|-------------|-----------|
| `NullBus` | `newNullBus()` | the default `app.bus` (deviation #31): `UiAction`s go nowhere, domain topics dispatch to subscribers synchronously, nothing is recorded |
| `BrokersBus` | `newBrokersBus()` | real routing over nim-brokers (`IvUiAction`, `IvDomainEvent`) |
| `StubBus` | `newStubBus()` | for tests: records `actions` and `domain`, dispatches domain topics synchronously |

---

## 6. Lifecycle: `dispose(v)`

Broker registrations hold STRONG refs to the view (closure captures, global
registry) — an undisposed view leaks under refc and ORC alike. Contract:

- `dispose(v)` recurses leaves-first, runs each view's `disposers`
  (mount-installed `on:` listeners, widget signal handlers), then
  `releaseInstanceCtx(brokerCtx)` and sets the ctx inert (`BrokerContext(0)`).
- Call it EXACTLY ONCE, when a subtree is permanently done. `remove()` /
  re-adding does NOT dispose — transient reparenting (menus, window
  re-adds) keeps wiring alive on purpose
  ([deviation #16](design-notes/DESIGN-DEVIATIONS.md)).
- Drop-then-release: anything YOU attached to a widget's ctx
  (model listeners) must be dropped by you before/independent of dispose —
  a stale listener survives into the recycled ctx id.
- Idempotent: double dispose is a strict no-op.

---

## 7. Layout & sizing

- `Dock`: `dkNone` (manual bounds), `dkTop/dkBottom/dkLeft/dkRight` (edge
  strips), `dkFill` (remainder).
- `SizeHint` helpers: `fixedHint(n)`, `prefHint(n, stretch = 0)`; stretch
  weights share leftover space in boxes/grids.
- Containers: `newVBox(spacing)`, `newHBox(spacing)`, `newGrid(cols, spacing)`,
  `newFormLayout(spacing)`; in mount via the `vbox`/`hbox`/`grid`/`form` type
  pragmas.
- Coordinates: `draw()`/mouse coords are CONTENT-local (border handled by
  the parent); a view's own border cells address as -1/`contentW`.

### 7.1 Alignment, anchoring, padding & forms

- `View.align` (`alignSelf` pragma): `alStretch` (default) / `alStart` /
  `alCenter` / `alEnd` — cross-axis in a box, in-cell for grid/form
  ([deviation #19](design-notes/DESIGN-DEVIATIONS.md) for the pragma name).
- `View.anchor.edges` (`anchors` pragma): edge-anchor a `dkNone` child — both
  edges of an axis stretch, one slides.
- `View.padding` (`padding` pragma): content inset, composes with the border.
- `FormLayout` (`form` pragma): two columns of (label, control) pairs; col 0
  auto-sizes to the widest label, col 1 stretches.

### 7.2 Text width

Widgets measure text in terminal **columns**, not runes
([deviation #45](design-notes/DESIGN-DEVIATIONS.md)). `illview/core/textwidth`
(re-exported by `drawcontext` and the umbrella module):

| Proc | Meaning |
|---|---|
| `runeWidth(r)` | 0 (combining marks, ZWJ, variation selectors), 2 (CJK, fullwidth, emoji), else 1 |
| `textWidth(s)` | columns `s` takes |
| `clipWidth(s, w)` / `padWidth(s, w)` | prefix that fits `w` columns / that prefix padded to exactly `w` |
| `colOf(runes, i)` / `indexAtCol(runes, col)` | rune index ↔ display column |

Emoji width is the terminal's: `App.enableTui` measures it once (deviation
#46) and calls `setEmojiWidth(1|2)` (`emojiWidth()` reads it; default 2).
`ILLVIEW_EMOJI_WIDTH=1|2` skips the measurement.

`DrawContext.write` advances by width; a wide character occupies its cell and
the next (a `Rune(0)` continuation); zero-width characters are stored in the
previous cell's `TerminalChar.extra`. `Input.scrollX` / `Editor.scrollX` are
display columns; `cursor` / `curCol` stay rune indexes.

---

## 8. Styling & themes

Resolution order: theme token → per-view `styleOv` → focus override.
Subtree theming via `View.theme`.

**Surfaces** ([deviation #34](design-notes/DESIGN-DEVIATIONS.md)):
`defaultTheme()` = `tvTheme()`, Turbo Vision's visual language. Every control
sits on a surface whose background differs from the one around it — enforced
by `tests/test_theme.nim` for every palette.

| Surface | Widgets | Tokens | window / dialog (default, gray) | opt-in `pBlue` window |
|---|---|---|---|---|
| desktop | Desktop (`░`) | `tkDesktop` | blue on lightgray | — |
| bar | MenuBar, StatusBar | `tkMenu*`, `tkStatusBar*` | black on lightgray, red hotkeys | — |
| control bar | ControlBar | `tkControlBar` (= cluster colour) | black on cyan | black on cyan (lightgray in `pCyan`) |
| window | Window/Dialog bg, Label | `tkWindowBg`, `tkText`, `tkLabelFocused`, frame/title tokens | black on lightgray | yellow on blue |
| cluster | Checkbox, Radio, TriStateCheckBox, GroupBox content | `tkCheckbox*`, `tkCluster` | black on cyan | black on cyan |
| field | Input, Editor | `tkInput*` | white on blue | black on lightgray |
| list | ListView, Table, TreeView, TextView | `tkList`, `tkSelection*`, `tkTableHeader`, `tkScrollBar` | black on cyan | black on cyan |
| button | Button | `tkButton*`, `tkButtonDefault` | black on green | black on green |

**TV gray** (deviation #37): every lightgray in `tvTheme()` is `bgGray`, a
256-colour background (`ESC[48;5;248m`, #a8a8a8 ≈ TV's #AAAAAA) — terminal
palettes render ANSI "white" (47) anywhere from gray to near-white. It is used
when `COLORTERM` is set or `TERM` names a 256-colour terminal; otherwise (and
on the Windows console) it falls back to ANSI 47. Force with
`ILLVIEW_COLORS=16|256`. `classicBlueTheme()` keeps `bgWhite`.

**Palettes**: `View.palette` (`pDefault`, `pBlue`, `pCyan`, `pGray`) switches a
subtree to `theme.variant(p)` (`Theme.variants`); the nearest palette wins,
an explicit `View.theme` closer to the view wins as-is. The base table is
the gray palette, so every window and dialog is lightgray (deviation #35);
`win.palette = pBlue` (or `pCyan`) opts a window into TV's other colour
sets. `classicBlueTheme()` is the old all-blue table (no variants).

**fg-only tokens**: `tkHotkey` (accelerator letter inside controls, via
`v.hotkeyStyle(host)` — keeps the control's bg). Bars and menus keep
`tkStatusBarHotkey`.

Theme tokens: `tkDesktop`, `tkWindowFrame`, `tkWindowFrameActive`,
`tkWindowTitle`, `tkWindowBg`, `tkText`, `tkTextDisabled`, `tkButton`,
`tkButtonFocused`, `tkCheckbox`, `tkCheckboxFocused`, `tkInput`,
`tkInputFocused`, `tkSelection`, `tkSelectionFocused`, `tkMenu`,
`tkMenuSelected`, `tkStatusBar`, `tkStatusBarHotkey`, `tkTableHeader`,
`tkGroupBox`, `tkProgress`, `tkBorder`, `tkShadow`, `tkScrollBar`, `tkControlBar`,
`tkHotkey`, `tkLabelFocused`, `tkCluster`, `tkList`, `tkButtonDefault`,
`tkWindowCloseBox`, `tkCursor`, `tkTextSelection`.

---

## 9. App

`newApp(fpsCap = 30, theme = nil, sessionCtx = BrokerContext(0), captureOutput = false)` → `App`
(session ctx = the thread's `globalBrokerContext()` unless one is passed,
[deviation #27](design-notes/DESIGN-DEVIATIONS.md)) with `desktop`, `bus`,
`running`, `onInput` hook; `await app.run()`, `app.stop()`,
`app.requestRedraw()`, `app.execView(g)` (modal, returns the closing
`Command`), `app.endModal(cmd)`, `app.focus`, `app.tuiActive`,
`app.enableTui()` / `app.disableTui()` (re-entrant suspend / resume). Frames
are dirty-driven and fps-capped; an idle app has zero pending timers.
Everything runs on ONE chronos thread — no marshaling; `--mm:refc` and
`--mm:orc` are both CI-gated (`nimble test` / `nimble testRefc`, see
[DESIGN.md §10](DESIGN.md#10-memory-model--platform-support)).

**Session ctx**: `newApp(sessionCtx = c)` calls `bindSessionCtx(c)` so views
built afterwards on this thread live under `c`; `bindSessionCtx(BrokerContext(0))`
restores "follow `globalBrokerContext()`". Standalone (no-App) users normally
call `setThreadBrokerContext` instead.

**Focus routing** (`core/routing`): `setFocus(scope, v)` redirects the focused
chain to `v` (`nil` clears); `focusNext(scope)` / `focusPrev(scope)` cycle
through visible, enabled, focusable views (Tab / Shift+Tab use them).

**Command gating**: `app.disableCommand(cmd)` / `app.enableCommand(cmd)`
/ `app.isCommandEnabled(cmd)`. A disabled command greys and blocks any
Button/Checkbox/StatusBar/menu item that carries it.

**Output capture** ([deviation #41](design-notes/DESIGN-DEVIATIONS.md); POSIX
with threads, `CaptureSupported`): with `captureOutput = true`, while the TUI
is up fd 1/2 point at a pty, so `echo`, C `printf` and child processes never
touch the screen. On `disableTui` (terminal mode, or exit) the collected
output is replayed into the terminal's scrollback — colours kept,
cursor/clear/mode sequences stripped — and from then on passes through live;
capture stays on until `run` returns, so the scrollback and the pane both get
every line. `app.captureTo(textView)` feeds it into a pane line by line as it
arrives (several panes may share it); `app.onCapturedOutput = proc(chunk)`
sees the raw bytes; `app.capturedOutput()` returns what is not yet replayed;
`app.captureLimit` bounds the history (default 1 MiB, drop-oldest). A small
internal drain thread reads the pty, so a large synchronous write never
blocks the loop. Architecture and flows:
[DESIGN.md §8](DESIGN.md#8-output-capture).

---

## 10. Platform support

The Windows input driver is **deferred**: POSIX only for now (design in
[design-notes/WINDOWS-DRIVER.md](design-notes/WINDOWS-DRIVER.md),
[deviation #18](design-notes/DESIGN-DEVIATIONS.md)). Memory model and
platform matrix: [DESIGN.md §10](DESIGN.md#10-memory-model--platform-support).
