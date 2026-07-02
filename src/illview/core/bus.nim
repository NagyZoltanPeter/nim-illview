## EventBus abstraction (§3.8). The real implementation wraps nim-brokers in
## Phase 6; until then everything codes against this + StubBus.
##
## `Command` lives here (not in events.nim as §3.5 sketches) because both the
## view layer and the bus need it and bus.nim is the dependency-free bottom.

type
  Command* = distinct int

  UiAction* = object
    cmd*: Command
    senderId*: int

  EventBus* = ref object of RootObj

const cmdNone* = Command(0)

proc `==`*(a, b: Command): bool {.borrow.}
proc `$`*(c: Command): string {.borrow.}

method publish*(bus: EventBus, a: UiAction) {.base, gcsafe.} =
  discard

method publishDomain*(bus: EventBus, topic: string, payload: string) {.base, gcsafe.} =
  discard

type
  StubBus* = ref object of EventBus
    ## Records everything published; backs unit tests for Phases 1-5.
    actions*: seq[UiAction]
    domain*: seq[tuple[topic, payload: string]]

proc newStubBus*(): StubBus =
  StubBus()

method publish*(bus: StubBus, a: UiAction) {.gcsafe.} =
  bus.actions.add a

method publishDomain*(bus: StubBus, topic: string, payload: string) {.gcsafe.} =
  bus.domain.add (topic, payload)
