/* SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * rmbl_core.c -- the shared C backend for the rmorie ecosystem.
 *
 * rmoriebricklayer is the compiled "core": it provides a small set of
 * generic numeric kernels (fast summary stats) and a self-contained
 * SHA-256 (for provenance) as plain C functions with C linkage. These
 * are:
 *   - wrapped as .Call entry points for rmoriebricklayer's own R API, and
 *   - published via R_RegisterCCallable (see init.c) so sibling packages
 *     (rmorie, rmoriedata) can LinkingTo: rmoriebricklayer and call them
 *     through inst/include/rmoriebricklayer.h with zero code duplication.
 *
 * The stats kernels intentionally do NOT drop NA -- NaN/NA propagate, the
 * same contract as the base-R primitives. Call stats::na.omit() first if
 * you want NA handling (the R wrappers document this).
 */

#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <math.h>
#include <string.h>
#include <stdint.h>
#include <stddef.h>

/* ------------------------------------------------------------------ */
/* Plain-C kernels (C linkage; these are the registered, linkable API) */
/* ------------------------------------------------------------------ */

double rmbl_mean(const double *x, R_xlen_t n) {
    if (n <= 0) return R_NaN;
    /* two-pass not needed for the mean; long double accumulator for
     * accuracy on large n. */
    long double s = 0.0L;
    for (R_xlen_t i = 0; i < n; i++) s += x[i];
    return (double) (s / (long double) n);
}

double rmbl_var(const double *x, R_xlen_t n) {
    if (n < 2) return R_NaN;             /* sample variance undefined for n<2 */
    long double m = 0.0L;
    for (R_xlen_t i = 0; i < n; i++) m += x[i];
    m /= (long double) n;
    long double ss = 0.0L;
    for (R_xlen_t i = 0; i < n; i++) {
        long double d = (long double) x[i] - m;
        ss += d * d;
    }
    return (double) (ss / (long double) (n - 1)); /* denom n-1, like R var() */
}

double rmbl_cor_pearson(const double *x, const double *y, R_xlen_t n) {
    if (n < 2) return R_NaN;
    long double mx = 0.0L, my = 0.0L;
    for (R_xlen_t i = 0; i < n; i++) { mx += x[i]; my += y[i]; }
    mx /= (long double) n; my /= (long double) n;
    long double sxy = 0.0L, sxx = 0.0L, syy = 0.0L;
    for (R_xlen_t i = 0; i < n; i++) {
        long double dx = (long double) x[i] - mx;
        long double dy = (long double) y[i] - my;
        sxy += dx * dy; sxx += dx * dx; syy += dy * dy;
    }
    long double denom = sqrtl(sxx * syy);
    if (denom == 0.0L) return R_NaN;     /* zero variance -> undefined */
    return (double) (sxy / denom);
}

double rmbl_normal_pdf(double x, double mu, double sigma) {
    if (sigma <= 0.0) return R_NaN;
    static const double inv_sqrt_2pi = 0.3989422804014326779399460599343819; /* 1/sqrt(2*pi) */
    double z = (x - mu) / sigma;
    return (inv_sqrt_2pi / sigma) * exp(-0.5 * z * z);
}

/* ------------------------------------------------------------------ */
/* SHA-256 -- self-contained, public-domain style (FIPS 180-4).        */
/* Provenance hashing for the ecosystem; verified against the standard */
/* "abc" test vector in tests/testthat/test-core.R.                    */
/* ------------------------------------------------------------------ */

typedef struct {
    uint8_t  data[64];
    uint32_t datalen;
    uint64_t bitlen;
    uint32_t state[8];
} rmbl_sha256_ctx;

#define ROTR(a,b) (((a) >> (b)) | ((a) << (32 - (b))))
#define CHs(x,y,z)  (((x) & (y)) ^ (~(x) & (z)))
#define MAJs(x,y,z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define EP0(x)  (ROTR(x,2)  ^ ROTR(x,13) ^ ROTR(x,22))
#define EP1(x)  (ROTR(x,6)  ^ ROTR(x,11) ^ ROTR(x,25))
#define SIG0(x) (ROTR(x,7)  ^ ROTR(x,18) ^ ((x) >> 3))
#define SIG1(x) (ROTR(x,17) ^ ROTR(x,19) ^ ((x) >> 10))

static const uint32_t rmbl_k[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

static void rmbl_sha256_transform(rmbl_sha256_ctx *ctx, const uint8_t data[64]) {
    uint32_t a,b,c,d,e,f,g,h,t1,t2,m[64];
    int i, j;
    for (i = 0, j = 0; i < 16; i++, j += 4)
        m[i] = ((uint32_t)data[j] << 24) | ((uint32_t)data[j+1] << 16) |
               ((uint32_t)data[j+2] << 8) | ((uint32_t)data[j+3]);
    for (; i < 64; i++)
        m[i] = SIG1(m[i-2]) + m[i-7] + SIG0(m[i-15]) + m[i-16];

    a = ctx->state[0]; b = ctx->state[1]; c = ctx->state[2]; d = ctx->state[3];
    e = ctx->state[4]; f = ctx->state[5]; g = ctx->state[6]; h = ctx->state[7];

    for (i = 0; i < 64; i++) {
        t1 = h + EP1(e) + CHs(e,f,g) + rmbl_k[i] + m[i];
        t2 = EP0(a) + MAJs(a,b,c);
        h = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }

    ctx->state[0] += a; ctx->state[1] += b; ctx->state[2] += c; ctx->state[3] += d;
    ctx->state[4] += e; ctx->state[5] += f; ctx->state[6] += g; ctx->state[7] += h;
}

static void rmbl_sha256_init(rmbl_sha256_ctx *ctx) {
    ctx->datalen = 0; ctx->bitlen = 0;
    ctx->state[0] = 0x6a09e667; ctx->state[1] = 0xbb67ae85;
    ctx->state[2] = 0x3c6ef372; ctx->state[3] = 0xa54ff53a;
    ctx->state[4] = 0x510e527f; ctx->state[5] = 0x9b05688c;
    ctx->state[6] = 0x1f83d9ab; ctx->state[7] = 0x5be0cd19;
}

static void rmbl_sha256_update(rmbl_sha256_ctx *ctx, const uint8_t *data, size_t len) {
    for (size_t i = 0; i < len; i++) {
        ctx->data[ctx->datalen] = data[i];
        ctx->datalen++;
        if (ctx->datalen == 64) {
            rmbl_sha256_transform(ctx, ctx->data);
            ctx->bitlen += 512;
            ctx->datalen = 0;
        }
    }
}

static void rmbl_sha256_final(rmbl_sha256_ctx *ctx, uint8_t hash[32]) {
    uint32_t i = ctx->datalen;
    ctx->data[i++] = 0x80;                       /* append the '1' bit */
    if (ctx->datalen < 56) {
        while (i < 56) ctx->data[i++] = 0x00;
    } else {
        while (i < 64) ctx->data[i++] = 0x00;
        rmbl_sha256_transform(ctx, ctx->data);
        memset(ctx->data, 0, 56);
    }
    ctx->bitlen += (uint64_t) ctx->datalen * 8;  /* total message length in bits */
    ctx->data[63] = (uint8_t)(ctx->bitlen);
    ctx->data[62] = (uint8_t)(ctx->bitlen >> 8);
    ctx->data[61] = (uint8_t)(ctx->bitlen >> 16);
    ctx->data[60] = (uint8_t)(ctx->bitlen >> 24);
    ctx->data[59] = (uint8_t)(ctx->bitlen >> 32);
    ctx->data[58] = (uint8_t)(ctx->bitlen >> 40);
    ctx->data[57] = (uint8_t)(ctx->bitlen >> 48);
    ctx->data[56] = (uint8_t)(ctx->bitlen >> 56);
    rmbl_sha256_transform(ctx, ctx->data);

    for (i = 0; i < 8; i++) {                    /* big-endian digest */
        hash[i*4]   = (uint8_t)(ctx->state[i] >> 24);
        hash[i*4+1] = (uint8_t)(ctx->state[i] >> 16);
        hash[i*4+2] = (uint8_t)(ctx->state[i] >> 8);
        hash[i*4+3] = (uint8_t)(ctx->state[i]);
    }
}

/* Public, linkable: hash `len` bytes of `data`, write 64 hex chars + NUL. */
void rmbl_sha256_hex(const unsigned char *data, size_t len, char out[65]) {
    rmbl_sha256_ctx ctx;
    uint8_t hash[32];
    static const char hx[] = "0123456789abcdef";
    rmbl_sha256_init(&ctx);
    rmbl_sha256_update(&ctx, data, len);
    rmbl_sha256_final(&ctx, hash);
    for (int i = 0; i < 32; i++) {
        out[i*2]   = hx[(hash[i] >> 4) & 0xf];
        out[i*2+1] = hx[hash[i] & 0xf];
    }
    out[64] = '\0';
}

/* ------------------------------------------------------------------ */
/* .Call wrappers -- rmoriebricklayer's own R-facing API.              */
/* ------------------------------------------------------------------ */

SEXP C_rmbl_mean(SEXP x) {
    x = PROTECT(coerceVector(x, REALSXP));
    double r = rmbl_mean(REAL(x), XLENGTH(x));
    UNPROTECT(1);
    return ScalarReal(r);
}

SEXP C_rmbl_var(SEXP x) {
    x = PROTECT(coerceVector(x, REALSXP));
    double r = rmbl_var(REAL(x), XLENGTH(x));
    UNPROTECT(1);
    return ScalarReal(r);
}

SEXP C_rmbl_cor(SEXP x, SEXP y) {
    x = PROTECT(coerceVector(x, REALSXP));
    y = PROTECT(coerceVector(y, REALSXP));
    if (XLENGTH(x) != XLENGTH(y)) {
        UNPROTECT(2);
        Rf_error("x and y must have the same length");
    }
    double r = rmbl_cor_pearson(REAL(x), REAL(y), XLENGTH(x));
    UNPROTECT(2);
    return ScalarReal(r);
}

SEXP C_rmbl_normal_pdf(SEXP x, SEXP mu, SEXP sigma) {
    x = PROTECT(coerceVector(x, REALSXP));
    double m = Rf_asReal(mu), s = Rf_asReal(sigma);
    R_xlen_t n = XLENGTH(x);
    SEXP out = PROTECT(allocVector(REALSXP, n));
    double *px = REAL(x), *po = REAL(out);
    for (R_xlen_t i = 0; i < n; i++) po[i] = rmbl_normal_pdf(px[i], m, s);
    UNPROTECT(2);
    return out;
}

/* Accepts a single CHARSXP string or a RAWSXP; returns a 64-char hex string. */
SEXP C_rmbl_sha256(SEXP x) {
    const unsigned char *data;
    size_t len;
    char out[65];
    if (TYPEOF(x) == RAWSXP) {
        data = (const unsigned char *) RAW(x);
        len  = (size_t) XLENGTH(x);
    } else if (TYPEOF(x) == STRSXP && XLENGTH(x) >= 1) {
        SEXP s = STRING_ELT(x, 0);
        if (s == NA_STRING) return ScalarString(NA_STRING);
        data = (const unsigned char *) CHAR(s);
        len  = strlen((const char *) data);
    } else {
        Rf_error("rmbl_sha256 expects a length-1 character vector or a raw vector");
    }
    rmbl_sha256_hex(data, len, out);
    return mkString(out);
}
