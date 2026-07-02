## Phase 9 exit criteria: bindValue keeps enclosing-view fields current;
## bindRequest routes updates through a replaceable sync RequestBroker
## provider; emits: auto-generated typed broker events fire on activation;
## the opened bus (subscribe + wildcards) works on StubBus and BrokersBus.

import std/[unittest, strutils]
import chronos
import ../src/illview/core/[geometry, events, bus, view, routing]
import ../src/illview/widgets/[window, checkbox, input, button]
import ../src/illview/dsl/pragmas
import ../src/illview/dsl/mount
import ../src/illview/dsl/uievents
import ../src/illview/bus_brokers

var handlerLog: seq[string]

type
  BoundForm {.view, vbox.} = ref object of Group
    name {.child, bindValue: "nameVal", bindTo: "onNameSubmit".}: Input
    accept {.child, bindValue: "acceptVal".}: Checkbox
    port {.child, bindValue: "portVal", bindRequest: "SetPort".}: Input
    run {.child, caption: "Run", emits: "RunClicked".}: Button
    submit {.child, caption: "Go", emits: "FormSubmitted".}: Input
    nameVal: string
    acceptVal: bool
    portVal: string

uiEvents(BoundForm)

proc onNameSubmit(self: BoundForm, sender: Input) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    handlerLog.add "submit:" & self.nameVal # store must run before bindTo

proc typeText(root: Group, s: string) =
  for c in s:
    discard dispatchKey(root, keyEvent(Key.None, Rune(c)))

suite "bindValue / bindRequest (plan-2 D4)":
  setup:
    handlerLog.setLen(0)
    let root = newGroup()
    root.bounds = rect(0, 0, 60, 20)
    let form = mount(BoundForm)
    form.dock = dkFill
    root.add form
    root.arrangeChildren()

  test "widget -> field, store runs before the bindTo handler":
    setFocus(root, form.name)
    typeText(root, "waku")
    check form.nameVal == "waku"
    discard dispatchKey(root, keyEvent(Key.Enter))
    check handlerLog == @["submit:waku"] # field already stored at handler time

  test "checkbox binds bool":
    setFocus(root, form.accept)
    discard dispatchKey(root, keyEvent(Key.Space))
    check form.acceptVal == true
    discard dispatchKey(root, keyEvent(Key.Space))
    check form.acceptVal == false

  test "bindRequest: default identity provider stores via the broker":
    setFocus(root, form.port)
    typeText(root, "8080")
    check form.portVal == "8080"

  test "bindRequest: replaced provider normalizes / vetoes":
    check SetPort.replaceProvider(DefaultBrokerContext,
      proc(value: string): Result[string, string] =
        if value.len > 2:
          err("too long") # veto: field keeps its previous value
        else:
          ok("p:" & value)).isOk # normalize
    setFocus(root, form.port)
    typeText(root, "42")
    check form.portVal == "p:42" # normalized by the provider
    typeText(root, "000")       # now "42000" etc: provider vetoes
    check form.portVal == "p:42" # unchanged after veto
    SetPort.clearProvider()

suite "emits: auto-generated typed events (plan-2 D5)":
  test "button activation emits RunClicked with senderId":
    var got: seq[int]
    check RunClicked.listen(
      proc(ev: RunClicked): Future[void] {.async: (raises: []), gcsafe.} =
        {.cast(gcsafe).}:
          got.add ev.senderId).isOk
    let root = newGroup()
    root.bounds = rect(0, 0, 60, 20)
    let form = mount(BoundForm)
    root.add form
    setFocus(root, form.run)
    discard dispatchKey(root, keyEvent(Key.Enter))
    waitFor sleepAsync(10.milliseconds)
    check got == @[form.run.id]
    waitFor RunClicked.dropAllListeners()

  test "input submit emits FormSubmitted with the text payload":
    var got: seq[string]
    check FormSubmitted.listen(
      proc(ev: FormSubmitted): Future[void] {.async: (raises: []), gcsafe.} =
        {.cast(gcsafe).}:
          got.add ev.text).isOk
    let root = newGroup()
    root.bounds = rect(0, 0, 60, 20)
    let form = mount(BoundForm)
    root.add form
    setFocus(root, form.submit)
    typeText(root, "hi")
    discard dispatchKey(root, keyEvent(Key.Enter))
    waitFor sleepAsync(10.milliseconds)
    check got == @["Gohi"] # caption "Go" is the initial text, "hi" typed
    waitFor FormSubmitted.dropAllListeners()

suite "opened bus: subscribe + wildcards (plan-2 D6)":
  test "topic matching rules":
    check matchTopic("net/peer", "net/peer")
    check matchTopic("net/*", "net/peer")
    check matchTopic("net/*", "net/relay/push")
    check matchTopic("*", "anything")
    check not matchTopic("net/*", "store/query")
    check not matchTopic("net/peer", "net/relay")

  test "StubBus: subscribe, wildcard, unsubscribe (synchronous)":
    let bus: EventBus = newStubBus()
    var got: seq[string]
    let idAll = bus.subscribeDomain("net/*",
      proc(t, p: string) {.gcsafe, raises: [].} =
        {.cast(gcsafe).}: got.add "net:" & t)
    discard bus.subscribeDomain("store/query",
      proc(t, p: string) {.gcsafe, raises: [].} =
        {.cast(gcsafe).}: got.add "store:" & p)
    bus.publishDomain("net/peer", "x")
    bus.publishDomain("store/query", "12 msgs")
    bus.publishDomain("other", "ignored")
    check got == @["net:net/peer", "store:12 msgs"]
    bus.unsubscribe(idAll)
    bus.publishDomain("net/peer", "y")
    check got.len == 2

  test "BrokersBus: subscription rides the real broker loop":
    let bus: EventBus = newBrokersBus()
    var got: seq[string]
    discard bus.subscribeDomain("viz/*",
      proc(t, p: string) {.gcsafe, raises: [].} =
        {.cast(gcsafe).}: got.add t & "=" & p)
    bus.publishDomain("viz/peer", "up")
    bus.publishDomain("nomatch", "z")
    waitFor sleepAsync(10.milliseconds)
    check got == @["viz/peer=up"]
