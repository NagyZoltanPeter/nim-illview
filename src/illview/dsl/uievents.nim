## uiEvents(T) — top-level companion of mount(T) (plan-2 D5): scans the
## same field pragmas and generates, per `emits: "Name"`, a nim-brokers
## EventBroker event type
##
##   Name = object
##     senderId*: int
##     <payload>          # by uiValueKind(FieldType), resolved at the
##                        # expansion site (deviation #29): upText -> text,
##                        # upChecked -> checked, upSelected -> selected,
##                        # upCheckState -> state,
##                        # upNone -> no payload. Stock overloads live in
##                        # dsl/mount.nim; a custom widget adds its own.
##
## plus a `uiEmit(sender, Name)` snapshot emitter that mount() wires to the
## widget's primary slot. The event fires on the sender's `sessionCtx` — the
## classCtx shared by every view (app-wide): the thread's global broker ctx
## unless the host installed or passed one (deviation #27) — so listeners
## subscribe with `Name.listen(v.sessionCtx, …)`. Per `bindRequest: "Name"`
## it generates a SYNC RequestBroker
##
##   proc Name*(value: VT): Result[VT, string]
##
## with a default identity provider (registered at module init unless one
## is already provided) — replace it via Name.replaceProvider for external
## validation/normalization (confirmed amendment to D4).
##
## Per `bindValue: "field"` it additionally generates the INVERSE writer
## (plan-3 D10, two-way binding):
##
##   proc set<Field>*(self: T, v: VT)   # store + Set-signal to the widget
##
## which writes the store field and signals the bound widget on its
## instance ctx (Input/Editor -> SetText, Checkbox -> SetChecked,
## TriStateCheckBox -> SetCheckState,
## Radio/ListView/Table -> SetSelected). The writer is authoritative: it
## deliberately BYPASSES any bindRequest provider, and — like all signal
## application — fires no change slots and re-emits nothing. Requires
## illview/vocab in scope at the callsite. (Explicit set<Field> naming, not
## a `field=` property: mount/uiEvents expand in the type's defining
## module, where direct field access would shadow a same-named setter.)
##
## Nim requires type generation at top level, which is why this cannot live
## inside mount(): call `uiEvents(MyForm)` right after the type section.

import std/[macros, strutils]
import results
import chronos
import brokers
import ./mount

export results, chronos, brokers

func valueTypeIdent(kind: UiPayloadKind): NimNode =
  case kind
  of upText: ident("string")
  of upChecked: ident("bool")
  of upSelected: ident("int")
  of upCheckState: ident("CheckState")
  of upNone: nil

proc viewRecList(T: NimNode): tuple[sym, recList: NimNode] =
  var sym = T.getTypeInst
  if sym.kind == nnkBracketExpr:
    sym = sym[1]
  let impl = sym.getImpl
  impl.expectKind nnkTypeDef
  var objTy = impl[2]
  if objTy.kind == nnkRefTy:
    objTy = objTy[0]
  (sym, objTy[2])

macro uiEventsImpl(T: typedesc, kinds: static seq[UiPayloadKind]): untyped =
  ## `kinds[i]` is uiValueKind(<type of the i-th field>), evaluated where
  ## uiEvents(T) was expanded, so user overloads count (deviation #29).
  let (sym, recList) = viewRecList(T)
  result = newStmtList()
  var fi = -1
  for identDefs in recList:
    if identDefs.kind != nnkIdentDefs:
      continue
    inc fi
    let kind = kinds[fi]
    let (fname, fprag, ftyp) = fieldInfo(identDefs)
    let typeName = if ftyp.kind == nnkSym: ftyp.strVal else: ""
    let ftypId = ident(typeName)

    let emitsArg = pragmaArg(fprag, "emits")
    if emitsArg != nil:
      let evId = ident(emitsArg.strVal)
      let evName = emitsArg.strVal
      # event type via quote; uiEmit via parseStmt — quote would close
      # `emit` onto chronos' AsyncEventQueue.emit instead of leaving it open
      # for the broker-generated overload at the expansion site. The payload
      # snapshot goes through widgetValue(sender) — the same overload point
      # bindValue uses — so it works for any widget, not only stock ones.
      var payloadCtor: string
      case kind
      of upText:
        result.add quote do:
          EventBroker:
            type `evId` = object
              senderId*: int
              text*: string
        payloadCtor = ", text: widgetValue(sender)"
      of upChecked:
        result.add quote do:
          EventBroker:
            type `evId` = object
              senderId*: int
              checked*: bool
        payloadCtor = ", checked: widgetValue(sender)"
      of upSelected:
        result.add quote do:
          EventBroker:
            type `evId` = object
              senderId*: int
              selected*: int
        payloadCtor = ", selected: widgetValue(sender)"
      of upCheckState:
        result.add quote do:
          EventBroker:
            type `evId` = object
              senderId*: int
              state*: CheckState
        payloadCtor = ", state: widgetValue(sender)"
      of upNone:
        result.add quote do:
          EventBroker:
            type `evId` = object
              senderId*: int
        payloadCtor = ""
      result.add parseStmt(
        "proc uiEmit*(sender: " & typeName & ", _: typedesc[" & evName &
        "]) {.gcsafe.} =\n  emit(" & evName & ", sender.sessionCtx, " & evName &
        "(senderId: sender.id" & payloadCtor & "))")

    let reqArg = pragmaArg(fprag, "bindRequest")
    if reqArg != nil:
      let reqId = ident(reqArg.strVal)
      let vt = valueTypeIdent(kind)
      if vt == nil:
        error("bindRequest: field type '" & typeName &
              "' has no bindable value", reqArg)
      # built with plain idents: the broker macro pattern-matches the
      # signature AST and rejects quote-bound Result syms
      let resultTy = newTree(nnkBracketExpr, ident("Result"), vt,
                             ident("string"))
      var sigProc = newProc(
        name = postfix(reqId, "*"),
        params = [resultTy, newIdentDefs(ident("value"), copyNimTree(vt))],
        body = newEmptyNode())
      result.add newCall(ident("RequestBroker"), ident("sync"),
                         newStmtList(sigProc))
      result.add quote do:
        if not isProvided(`reqId`):
          discard setProvider(`reqId`,
            proc(value: `vt`): Result[`vt`, string] = ok(value))

    # two-way binding writer (plan-3 D10): set<Field> = store + Set-signal.
    # Built with parseStmt so SetText/SetChecked/SetSelected stay raw and
    # bind to illview/vocab at the expansion site (same trap as uiEmit).
    let bindValArg = pragmaArg(fprag, "bindValue")
    if bindValArg != nil and bindValArg.kind in {nnkStrLit, nnkRStrLit}:
      let (sigName, sigField, vtName) =
        case kind
        of upText: ("SetText", "text", "string")
        of upChecked: ("SetChecked", "checked", "bool")
        of upSelected: ("SetSelected", "selected", "int")
        of upCheckState: ("SetCheckState", "state", "CheckState")
        of upNone: ("", "", "")
      if sigName.len == 0:
        error("bindValue: field type '" & typeName &
              "' has no Set-signal for a set<Field> writer", bindValArg)
      # "field" or "model.field" (deviation #30): the store path is used as-is,
      # the writer/notifier names come from the last segment
      let storeName = bindValArg.strVal
      let procStem = capitalizeAscii(storeName.rsplit('.', maxsplit = 1)[^1])
      let sigCall = "discard " & sigName & ".signal(self." & $fname &
                    ".brokerCtx, " & sigName & "(" & sigField & ": "
      result.add parseStmt(
        "proc set" & procStem & "*(self: " & sym.strVal &
        ", v: " & vtName & ") {.gcsafe, raises: [].} =\n" &
        "  {.cast(gcsafe).}:\n" &
        "    self." & storeName & " = v\n" &
        "    " & sigCall & "v))")
      # notify<Field>: the store was mutated directly; push it to the widget
      result.add parseStmt(
        "proc notify" & procStem & "*(self: " & sym.strVal &
        ") {.gcsafe, raises: [].} =\n" &
        "  {.cast(gcsafe).}:\n" &
        "    " & sigCall & "self." & storeName & "))")

macro uiEvents*(T: typedesc): untyped =
  ## Top-level companion of mount(T): expands to `uiEventsImpl(T, kinds)`
  ## where `kinds` holds `uiValueKind(FieldType)` per record field, so the
  ## value shape of every child is decided by overloads in scope HERE.
  let (_, recList) = viewRecList(T)
  var kinds = nnkBracket.newTree()
  for identDefs in recList:
    if identDefs.kind != nnkIdentDefs:
      continue
    let (_, _, ftyp) = fieldInfo(identDefs)
    let ftypId = if ftyp.kind == nnkSym: ident(ftyp.strVal) else: ftyp
    kinds.add newCall(ident("uiValueKind"), ftypId)
  result = newCall(bindSym("uiEventsImpl"), T, nnkPrefix.newTree(ident("@"), kinds))
