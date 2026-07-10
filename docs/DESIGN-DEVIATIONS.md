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
