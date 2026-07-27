# illview — Audit Implementation Plan

*Companion to [AUDIT-REVIEW.md](AUDIT-REVIEW.md). Eleven workstreams (WS1–WS11),
each with goal, concrete tasks, API sketches where relevant, acceptance
criteria, effort (S ≤ 1 day, M ≤ 1 week, L > 1 week), and dependencies.
Sketches are proposals, not commitments — final signatures may change during
implementation.*

## Suggested ordering

| Phase | Workstreams | Rationale |
|-------|-------------|-----------|
| 1 | WS1, WS3 | Doc correctness + CI first: everything later is verified by CI, and the doc bugs actively mislead today. |
| 2 | WS4, WS5, WS6 | Macro hardening and host hygiene are small, high-leverage code changes; the testing module makes all later work testable by users. |
| 3 | WS2, WS7 | Architecture guidance + chronicles router unblock the logos-delivery integration. |
| 4 | WS8, WS9, WS10 | Strategic design work, each independently shippable. |
| 5 | WS11 | Long-term seam; do last, informed by any remote-attach requirement. |

---

## WS1 — Documentation correctness pass

**Goal:** no statement in user-facing docs contradicts the code.
**Effort:** S–M. **Dependencies:** none.

Tasks:

1. Fix `docs/REFERENCE.md:47` and `:162` — `emits:` fires on the **session
   ctx** (`sender.sessionCtx`, `src/illview/dsl/uievents.nim:120-123`), not
   the default ctx. Add one sentence on *why* (two UIs in one process must
   not cross-talk).
2. Fix `docs/REFERENCE.md:190` and cookbook recipe 12 — `dispose` does **not**
   currently release/recycle the instance ctx (`src/illview/core/view.nim:326-329`).
   Describe actual behavior; if WS9 later adds reclamation, update again.
3. Reconcile the Nim floor: pick one of "≥ 2.0" (`README.md:294`,
   `docs/DESIGN.md:41`) or `>= 2.2.4` (`illview.nimble:14`), verify with CI
   (WS3), and state it in exactly one place that the others link to.
4. Fix test-count drift (`README.md:9,34` vs `:289`) — ideally replace static
   numbers with a CI badge (WS3).
5. Correct `docs/REFERENCE.md:39` ("`child` valid on any widget") to list the
   widgets with `createView` overloads until WS4 closes the fallback hole.
6. De-jargonize: strip or move to an appendix every "plan-2 D4",
   "deviation #15", "P22/D19" reference in REFERENCE.md and
   `src/illview/dsl/pragmas.nim` doc comments. Internal design docs keep
   their cross-references; the user-facing reference does not.
7. Add a front-line **"Lifecycle & memory"** section to README + cookbook:
   dispose-exactly-once (leak otherwise, under refc *and* orc),
   `remove()` keeps wiring alive on purpose, drop your own ctx listeners
   before dispose, and the ORC churn crash signature with the
   build-once/add-remove pattern (promote `repro/README.md` and deviation #22
   content).
8. Examples-table refresh in README (add `ex14_logpane`, note the ex08 gap or
   renumber).
9. Make the `{.gcsafe, raises: [].}` requirement statement consistent across
   README/COOKBOOK/REFERENCE (state precisely when it is required and when
   inference suffices).

Acceptance criteria: a grep for `default ctx` in REFERENCE finds no claim
about `emits:`; a grep for `D1[0-9]|deviation #|plan-2` in REFERENCE.md and
pragmas.nim doc comments returns nothing; README numbers match `nimble test`
output; a new reader can learn the dispose rules without opening
`DESIGN-DEVIATIONS.md`.

---

## WS2 — Prescriptive architecture & composition guidance

**Goal:** a team adopting illview gets one recommended architecture and one
documented component-library pattern, instead of nine sanctioned channels and
single-module examples.
**Effort:** M. **Dependencies:** WS1 (builds on corrected facts).

Tasks:

1. New doc (or COOKBOOK part II) **"Architecture"**:
   - The recommended default: *semantic events out* (`emits:` / hand-defined
     `EventBroker` types), *signals + `set<Field>` in*, `bindRequest` for
     validation; tier-1 closure slots only for widget-local cosmetics; domain
     bus only for observability feeds.
   - A decision table for all nine channels (slot / `bindTo` / `on:` /
     `emits:` / `action:` / domain bus / `bindValue` / `bindRequest` /
     signal): when to use, when not to, firing order when combined.
   - The context-scope matrix (session ctx / widget brokerCtx /
     DefaultBrokerContext) in one prominent table.
   - An explicit anti-pattern list (domain logic in tier-1 slots; `bindTo` +
     `on:{Clicked}` on the same field; listening on instance ctx for
     semantic concerns; model logic keyed on `senderId`).
2. Name and document the **"strict MVU profile"**: single dispatcher proc,
   external store, semantic-events-out/signals-in only, with a worked
   example. (Pure convention today — no code change needed; the no-echo
   setter guarantee `vocab.nim:11-13` is the load-bearing fact to cite.)
3. New cookbook recipe **"Reusable components across modules"**: component
   type + handlers + `uiEvents(T)` + exported factory
   `proc newFoo*(): Foo = mount(Foo)` in the defining module; explain the
   expansion-site identifier binding that makes the factory necessary.
4. Recipe: hand-defining semantic `EventBroker` types in a shared
   `events.nim` and reusing them from `emits:`/menus (the ex13 pattern,
   generalized) — the interim answer to keeping widget modules out of the
   model's import graph until WS8 lands.
5. Converge context scopes where cheap: move menu `item(label, EventType)`
   emission from `DefaultBrokerContext` to the session ctx (cookbook already
   flags it "for now"); evaluate session-scoping `bindRequest` provider
   registration (breaking change — gate on WS8 decision).

Acceptance criteria: a new team can answer "which mechanism do I use for X"
from one table; a component defined in module A mounts from module B by
following one recipe; the strict profile has a runnable example under
`examples/`.

---

## WS3 — CI, release, packaging

**Goal:** a clean-machine install is continuously proven; adopters
(logos-delivery) have something to pin.
**Effort:** S–M. **Dependencies:** none (do first).

Tasks:

1. GitHub Actions workflow: matrix over {oldest supported Nim (per WS1 task
   3), latest stable Nim} × {linux, macos}; steps: `nimble install -y`
   (clean resolution of `chronos`/`brokers` from the registry),
   `nimble test`, `nimble examples`, `nimble screenshots` (artifact upload of
   the SVGs doubles as a visual smoke test).
2. Add `nimble docs` task running `nim doc --project` on `src/illview.nim`;
   publish to GitHub Pages from CI.
3. Tag `v0.1.0` (or `v0.2.0` after WS1); add a `CHANGELOG.md`; register the
   package in the nimble registry so install-by-URL becomes optional.
4. Add a lock file (`nimble lock`) or, if targeting nimbus-build-system
   consumers, document the exact tested versions of `chronos` and `brokers`
   in the README and keep them updated by CI.
5. Replace static README badges with CI/version badges.
6. Decide and enforce the memory-model position: if orc is required, add
   `--mm:orc` to `config.nims` for consumers or assert at compile time; if
   refc is genuinely supported (as `REFERENCE.md:250` claims), add a refc job
   to the CI matrix.

Acceptance criteria: green CI on a PR is sufficient evidence that a new user
can install and run tests on a clean machine; `nimble install illview@0.x`
works; API docs are browsable online.

---

## WS4 — DSL macro hardening

**Goal:** every DSL mistake fails at compile time, at the pragma's source
location, with an actionable message. No silent fallbacks.
**Effort:** M. **Dependencies:** none; coordinate doc updates with WS1.

Tasks:

1. **Validate names inside pragma strings** in `mount`/`uiEvents`
   (`src/illview/dsl/mount.nim:289-337`): the macro already walks the
   `recList` — check that `bindValue`/`bindTo` targets name an existing field
   of a bindable type, and `error()` anchored to the pragma node on mismatch,
   with a near-miss suggestion (simple case-insensitive/edit-distance-1 scan
   over field names).
2. **Replace the `on:` arity probe** (`mount.nim:339-353`): instead of
   `when compiles(handler(self, ev)) ... else: handler(self)`, generate an
   explicit check — if a matching two-arg overload exists but does not
   typecheck against the actual payload type, emit a compile error naming
   the expected signature; fall back to one-arg only when *no* two-arg
   overload with that name exists.
3. **Close the generic `createView` fallback** (`mount.nim:366-368`): accept
   only types carrying `{.view.}` (check via `hasCustomPragma`); otherwise
   `error()` listing the built-in widgets with overloads and pointing to the
   custom-widget integration doc (WS10). Update `REFERENCE.md:39`
   accordingly.
4. **Reject inherited `{.child.}` fields loudly**: if a `{.view.}` type's
   base type also carries `{.view.}` (or has `{.child.}` fields), emit a
   compile error stating that composition (a child field of the base type)
   is the supported reuse mechanism. (Alternative — actually walking base
   recLists — is a larger feature; the error is the safe first step.)
5. **Replace `parseStmt` string assembly** in `uievents.nim:120-123,162-168`
   with quasi-quoting (`quote do` / `genAst`) so generated code carries
   source positions.
6. Detect duplicate `emits:` names within a module at `uiEvents` expansion
   and error with both field positions.
7. Tests: a new `tests/test_mount_errors.nim` using
   `compiles()`-based negative assertions (or `nim check` fixtures under
   `tests/errfixtures/`) covering: typo'd bindValue field, wrong-payload
   `on:` handler, non-view child fallback, inherited child fields, duplicate
   emits.

Acceptance criteria: each of the five error classes produces a compile error
pointing at the pragma line with a message naming the fix; no
`when compiles` remains in handler resolution; negative tests lock the
diagnostics in.

---

## WS5 — Host-integration hygiene (signals, tty, shutdown)

**Goal:** illview is a polite guest inside a daemon that has its own signal
handlers, logging, and service manager.
**Effort:** M. **Dependencies:** none. High priority for logos-delivery.

Tasks:

1. **Chain signal handlers.** Save the previous handler (`sigaction` with
   old-action out-param) for SIGWINCH in the driver
   (`src/illview/backend/driver_posix.nim:116,124`) and restore *it* — not
   `SIG_DFL` — on stop. Same for the crash-restore set
   (`src/illview/core/app.nim:73-97`): record prior handlers, re-raise into
   them after writing the restore sequence, and uninstall on `disableTui`.
2. **Remove SIGTSTP/SIGCONT handlers in `consoleDeinit`**
   (`src/illview/backend/illwill_vendored.nim:602-604,641-642`) — vendored
   file, keep the patch minimal and note it in the provenance header.
3. **SIGINT/SIGTERM restore net.** Extend the async-signal-safe restore-seq
   mechanism to optionally cover INT/TERM: write RestoreSeq, restore the
   previous handler, re-raise. Make it opt-out (`-d:noExitRestore`) and
   document loudly that hosts doing their own INT/TERM handling must call
   `disableTui()` in their shutdown path.
4. **`isatty` guard.** `enableTui` checks `isatty` on the target fds and
   fails cleanly (raise a typed error or return `Result`) instead of writing
   escapes into a pipe; `app.run()` surfaces this as a normal error so a
   daemon started under systemd with a stray `--tui` flag logs one line and
   keeps running headless.
5. **Document `-d:noCrashRestore`** prominently (README embedding section +
   the WS7 integration guide) for hosts with libbacktrace/crash-dump
   machinery.
6. **Cross-thread ingestion recipe** (doc + example): a `ThreadSignalPtr` +
   locked queue drained by a loop-side pump into `publishDomain`/typed
   events; evaluate adding a small `postToLoop(proc)` helper on `App`.
   Document clearly that everything else is loop-thread-only
   (`assertLoopThread`).
7. Tests where feasible: unit-test handler save/restore by installing a
   sentinel handler before `enableTui`+`disableTui` in a pty-less harness
   (signal-handler state is inspectable via `sigaction` query without
   delivering signals).

Acceptance criteria: after `enableTui`+`disableTui`, all signal dispositions
equal their prior values; Ctrl-C on a host that never calls `disableTui`
still leaves a usable terminal; `enableTui` under a pipe returns an error
instead of emitting escapes; an example demonstrates worker-thread → UI
event flow.

---

## WS6 — Public `illview/testing` module

**Goal:** app authors snapshot-test their own screens with the same power the
framework's tests have, without importing vendored internals.
**Effort:** S–M. **Dependencies:** none; document alongside WS1.

Tasks:

1. New module `src/illview/testing.nim` exporting:
   - `newTerminalBuffer(w, h)` re-export plus cell access (read of char,
     fg/bg, style at x,y) without touching
     `backend/illwill_vendored` paths directly from user code.
   - The helpers currently private in `tests/test_render_snapshot.nim:25-35`:
     `render(view, w, h): TerminalBuffer` (arrange + draw off-screen),
     `rowStr(tb, y): string`, `cellStr(tb, x, y): string`.
   - Convenience drivers: `dispatchKey(app/view, key)`,
     `dispatchMouse(...)` re-exports, and a `pumpBroker()` helper wrapping
     the chronos-tick idiom from cookbook recipe 14.
   - `StubBus` re-export with its recorded-publishes accessor.
2. Migrate the framework's own tests to import `illview/testing` (proves the
   surface is sufficient; deletes per-file helper duplication).
3. Cookbook recipe **"Snapshot-testing your UI"**: full example — mount a
   declarative form, render off-screen, assert rows/cells, drive a key,
   assert the diff. Include the gotchas currently buried in recipe 14
   (`{.cast(gcsafe).}` in `suite` bodies, ctx-listener hygiene) as part of
   the recipe's template rather than a trailing warning list.
4. Optional (stretch): a `snapshotSvg(view, path)` helper reusing
   `tools/screenshots.nim` machinery, for golden-image style review.

Acceptance criteria: a user project depending on illview via nimble can write
a cell-exact render test importing only `illview` + `illview/testing`; the
framework's own snapshot tests no longer import
`../src/illview/backend/illwill_vendored`.

---

## WS7 — Chronicles router API + logos-delivery integration guide

**Goal:** a chronicles-based daemon adds the TUI with one module import and
one page of instructions.
**Effort:** M. **Dependencies:** WS5 recommended first (shutdown/isatty
behavior belongs in the same guide).

Tasks:

1. New optional module `src/illview/chronicles_sink.nim` (imported
   explicitly, like `bus_brokers`, so chronicles stays out of the default
   dependency graph — keep chronicles out of `illview.nimble` requires; the
   module compiles only when the host project provides chronicles):
   - `installChroniclesRouter(app: App, target: TextView)` packaging the
     ex14 dynamic-writer pattern (`examples/ex14_logpane.nim:28-42`): route
     records to the target view while `tuiActive`, else to stderr.
   - Buffering of records emitted while headless/pre-mount, flushed into the
     pane on attach (bounded ring, configurable).
   - Documented required build flags
     (`--define:chronicles_sinks=textlines[dynamic]`) with a copy-paste
     `nim.cfg` block.
2. Rework `examples/ex14_logpane.nim` to consume the new API (shrinks to a
   few lines; remains the reference for custom routing).
3. New doc `docs/INTEGRATION.md` — the logos-delivery guide promised by
   DESIGN.md §9, one page:
   - confutils flag → `enableTui()` on demand; headless default; attach /
     detach / suspend patterns (`ex01`, `ex14`).
   - chronicles routing (the new module) + the "non-chronicles output
     corrupts the screen" caveat and mitigations.
   - shutdown ordering: who calls `app.stop()` / `disableTui()` on
     SIGINT/SIGTERM (aligned with WS5 behavior).
   - signal-handler cohabitation summary and `-d:noCrashRestore`.
   - data-in patterns: typed events for semantics, domain bus for feeds,
     with the "prefer typed for anything the UI acts on" guidance.
   - dependency pinning: exact tested chronos/brokers versions (from WS3),
     vendoring `brokers` in a nimbus-style build.
4. Optional (stretch): typed domain-feed variant for `NetVizWidget` — accept
   structured events (topic + fields + render callback) so daemons stop
   pre-formatting payloads into display strings. Can be split out if it
   grows.

Acceptance criteria: a demo daemon (can live under `examples/`) shows: start
headless → attach TUI on a keypress/flag → logs flow into the pane →
Ctrl-C leaves a clean terminal; INTEGRATION.md answers every question the
audit's aspect-2 findings raised, in one page.

---

## WS8 — Model/store decoupling in the blessed path

**Goal:** the ergonomic declarative path keeps domain state *off* the widget
tree, and models never import widget modules.
**Effort:** L. **Dependencies:** WS4 (macro infrastructure), WS2 (guidance
frames the target architecture).

Tasks:

1. **External-store binding.** Extend `mount` to accept a store:
   `mount(LoginForm, store)` where `bindValue: "userVal"` resolves the field
   on the store object when one is supplied (fallback: current on-view
   fields). Generated `set<Field>` writers move to (or are duplicated for)
   the store type. Sketch:
   ```nim
   type LoginModel = ref object
     userVal, passVal: string
   let m = LoginModel()
   let form = mount(LoginForm, m)   # bindValue targets m's fields
   ```
   Design decisions to settle: does the store need a marker pragma
   (`{.model.}`)? Are store writes signaled back to widgets automatically
   (MVVM-style change notification) or via existing explicit `set<Field>`
   (keeps the no-echo guarantee — recommended first step)?
2. **Pre-declared event types for `uiEvents`.** Allow
   `emits: "RunRequested"` to bind to an *existing* `EventBroker` type
   imported from a shared events module instead of generating one:
   generation becomes the fallback when the identifier does not resolve.
   This removes the model → form-module → widget-stack import chain
   (`uievents.nim:37-38` constraint).
3. **`senderId` demotion.** Mark `senderId` diagnostic-only in docs, or make
   its inclusion opt-in per `emits:` (`emitsWithSender:`). Provide a
   sanctioned instance-discrimination alternative: an optional
   `instanceTag: string` pragma carried in generated events, or an
   id→view lookup helper if view identity is genuinely needed.
4. **Standalone-model proof.** New example + test: a model object holding
   only ctx values and subscriptions, driving two mounted form instances,
   unit-tested with *no view constructed* (emit events, assert model state;
   feed an inert ctx and assert the driver stops on `err`). This is the
   executable proof behind the README's decoupling claim.
5. **Ctx-scoped `bindRequest` providers.** Register generated providers on
   the session ctx (or optionally the instance ctx) instead of
   `DefaultBrokerContext` (`uievents.nim:142-145`), enabling per-instance
   validation and removing global-singleton test hygiene. Breaking change —
   document migration in the changelog.

Acceptance criteria: an app can keep all domain state in a store type that
imports zero illview widget modules, with declarative binding; a model
module's import list contains only the shared events module and brokers;
two instances of one form validate independently; the standalone-model test
runs headless with no view constructed.

---

## WS9 — Screen/navigator layer + lifecycle scalability

**Goal:** a dozens-of-views app has a supported organization primitive, and
dynamic screen churn stops being dangerous.
**Effort:** L. **Dependencies:** WS1 (lifecycle docs), ideally after WS8.

Tasks:

1. **Navigator module** (e.g. `src/illview/navigator.nim`) productizing the
   ex13 `exCache` pattern (`examples/ex13_showcase.nim:59-186`):
   - named-view registry: `nav.register("settings", () => mount(SettingsScreen))`
     (factory, lazy — constructed on first show);
   - `nav.open("settings")` = activate-or-open (raise existing window /
     add cached subtree);
   - `nav.close(name)` = remove (membership only, per current semantics);
   - explicit contract: screens are cached for the navigator's lifetime,
     disposed only via `nav.dispose()` at teardown — encoding the
     build-once/add-remove pattern instead of asking every app to rediscover
     it.
   - optional back-stack (`nav.back()`) for wizard-style flows.
2. **Instance-ctx reclamation.** Design work: make `dispose` release the
   instance ctx safely. Requires solving the recycled-ctx contamination
   hazard first — e.g. brokers-side "drop all listeners for ctx" on release,
   or a generation counter widening the effective id space. Coordinate with
   nim-brokers (same author) — this may be a brokers feature. Until then,
   document the 16-bit budget (`view.nim:132`) and that the navigator's
   caching contract is the supported answer.
3. **ORC churn crash.** Track the upstream Nim issue from `repro/`; add a CI
   job running the repro against new Nim releases so the "build-once"
   restriction can be lifted the moment upstream fixes it; consider a
   `-d:illviewChurnGuard` debug mode that counts mounted-then-disposed
   subtrees and warns on churn patterns.
4. **Focus scoping.** Optional: a `focusScope` flag on Group/Window making
   Tab traversal cycle within the scope (`routing.nim:41-56` currently
   recurses the whole desktop) — needed for coherent multi-window apps and
   cheap once the navigator exists.
5. Showcase migration: rebuild ex13's window management on the navigator
   (deletes ~40 lines of app ceremony; validates the API).

Acceptance criteria: ex13 uses the navigator with no hand-rolled cache; a
new example shows 10+ screens registered lazily; the lifecycle chapter
(WS1) points at the navigator as the default answer; churn safety is either
fixed upstream (CI-verified) or guarded/documented.

---

## WS10 — Extension surfaces: custom widgets, themes, layout pragmas

**Goal:** third parties can ship widget libraries that are first-class in
the DSL, themable, and layout-complete.
**Effort:** L (three independent sub-tracks; each shippable alone).
**Dependencies:** WS4 (the `createView` error message links here).

### 10a — Custom-widget contract & DSL integration (M)

1. New doc chapter **"Writing a widget"** consolidating the `view.nim`
   comments and cookbook recipe 15: required methods
   (`draw`/`measure`/`arrange`/`handleEvent`/`clientRect`/`drawOverlay`),
   coordinate conventions (content-local; border at −1/`contentW`),
   `measure` vs `outerHints`, `invalidate` rules, focus/hotkey hooks,
   joining the signal vocabulary (`installSignal`/`installFocusMe`,
   `vocab.nim:77-99`).
2. Bless the DSL integration surface: document `createView`, `setCaption`,
   `bindSlot`, `bindValueSlot`, `widgetValue` overloads
   (`mount.nim:14-77`) as the official way to make a custom widget usable
   as `{.child.}` with `caption:`/`on:`/`bindValue:`; add a worked example
   (the recipe-15 Dial, completed).
3. Fix the type-name-string keying in `uievents.nim:51-63`: resolve payload
   schemas via the overloadable procs (e.g. a `bindValueType(T)` typedesc
   hook) instead of matching on `"Input"`/`"Checkbox"` strings — removes
   both the custom-widget limitation and the name-collision hazard.

### 10b — Theme extensibility (M)

1. Replace/augment the closed `array[ThemeToken, Style]` (`theme.nim:18-46`)
   with a registry keyed by token identifiers so custom widgets can define
   tokens (e.g. `tkDial`), while built-ins keep enum-speed access.
2. Add derivation: `theme.derive(overrides)` (defaultTheme except N
   entries) and per-token fallback in `effectiveTheme`
   (`view.nim:154-160`): subtree theme consulted first, parent/default
   theme per token when unset — enabling partial themes.
3. Cookbook recipe: theming a custom widget; restyling two tokens app-wide.

### 10c — Declarative layout completeness (S–M)

1. New pragmas: `prefW`, `prefH`, `minW`, `minH`, `stretchW`, `stretchH`
   (per-axis; `stretch` stays as the both-axes shorthand) — removes the
   post-mount hint surgery seen in `ex10_instance_ctx.nim:69-70`.
2. A `Spacer` widget (flexible glue), replacing the undocumented
   stretchy-empty-Label idiom.
3. Backlog (explicitly deferred, document as non-goals for now unless
   demand appears): grid cell spanning, wrap/flow layout, per-child margin,
   justify/gravity for leftover space.

Acceptance criteria: a third-party widget in its own nimble package works as
a `{.child.}` field with pragma wiring, defines its own theme token, and no
example needs imperative hint patch-up after `mount`.

---

## WS11 — Render-target seam (long-term)

**Goal:** turn de-facto headless renderability into a supported interface,
opening remote/web attach ("view a running node's UI") without a rewrite.
**Effort:** L. **Dependencies:** none hard; do after the above — any remote
console requirement from logos-delivery should shape it.

Tasks:

1. Define a minimal render-target interface over what `frame()` needs:
   cell grid in (`TerminalBuffer`-shaped: rune, fg, bg, style per cell),
   `display()` out, plus size/resize notification. The vendored illwill
   terminal becomes implementation #1; the off-screen buffer used by tests
   and `tools/screenshots.nim` becomes implementation #2 (already
   proves the seam exists in practice).
2. Decouple public types: re-export color/style enums through an illview
   module so user code stops importing vendored/`std/terminal` types
   directly (prerequisite for any non-terminal target).
3. Split input-driver attach from renderer attach in `App` (today
   `enableTui` bundles both) so a headless-with-rendering app (renderer
   attached, no tty driver) is constructible without bypassing `frame()`.
4. Proof-of-concept target (pick one, gated on real demand): SVG stream
   (screenshots machinery, trivially), or a websocket cell-diff feed +
   minimal browser viewer — the natural remote-attach answer for a daemon.

Acceptance criteria: `frame()` renders to a target chosen at App
construction; tests/screenshots use the public off-screen target; a PoC
demonstrates one non-terminal target end-to-end.

---

## Cross-cutting notes

- **Breaking changes** (WS8 task 5 provider scoping, WS10a payload-schema
  hook, WS4 fallback closure) should batch into one minor release with a
  migration section in the changelog, after WS3 gives adopters a version to
  stay on.
- **nim-brokers coordination:** WS9 ctx reclamation and possibly WS8
  ctx-scoped providers need (or benefit from) brokers-side features; being
  the same author, plan those releases together and update the
  `brokers >= x.y` floor once.
- **Verification discipline:** every workstream that changes behavior adds
  tests in the same PR; WS3's CI is the backstop that keeps the audit's
  doc-vs-code drift class from reappearing.
