
open Types

(* *** Global Options *** *)

val name        : ident ref
val out         : out_channel ref
val quiet       : bool ref
val export      : bool ref
val raphael     : bool ref

val set_name    : string -> unit 
val set_out     : string -> unit 

(* *** Info messages *** *)

val sprint      : string -> unit                        (* Print a string on standard output *)
val eprint      : string -> unit                        (* Print a string on standard error *)
val vprint      : string Lazy.t -> unit                        (* Print a string on standard output if in verbose mode *)
val error       : loc -> string -> string -> unit       (* Print an error message and exit *)

