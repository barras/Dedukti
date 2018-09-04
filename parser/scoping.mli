open Basic
open Term
open Constsigntype

(** Scope managmement: from preterms to terms. *)
val scope_term : mident -> typed_context -> Preterm.preterm -> term
val scope_rule : mident -> Preterm.prule -> Rule.untyped_rule

type clos_env = (ident * const) list
val scope_clos_env :
  mident -> Preterm.clos_env -> clos_env
val scope_clos : clos_env -> loc * ident -> const
