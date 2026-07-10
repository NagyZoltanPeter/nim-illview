# illview — Build Plan, Iteration 4 (phases 16–27)

Scope decided 2026-07-10: **Tier 1 + Tier 2** of the Turbo Vision gap
analysis, plus the **layout upgrades** (padding / alignment / anchors /
FormLayout). The **Windows input driver is deferred** — documented only
(Phase 16, docs/WINDOWS-DRIVER.md). Nothing from Tier 3.

Prime directives carry over unchanged from BUILD-PLAN.md: single thread,
dirty-driven fps-capped rendering with zero idle cost, framework-owned
input distribution, minimal deps, no editor scope creep. Every phase:
compiles, tests green, demoable, committed.

## Decisions (continuing plan-3 numbering)

- **D13 — Windows driver deferred.** Design is captured in
  docs/WINDOWS-DRIVER.md (INPUT_RECORD route + RegisterWaitForSingleObject
  → ThreadSignalPtr wake-up). Revisit when a native-Windows consumer
  exists. Until then illview is POSIX-only (macOS/Linux/WSL).
- **D14 — Layout semantics.** `padding` shrinks a container's clientRect
  (composes with border insets). `align` (alStretch default, alStart /
  alCenter / alEnd) applies on the cross axis of boxes and on both axes of
  grid cells; alStretch preserves today's behavior so existing layouts are
  untouched. `anchors: set[Anchor]` ({aLeft, aTop, aRight, aBottom}) is a
  per-child mode honored by plain Group.arrangeChildren for dock==dkNone
  children — edge offsets captured at first arrange, maintained on resize
  (TV growMode equivalent). Anchors and dock are mutually exclusive.
- **D15 — ScrollBar is a standalone passive widget** (vertical first,
  horizontal same type). It renders track/thumb, handles click/drag/wheel,
  and reports via `onScroll(pos)`. ListView/Table/TextView additionally get
  a built-in optional indicator column (`showScrollbar`) so the common case
  needs no wiring; the standalone widget serves Scroller and custom uses.
- **D16 — Scroller = offset-translated viewport.** A Group whose child is
  arranged at its measured (virtual) size; drawing translates by
  (-offsetX, -offsetY) and the existing DrawContext clip does the rest.
  Mouse routing translates the same way. Wheel scrolls; scrollbars sync.
- **D17 — Hotkey markup is TV-style tildes**: `"~F~ile"`, `"~O~K"`.
  Parsed at caption-set time into (clean text, hotkey rune, highlight col).
  Alt+letter routes: menubar first, then focused window's subtree. Label
  gains `linkTo`: its hotkey focuses the linked control.
- **D18 — Validators stay two-layer.** Value-level validation IS the
  existing bindRequest provider (veto/normalize — unchanged). New key-level
  layer: `filter` closure on Input (`proc(r: Rune, text: string): bool`)
  rejecting runes at input time, plus shipped helpers (digitsOnly,
  charSet(...), maxLen(n)) and provider helpers (intRange(lo, hi)).
  No regex — no new deps.
- **D19 — Command set on App.** `enableCommand` / `disableCommand` /
  `isEnabled` on a global set, reachable from widgets via a root-group
  closure (same pattern as invalidateCb). Menu/status items carrying a
  disabled Command render greyed (new tkDisabled theme token) and refuse
  activation. Default: everything enabled.
- **D20 — Stock dialogs are plain compositions** over execView:
  `messageBox(app, title, text, buttons): Future[Command]`,
  `inputBox(app, title, prompt, initial = "", filter = nil):
  Future[Option[string]]`, `confirm(app, text): Future[bool]`. Standard
  commands cmOk/cmCancel/cmYes/cmNo join core/bus.nim.

## Phases

### Phase 16 — Windows driver documentation (docs only)
- Write docs/WINDOWS-DRIVER.md: POSIX driver anatomy, what Windows needs,
  chosen future design, cost/risk, testing constraints, revisit criteria.
- Record D13 in docs/DESIGN-DEVIATIONS.md (#18).
- Exit: doc committed; no code change.

### Phase 17 — Layout: padding, align, anchors, FormLayout
- `padding*: int` on Group (clientRect insets after border);
  `align*: Align` on View; honored by BoxLayout (cross axis) and Grid
  (both axes). `anchors*: set[Anchor]` honored by Group.arrangeChildren.
- FormLayout: Grid(cols = 2) preset with auto-sized label column
  (col 0 = max label pref, col 1 stretches); `newFormLayout(spacing)`.
- DSL: `padding(n)`, `align(a)`, `anchors(...)` pragmas + `form` type-level
  container pragma; mount() wiring.
- Tests: distribute unchanged; new arrange tests for align/anchor/padding;
  form column sizing. Snapshot test for a padded, anchored window.
- Exit: existing 123 tests still green (alStretch default = old behavior).

### Phase 18 — Mouse infra + ScrollBar
- Double-click synthesis in routing (Moment-based threshold, 300 ms;
  evMouse gains `clicks` count). Wheel events routed to the hovered view
  (not the focused one — TV semantics).
- ScrollBar widget (vertical + horizontal): track/thumb glyphs, click-page,
  drag-thumb (mouse capture), wheel; `setRange(total, page, pos)`,
  `onScroll`.
- ListView/Table/TextView: consume wheel; optional `showScrollbar`
  indicator column.
- Tests: synthesis thresholds, wheel routing, thumb math, indicator
  snapshot.

### Phase 19 — Scroller viewport
- `Scroller` Group: virtual-size child arrange, offset draw/route
  translation, wheel + keyboard (PgUp/PgDn/arrows when focused), scrollbar
  sync, `scrollTo/ensureVisible`.
- Test: big form inside 10-row scroller — focus walk keeps the focused
  widget visible (Tab into off-screen widget auto-scrolls).
- Example: ex11_scroller.

### Phase 20 — Splitter
- `Splitter` Group: exactly two children + a 1-cell divider (axis param);
  divider drag (mouse capture) rebalances two ratios; Alt+arrows nudge when
  divider focused; min sizes respected via child hints.
- Tests: drag math, min clamp, keyboard nudge. Example: ex12_splitter
  (netviz | log side by side).

### Phase 21 — Window chrome + desktop management
- Close `[■]` and zoom `[↕]` regions on the title row (drawOverlay + title
  hit test); zoom = save/restore bounds to desktop size; `onClose` hook
  (default: remove + dispose).
- Alt+1..9 selects/raises the Nth window; desktop `tile()` / `cascade()`
  + standard commands.
- Tests: hit regions, zoom restore, Alt+N focus, tile geometry.

### Phase 22 — Command set + hotkeys
- App command set per D19; tkDisabled token; greyed menu/status rendering;
  disabled items don't activate.
- Tilde hotkey parsing (shared helper) in Button/Checkbox/Label/menu
  captions; Alt+letter routing; `Label.linkTo` focuses its control.
- Tests: parse, render highlight snapshot, Alt+letter dispatch, disabled
  command refuses activation, enable/disable repaints.

### Phase 23 — Submenus
- MenuItem gains optional `submenu`; MenuPopup opens child popups
  (right/left auto-placement), Left/Right + Esc navigation; greyed items
  skipped by selection walk.
- Tests: nested navigation, placement at screen edge.

### Phase 24 — Validators
- `Input.filter` per D18 + helpers (digitsOnly, charSet, maxLen,
  intRange provider). Filter runs before storage/emit; rejected runes are
  swallowed silently (TV behavior).
- Tests: filter rejection, helper providers, interaction with
  bindValue/bindRequest ordering.

### Phase 25 — Stock dialogs
- dialogs.nim: messageBox / inputBox / confirm per D20; standard commands;
  Esc = cancel, Enter = default button; buttons get tilde hotkeys.
- Tests: modal Future resolution, Esc/Enter mapping, inputBox filter
  pass-through. Example usage folded into ex04 gallery.

### Phase 26 — History dropdown + TreeView
- `Input.history` (bounded seq + Down-arrow popup via runModal, like
  MenuPopup; Enter picks, updates recency).
- `TreeView` widget: expand/collapse (+/− glyphs, Left/Right keys),
  `onSelect/onActivate`, lazy children callback optional.
- Tests: history recency order, popup pick; tree expand/collapse/keys
  snapshot + selection.

### Phase 27 — Docs, examples, screenshots
- README widget table + REFERENCE.md + COOKBOOK.md updated for everything
  above; regenerate SVG screenshots (gallery scene gains scrollbar,
  splitter, tree, dialog); examples list refreshed; DESIGN-DEVIATIONS.md
  entries for anything that drifted.
- Exit: `nimble test` green, `nimble examples` builds all, screenshots
  regenerated, docs consistent.

## Test budget
Each widget/behavior phase adds its own test file section; expected total
roughly 123 → ~175. Snapshot tests use the existing offscreen render
harness; no terminal needed.
