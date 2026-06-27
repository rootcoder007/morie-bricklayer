/* SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * init.c -- DLL registration for rmoriebricklayer.
 *
 * Two things happen here:
 *   1. The .Call entry points used by rmoriebricklayer's own R wrappers
 *      are registered (R_registerRoutines + R_useDynamicSymbols FALSE).
 *   2. The plain-C kernels are published with R_RegisterCCallable so that
 *      packages declaring `LinkingTo: rmoriebricklayer` can resolve them
 *      at load time via the inline shims in inst/include/rmoriebricklayer.h.
 */

#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <stddef.h>

/* .Call wrappers (defined in rmbl_core.c) */
extern SEXP C_rmbl_mean(SEXP);
extern SEXP C_rmbl_var(SEXP);
extern SEXP C_rmbl_cor(SEXP, SEXP);
extern SEXP C_rmbl_normal_pdf(SEXP, SEXP, SEXP);
extern SEXP C_rmbl_sha256(SEXP);

/* plain-C kernels (defined in rmbl_core.c) -- the cross-package API */
extern double rmbl_mean(const double *, R_xlen_t);
extern double rmbl_var(const double *, R_xlen_t);
extern double rmbl_cor_pearson(const double *, const double *, R_xlen_t);
extern double rmbl_normal_pdf(double, double, double);
extern void   rmbl_sha256_hex(const unsigned char *, size_t, char *);

static const R_CallMethodDef CallEntries[] = {
    {"C_rmbl_mean",       (DL_FUNC) &C_rmbl_mean,       1},
    {"C_rmbl_var",        (DL_FUNC) &C_rmbl_var,        1},
    {"C_rmbl_cor",        (DL_FUNC) &C_rmbl_cor,        2},
    {"C_rmbl_normal_pdf", (DL_FUNC) &C_rmbl_normal_pdf, 3},
    {"C_rmbl_sha256",     (DL_FUNC) &C_rmbl_sha256,     1},
    {NULL, NULL, 0}
};

void R_init_rmoriebricklayer(DllInfo *dll) {
    R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);

    /* Publish the linkable kernels for sibling packages. */
    R_RegisterCCallable("rmoriebricklayer", "rmbl_mean",        (DL_FUNC) rmbl_mean);
    R_RegisterCCallable("rmoriebricklayer", "rmbl_var",         (DL_FUNC) rmbl_var);
    R_RegisterCCallable("rmoriebricklayer", "rmbl_cor_pearson", (DL_FUNC) rmbl_cor_pearson);
    R_RegisterCCallable("rmoriebricklayer", "rmbl_normal_pdf",  (DL_FUNC) rmbl_normal_pdf);
    R_RegisterCCallable("rmoriebricklayer", "rmbl_sha256_hex",  (DL_FUNC) rmbl_sha256_hex);
}
