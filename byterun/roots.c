/***********************************************************************/
/*                                                                     */
/*                                OCaml                                */
/*                                                                     */
/*         Xavier Leroy and Damien Doligez, INRIA Rocquencourt         */
/*                                                                     */
/*  Copyright 1996 Institut National de Recherche en Informatique et   */
/*  en Automatique.  All rights reserved.  This file is distributed    */
/*  under the terms of the GNU Library General Public License, with    */
/*  the special exception on linking described in file ../LICENSE.     */
/*                                                                     */
/***********************************************************************/

/* To walk the memory roots for garbage collection */

#include "caml/finalise.h"
#include "caml/globroots.h"
#include "caml/major_gc.h"
#include "caml/memory.h"
#include "caml/minor_gc.h"
#include "caml/misc.h"
#include "caml/mlvalues.h"
#include "caml/roots.h"
#include "caml/fiber.h"

CAMLexport struct caml__roots_block *caml_local_roots = NULL;

CAMLexport void (*caml_scan_roots_hook) (scanning_action f, int) = NULL;

/* FIXME should rename to [caml_oldify_young_roots] and synchronise with
   asmrun/roots.c */
/* Call [caml_oldify_one] on (at least) all the roots that point to the minor
   heap. */
void caml_oldify_local_roots (void)
{
  struct caml__roots_block *lr;
  intnat i, j;
  value * sp;

  /* The stacks */
  caml_oldify_one (caml_current_stack, &caml_current_stack);

  /* Local C roots */  /* FIXME do the old-frame trick ? */
  for (lr = caml_local_roots; lr != NULL; lr = lr->next) {
    for (i = 0; i < lr->ntables; i++){
      for (j = 0; j < lr->nitems; j++){
        sp = &(lr->tables[i][j]);
        caml_oldify_one (*sp, sp);
      }
    }
  }
  /* Global C roots */
  caml_scan_global_young_roots(&caml_oldify_one);
  /* Finalised values */
  caml_final_do_young_roots (&caml_oldify_one);
  /* Hook */
  if (caml_scan_roots_hook != NULL) (*caml_scan_roots_hook)(&caml_oldify_one, 0);
}


/* Call [caml_darken] on all roots */

void caml_darken_all_roots (void)
{
  caml_do_roots (caml_darken, 0);
}

void caml_do_roots (scanning_action f, int is_compaction)
{
  /* Global variables */
  f(caml_global_data, &caml_global_data);
  /* The stack and the local C roots */
  caml_do_local_roots(f, caml_local_roots, &caml_current_stack, is_compaction);
  /* Global C roots */
  caml_scan_global_roots(f);
  /* Finalised values */
  caml_final_do_strong_roots (f);
  /* Hook */
  if (caml_scan_roots_hook != NULL) (*caml_scan_roots_hook)(f, is_compaction);
}

CAMLexport void caml_do_local_roots (scanning_action f,
                                     struct caml__roots_block *local_roots,
                                     value* stackp,
                                     int is_compaction)
{
  struct caml__roots_block *lr;
  int i, j;
  value * sp;

  if (!is_compaction) caml_scan_stack (f, *stackp);
  f (*stackp, stackp);

  for (lr = local_roots; lr != NULL; lr = lr->next) {
    for (i = 0; i < lr->ntables; i++){
      for (j = 0; j < lr->nitems; j++){
        sp = &(lr->tables[i][j]);
        f (*sp, sp);
      }
    }
  }
}
