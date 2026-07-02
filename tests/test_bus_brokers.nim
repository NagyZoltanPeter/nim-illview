## Phase 6: BrokersBus over the real nim-brokers single-thread EventBroker.
## publish/publishDomain -> emit -> listeners fire on the same chronos loop.

import std/[unittest, tables]
import chronos
import results
import ../src/illview/core/bus
import ../src/illview/bus_brokers
import ../src/illview/widgets/netviz

suite "BrokersBus":
  test "UiAction round-trips through the broker":
    var got: seq[UiAction]
    check IvUiAction.listen(
      proc(ev: IvUiAction): Future[void] {.async: (raises: []), gcsafe.} =
        {.cast(gcsafe).}:
          got.add UiAction(cmd: Command(ev.cmd), senderId: ev.senderId)).isOk
    let bus: EventBus = newBrokersBus()
    bus.publish(UiAction(cmd: Command(7), senderId: 99))
    waitFor sleepAsync(10.milliseconds) # let the asyncSpawn'd notify run
    check got.len == 1
    check got[0].cmd == Command(7)
    check got[0].senderId == 99

  test "domain events fan out to a NetVizWidget with no input plumbing":
    let nv = newNetVizWidget()
    check onDomainEvent(
      proc(topic, payload: string) {.gcsafe, raises: [].} =
        {.cast(gcsafe).}:
          nv.addEvent(topic, payload)).isOk
    let bus: EventBus = newBrokersBus()
    bus.publishDomain("peer", "connected 16Uiu2...")
    bus.publishDomain("msg", "relay push 1.2kB")
    bus.publishDomain("peer", "disconnected")
    waitFor sleepAsync(10.milliseconds)
    check nv.total == 3
    check nv.perTopic["peer"] == 2
    check nv.perTopic["msg"] == 1
    check nv.lines.len == 3
    check nv.lines[1] == "[msg] relay push 1.2kB"
