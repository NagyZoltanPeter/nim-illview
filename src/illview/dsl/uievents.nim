## uiEvents(T) — top-level companion of mount(T) (plan-2 D5): scans the
## same field pragmas and generates, per `emits: "Name"`, a nim-brokers
## EventBroker event type
##
##   Name = object
##     senderId*: int
##     <payload>          # Input/Editor: text, Checkbox: checked,
##                        # Radio/ListView/Table: selected; Button: none
##
## plus a `uiEmit(sender, Name)` snapshot emitter that mount() wires to the
## widget's primary slot. Per `bindRequest: "Name"` it generates a SYNC
## RequestBroker
##
##   proc Name*(value: VT): Result[VT, string]
##
## with a default identity provider (registered at module init unless one
## is already provided) — replace it via Name.replaceProvider for external
## validation/normalization (confirmed amendment to D4).
##
## Nim requires type generation at top level, which is why this cannot live
## inside mount(): call `uiEvents(MyForm)` right after the type section.

import std/macros
import results
import chronos
import brokers
import ./mount

export results, chronos, brokers

type UiPayloadKind = enum
  upNone, upText, upChecked, upSelected

func payloadKind(typeName: string): UiPayloadKind =
  case typeName
  of "Input", "Editor": upText
  of "Checkbox": upChecked
  of "Radio", "ListView", "Table": upSelected
  else: upNone

func valueTypeIdent(typeName: string): NimNode =
  case payloadKind(typeName)
  of upText: ident("string")
  of upChecked: ident("bool")
  of upSelected: ident("int")
  of upNone: nil

macro uiEvents*(T: typedesc): untyped =
  var sym = T.getTypeInst
  if sym.kind == nnkBracketExpr:
    sym = sym[1]
  let impl = sym.getImpl
  impl.expectKind nnkTypeDef
  var objTy = impl[2]
  if objTy.kind == nnkRefTy:
    objTy = objTy[0]
  let recList = objTy[2]

  result = newStmtList()
  for identDefs in recList:
    if identDefs.kind != nnkIdentDefs:
      continue
    let (_, fprag, ftyp) = fieldInfo(identDefs)
    let typeName = if ftyp.kind == nnkSym: ftyp.strVal else: ""
    let ftypId = ident(typeName)

    let emitsArg = pragmaArg(fprag, "emits")
    if emitsArg != nil:
      let evId = ident(emitsArg.strVal)
      let evName = emitsArg.strVal
      # event type via quote; uiEmit via parseStmt — quote would close
      # `emit` onto chronos' AsyncEventQueue.emit instead of leaving it open
      # for the broker-generated overload at the expansion site
      var payloadField, payloadCtor: string
      case payloadKind(typeName)
      of upText:
        result.add quote do:
          EventBroker:
            type `evId` = object
              senderId*: int
              text*: string
        payloadCtor = ", text: sender.text"
      of upChecked:
        result.add quote do:
          EventBroker:
            type `evId` = object
              senderId*: int
              checked*: bool
        payloadCtor = ", checked: sender.checked"
      of upSelected:
        result.add quote do:
          EventBroker:
            type `evId` = object
              senderId*: int
              selected*: int
        payloadCtor = ", selected: sender.selected"
      of upNone:
        result.add quote do:
          EventBroker:
            type `evId` = object
              senderId*: int
        payloadCtor = ""
      result.add parseStmt(
        "proc uiEmit*(sender: " & typeName & ", _: typedesc[" & evName &
        "]) {.gcsafe.} =\n  emit(" & evName & "(senderId: sender.id" &
        payloadCtor & "))")

    let reqArg = pragmaArg(fprag, "bindRequest")
    if reqArg != nil:
      let reqId = ident(reqArg.strVal)
      let vt = valueTypeIdent(typeName)
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
