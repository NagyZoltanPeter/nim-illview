# Windows input driver — design (deferred, D13)

Status: **not implemented** (decision 2026-07-10, plan-4 D13). illview is
POSIX-only: macOS, Linux, and Windows via WSL. This document captures the
design so implementation can start without re-deriving it.

## Why rendering is NOT the gap

The vendored illwill backend already writes to the Windows console; the
diffed `display()` path is platform-neutral. Everything missing is on the
**input** side, plus raw mode and resize detection.

## What the POSIX driver does (the contract to replicate)

`src/illview/backend/driver_posix.nim`:

| Concern | POSIX mechanism |
|---|---|
| Raw mode | termios (via illwill's terminal setup) |
| Readable input fd | opens `ttyname(0|1|2)` as a **dedicated** read fd — never `O_NONBLOCK` on fd 0 (shared file description would break stdout, deviation #14) |
| Async readiness | chronos `register2` + `addReader2` (kqueue/epoll) — zero idle cost, no polling |
| Resize | SIGWINCH handler writes one byte to a self-pipe; the pipe's read end is a second chronos reader |
| Decoding | bytes → `decoder.feed()` → `seq[InputEvent]` (incremental state machine: keys, SGR mouse, bracketed paste) |

The driver's contract upward is small: deliver `InputEvent`s and resize
notifications into `App.handleInput`, asynchronously, with no idle wake-ups.

## What Windows needs

| Piece | Mechanism | Difficulty |
|---|---|---|
| Raw mode | `SetConsoleMode(hIn, mode - ENABLE_LINE_INPUT - ENABLE_ECHO_INPUT + ENABLE_MOUSE_INPUT + ENABLE_WINDOW_INPUT)` | trivial |
| Input readiness | **The hard part.** The console input handle is not IOCP-compatible, and chronos on Windows polls IOCP only. Chosen route: `RegisterWaitForSingleObject` on the handle → kernel thread-pool callback that ONLY fires a chronos `ThreadSignalPtr` → the event loop wakes on its own thread and drains input | hard |
| Decoding | Translate `INPUT_RECORD`s (`ReadConsoleInputW`) directly to `InputEvent` — key events with modifier flags, `MOUSE_EVENT` for position/buttons/wheel. Chosen over `ENABLE_VIRTUAL_TERMINAL_INPUT` (which would reuse decoder.nim verbatim) because VT input mouse reporting only works reliably in Windows Terminal, not legacy conhost | moderate |
| Resize | `WINDOW_BUFFER_SIZE_EVENT` arrives in the same `INPUT_RECORD` stream — simpler than SIGWINCH, no self-pipe needed | trivial |
| Paste | No bracketed paste in conhost; Windows Terminal pastes as a burst of key records. Heuristic burst-coalescing or accept per-key delivery initially | easy/deferred |

## Threading caveat (prime-directive tension)

The `RegisterWaitForSingleObject` callback runs on a kernel-managed
thread-pool thread. It must do exactly one thing: signal the
`ThreadSignalPtr`. All reads, decoding, and state live on the chronos
thread. This bends the "single thread" prime directive in letter but not
in spirit — record it as a deviation when implemented. The alternative
(a polling timer) violates the zero-idle-cost directive and is rejected.

## Cost / risk

- **Cost: L** — roughly 1–2 weeks. The chronos wake-up integration and
  INPUT_RECORD translation dominate; raw mode and resize are trivial.
- **Risk: medium-high.** Terminal diversity (legacy conhost vs Windows
  Terminal) affects mouse and paste behavior; the signal-wakeup pattern
  needs care around shutdown ordering (`UnregisterWaitEx` before closing
  the signal).
- **Testing: the real blocker.** No pty equivalent on Windows — the
  ptyrun.py verification harness has no counterpart. Needs a real Windows
  box or a self-hosted CI runner; ConPTY could host automated tests but is
  its own project.

## Structure when implemented

- `src/illview/backend/driver_windows.nim` exposing the same surface as
  driver_posix (`newInputDriver`, start/stop, event callback).
- `when defined(windows)` dispatch in core/app.nim (currently imports
  driver_posix unconditionally).
- decoder.nim stays untouched — it remains the POSIX byte decoder; the
  Windows driver produces `InputEvent`s directly.

## Revisit criteria

Implement when a native-Windows consumer exists — e.g. the logos-delivery
daemon TUI being required on native Windows nodes (WSL not acceptable), or
external adoption asking for it.
