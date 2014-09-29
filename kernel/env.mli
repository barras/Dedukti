open Basics
open Term

(** Global context management. *)

val ignore_redecl       : bool ref
val autodep             : bool ref

val get_name            : unit -> ident

module H : Hashtbl.S with type key := ident

type rw_infos = private
  | Decl    of term
  | Def     of term*term
  | Decl_rw of term*Rule.rule list*int*Rule.dtree

(** Initialize the global context. *)
val init                : ident -> unit

(** Create the dko file and clear the global context. *)
val export    : unit -> unit
val clear    : unit -> unit

(** [Env.get_infos l md id] returns the context infos corresponding to the
 constant symbol [id] in the module [md]. *)
val get_infos           : loc -> ident -> ident -> rw_infos

(** [Env.get_type l md id] returns the type of the constant symbol [id] in
 the module [md]. *)
val get_type            : loc -> ident -> ident -> term

(** [Env.add_decl l id ty] declares a constant symbol [id] of type [ty] in the
 the current module. *)
val add_decl            : loc -> ident -> term -> unit

(** [Env.add_def l id te ty] defines the alias [id] for the term [te] of type
  [ty] in the the current module. *)
val add_def             : loc -> ident -> term -> term -> unit

(** Add a list of rewrite rules in the context.
All these rules must have the same head symbol and the same arity. *)
val add_rw              : Rule.rule list -> unit

val marshal : ident -> string list -> rw_infos H.t -> unit

val unmarshal : loc -> string -> (string list*rw_infos H.t)

val get_all_rules : string -> (string*Rule.rule list) list