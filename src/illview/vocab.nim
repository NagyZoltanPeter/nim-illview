## Framework event/signal vocabulary (Phase 12, plan-3 D8).
##
## Widget identity lives in the ROUTE, not the payload: every View owns a
## BrokerContext (`view.brokerCtx`) — widgets emit these events on it and
## handle these signals on it. No senderId fields anywhere: listen on a
## widget's ctx to hear exactly that widget; signal a widget's ctx to direct
## exactly that widget. App-level SEMANTIC events (`emits:` / uiEvents) stay
## separate on the default ctx — models should listen there by default and
## reach for instance-ctx listening only for genuinely widget-bound concerns.
##
## Signal application deliberately bypasses change slots and re-emission:
## programmatic setters (setText & co.) have never fired onChange in illview,
## so there is no echo path and no guard flag is needed (plan-3 D8 deviation).

import chronos
import results
import brokers
import ./core/[view, routing]

# Deliberately NOT `export brokers`: event_broker re-exports std/tables,
# whose Table would collide with the Table widget in the umbrella module.
# Everything callers need is either generated in THIS module (listen/emit/
# signal/drop*/has* for the vocab types) or exported selectively below.
export results, chronos
export broker_context

# --- events: widget → app (EventBroker: many listeners per (type, ctx)) ------

EventBroker:
  type Clicked* = void ## Button activation

EventBroker:
  type TextChanged* = object ## Input / Editor, live edits
    text*: string

EventBroker:
  type Submitted* = object ## Input, Enter
    text*: string

EventBroker:
  type Toggled* = object ## Checkbox
    checked*: bool

EventBroker:
  type SelectionChanged* = object ## Radio / ListView / Table, selection moved
    selected*: int

EventBroker:
  type Activated* = object ## ListView / Table, Enter or item re-click
    selected*: int

# --- signals: app → widget (SignalBroker: ONE handler per (type, ctx) -------
# --- = exactly the mounted widget; err "no signal handler installed" =
# --- widget gone / not constructed) ------------------------------------------

SignalBroker:
  type SetText* = object ## Input, Editor, Label
    text*: string

SignalBroker:
  type SetChecked* = object ## Checkbox
    checked*: bool

SignalBroker:
  type SetSelected* = object ## Radio, ListView, Table
    selected*: int

SignalBroker:
  type SetProgress* = object ## ProgressBar
    value*: int

SignalBroker:
  type FocusMe* = void ## any focusable widget

# --- installation helpers (used by widget constructors) ----------------------

template installSignal*(w: typed, S: typedesc, body: untyped) =
  ## Install the single `S` handler on w's brokerCtx (payload injected as
  ## `sig`) and record the teardown in w.disposers for dispose().
  discard S.onSignal(
    w.brokerCtx,
    proc(sig {.inject.}: S): Future[void] {.async: (raises: []), gcsafe.} =
      {.cast(gcsafe).}:
        body)
  w.disposers.add(
    proc() {.gcsafe, raises: [].} =
      asyncSpawn S.dropSignalHandler(w.brokerCtx))

proc installFocusMe*(v: View) =
  ## Focusable widget constructors call this: `FocusMe.signal(v.brokerCtx)`
  ## then focuses the widget (no-op while detached or not focusable).
  discard FocusMe.onSignal(
    v.brokerCtx,
    proc(): Future[void] {.async: (raises: []), gcsafe.} =
      {.cast(gcsafe).}:
        let r = v.root
        if r of Group and canFocus(v):
          setFocus(Group(r), v))
  v.disposers.add(
    proc() {.gcsafe, raises: [].} =
      asyncSpawn FocusMe.dropSignalHandler(v.brokerCtx))
