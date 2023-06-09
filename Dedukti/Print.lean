import Dedukti.Types

deriving instance Repr for Lean.ConstantVal

deriving instance Repr for Lean.AxiomVal

deriving instance Repr for Lean.ReducibilityHints
deriving instance Repr for Lean.DefinitionVal

deriving instance Repr for Lean.TheoremVal

deriving instance Repr for Lean.OpaqueVal

deriving instance Repr for Lean.QuotKind
deriving instance Repr for Lean.QuotVal

deriving instance Repr for Lean.InductiveVal

deriving instance Repr for Lean.ConstructorVal

deriving instance Repr for Lean.RecursorRule
deriving instance Repr for Lean.RecursorVal

deriving instance Repr for Lean.ConstantInfo

namespace Dedukti

structure PrintCtx where
  env : Env
  lvl : Nat := 0
  deriving Inhabited
  
structure PrintState where
  printedConsts : Lean.HashSet Name := default
  out           : List String := []
  deriving Inhabited

abbrev PrintM := ReaderT PrintCtx $ StateT PrintState $ ExceptT String Id

def withResetPrintMLevel : PrintM α → PrintM α :=
  withReader fun ctx => { ctx with lvl := 0 }

def withNewPrintMLevel : PrintM α → PrintM α :=
  withReader fun ctx => { ctx with
    lvl := ctx.lvl + 1 }

def withSetPrintMLevel (lvl : Nat) : PrintM α → PrintM α :=
  withReader fun ctx => { ctx with lvl }

def dkExprNeedsAppParens : Expr → Bool
  | .var .. => false
  | .const .. => false
  | .fixme .. => true
  | .app .. => false
  | .lam .. => true
  | .pi .. => true -- should never happen but whatever
  | .type => false
  | .kind => false

def dkExprNeedsPiParens : Expr → Bool
  | .var .. => false
  | .const .. => false
  | .fixme .. => true
  | .app .. => true
  | .lam .. => true -- should never happen but whatever
  | .pi .. => true
  | .type => false
  | .kind => false

instance : ToString Name where toString name := name.toStringWithSep "_" false -- TODO what does the "escape" param do exactly?

mutual
  partial def Rule.print (rule : Rule) : PrintM String := do
    match rule with
    | .mk (vars : Nat) (lhs : Expr) (rhs : Expr) =>
      let mut varsStrings := []
      for i in [0:vars] do
        varsStrings := varsStrings ++ [s!"x{i}"]
      let varsString := ", ".intercalate varsStrings
      withSetPrintMLevel vars do
        pure s!"[{varsString}] {← lhs.print} --> {← rhs.print}."

  partial def Expr.print (expr : Expr) : PrintM String := do
    match expr with
    | .var (idx : Nat) => pure s!"x{(← read).lvl - (idx + 1)}"
    | .const (name : Name) =>
      if ! ((← get).printedConsts.contains name) then
        -- print this constant first to make sure the DAG of constant dependencies
        -- is correctly linearized upon printing the .dk file
        let some const := (← read).env.constMap.find? name | throw s!"could not find referenced constant \"{name}\""
        const.print
      pure $ toString name
    | .fixme (msg : String) => pure s!"Type (;{msg};)"
    | .app (fn : Expr) (arg : Expr) =>
      let fnExprString ← fn.print
      let fnString := if (dkExprNeedsAppParens fn) then s!"({fnExprString})" else fnExprString
      pure s!"{fnString} {← arg.print}"
    | .lam (bod : Expr) => pure s!"x{(← read).lvl} => {← withNewPrintMLevel $ bod.print}"
    | .pi (dom : Expr) (img : Expr) =>
      let domExprString ← dom.print
      let domString := if dkExprNeedsPiParens dom then s!"({domExprString})" else domExprString
      pure s!"x{(← read).lvl}:{domString} -> {← withNewPrintMLevel $ img.print}"
    | .type => pure "Type"
    | .kind => pure "Kind"

  partial def Const.print (const : Const) : PrintM PUnit := withResetPrintMLevel do
    if ((← get).printedConsts.contains const.name) then return

    -- mark this constant as printed to avoid infinite loops
    modify fun s => { s with printedConsts := s.printedConsts.insert const.name}

    let constString ← match const with
      | .static (name : Name) (type : Expr) => do pure s!"{name} : {← type.print}."
      | .definable (name : Name) (type : Expr) (rules : List Rule) => do
        let decl := s!"def {name} : {← type.print}."
        let rules := "\n".intercalate (← rules.mapM (·.print))
        pure s!"{decl}\n{rules}"

    modify fun s => { s with out := s.out ++ [constString] }

end
    
def Env.print (env : Env) : PrintM PUnit := do
  env.constMap.forM (fun _ const =>
    --dbg_trace s!"printing: {const.name}"
     const.print)

end Dedukti
