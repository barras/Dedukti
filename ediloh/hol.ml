open Basic

let compile_proofs = ref true

(* TODO: suppress ctx in the last translation *)
type name = ident * ident

type _ty =
  | VarTy of ident
  | Arrow of _ty * _ty
  | OpType of name * _ty list
  | Bool

type ty =
  | ForallK of ident * ty
  | Type of _ty

type _term =
  | Forall of ident * _ty * _term
  | Impl of _term * _term
  | VarTerm of ident * _ty
  | Const of name * _ty
  | App of _term * _term list
  | Lam of ident * _ty * _term

let mk_App f args =
  match f with
    | App (f',args') -> App (f',args'@args)
    | _ -> App(f,args)

type term =
  | ForallT of ident * term
  | Term of _term

type rw_ctx = (ident * term)

type ty_ctx = Basic.ident list

type term_ctx = (Basic.ident * ty) list

type ty_subst = (Basic.ident * _ty) list

type te_subst = (Basic.ident * _term) list

type proof_ctx = (Basic.ident * term) list

type _proof =
  | Lemma of name * term * ty_subst
  | Assume of _term * ty_subst
  | ForallI of ident * _ty * _prooft
  | ImplI of _term * _prooft
  | ForallE of _prooft * _term
  | ImplE of _prooft * _prooft
  | DeltaU of name * rw_ctx * _prooft
  | BetaU of term * rw_ctx * term



and _prooft =
  {
    _term:_term;
    _proof:_proof;
  }

type proof =
  | ForallP of ident * prooft
  | DeltaF of name * rw_ctx * prooft
  | BetaF of term * rw_ctx * term
  | Proof of _prooft

and prooft =
  {
    term:term;
    proof:proof;
  }

type obj =
  | Cst of name * ty * term option
  | TyOp of name * _ty list
  | Thm of name * term * prooft option



type decl = loc * ident * Term.term

type compile_type_err = TypeError of Term.term

type compile_term_err = TermError of Term.term | UntypedLambda of Term.term

type compile_decl_err =
  | DeclarationError of decl
  | DeclarationTypeError of compile_type_err * decl
  | DeclarationTermError of compile_term_err * decl

type compile_proof_err = ProofError of Term.term

type compile_defn_err =
  | DefinitionError of decl * Term.term
  | DefinitionTypeError of compile_type_err * decl * Term.term
  | DefinitionTermError of compile_term_err * decl * Term.term
  | DefinitionProofError of compile_proof_err * decl * Term.term

let print_name out (md,id) =
  Format.fprintf out "%a.%a" Pp.print_ident md Pp.print_ident id

(* FIXME: printing is won't work to print dedukti code. Some parenthesis are missing but right now it is only used for debugging *)
let rec print_hol__type out ty =
  match ty with
  | VarTy id -> Format.fprintf out "%a " Pp.print_ident id
  | Arrow(tyl,tyr) -> Format.fprintf out "hol.arrow (%a) (%a)" print_hol__type tyl print_hol__type tyr
  | OpType(name,tys) -> Format.fprintf out "%a %a"
                          print_name name (Pp.print_list " " print_hol__type) tys
  | Bool -> Format.fprintf out "hol.prop"

let rec print_hol_type out ty =
  match ty with
  | ForallK(var,ty) -> Format.fprintf out "hol.forall_kind_type (%a:hol.type => %a)"
                         Pp.print_ident var print_hol_type ty
  | Type(ty) -> print_hol__type out ty

let print_ty_subst out subst =
  let print_item out (id,_ty) =
    Format.fprintf out "%a[%a]" Pp.print_ident id print_hol__type _ty
  in
  Format.fprintf out "%a" (Pp.print_list "@." print_item) subst

let rec print_hol__term out te =
  match te with
  | Forall (id, _ty, _te) ->
    Format.printf "hol.forall (%a) (%a:(hol.eta (%a)) => %a)" print_hol__type _ty Pp.print_ident id print_hol__type _ty print_hol__term  _te
  | Impl (tel,ter) ->
    Format.printf "hol.impl (%a) (%a)" print_hol__term tel print_hol__term ter
  | App(_te,_tes) ->
    Format.printf "%a %a" print_hol__term _te (Pp.print_list " " print_hol__term) _tes
  | VarTerm(id,_ty) ->
    Format.printf "%a" Pp.print_ident id
  | Const((md,id),_ty) ->
    Format.printf "%a.%a" Pp.print_ident md Pp.print_ident id
  | Lam(id, _ty, _te) ->
    Format.printf "( %a :(%a) => %a)" Pp.print_ident id print_hol__type _ty print_hol__term  _te

let rec print_hol_term out te =
  match te with
  | ForallT(id, te) ->
    Format.printf "hol.forall_kind_type (%a: hol.type => %a)" Pp.print_ident id print_hol_term te
  | Term te -> print_hol__term out te

exception CompileTypeError of compile_type_err

exception CompileTermError of compile_term_err

exception CompileProofError of compile_proof_err

let hol_module = hstring "hol"
let hol_type = hstring "type"
let hol_eta = hstring "eta"
let hol_arrow = hstring "arrow"
let hol_forall = hstring "forall"
let hol_impl = hstring "impl"
let hol_prop = hstring "prop"
let hol_eps = hstring "eps"
let hol_forall_kind_type = hstring "forall_kind_type"
let hol_forall_kind_prop = hstring "forall_kind_prop"

let (===) = Basic.ident_eq

let is_hol_const c t =
  match t with
  | Term.Const(_, m, id) -> (m === hol_module) &&  (c === id)
  | _ -> false

let is_type t =
  match t with
  | Term.App(cst, ty, _) when is_hol_const hol_eta cst -> true
  | _ -> false

let is_term t =
  match t with
  | Term.App(cst, ty, _) when is_hol_const hol_eps cst -> true
  | _ -> false


let rec poly_subst_ty (subst:ty_subst) (ty:ty) : _ty =
  match ty with
  | ForallK(var, ty') ->
    assert(List.mem_assoc var subst);
    poly_subst_ty subst ty'
  | Type(ty') -> poly_subst__ty subst ty'

and poly_subst__ty (subst:ty_subst) (ty:_ty) : _ty =
  match ty with
  | VarTy(var) ->
    if List.mem_assoc var subst then
      List.assoc var subst
    else
      VarTy(var)
  | Arrow(tyl,tyr) ->
    let tyl' = poly_subst__ty subst tyl in
    let tyr' = poly_subst__ty subst tyr in
    Arrow(tyl',tyr')
  | OpType(name,tys) ->
    OpType(name, List.map (poly_subst__ty subst) tys)
  | Bool -> Bool

let rec poly_subst_te (subst:ty_subst) (te:term) : _term =
  match te with
  | ForallT(var, te') ->
    assert(List.mem_assoc var subst);
    poly_subst_te subst te'
  | Term(te') -> poly_subst__te subst te'

and poly_subst__te (subst:ty_subst) (te:_term) : _term =
  match te with
  | Forall(var,_ty, _term) ->
    let _term' = poly_subst__te subst _term in
    Forall(var, poly_subst__ty subst _ty, _term')
  | Impl(_tel, _ter) ->
    let _tel' = poly_subst__te subst _tel in
    let _ter' = poly_subst__te subst _ter in
    Impl(_tel', _ter')
  | VarTerm(id, _ty) ->
    let _ty' = poly_subst__ty subst _ty in
    VarTerm(id, _ty')
  | App(f,_tes) ->
    let _tes' = List.map (poly_subst__te subst) _tes in
    let f' = poly_subst__te subst f in
    mk_App f' _tes'
  | Const(name, _ty) ->
    let _ty' = poly_subst__ty subst _ty in
    Const(name, _ty')
  | Lam(id, _ty, _te) ->
    let _te' = poly_subst__te subst _te in
    let _ty' = poly_subst__ty subst _ty in
    Lam(id, _ty', _te')

let rec term_subst__te (subst:te_subst) (te:_term) : _term =
  match te with
  | Forall(var,_ty,_term) ->
    let _term' = term_subst__te subst _term in
    Forall(var, _ty, _term')
  | Impl(_tel, _ter) ->
    let _tel' = term_subst__te subst _tel in
    let _ter' = term_subst__te subst _ter in
    Impl(_tel', _ter')
  | VarTerm(id, _ty) ->
    if List.mem_assoc id subst then
      List.assoc id subst
    else
      te
  | App(f,_tes) ->
    let _tes' = List.map (term_subst__te subst) _tes in
    let f' = term_subst__te subst f in
    mk_App f' _tes'
  | Const(name, _ty) ->
    Const(name, _ty)
  | Lam(id, _ty, _te) ->
    let _te' = term_subst__te subst _te in
    Lam(id, _ty, _te')

let rec poly_var_of_ty (ty:ty) : ident list =
  match ty with
  | Type _ -> []
  | ForallK(id, ty') ->
    let vars = poly_var_of_ty ty' in
    id::vars

let rec poly_var_of_te (te:term) : ident list =
  match te with
  | Term _ -> []
  | ForallT(id, te') ->
    let vars = poly_var_of_te te' in
    id::vars

let mk_name md id = md,id

let const_of_name (md,id) = Term.mk_Const dloc md id

let rec compile_tyOp ty_ctx md id args =
  let args' = List.map (compile__type ty_ctx) args in
  OpType(mk_name md id, args')

and compile_type (ty_ctx:ty_ctx) (ty:Term.term) : ty =
  match ty with
  | Term.App(c, Term.Lam(_, var, _, ty), []) when is_hol_const hol_forall_kind_type c ->
    let ty' = compile_type (var::ty_ctx) ty in
    ForallK(var, ty')
  | _ -> Type (compile__type ty_ctx ty)

and compile__type (ty_ctx:ty_ctx) (ty:Term.term) : _ty =
  match ty with
  | Term.Const(_,md,id) when is_hol_const hol_prop ty -> Bool
  | Term.App(c,left,[right]) when is_hol_const hol_arrow c ->
    let left' = compile__type ty_ctx left in
    let right' = compile__type ty_ctx right in
    Arrow(left',right')
  | Term.App(Term.Const(_,md,id),a,args) -> compile_tyOp ty_ctx md id (a::args)
  | Term.Const(_,md,id) -> compile_tyOp ty_ctx md id []
  | Term.DB(_,var,_) ->
    if List.mem var ty_ctx then
      VarTy(var)
    else
      assert false
  | _ ->
    raise (CompileTypeError(TypeError(ty)))

let compile_eta_type (ty_ctx:ty_ctx) (ty:Term.term) : ty =
  match ty with
  | Term.App(cst, a, []) when is_hol_const hol_eta cst -> compile_type ty_ctx a
  | _ -> assert false

let ty_of_const lc md id =
  match Env.get_type lc md id with
  | OK ty -> ty
  | Err er -> Errors.fail_signature_error er

let rec compile__term (ty_ctx:ty_ctx) (te_ctx:term_ctx) (te:Term.term) : _term =
  let lookup_ty var =
    if List.mem_assoc var te_ctx then
      List.assoc var te_ctx
    else
      assert false
  in
  match te with
  | Term.App(cst, ty, [Term.Lam(_,id, Some tyvar, te)]) when is_hol_const hol_forall cst ->
    let ty' = compile__type ty_ctx ty in
    let te' = compile__term ty_ctx ((id,Type ty')::te_ctx) te in
    Forall(id, ty', te')
  | Term.App(cst, tel, [ter]) when is_hol_const hol_impl cst ->
    let tel' = compile__term ty_ctx te_ctx tel in
    let ter' = compile__term ty_ctx te_ctx ter in
    Impl(tel',ter')
  | Term.Const(lc,md,id) ->
    let ty = ty_of_const lc md id in
    let ty' = compile_eta_type ty_ctx ty in
    begin
      match ty' with
      | ForallK(var,te) -> assert false
      | Type(ty) -> Const(mk_name md id, ty)
    end
  | Term.DB(_,var,_) ->
    let ty = lookup_ty var in
    begin
      match ty with
      | ForallK(var,te) -> assert false
      | Type(ty) -> VarTerm(var,ty)
    end
  | Term.Lam(_,id, Some cst, te) when is_hol_const hol_type cst ->
    compile__term (id::ty_ctx) te_ctx te
  | Term.Lam(_,id, Some tyvar, te) ->
    let ty = compile_eta_type ty_ctx tyvar in
    let _ty' =
      begin
        match ty with
        | ForallK(var,te) -> assert false
        | Type(ty) -> ty
      end
    in
    let te' = compile__term ty_ctx ((id,ty)::te_ctx) te in
    Lam(id,_ty', te')
  | Term.Lam(_, _, None, _) ->
    raise(CompileTermError(UntypedLambda(te)))
  | Term.App(Term.Const(lc,md,id),a,args) ->
    let ty = ty_of_const lc md id in
    let ty' = compile_eta_type ty_ctx ty in
    let ty'', args' = _ty_of_ty ty_ctx te_ctx ty' (a::args) in
    App(Const(mk_name md id, ty''), args')
  | Term.App(Term.DB(_,var,_),a,args) ->
    let ty = lookup_ty var in
    let ty', args' = _ty_of_ty ty_ctx te_ctx ty (a::args) in
    App(VarTerm(var, ty'), args')
  | _ -> raise(CompileTermError(TermError(te)))


and _ty_of_ty (ty_ctx:ty_ctx) (te_ctx:term_ctx) (ty:ty) (args:Term.term list)
  : _ty * _term list =
  let rec split l n =
    if n = 0 then
      [],l
    else
      match l with
      | [] -> assert false
      | x::t ->
        let poly,args = split t (n-1) in
        x::poly,args
  in
  let poly_vars = poly_var_of_ty ty in
  let n = List.length poly_vars in
  let poly_args,args = split args n in
  let poly_args' = List.map (compile__type ty_ctx) poly_args in
  let subst = List.combine poly_vars poly_args' in
  let _ty = poly_subst_ty subst ty in
  let args' = List.map (compile__term ty_ctx te_ctx) args in
  _ty, args'

and compile_term (ty_ctx:ty_ctx) (te_ctx:term_ctx) (te:Term.term) : term =
  match te with
  | Term.App(cst, Term.Lam(_,x, Some ty, te'), []) when is_hol_const hol_forall_kind_prop cst ->
    assert (is_hol_const hol_type ty);
    ForallT(x,compile_term (x::ty_ctx) (te_ctx) te')
  | _ -> Term (compile__term ty_ctx te_ctx te)

let compile_eps_term (ty_ctx:ty_ctx) (te_ctx:term_ctx) (te:Term.term) : term =
  match te with
  | Term.App(cst, a, []) when is_hol_const hol_eps cst -> compile_term ty_ctx te_ctx a
  | _ -> assert false

let is_delta_rw cst =
  match cst with
  | Term.Const(_,_,id) -> Str.(string_match (regexp "__eq_\\|__eq_sym") (string_of_ident id) 0)
  | _ -> false

let get_infos_of_delta_rw md id = Str.(
    let id = string_of_ident id in
    if string_match (regexp "\\(__eq__\\)\\(.*\\)") id 0 then
      let id = matched_group 2 id in
      let cst = Term.mk_Const Basic.dloc md (hstring id) in
      match Env.reduction Reduction.OneStep cst with
      | OK te -> (hstring id),te
      | Err err -> Errors.fail_env_error err
    else
      assert false
)


let rec compile__proof (ty_ctx:ty_ctx) (te_ctx:term_ctx) (pf_ctx:proof_ctx) proof : _prooft =
  match proof with
  | Term.Lam(_,x, Some ty, proof) when is_type ty ->
    let ty' = compile_eta_type ty_ctx ty in
    let _prooft' = compile__proof ty_ctx ((x,ty')::te_ctx) pf_ctx proof in
    let _ty' =
      match ty' with
      | ForallK _ -> assert false
      | Type(_ty) -> _ty
    in
    let _term = Forall(x,_ty', _prooft'._term) in
    let _proof = ForallI(x,_ty', _prooft') in
    {_term;_proof}
  | Term.Lam(_,x, Some te, proof) when is_term te ->
    let te' = compile_eps_term ty_ctx te_ctx te in
    let _prooft' = compile__proof ty_ctx te_ctx ((x,te')::pf_ctx) proof in
    let _te' =
      match te' with
      | ForallT _ -> assert false
      | Term(_te) -> _te
    in
    let _term = Impl(_te', _prooft'._term) in
    let _proof = ImplI(_te', _prooft') in
    {_term;_proof}
  | Term.DB(_,id,_) ->
    if List.mem_assoc id pf_ctx then
      let te' = List.assoc id pf_ctx in
      let _term =
        match te' with
        | ForallT _ -> assert false
        | Term(_te) -> _te
      in
      let _proof = Assume(_term,[]) in
      {_term;_proof}
    else
      assert false
  | Term.Const(lc,md,id) ->
    let te =
      match Env.get_type lc md id with
      | OK ty -> ty
      | Err err -> Errors.fail_signature_error err
    in
    let te' = compile_eps_term ty_ctx te_ctx te in
    let _term =
      match te' with
      | ForallT _ -> assert false
      | Term(_te) -> _te
    in
    let _proof = Lemma((md,id),te', []) in
    {_term;_proof}
  | Term.App(Term.Const(_,md,id) as rw, ctx, cst::args) when is_delta_rw rw ->
    let id,te = get_infos_of_delta_rw md id in
    let term =
      match Env.reduction ~red:Tracer.only_beta Reduction.OneStep (Term.mk_App ctx te []) with
      | OK te -> te
      | Err err -> Errors.fail_env_error err
    in
    let term' = compile_term ty_ctx te_ctx term in
    let _term', subst, args = _te_of_te ty_ctx te_ctx term' args in
    let prooft' = {_term=_term'; _proof=Lemma((md,id),term', subst)} in
    begin
      match ctx with
      | Term.Lam(_, var, Some ty, te) ->
        let ty' = compile_type ty_ctx ty in
        let _proof = DeltaU((md,id),(id,compile_term ty_ctx ((var,ty')::te_ctx) te), prooft') in
        let prooft = {prooft' with _proof} in
        compile_app ty_ctx te_ctx pf_ctx prooft args
      | _ -> assert false
    end
  | Term.App(Term.Const(lc,md,id),a,args) ->
    let te =
      match Env.get_type lc md id with
      | OK ty -> ty
      | Err err -> Errors.fail_signature_error err
    in
    let te' = compile_eps_term ty_ctx te_ctx te in
    let _te', subst, args = _te_of_te ty_ctx te_ctx te' (a::args) in
    let prooft  = {_term=_te'; _proof= Lemma((md,id),te', subst)} in
    compile_app ty_ctx te_ctx pf_ctx prooft args
  | Term.App(Term.DB(_,var,_),a,args) ->
    let te' =
      if List.mem_assoc var pf_ctx then
        List.assoc var pf_ctx
      else
        assert false
    in
    let _te', subst, args = _te_of_te ty_ctx te_ctx te' (a::args) in
    let prooft:_prooft = {_term=_te'; _proof= Assume(_te', subst)} in
    compile_app ty_ctx te_ctx pf_ctx prooft args
  | _ -> failwith "todo proof"

and _te_of_te (ty_ctx:ty_ctx) (te_ctx:term_ctx) (te:term) (args:Term.term list) =
  let rec split l n =
    if n = 0 then
      [],l
    else
      match l with
      | [] -> assert false
      | x::t ->
        let poly,args = split t (n-1) in
        x::poly,args
  in
  let poly_vars = poly_var_of_te te in
  let n = List.length poly_vars in
  let poly_args,args = split args n in
  let poly_args' = List.map (compile__type ty_ctx) poly_args in
  let subst = List.combine poly_vars poly_args' in
  let _te = poly_subst_te subst te in
  _te, subst, args

and compile_app (ty_ctx:ty_ctx) (te_ctx:term_ctx) (pf_ctx:proof_ctx) (prooft:_prooft)
    (args:Term.term list) : _prooft =
  let rec compile_arg (prooft:_prooft) arg =
    Format.printf "debug:  %a@." print_hol__term prooft._term;
    Format.printf "term: %a@." Pp.print_term arg;
    match prooft._term with
    | Forall(id,_ty,_term) ->
      let _term' = compile__term ty_ctx te_ctx arg in
      let term = term_subst__te [id,_term'] _term in
      {_term=term;_proof=ForallE(prooft, _term')}
    | Impl(_tel, _telr) ->
      let prooft' = compile__proof ty_ctx te_ctx pf_ctx arg in
      {_term=_telr;_proof=ImplE(prooft, prooft')}
    | App(Const(name, _ty), _tes) -> assert false
    | App(VarTerm(id, _ty), _tes) -> assert false
    | App _ -> failwith "don't know what to do"
    | Const _
    | VarTerm _ -> assert false
    | Lam _ -> assert false
  in
  List.fold_left compile_arg prooft args



let rec compile_proof (ty_ctx:ty_ctx) (te_ctx:term_ctx) (proof:Term.term) : prooft =
  match proof with
  | Term.Lam(_,x, Some ty, proof') when is_hol_const hol_type ty ->
    let prooft' = compile_proof (x::ty_ctx) te_ctx proof' in
    {term=ForallT(x,prooft'.term); proof=ForallP(x, prooft')}
  | Term.App(Term.Const(_,md,id) as cst, ctx, [proof]) when is_delta_rw cst ->
    let id,_ = get_infos_of_delta_rw md id in
    let arg = Term.mk_Const Basic.dloc md id in
    let term =
      match Env.reduction ~red:Tracer.only_beta Reduction.OneStep (Term.mk_App ctx arg []) with
      | OK te -> te
      | Err err -> Errors.fail_env_error err
    in
    let term' = compile_term ty_ctx te_ctx term in
    let prooft' = compile_proof ty_ctx te_ctx proof in
    begin
      match ctx with
      | Term.Lam(_, var, Some ty, te) ->
        let ty' = compile_type ty_ctx ty in
        {term=term';proof=DeltaF((md,id),(id,compile_term ty_ctx ((var,ty')::te_ctx) te), prooft')}
      | _ -> assert false
    end
  | _ ->
    let _prooft' = compile__proof ty_ctx te_ctx [] proof in
    {term=Term(_prooft'._term); proof=Proof(_prooft')}

let compile_declaration (lc:loc) (id:ident) (te:Term.term) : (obj, compile_decl_err) error =
  let md = Env.get_name () in
  try
    match te with
    | Term.App(cst,a,[]) when is_hol_const hol_eta cst ->
      OK(Cst(mk_name md id, compile_type [] a, None))
    | Term.App(cst,a,[]) when is_hol_const hol_eps cst ->
      OK(Thm(mk_name md id, compile_term [] [] a, None))
    | Term.Const(_,md,id) when is_hol_const hol_type te ->
      OK(TyOp(mk_name md id, []))
    | _ -> Err(DeclarationError(lc,id,te))
  with
  | CompileTermError(err) ->
    Err(DeclarationTermError(err,(lc,id,te)))
  | CompileTypeError(err) ->
    Err(DeclarationTypeError(err,(lc,id,te)))

let fail_compile_declaration (err:compile_decl_err) : 'a =
  match err with
  | DeclarationError(lc,id,te) ->
    Errors.fail lc "Error while compiling the declaration '%a:%a'. It seems that the type is not recognized by the compiler." Pp.print_ident id Pp.print_term te
  | DeclarationTermError(err,(lc,id,te)) ->
    begin
      match err with
      | UntypedLambda(te) ->
        Errors.fail lc "Error while compiling the declaration '%a' as an axiom. The term %a has untyped lambdas." Pp.print_ident id Pp.print_term te
      | TermError(te) ->
        Errors.fail lc "Error while compiling the declaration '%a' as an axiom. The term %a seems not to be an hol theorem." Pp.print_ident id Pp.print_term te
    end
  | DeclarationTypeError(err,(lc,id,te)) ->
    begin
      match err with
      | TypeError(ty) ->
        Errors.fail lc "Error while compiling the declaration '%a' as a constant. The type %a seems not to be an hol type." Pp.print_ident id Pp.print_term te
    end

let compile_definition (lc:loc) (id:ident) (ty:Term.term) (te:Term.term)
  : (obj, compile_defn_err) error =
  let md = Env.get_name () in
  try
    match ty with
    | Term.App(cst,a,[]) when is_hol_const hol_eta cst ->
      let te' = compile_term [] [] te in
      OK(Cst(mk_name md id, compile_type [] a, Some te'))
    | Term.App(cst,a,[]) when is_hol_const hol_eps cst ->
      let proof' =
        if !compile_proofs then
          let te' = Tracer.leibnize_term te in
          let te'' = Tracer.leibnize Tracer.Fold te' ty in
          Some (compile_proof [] [] te'')
        else
          None
      in
        OK(Thm(mk_name md id, compile_term [] [] a, proof'))
    | _ -> Err(DefinitionError((lc,id,te),ty))
  with
  | CompileTermError(err) ->
    Err(DefinitionTermError(err,(lc,id,te),ty))
  | CompileTypeError(err) ->
    Err(DefinitionTypeError(err,(lc,id,te),ty))
  | CompileProofError(err) ->
    Err(DefinitionProofError(err,(lc,id,te),ty))
(*
           match compile_declaration lc id ty with
  | OK(obj) -> OK(obj)
  | Err err -> fail_compile_declaration err *)

let fail_compile_definition (err:compile_defn_err) : 'a =
  match err with
  | DefinitionError((lc,id,te),ty) ->
    Errors.fail lc "Error while compiling the definition '%a:%a:=%a'. It seems that the definition is not recognized by the compiler." Pp.print_ident id Pp.print_term te Pp.print_term ty
  | DefinitionTermError(err,(lc,id,te),ty) ->
    begin
      match err with
      | UntypedLambda(te) ->
        Errors.fail lc "Error while compiling the definition '%a'. The term %a has untyped lambdas." Pp.print_ident id Pp.print_term te
      | TermError(te) ->
        Errors.fail lc "Error while compiling the definition '%a'. The term %a seems not to be an hol theorem." Pp.print_ident id Pp.print_term te
    end
  | DefinitionTypeError(err,(lc,id,te),ty) ->
    begin
      match err with
      | TypeError(ty) ->
        Errors.fail lc "Error while compiling the definition '%a' as a constant. The type %a seems not to be an hol term." Pp.print_ident id Pp.print_term te
    end
  | DefinitionProofError(err,(lc,id,te),ty) ->
    begin
      match err with
      | ProofError(ty) ->
        Errors.fail lc "Error while compiling the definition '%a' as a proof. The term %a seems not to be an hol proof." Pp.print_ident id Pp.print_term te
    end
module OT = Openstt.OpenTheory

(* FIXME: rename this *)
let name_of_var var = OT.mk_name [] (string_of_ident var)

let compile_hol_name (md,id) =
  let md' = string_of_ident md in
  let id' = string_of_ident id in
  OT.mk_name [md'] id'


(* FIXME: ctx are unecessary. They can be useful to make some assertions *)
let rec compile_hol__type (ty_ctx:ty_ctx) (_ty:_ty) =
  match _ty with
  | VarTy(var) -> OT.mk_varType (name_of_var var)
  | Arrow(_tyl,_tyr) ->
    let _tyl' = compile_hol__type ty_ctx _tyl in
    let _tyr' = compile_hol__type ty_ctx _tyr in
    OT.mk_arrow_type _tyl' _tyr'
  | OpType(name, tys) ->
    let tyop' = OT.mk_tyOp (compile_hol_name name) in
    let tys' = List.map (compile_hol__type ty_ctx) tys in
    OT.ty_of_tyOp tyop' tys'
  | Bool -> OT.mk_bool_type

let rec compile_hol_type (ty_ctx:ty_ctx) (ty:ty) =
  match ty with
  | ForallK(var,te) -> compile_hol_type (var::ty_ctx) te
  | Type(te) -> compile_hol__type ty_ctx te


(* FIXME: ctx are unecessary. They can be useful to make some assertions *)
let rec compile_hol__term (ty_ctx:ty_ctx) (te_ctx:term_ctx) term =
  match term with
  | Forall(var,_ty, _te) ->
    let _ty' = compile_hol__type ty_ctx _ty in
    let lambda = Lam(var, _ty,_te) in
    let lambda' = compile_hol__term ty_ctx te_ctx lambda in
    OT.mk_forall_term lambda' _ty'
  | Impl(_tel, _ter) ->
    let _tel' = compile_hol__term ty_ctx te_ctx _tel in
    let _ter' = compile_hol__term ty_ctx te_ctx _ter in
    OT.mk_impl_term _tel' _ter'
  | App(f, args) ->
    let f' = compile_hol__term ty_ctx te_ctx f in
    let args' = List.map (compile_hol__term ty_ctx te_ctx) args in
    List.fold_left (fun app arg ->
        OT.mk_app_term app arg) f' args'
  | VarTerm(var,_ty) ->
    let _ty' = compile_hol__type ty_ctx _ty in
    OT.mk_var_term (OT.mk_var (name_of_var var) _ty')
  | Const(name, _ty) ->
    let _ty' = compile_hol__type ty_ctx _ty in
    let cst = OT.const_of_name (compile_hol_name name) in
    OT.term_of_const cst _ty'
  | Lam(var,ty,_term) ->
    let _term' = compile_hol__term ty_ctx ((var,Type ty)::te_ctx) _term in
    let _ty' = compile_hol__type ty_ctx ty in
    let var' = OT.mk_var (name_of_var var) _ty' in
    OT.mk_abs_term var' _term'

let rec compile_hol_term (ty_ctx:ty_ctx) (te_ctx:term_ctx) term =
  match term with
  | ForallT(var,te) -> compile_hol_term (var::ty_ctx) te_ctx te
  | Term(te) -> compile_hol__term ty_ctx te_ctx te

let compile_ctx eq_proof (var,ctx) =
  let rec compile_ctx ctx =
    match ctx with
    | VarTerm(var', _ty) when var' = var -> eq_proof
    | _ -> failwith "todo compile_ctx"
  in
  compile_ctx ctx

let compile_hol_subst ty_ctx subst =
  let compile_binding (var,ty) = name_of_var var, compile_hol__type ty_ctx ty in
  List.map compile_binding subst

(* FIXME: ctx are not update *)
let rec compile_hol__proof (ty_ctx:ty_ctx) (te_ctx:term_ctx) (pf_ctx:proof_ctx) proof  =
  let open OT in
  match proof with
  | Lemma(name,term, subst) ->
    let proof =
      try
        thm_of_lemma (compile_hol_name name)
      with Failure _ ->
        mk_axiom (mk_hyp []) (compile_hol_term ty_ctx te_ctx term)
    in
    mk_subst proof (compile_hol_subst ty_ctx subst) []
  | Assume(_te, subst) ->
    mk_subst (OT.mk_assume (compile_hol__term ty_ctx te_ctx _te)) (compile_hol_subst ty_ctx subst) []
  | ForallI(id,_ty, _prooft) ->
    let name = name_of_var id in
    let _ty = compile_hol__type ty_ctx _ty in
    let _term = compile_hol__term ty_ctx te_ctx _prooft._term in
    let _proof = compile_hol__proof ty_ctx te_ctx pf_ctx _prooft._proof in
    mk_rule_intro_forall name _ty _term _proof
  | ImplI(_term, _prooft) ->
    let _proof = compile_hol__proof ty_ctx te_ctx pf_ctx _prooft._proof in
    let p = compile_hol__term ty_ctx te_ctx _term in
    let q = compile_hol__term ty_ctx te_ctx _prooft._term in
    mk_rule_intro_impl _proof p q
  | ForallE(_prooft,_term) ->
    let id,_ty,lam =
      match _prooft._term with
      | Forall(id,_ty,_term) -> id,_ty, Lam(id, _ty, _term)
      | _ -> assert false
    in
    let _ty' = compile_hol__type ty_ctx _ty in
    let lam' = compile_hol__term ty_ctx te_ctx lam in
    let _proof' = compile_hol__proof ty_ctx ((id,Type _ty)::te_ctx) pf_ctx _prooft._proof in
    let _term' = compile_hol__term ty_ctx te_ctx _term in
    mk_rule_elim_forall _proof' lam' _ty' _term'
  | ImplE(_prooftl,_prooftr) ->
    let p,q =
      match _prooftl._term with
      | Impl(p,q) -> p,q
      | _ -> assert false
    in
    let p' = compile_hol__term ty_ctx te_ctx p in
    let q' = compile_hol__term ty_ctx te_ctx q in
    let proofimpl = compile_hol__proof ty_ctx te_ctx pf_ctx _prooftl._proof in
    let proofp = compile_hol__proof ty_ctx te_ctx pf_ctx _prooftr._proof in
    mk_rule_elim_impl proofp proofimpl p' q'
  | DeltaU _ -> failwith "todo deltaU"
  | BetaU _ -> failwith "todo betaU"

let rec compile_hol_proof (ty_ctx:ty_ctx) (te_ctx:term_ctx) (pf_ctx:proof_ctx) proof =
  match proof with
  | ForallP(var,pf) -> compile_hol_proof (var::ty_ctx) te_ctx pf_ctx pf.proof
  | Proof(pf) -> compile_hol__proof ty_ctx te_ctx pf_ctx pf._proof
  | DeltaF(name,rw_ctx, pf) ->
    let proof = OT.mk_sym @@ OT.thm_of_const_name (compile_hol_name name) in
    let pi = compile_hol_proof ty_ctx te_ctx pf_ctx pf.proof in
    OT.mk_eqMp pi proof
  | BetaF _ -> failwith "todo betaF"

let compile_hol_const name ty term =
  match term with
  | None -> ()
  | Some term ->
    let term' = compile_hol_term [] [] term in
    OT.mk_const (compile_hol_name name) term'

let compile_hol_TyOp name tys = ()

let compile_hol_axiom name hyp term =
  let term' = compile_hol_term [] [] term in
  let hyp' = OT.mk_hyp hyp in
  let thm = OT.mk_axiom hyp' term' in
  OT.mk_thm (compile_hol_name name) term' hyp' thm

let compile_hol_thm name term proof_op =
  match proof_op with
  | None -> compile_hol_axiom name [] term
  | Some proof ->
    let name' = compile_hol_name name in
    OT.mk_thm name'
      (compile_hol_term [] [] term) (OT.mk_hyp []) (compile_hol_proof [] [] [] proof.proof)


let compile_hol_obj (obj:obj) =
  match obj with
  | Cst(name,ty,term) -> compile_hol_const name ty term
  | TyOp(name,tys) -> compile_hol_TyOp name tys
  | Thm(name,term, proof_op) -> compile_hol_thm name term proof_op