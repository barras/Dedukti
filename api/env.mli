(** The main functionalities of Dedukti:
    This is essentialy a wrapper around Signature, Typing and Reduction *)
open Basic
open Term

(** {2 Error Datatype} *)

type env_error =
  | EnvErrorType        of Typing.typing_error
  | EnvErrorSignature   of Signature.signature_error
  | NonLinearRule       of name
  | NotEnoughArguments  of ident * int * int * int
  | KindLevelDefinition of ident
  | ParseError          of string
  | AssertError

exception EnvError of loc * env_error

val check_arity     : bool ref
(** Flag to check for variables arity. Default is true. *)

(** {2 The Global Environment} *)

val init        : string -> mident
(** [init name] initializes a new global environement giving it the name of
    the corresponding source file. The function returns the module identifier
    corresponding to this file, built from its basename. Every toplevel
    declaration will be qualified by this name. *)

val get_signature : unit -> Signature.t
(** [get_signature ()] returns the signature used by this module. *)

val get_name    : unit -> mident
(** [get_name ()] returns the name of the module. *)

val get_type    : loc -> name -> term
(** [get_type l md id] returns the type of the constant [md.id]. *)

val is_static   : loc -> name -> bool
(** [is_static l cst] returns [true] if the symbol is declared as [static], [false] otherwise *)

val get_dtree   : loc -> name -> Dtree.t
(** [get_dtree l md id] returns the decision/matching tree associated with [md.id]. *)

val export      : unit -> unit
(** [export ()] saves the current environment in a [*.dko] file. *)

val import      : loc -> mident -> unit
(** [import lc md] the module [md] in the current environment. *)

val declare     : loc -> ident -> Signature.staticity -> term -> unit
(** [declare_constant l id st ty] declares the symbol [id] of type [ty] and
   staticity [st]. *)

val define      : loc -> ident -> bool -> term -> term option -> unit
(** [define l id body ty] defined the symbol [id] of type [ty] to be an alias of [body]. *)

val add_rules   : Rule.untyped_rule list -> (Subst.Subst.t * Rule.typed_rule) list
(** [add_rules rule_lst] adds a list of rule to a symbol. All rules must be on the
    same symbol. *)

(** {2 Type checking/inference} *)

val infer : ?ctx:typed_context -> term         -> term
(** [infer ctx term] infers the type of [term] given the typed context [ctx] *)

val check : ?ctx:typed_context -> term -> term -> unit
(** [infer ctx te ty] checks that [te] is of type [ty] given the typed context [ctx] *)

(** {2 Safe Reduction/Conversion} *)
(** terms are typechecked before the reduction/conversion *)

val reduction : ?ctx:typed_context -> ?red:(Reduction.red_cfg) -> term -> term
(** [reduction ctx red te] checks first that [te] is well-typed then reduces it
    according to the reduction configuration [red] *)

val are_convertible : ?ctx:typed_context -> term -> term -> bool
(** [are_convertible ctx tl tr] checks first that [tl] [tr] have the same type,
    and then that they are convertible *)

val unsafe_reduction : ?red:(Reduction.red_cfg) -> term -> term
(** [unsafe_reduction red te] reduces [te] according to the reduction configuration [red] *)
