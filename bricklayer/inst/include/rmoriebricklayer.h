/* SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * rmoriebricklayer.h -- public C API of the rmorie ecosystem core.
 *
 * Sibling packages connect to the shared backend by adding
 *
 *     LinkingTo: rmoriebricklayer
 *
 * to their DESCRIPTION and then, in their own C/C++ sources:
 *
 *     #include <rmoriebricklayer.h>
 *     double m = rmbl_mean(REAL(x), XLENGTH(x));
 *
 * Each symbol resolves once (lazily) through R_GetCCallable against the
 * loaded rmoriebricklayer DLL -- no duplicated kernels, one source of
 * truth. This header is for CONSUMERS; rmoriebricklayer itself defines
 * the real functions in src/rmbl_core.c and must NOT include this file.
 */

#ifndef RMORIEBRICKLAYER_H
#define RMORIEBRICKLAYER_H

#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

static R_INLINE double rmbl_mean(const double *x, R_xlen_t n) {
    static double (*fn)(const double *, R_xlen_t) = NULL;
    if (fn == NULL)
        fn = (double (*)(const double *, R_xlen_t))
             R_GetCCallable("rmoriebricklayer", "rmbl_mean");
    return fn(x, n);
}

static R_INLINE double rmbl_var(const double *x, R_xlen_t n) {
    static double (*fn)(const double *, R_xlen_t) = NULL;
    if (fn == NULL)
        fn = (double (*)(const double *, R_xlen_t))
             R_GetCCallable("rmoriebricklayer", "rmbl_var");
    return fn(x, n);
}

static R_INLINE double rmbl_cor_pearson(const double *x, const double *y, R_xlen_t n) {
    static double (*fn)(const double *, const double *, R_xlen_t) = NULL;
    if (fn == NULL)
        fn = (double (*)(const double *, const double *, R_xlen_t))
             R_GetCCallable("rmoriebricklayer", "rmbl_cor_pearson");
    return fn(x, y, n);
}

static R_INLINE double rmbl_normal_pdf(double x, double mu, double sigma) {
    static double (*fn)(double, double, double) = NULL;
    if (fn == NULL)
        fn = (double (*)(double, double, double))
             R_GetCCallable("rmoriebricklayer", "rmbl_normal_pdf");
    return fn(x, mu, sigma);
}

static R_INLINE void rmbl_sha256_hex(const unsigned char *data, size_t len, char *out /* >= 65 */) {
    static void (*fn)(const unsigned char *, size_t, char *) = NULL;
    if (fn == NULL)
        fn = (void (*)(const unsigned char *, size_t, char *))
             R_GetCCallable("rmoriebricklayer", "rmbl_sha256_hex");
    fn(data, len, out);
}

#ifdef __cplusplus
}
#endif

#endif /* RMORIEBRICKLAYER_H */
