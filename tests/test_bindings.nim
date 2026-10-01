## Phase 9 exit criteria: bindValue keeps enclosing-view fields current;
## bindRequest routes updates through a replaceable sync RequestBroker
## provider; emits: auto-generated typed broker events fire on activation;
## the opened bus (subscribe + wildcards) works on StubBus and BrokersBus.

import std/[unittest, strutils]
import chronos
import ../src/illview/core/[geometry, events, bus, view, routing, app]
import ../src/illview/widgets/[window, checkbox, input, button]
import ../src/illview/dsl/pragmas
import ../src/illview/dsl/mount
import ../src/illview/dsl/uievents
import ../src/illview/bus_brokers
import ../src/illview/vocab # set<Field> writers signal on instance ctxs (D10)

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

# --- set<Field> writers (plan-3 D10) --------------------------------------------

suite "set<Field> writers (plan-3 D10)":
  setup:
    handlerLog.setLen(0)
    let root = newGroup()
    root.bounds = rect(0, 0, 60, 20)
    let form = mount(BoundForm)
    form.dock = dkFill
    root.add form
    root.arrangeChildren()

  test "setter writes the store AND the widget; nothing re-emits":
    var edits: seq[string]
    check TextChanged.listen(form.name.brokerCtx,
      proc(ev: TextChanged): Future[void] {.async: (raises: []), gcsafe.} =
        {.cast(gcsafe).}: edits.add ev.text).isOk

    form.setNameVal("nimbus")
    waitFor sleepAsync(5.milliseconds)
    check form.nameVal == "nimbus"
    check form.name.text == "nimbus"
    check edits.len == 0 # signal apply must not re-emit TextChanged

    # user edit still emits exactly once and stores via bindValue
    setFocus(root, form.name)
    discard dispatchKey(root, keyEvent(Key.None, Rune('!')))
    waitFor sleepAsync(5.milliseconds)
    check form.nameVal == "nimbus!"
    check edits == @["nimbus!"]

    waitFor TextChanged.dropAllListeners(form.name.brokerCtx)
    dispose(form)

  test "bool setter drives the checkbox":
    form.setAcceptVal(true)
    waitFor sleepAsync(5.milliseconds)
    check form.acceptVal == true
    check form.accept.checked == true
    dispose(form)

  test "setter bypasses the bindRequest provider (writer is authoritative)":
    check SetPort.replaceProvider(DefaultBrokerContext,
      proc(value: string): Result[string, string] =
        err("always veto")).isOk
    form.setPortVal("9000") # provider must NOT run: no veto possible
    waitFor sleepAsync(5.milliseconds)
    check form.portVal == "9000"
    check form.port.text == "9000"
    SetPort.clearProvider()
    dispose(form)

suite "emits: auto-generated typed events (plan-2 D5)":
  test "button activation emits RunClicked on the session ctx (== the thread's global ctx)":
    var got: seq[int]
    let root = newGroup()
    root.bounds = rect(0, 0, 60, 20)
    let form = mount(BoundForm)
    root.add form
    # emits: fires on the view's session ctx (shared classCtx, instance 0). On a
    # bare thread that IS the thread's global broker ctx — the UI shares the
    # scope its host process keys on (deviation #27).
    check form.sessionCtx == globalBrokerContext()
    check RunClicked.listen(form.sessionCtx,
      proc(ev: RunClicked): Future[void] {.async: (raises: []), gcsafe.} =
        {.cast(gcsafe).}:
          got.add ev.senderId).isOk
    setFocus(root, form.run)
    discard dispatchKey(root, keyEvent(Key.Enter))
    waitFor sleepAsync(10.milliseconds)
    check got == @[form.run.id]
    waitFor RunClicked.dropAllListeners(form.sessionCtx)

  test "input submit emits FormSubmitted with the text payload":
    var got: seq[string]
    let root = newGroup()
    root.bounds = rect(0, 0, 60, 20)
    let form = mount(BoundForm)
    root.add form
    check FormSubmitted.listen(form.sessionCtx,
      proc(ev: FormSubmitted): Future[void] {.async: (raises: []), gcsafe.} =
        {.cast(gcsafe).}:
          got.add ev.text).isOk
    setFocus(root, form.submit)
    typeText(root, "hi")
    discard dispatchKey(root, keyEvent(Key.Enter))
    waitFor sleepAsync(10.milliseconds)
    check got == @["Gohi"] # caption "Go" is the initial text, "hi" typed
    waitFor FormSubmitted.dropAllListeners(form.sessionCtx)

  test "a user-installed session ctx sandboxes emits (setThreadBrokerContext)":
    let uiCtx = NewBrokerContext()   # a saved/sandbox context
    setThreadBrokerContext(uiCtx)    # install it for this thread
    var got: seq[int]
    var gotDefault: seq[int]
    let root = newGroup()
    root.bounds = rect(0, 0, 60, 20)
    let form = mount(BoundForm)      # views built now hang off uiCtx
    root.add form
    check form.sessionCtx == uiCtx   # the session ctx IS the installed one
    check RunClicked.listen(uiCtx,   # listen on the saved ctx directly
      proc(ev: RunClicked): Future[void] {.async: (raises: []), gcsafe.} =
        {.cast(gcsafe).}:
          got.add ev.senderId).isOk
    # a listener on the global default ctx must receive nothing: isolation
    check RunClicked.listen(
      proc(ev: RunClicked): Future[void] {.async: (raises: []), gcsafe.} =
        {.cast(gcsafe).}:
          gotDefault.add ev.senderId).isOk
    setFocus(root, form.run)
    discard dispatchKey(root, keyEvent(Key.Enter))
    waitFor sleepAsync(10.milliseconds)
    check got == @[form.run.id]
    check gotDefault.len == 0
    waitFor RunClicked.dropAllListeners(uiCtx)
    waitFor RunClicked.dropAllListeners()
    setThreadBrokerContext(DefaultBrokerContext) # restore for other tests

suite "session ctx resolution (deviation #27)":
  test "newApp adopts the thread's global ctx and never installs one":
    let hostCtx = NewBrokerContext()
    setThreadBrokerContext(hostCtx)  # what a host process (a node) already did
    let app = newApp()
    check app.sessionCtx == hostCtx
    check threadGlobalBrokerContext() == hostCtx # untouched by newApp
    let form = mount(BoundForm)
    check form.sessionCtx == hostCtx
    setThreadBrokerContext(DefaultBrokerContext)

  test "newApp on a bare thread lands on DefaultBrokerContext":
    let app = newApp()
    check app.sessionCtx == DefaultBrokerContext
    check threadGlobalBrokerContext() == DefaultBrokerContext
    var got: seq[int]
    let root = newGroup()
    root.bounds = rect(0, 0, 60, 20)
    let form = mount(BoundForm)
    root.add form
    check RunClicked.listen(         # a plain default-ctx listener hears it
      proc(ev: RunClicked): Future[void] {.async: (raises: []), gcsafe.} =
        {.cast(gcsafe).}:
          got.add ev.senderId).isOk
    setFocus(root, form.run)
    discard dispatchKey(root, keyEvent(Key.Enter))
    waitFor sleepAsync(10.milliseconds)
    check got == @[form.run.id]
    waitFor RunClicked.dropAllListeners()

  test "an explicit sessionCtx binds views without touching the thread ctx":
    let mine = NewBrokerContext()
    let app = newApp(sessionCtx = mine)
    check app.sessionCtx == mine
    check threadGlobalBrokerContext() == DefaultBrokerContext
    check mount(BoundForm).sessionCtx == mine
    # a later plain newApp drops the binding: views follow the global ctx again
    let app2 = newApp()
    check app2.sessionCtx == DefaultBrokerContext
    check mount(BoundForm).sessionCtx == DefaultBrokerContext

# --- bindValue on an external model (deviation #30) --------------------------------

type
  FormModel = ref object
    name: string
    accept: bool
  ModelForm {.view, vbox.} = ref object of Group
    name {.child, bindValue: "model.name".}: Input
    accept {.child, bindValue: "model.accept".}: Checkbox
    model: FormModel

uiEvents(ModelForm)

suite "bindValue on an external model (deviation #30)":
  test "store on the model; set<Field> and notify<Field> drive the widget":
    let form = mount(ModelForm)
    form.model = FormModel()
    let root = newGroup()
    root.bounds = rect(0, 0, 60, 20)
    root.add form
    root.arrangeChildren()
    setFocus(root, form.name)
    typeText(root, "waku")
    check form.model.name == "waku"        # widget -> model
    form.setName("nimbus")                 # writer: model + widget
    waitFor sleepAsync(5.milliseconds)
    check form.model.name == "nimbus"
    check form.name.text == "nimbus"
    form.model.name = "direct"             # model mutated behind our back
    form.notifyName()                      # ... re-synced on request
    form.model.accept = true
    form.notifyAccept()
    waitFor sleepAsync(5.milliseconds)
    check form.name.text == "direct"
    check form.accept.checked
    dispose(form)

# --- third-party widget joining bindValue/emits (deviation #29) --------------------

type Dialish = ref object of View
  value: int
  onTurn: proc(sender: Dialish) {.gcsafe, raises: [].}

proc newDialish(): Dialish =
  result = Dialish()
  initView(result)
  let d = result
  d.installSignal(SetSelected):
    d.value = sig.selected

proc turn(d: Dialish, v: int) =
  d.value = v
  if d.onTurn != nil:
    d.onTurn(d)

# the extension contract (docs/EXTENDING.md §3), all resolved at this site
proc createView(t: typedesc[Dialish]): Dialish = newDialish()
template uiValueKind(t: typedesc[Dialish]): UiPayloadKind = upSelected
proc widgetValue(w: Dialish): int = w.value
proc bindSlot(w: Dialish, h: proc(sender: Dialish) {.gcsafe, raises: [].}) =
  w.onTurn = chain(w.onTurn, h)
proc bindValueSlot(w: Dialish, h: proc(sender: Dialish) {.gcsafe, raises: [].}) =
  w.onTurn = chain(w.onTurn, h)

type DialForm {.view, vbox.} = ref object of Group
  dial {.child, bindValue: "dialVal", emits: "DialTurned".}: Dialish
  dialVal: int

uiEvents(DialForm)

suite "third-party widget joins bindValue/emits (deviation #29)":
  test "uiValueKind overload: typed payload, store and set<Field> writer":
    let form = mount(DialForm)
    var got: seq[int]
    check DialTurned.listen(form.sessionCtx,
      proc(ev: DialTurned): Future[void] {.async: (raises: []), gcsafe.} =
        {.cast(gcsafe).}:
          got.add ev.selected).isOk
    form.dial.turn(7)          # user path: bindValue store, then emits
    waitFor sleepAsync(10.milliseconds)
    check form.dialVal == 7
    check got == @[7]
    form.setDialVal(3)         # writer: store + SetSelected to the widget
    waitFor sleepAsync(10.milliseconds)
    check form.dial.value == 3
    waitFor DialTurned.dropAllListeners(form.sessionCtx)
    dispose(form)

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
