## EventBus abstraction (§3.8 + plan-2 D6). The real implementation wraps
## nim-brokers (illview/bus_brokers.nim); StubBus backs unit tests.
##
## Iteration 2 opens the bus up: string-topic subscription with `prefix/*`
## wildcards lives in the BASE class, so every implementation dispatches
## the same way; implementations decide how published events reach
## dispatchDomain (StubBus: synchronously; BrokersBus: via the broker loop).
##
## `Command` lives here (not in events.nim as §3.5 sketches) because both
## the view layer and the bus need it and bus.nim is the dependency-free
## bottom.

import std/strutils

type
  Command* = distinct int

  UiAction* = object
    cmd*: Command
    senderId*: int

  SubId* = distinct int

  DomainHandler* = proc(topic, payload: string) {.gcsafe, raises: [].}

  EventBus* = ref object of RootObj
    subs: seq[tuple[id: int, pattern: string, handler: DomainHandler]]
    nextSubId: int

const cmdNone* = Command(0)

# Standard dialog commands (plan-4 D20). Negative so they never collide with
# an app's own (positive) command numbering.
const
  cmOk* = Command(-2)
  cmCancel* = Command(-3)
  cmYes* = Command(-4)
  cmNo* = Command(-5)

proc `==`*(a, b: Command): bool {.borrow.}
proc `$`*(c: Command): string {.borrow.}
proc `==`*(a, b: SubId): bool {.borrow.}

func matchTopic*(pattern, topic: string): bool =
  ## Exact match, or `prefix/*` prefix wildcard ("net/*" matches "net/peer").
  if pattern == topic or pattern == "*":
    return true
  pattern.endsWith("/*") and topic.startsWith(pattern[0 ..^ 2])

proc dispatchDomain*(bus: EventBus, topic, payload: string) {.gcsafe, raises: [].} =
  ## Deliver to every matching subscriber. Implementations call this from
  ## wherever their published events surface.
  for sub in bus.subs:
    if matchTopic(sub.pattern, topic):
      sub.handler(topic, payload)

method publish*(bus: EventBus, a: UiAction) {.base, gcsafe, raises: [].} =
  discard

method publishDomain*(bus: EventBus, topic: string, payload: string) {.base, gcsafe, raises: [].} =
  discard

method subscribeDomain*(bus: EventBus, pattern: string,
                        handler: DomainHandler): SubId {.base, gcsafe, raises: [].} =
  ## Subscribe to a topic (exact or `prefix/*`). Returns a handle for
  ## unsubscribe().
  inc bus.nextSubId
  bus.subs.add (bus.nextSubId, pattern, handler)
  SubId(bus.nextSubId)

method unsubscribe*(bus: EventBus, id: SubId) {.base, gcsafe, raises: [].} =
  for i in 0 ..< bus.subs.len:
    if bus.subs[i].id == int(id):
      bus.subs.delete(i)
      return

type
  StubBus* = ref object of EventBus
    ## Records everything published and dispatches to subscribers
    ## synchronously; backs the terminal-free unit tests.
    actions*: seq[UiAction]
    domain*: seq[tuple[topic, payload: string]]

proc newStubBus*(): StubBus =
  StubBus()

method publish*(bus: StubBus, a: UiAction) {.gcsafe, raises: [].} =
  bus.actions.add a

method publishDomain*(bus: StubBus, topic: string, payload: string) {.gcsafe, raises: [].} =
  bus.domain.add (topic, payload)
  bus.dispatchDomain(topic, payload)

type
  NullBus* = ref object of EventBus
    ## The default `app.bus` (plan-5 P30): tier-2 `UiAction`s go nowhere,
    ## domain topics dispatch to subscribers synchronously, nothing is
    ## recorded — a long-running app accumulates no history. Set
    ## `app.bus = newBrokersBus()` for real routing; tests that assert on
    ## publishes use `newStubBus()`.

proc newNullBus*(): NullBus =
  NullBus()

method publishDomain*(bus: NullBus, topic: string, payload: string) {.gcsafe, raises: [].} =
  bus.dispatchDomain(topic, payload)
