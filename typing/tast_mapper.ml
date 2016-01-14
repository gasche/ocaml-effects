(***********************************************************************)
(*                                                                     *)
(*                                OCaml                                *)
(*                                                                     *)
(*                       Alain Frisch, LexiFi                          *)
(*                                                                     *)
(*  Copyright 2015 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the Q Public License version 1.0.               *)
(*                                                                     *)
(***********************************************************************)

open Asttypes
open Typedtree

(* TODO: add 'methods' for location, attribute, extension,
   open_description, include_declaration, include_description *)

type mapper =
  {
    case: mapper -> case -> case;
    cases: mapper -> case list -> case list;
    class_declaration: mapper -> class_declaration -> class_declaration;
    class_description: mapper -> class_description -> class_description;
    class_expr: mapper -> class_expr -> class_expr;
    class_field: mapper -> class_field -> class_field;
    class_signature: mapper -> class_signature -> class_signature;
    class_structure: mapper -> class_structure -> class_structure;
    class_type: mapper -> class_type -> class_type;
    class_type_declaration: mapper -> class_type_declaration ->
      class_type_declaration;
    class_type_field: mapper -> class_type_field -> class_type_field;
    env: mapper -> Env.t -> Env.t;
    expr: mapper -> expression -> expression;
    extension_constructor: mapper -> extension_constructor ->
      extension_constructor;
    module_binding: mapper -> module_binding -> module_binding;
    module_coercion: mapper -> module_coercion -> module_coercion;
    module_declaration: mapper -> module_declaration -> module_declaration;
    module_expr: mapper -> module_expr -> module_expr;
    module_type: mapper -> module_type -> module_type;
    module_type_declaration:
      mapper -> module_type_declaration -> module_type_declaration;
    package_type: mapper -> package_type -> package_type;
    pat: mapper -> pattern -> pattern;
    row_field: mapper -> row_field -> row_field;
    signature: mapper -> signature -> signature;
    signature_item: mapper -> signature_item -> signature_item;
    structure: mapper -> structure -> structure;
    structure_item: mapper -> structure_item -> structure_item;
    typ: mapper -> core_type -> core_type;
    type_declaration: mapper -> type_declaration -> type_declaration;
    type_declarations: mapper -> (rec_flag * type_declaration list) ->
      (rec_flag * type_declaration list);
    type_extension: mapper -> type_extension -> type_extension;
    type_kind: mapper -> type_kind -> type_kind;
    value_binding: mapper -> value_binding -> value_binding;
    value_bindings: mapper -> (rec_flag * value_binding list) ->
      (rec_flag * value_binding list);
    value_description: mapper -> value_description -> value_description;
    with_constraint: mapper -> with_constraint -> with_constraint;
  }

let id x = x
let tuple2 f1 f2 (x, y) = (f1 x, f2 y)
let tuple3 f1 f2 f3 (x, y, z) = (f1 x, f2 y, f3 z)
let opt f = function None -> None | Some x -> Some (f x)

let structure sub {str_items; str_type; str_final_env} =
  {
    str_items = List.map (sub.structure_item sub) str_items;
    str_final_env = sub.env sub str_final_env;
    str_type;
  }

let class_infos sub f x =
  {x with
   ci_params = List.map (tuple2 (sub.typ sub) id) x.ci_params;
   ci_expr = f x.ci_expr;
  }

let module_type_declaration sub x =
  let mtd_type = opt (sub.module_type sub) x.mtd_type in
  {x with mtd_type}

let module_declaration sub x =
  let md_type = sub.module_type sub x.md_type in
  {x with md_type}

let include_infos f x = {x with incl_mod = f x.incl_mod}

let class_type_declaration sub x =
  class_infos sub (sub.class_type sub) x

let class_declaration sub x =
  class_infos sub (sub.class_expr sub) x

let structure_item sub {str_desc; str_loc; str_env} =
  let str_env = sub.env sub str_env in
  let str_desc =
    match str_desc with
    | Tstr_eval (exp, attrs) -> Tstr_eval (sub.expr sub exp, attrs)
    | Tstr_value (rec_flag, list) ->
        let (rec_flag, list) = sub.value_bindings sub (rec_flag, list) in
        Tstr_value (rec_flag, list)
    | Tstr_primitive v -> Tstr_primitive (sub.value_description sub v)
    | Tstr_type (rec_flag, list) ->
        let (rec_flag, list) = sub.type_declarations sub (rec_flag, list) in
        Tstr_type (rec_flag, list)
    | Tstr_typext te -> Tstr_typext (sub.type_extension sub te)
    | Tstr_exception ext -> Tstr_exception (sub.extension_constructor sub ext)
    | Tstr_effect ext -> Tstr_effect (sub.extension_constructor sub ext)
    | Tstr_module mb -> Tstr_module (sub.module_binding sub mb)
    | Tstr_recmodule list ->
        Tstr_recmodule (List.map (sub.module_binding sub) list)
    | Tstr_modtype x -> Tstr_modtype (sub.module_type_declaration sub x)
    | Tstr_class list ->
        Tstr_class
          (List.map (tuple2 (sub.class_declaration sub) id) list)
    | Tstr_class_type list ->
        Tstr_class_type
          (List.map (tuple3 id id (sub.class_type_declaration sub)) list)
    | Tstr_include incl ->
        Tstr_include (include_infos (sub.module_expr sub) incl)
    | Tstr_open _
    | Tstr_attribute _ as d -> d
  in
  {str_desc; str_env; str_loc}

let value_description sub x =
  let val_desc = sub.typ sub x.val_desc in
  {x with val_desc}

let label_decl sub x =
  let ld_type = sub.typ sub x.ld_type in
  {x with ld_type}

let constructor_decl sub cd =
  let cd_args = List.map (sub.typ sub) cd.cd_args in
  let cd_res = opt (sub.typ sub) cd.cd_res in
  {cd with cd_args; cd_res}

let type_kind sub = function
  | Ttype_abstract -> Ttype_abstract
  | Ttype_variant list -> Ttype_variant (List.map (constructor_decl sub) list)
  | Ttype_record list -> Ttype_record (List.map (label_decl sub) list)
  | Ttype_open -> Ttype_open

let type_declaration sub x =
  let typ_cstrs =
    List.map
      (tuple3 (sub.typ sub) (sub.typ sub) id)
      x.typ_cstrs
  in
  let typ_kind = sub.type_kind sub x.typ_kind in
  let typ_manifest = opt (sub.typ sub) x.typ_manifest in
  let typ_params = List.map (tuple2 (sub.typ sub) id) x.typ_params in
  {x with typ_cstrs; typ_kind; typ_manifest; typ_params}

let type_declarations sub (rec_flag, list) =
  (rec_flag, List.map (sub.type_declaration sub) list)

let type_extension sub x =
  let tyext_params = List.map (tuple2 (sub.typ sub) id) x.tyext_params in
  let tyext_constructors =
    List.map (sub.extension_constructor sub) x.tyext_constructors
  in
  {x with tyext_constructors; tyext_params}

let extension_constructor sub x =
  let ext_kind =
    match x.ext_kind with
      Text_decl(ctl, cto) ->
        Text_decl(List.map (sub.typ sub) ctl, opt (sub.typ sub) cto)
    | Text_rebind _ as d -> d
  in
  {x with ext_kind}

let pat sub x =
  let extra = function
    | Tpat_type _
    | Tpat_unpack as d -> d
    | Tpat_constraint ct -> Tpat_constraint (sub.typ sub ct)
  in
  let pat_env = sub.env sub x.pat_env in
  let pat_extra = List.map (tuple3 extra id id) x.pat_extra in
  let pat_desc =
    match x.pat_desc with
    | Tpat_any
    | Tpat_var _
    | Tpat_constant _ as d -> d
    | Tpat_tuple l -> Tpat_tuple (List.map (sub.pat sub) l)
    | Tpat_construct (loc, cd, l) ->
        Tpat_construct (loc, cd, List.map (sub.pat sub) l)
    | Tpat_variant (l, po, rd) -> Tpat_variant (l, opt (sub.pat sub) po, rd)
    | Tpat_record (l, closed) ->
        Tpat_record (List.map (tuple3 id id (sub.pat sub)) l, closed)
    | Tpat_array l -> Tpat_array (List.map (sub.pat sub) l)
    | Tpat_or (p1, p2, rd) ->
        Tpat_or (sub.pat sub p1, sub.pat sub p2, rd)
    | Tpat_alias (p, id, s) -> Tpat_alias (sub.pat sub p, id, s)
    | Tpat_lazy p -> Tpat_lazy (sub.pat sub p)
  in
  {x with pat_extra; pat_desc; pat_env}

let expr sub x =
  let extra = function
    | Texp_constraint cty ->
        Texp_constraint (sub.typ sub cty)
    | Texp_coerce (cty1, cty2) ->
        Texp_coerce (opt (sub.typ sub) cty1, sub.typ sub cty2)
    | Texp_open (ovf, path, loc, env) ->
        Texp_open (ovf, path, loc, sub.env sub env)
    | Texp_newtype _ as d -> d
    | Texp_poly cto -> Texp_poly (opt (sub.typ sub) cto)
  in
  let exp_extra = List.map (tuple3 extra id id) x.exp_extra in
  let exp_env = sub.env sub x.exp_env in
  let exp_desc =
    match x.exp_desc with
    | Texp_ident _
    | Texp_constant _ as d -> d
    | Texp_let (rec_flag, list, exp) ->
        let (rec_flag, list) = sub.value_bindings sub (rec_flag, list) in
        Texp_let (rec_flag, list, sub.expr sub exp)
    | Texp_function (l, cases, p) ->
        Texp_function (l, sub.cases sub cases, p)
    | Texp_apply (exp, list) ->
        Texp_apply (
          sub.expr sub exp,
          List.map (tuple3 id (opt (sub.expr sub)) id) list
        )
    | Texp_match (exp, cases, exn_cases, eff_cases, p) ->
        Texp_match (
          sub.expr sub exp,
          sub.cases sub cases,
          sub.cases sub exn_cases,
          sub.cases sub eff_cases,
          p
        )
    | Texp_try (exp, exn_cases, eff_cases) ->
        Texp_try (
          sub.expr sub exp,
          sub.cases sub exn_cases,
          sub.cases sub eff_cases
        )
    | Texp_tuple list ->
        Texp_tuple (List.map (sub.expr sub) list)
    | Texp_construct (lid, cd, args) ->
        Texp_construct (lid, cd, List.map (sub.expr sub) args)
    | Texp_variant (l, expo) ->
        Texp_variant (l, opt (sub.expr sub) expo)
    | Texp_record (list, expo) ->
        Texp_record (
          List.map (tuple3 id id (sub.expr sub)) list,
          opt (sub.expr sub) expo
        )
    | Texp_field (exp, lid, ld) ->
        Texp_field (sub.expr sub exp, lid, ld)
    | Texp_setfield (exp1, lid, ld, exp2) ->
        Texp_setfield (
          sub.expr sub exp1,
          lid,
          ld,
          sub.expr sub exp2
        )
    | Texp_array list ->
        Texp_array (List.map (sub.expr sub) list)
    | Texp_ifthenelse (exp1, exp2, expo) ->
        Texp_ifthenelse (
          sub.expr sub exp1,
          sub.expr sub exp2,
          opt (sub.expr sub) expo
        )
    | Texp_sequence (exp1, exp2) ->
        Texp_sequence (
          sub.expr sub exp1,
          sub.expr sub exp2
        )
    | Texp_while (exp1, exp2) ->
        Texp_while (
          sub.expr sub exp1,
          sub.expr sub exp2
        )
    | Texp_for (id, p, exp1, exp2, dir, exp3) ->
        Texp_for (
          id,
          p,
          sub.expr sub exp1,
          sub.expr sub exp2,
          dir,
          sub.expr sub exp3
        )
    | Texp_send (exp, meth, expo) ->
        Texp_send
          (
            sub.expr sub exp,
            meth,
            opt (sub.expr sub) expo
          )
    | Texp_new _
    | Texp_instvar _ as d -> d
    | Texp_setinstvar (path1, path2, id, exp) ->
        Texp_setinstvar (
          path1,
          path2,
          id,
          sub.expr sub exp
        )
    | Texp_override (path, list) ->
        Texp_override (
          path,
          List.map (tuple3 id id (sub.expr sub)) list
        )
    | Texp_letmodule (id, s, mexpr, exp) ->
        Texp_letmodule (
          id,
          s,
          sub.module_expr sub mexpr,
          sub.expr sub exp
        )
    | Texp_assert exp ->
        Texp_assert (sub.expr sub exp)
    | Texp_lazy exp ->
        Texp_lazy (sub.expr sub exp)
    | Texp_object (cl, sl) ->
        Texp_object (sub.class_structure sub cl, sl)
    | Texp_pack mexpr ->
        Texp_pack (sub.module_expr sub mexpr)
  in
  {x with exp_extra; exp_desc; exp_env}


let package_type sub x =
  let pack_fields = List.map (tuple2 id (sub.typ sub)) x.pack_fields in
  {x with pack_fields}

let signature sub x =
  let sig_final_env = sub.env sub x.sig_final_env in
  let sig_items = List.map (sub.signature_item sub) x.sig_items in
  {x with sig_items; sig_final_env}

let signature_item sub x =
  let sig_env = sub.env sub x.sig_env in
  let sig_desc =
    match x.sig_desc with
    | Tsig_value v ->
        Tsig_value (sub.value_description sub v)
    | Tsig_type (rec_flag, list) ->
        let (rec_flag, list) = sub.type_declarations sub (rec_flag, list) in
        Tsig_type (rec_flag, list)
    | Tsig_typext te ->
        Tsig_typext (sub.type_extension sub te)
    | Tsig_exception ext ->
        Tsig_exception (sub.extension_constructor sub ext)
    | Tsig_effect ext ->
        Tsig_effect (sub.extension_constructor sub ext)
    | Tsig_module x ->
        Tsig_module (sub.module_declaration sub x)
    | Tsig_recmodule list ->
        Tsig_recmodule (List.map (sub.module_declaration sub) list)
    | Tsig_modtype x ->
        Tsig_modtype (sub.module_type_declaration sub x)
    | Tsig_include incl ->
        Tsig_include (include_infos (sub.module_type sub) incl)
    | Tsig_class list ->
        Tsig_class (List.map (sub.class_description sub) list)
    | Tsig_class_type list ->
        Tsig_class_type
          (List.map (sub.class_type_declaration sub) list)
    | Tsig_open _
    | Tsig_attribute _ as d -> d
  in
  {x with sig_desc; sig_env}

let class_description sub x =
  class_infos sub (sub.class_type sub) x

let module_type sub x =
  let mty_env = sub.env sub x.mty_env in
  let mty_desc =
    match x.mty_desc with
    | Tmty_ident _
    | Tmty_alias _ as d -> d
    | Tmty_signature sg -> Tmty_signature (sub.signature sub sg)
    | Tmty_functor (id, s, mtype1, mtype2) ->
        Tmty_functor (
          id,
          s,
          opt (sub.module_type sub) mtype1,
          sub.module_type sub mtype2
        )
    | Tmty_with (mtype, list) ->
        Tmty_with (
          sub.module_type sub mtype,
          List.map (tuple3 id id (sub.with_constraint sub)) list
        )
    | Tmty_typeof mexpr ->
        Tmty_typeof (sub.module_expr sub mexpr)
  in
  {x with mty_desc; mty_env}

let with_constraint sub = function
  | Twith_type decl -> Twith_type (sub.type_declaration sub decl)
  | Twith_typesubst decl -> Twith_typesubst (sub.type_declaration sub decl)
  | Twith_module _
  | Twith_modsubst _ as d -> d

let module_coercion sub = function
  | Tcoerce_none -> Tcoerce_none
  | Tcoerce_functor (c1,c2) ->
      Tcoerce_functor (sub.module_coercion sub c1, sub.module_coercion sub c2)
  | Tcoerce_alias (p, c1) ->
      Tcoerce_alias (p, sub.module_coercion sub c1)
  | Tcoerce_structure (l1, l2) ->
      let l1' = List.map (fun (i,c) -> i, sub.module_coercion sub c) l1 in
      let l2' = List.map (fun (id,i,c) -> id, i, sub.module_coercion sub c) l2 in
      Tcoerce_structure (l1', l2')
  | Tcoerce_primitive pc ->
      Tcoerce_primitive {pc with pc_env = sub.env sub pc.pc_env}

let module_expr sub x =
  let mod_env = sub.env sub x.mod_env in
  let mod_desc =
    match x.mod_desc with
    | Tmod_ident _ as d -> d
    | Tmod_structure st -> Tmod_structure (sub.structure sub st)
    | Tmod_functor (id, s, mtype, mexpr) ->
        Tmod_functor (
          id,
          s,
          opt (sub.module_type sub) mtype,
          sub.module_expr sub mexpr
        )
    | Tmod_apply (mexp1, mexp2, c) ->
        Tmod_apply (
          sub.module_expr sub mexp1,
          sub.module_expr sub mexp2,
          sub.module_coercion sub c
        )
    | Tmod_constraint (mexpr, mt, Tmodtype_implicit, c) ->
        Tmod_constraint (sub.module_expr sub mexpr, mt, Tmodtype_implicit,
                         sub.module_coercion sub c)
    | Tmod_constraint (mexpr, mt, Tmodtype_explicit mtype, c) ->
        Tmod_constraint (
          sub.module_expr sub mexpr,
          mt,
          Tmodtype_explicit (sub.module_type sub mtype),
          sub.module_coercion sub c
        )
    | Tmod_unpack (exp, mty) ->
        Tmod_unpack
          (
            sub.expr sub exp,
            mty
          )
  in
  {x with mod_desc; mod_env}

let module_binding sub x =
  let mb_expr = module_expr sub x.mb_expr in
  {x with mb_expr}

let class_expr sub x =
  let cl_env = sub.env sub x.cl_env in
  let cl_desc =
    match x.cl_desc with
    | Tcl_constraint (cl, clty, vals, meths, concrs) ->
        Tcl_constraint (
          sub.class_expr sub cl,
          opt (sub.class_type sub) clty,
          vals,
          meths,
          concrs
        )
    | Tcl_structure clstr ->
        Tcl_structure (sub.class_structure sub clstr)
    | Tcl_fun (label, pat, priv, cl, partial) ->
        Tcl_fun (
          label,
          sub.pat sub pat,
          List.map (tuple3 id id (sub.expr sub)) priv,
          sub.class_expr sub cl,
          partial
        )
    | Tcl_apply (cl, args) ->
        Tcl_apply (
          sub.class_expr sub cl,
          List.map (tuple3 id (opt (sub.expr sub)) id) args
        )
    | Tcl_let (rec_flag, value_bindings, ivars, cl) ->
        let (rec_flag, value_bindings) = sub.value_bindings sub (rec_flag, value_bindings) in
        Tcl_let (
          rec_flag,
          value_bindings,
          List.map (tuple3 id id (sub.expr sub)) ivars,
          sub.class_expr sub cl
        )
    | Tcl_ident (path, lid, tyl) ->
        Tcl_ident (path, lid, List.map (sub.typ sub) tyl)
  in
  {x with cl_desc; cl_env}

let class_type sub x =
  let cltyp_env = sub.env sub x.cltyp_env in
  let cltyp_desc =
    match x.cltyp_desc with
    | Tcty_signature csg -> Tcty_signature (sub.class_signature sub csg)
    | Tcty_constr (path, lid, list) ->
        Tcty_constr (
          path,
          lid,
          List.map (sub.typ sub) list
        )
    | Tcty_arrow (label, ct, cl) ->
        Tcty_arrow
          (label,
           sub.typ sub ct,
           sub.class_type sub cl
          )
  in
  {x with cltyp_desc; cltyp_env}

let class_signature sub x =
  let csig_self = sub.typ sub x.csig_self in
  let csig_fields = List.map (sub.class_type_field sub) x.csig_fields in
  {x with csig_self; csig_fields}

let class_type_field sub x =
  let ctf_desc =
    match x.ctf_desc with
    | Tctf_inherit ct ->
        Tctf_inherit (sub.class_type sub ct)
    | Tctf_val (s, mut, virt, ct) ->
        Tctf_val (s, mut, virt, sub.typ sub ct)
    | Tctf_method (s, priv, virt, ct) ->
        Tctf_method (s, priv, virt, sub.typ sub ct)
    | Tctf_constraint  (ct1, ct2) ->
        Tctf_constraint (sub.typ sub ct1, sub.typ sub ct2)
    | Tctf_attribute _ as d -> d
  in
  {x with ctf_desc}

let typ sub x =
  let ctyp_env = sub.env sub x.ctyp_env in
  let ctyp_desc =
    match x.ctyp_desc with
    | Ttyp_any
    | Ttyp_var _ as d -> d
    | Ttyp_arrow (label, ct1, ct2) ->
        Ttyp_arrow (label, sub.typ sub ct1, sub.typ sub ct2)
    | Ttyp_tuple list -> Ttyp_tuple (List.map (sub.typ sub) list)
    | Ttyp_constr (path, lid, list) ->
        Ttyp_constr (path, lid, List.map (sub.typ sub) list)
    | Ttyp_object (list, closed) ->
        Ttyp_object (
          List.map (tuple3 id id (sub.typ sub)) list,
          closed
        )
    | Ttyp_class (path, lid, list) ->
        Ttyp_class
          (path,
           lid,
           List.map (sub.typ sub) list
          )
    | Ttyp_alias (ct, s) ->
        Ttyp_alias (sub.typ sub ct, s)
    | Ttyp_variant (list, closed, labels) ->
        Ttyp_variant (List.map (sub.row_field sub) list, closed, labels)
    | Ttyp_poly (sl, ct) ->
        Ttyp_poly (sl, sub.typ sub ct)
    | Ttyp_package pack ->
        Ttyp_package (sub.package_type sub pack)
  in
  {x with ctyp_desc; ctyp_env}

let class_structure sub x =
  let cstr_self = sub.pat sub x.cstr_self in
  let cstr_fields = List.map (sub.class_field sub) x.cstr_fields in
  {x with cstr_self; cstr_fields}

let row_field sub = function
  | Ttag (label, attrs, b, list) ->
      Ttag (label, attrs, b, List.map (sub.typ sub) list)
  | Tinherit ct -> Tinherit (sub.typ sub ct)

let class_field_kind sub = function
  | Tcfk_virtual ct -> Tcfk_virtual (sub.typ sub ct)
  | Tcfk_concrete (ovf, e) -> Tcfk_concrete (ovf, sub.expr sub e)

let class_field sub x =
  let cf_desc =
    match x.cf_desc with
    | Tcf_inherit (ovf, cl, super, vals, meths) ->
        Tcf_inherit (ovf, sub.class_expr sub cl, super, vals, meths)
    | Tcf_constraint (cty, cty') ->
        Tcf_constraint (
          sub.typ sub cty,
          sub.typ sub cty'
        )
    | Tcf_val (s, mf, id, k, b) ->
        Tcf_val (s, mf, id, class_field_kind sub k, b)
    | Tcf_method (s, priv, k) ->
        Tcf_method (s, priv, class_field_kind sub k)
    | Tcf_initializer exp ->
        Tcf_initializer (sub.expr sub exp)
    | Tcf_attribute _ as d -> d
  in
  {x with cf_desc}

let value_bindings sub (rec_flag, list) =
  (rec_flag, List.map (sub.value_binding sub) list)

let cases sub l =
  List.map (sub.case sub) l

let case sub {c_lhs; c_cont; c_guard; c_rhs} =
  {
    c_lhs = sub.pat sub c_lhs;
    c_cont = c_cont;
    c_guard = opt (sub.expr sub) c_guard;
    c_rhs = sub.expr sub c_rhs;
  }

let value_binding sub x =
  let vb_pat = sub.pat sub x.vb_pat in
  let vb_expr = sub.expr sub x.vb_expr in
  {x with vb_pat; vb_expr}

let env _sub x = x

let default =
  {
    case;
    cases;
    class_declaration;
    class_description;
    class_expr;
    class_field;
    class_signature;
    class_structure;
    class_type;
    class_type_declaration;
    class_type_field;
    env;
    expr;
    extension_constructor;
    module_binding;
    module_coercion;
    module_declaration;
    module_expr;
    module_type;
    module_type_declaration;
    package_type;
    pat;
    row_field;
    signature;
    signature_item;
    structure;
    structure_item;
    typ;
    type_declaration;
    type_declarations;
    type_extension;
    type_kind;
    value_binding;
    value_bindings;
    value_description;
    with_constraint;
  }
