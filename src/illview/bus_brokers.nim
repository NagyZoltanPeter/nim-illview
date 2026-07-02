## Real nim-brokers EventBus implementation (Phase 6, §3.8).
##
## Uses the single-thread EventBroker (default mode): emit() asyncSpawns the
## listener notification on the SAME chronos loop illview runs on — no
## threads, no marshaling, matching prime directive §0.1. Two broker event
## types carry the illview traffic:
##   IvUiAction   — tier-2 widget actions (UiAction publish)
##   IvDomainEvent — topic/payload domain events (network etc.)
##
## Subscribe with onUiAction / onDomainEvent (thin sync wrappers over the
## generated async listen()).

import results
import chronos
import brokers
import ./core/bus

export bus

EventBroker:
  type IvUiAction* = object
    cmd*: int
    senderId*: int

EventBroker:
  type IvDomainEvent* = object
    topic*: string
    payload*: string

type
  BrokersBus* = ref object of EventBus
    listening: bool # IvDomainEvent.listen registered for subscriber dispatch

proc newBrokersBus*(): BrokersBus =
  BrokersBus()

method subscribeDomain*(bus: BrokersBus, pattern: string,
                        handler: DomainHandler): SubId {.gcsafe, raises: [].} =
  ## Subscriptions ride ONE broker listener (registered lazily): domain
  ## events published by anyone — this bus or other IvDomainEvent emitters —
  ## fan out to matching illview subscribers on the chronos loop.
  if not bus.listening:
    let res = IvDomainEvent.listen(
      proc(ev: IvDomainEvent): Future[void] {.async: (raises: []), gcsafe.} =
        bus.dispatchDomain(ev.topic, ev.payload))
    if res.isOk:
      bus.listening = true
  procCall subscribeDomain(EventBus(bus), pattern, handler)

method publish*(bus: BrokersBus, a: UiAction) {.gcsafe, raises: [].} =
  emit(IvUiAction(cmd: int(a.cmd), senderId: a.senderId))

method publishDomain*(bus: BrokersBus, topic: string,
                      payload: string) {.gcsafe, raises: [].} =
  emit(IvDomainEvent(topic: topic, payload: payload))

proc onUiAction*(handler: proc(a: UiAction) {.gcsafe, raises: [].}):
    Result[IvUiActionListener, string] =
  IvUiAction.listen(
    proc(ev: IvUiAction): Future[void] {.async: (raises: []), gcsafe.} =
      handler(UiAction(cmd: Command(ev.cmd), senderId: ev.senderId)))

proc onDomainEvent*(handler: proc(topic, payload: string) {.gcsafe, raises: [].}):
    Result[IvDomainEventListener, string] =
  IvDomainEvent.listen(
    proc(ev: IvDomainEvent): Future[void] {.async: (raises: []), gcsafe.} =
      handler(ev.topic, ev.payload))
