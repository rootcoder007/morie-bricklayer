# SPDX-License-Identifier: AGPL-3.0-or-later
## =====================================================================
## lib_synthetic.R — schema-driven synthetic data generation
##
## Part of morie-bricklayer. The generic primitives here let you build a
## synthetic CSV from a schema definition without writing project-
## specific generator code. Falls back gracefully when the schema is
## under-specified.
##
## Provides:
##   make_synthetic_csv(schema, out_path, n_rows, seed)
##   make_synthetic_column(spec, n, base_p)
##
## Schema format (from data_provenance.json schema.synthetic_recipe):
##   {
##     "n_rows": 75000,                       # target rows
##     "seed":   91735246,                    # reproducible seed
##     "columns": {
##       "EndFiscalYear": {
##         "type":     "sample",
##         "values":   [2023, 2024, 2025],
##         "weights":  [0.33, 0.33, 0.34]     # optional
##       },
##       "Gender": {
##         "type":     "sample",
##         "values":   ["Male", "Female"],
##         "weights":  [0.92, 0.08]
##       },
##       "MentalHealth_Alert": {
##         "type":            "bernoulli",
##         "p":               0.18,
##         "p_with_baserate": 0.15,           # add row-level latent variation
##         "labels":          ["Yes", "No"]
##       },
##       "Number_Of_Placements": {
##         "type":   "poisson",
##         "lambda": 25,
##         "min":    1
##       },
##       "UniqueIndividual_ID": {
##         "type":    "id_pattern",
##         "pattern": "{year}-{seq:05d}-RC",
##         "year_col": "EndFiscalYear"
##       }
##     }
##   }
##
## Licence: AGPL-3.0-or-later
## =====================================================================

#' Generate One Synthetic Column From a Spec
#'
#' Builds a single synthetic data column according to a column spec drawn
#' from a provenance synthetic recipe. Supported `type`s are `"sample"`
#' (categorical, optionally weighted), `"bernoulli"` (two-label draw with
#' optional per-row base rate), `"poisson"` (counts with a floor),
#' `"id_pattern"` (templated IDs, optionally per-year sequenced), and
#' `"sequence"` (a running integer sequence).
#'
#' @param spec A list describing the column; recognised fields depend on
#'   `spec$type` (e.g. `values`, `weights`, `p`, `p_with_baserate`,
#'   `labels`, `lambda`, `min`, `pattern`, `year_col`, `from`).
#' @param n Number of values to generate.
#' @param ctx Named list of already-generated columns, letting later
#'   columns (such as `id_pattern` with a `year_col`) reference earlier
#'   ones. Defaults to an empty list.
#' @param base_p Optional numeric vector of per-row latent propensities
#'   used by the `"bernoulli"` type to add row-level variation.
#' @return A vector of length `n` for the requested column type. Errors on
#'   an unknown `type`.
#' @export
make_synthetic_column <- function(spec, n, ctx = list(), base_p = NULL) {
  type <- spec$type %||% "sample"
  switch(type,
    sample = {
      vals <- unlist(spec$values)
      w    <- if (!is.null(spec$weights)) unlist(spec$weights) else NULL
      sample(vals, n, replace = TRUE, prob = w)
    },
    bernoulli = {
      p_base <- spec$p %||% 0.1
      p_extra <- spec$p_with_baserate %||% 0
      p_per_row <- if (!is.null(base_p)) p_base + p_extra * base_p else p_base
      labels <- spec$labels %||% c("Yes", "No")
      ifelse(stats::runif(n) < p_per_row, labels[1], labels[2])
    },
    poisson = {
      lambda <- spec$lambda %||% 1
      out <- stats::rpois(n, lambda = lambda)
      mn <- spec$min %||% 0
      pmax(out, mn)
    },
    id_pattern = {
      pattern <- spec$pattern %||% "id-{seq:05d}"
      year_col <- spec$year_col %||% NULL
      if (!is.null(year_col) && year_col %in% names(ctx)) {
        years <- ctx[[year_col]]
        seq_per_yr <- ave(seq_along(years), years, FUN = seq_along)
        ids <- mapply(function(y, s) {
          out <- gsub("\\{year\\}", as.character(y), pattern)
          gsub("\\{seq:05d\\}", sprintf("%05d", s), out)
        }, years, seq_per_yr)
        return(ids)
      }
      seqs <- seq_len(n)
      gsub("\\{seq:05d\\}", sprintf("%05d", seqs), pattern)
    },
    sequence = {
      from <- spec$from %||% 1L
      seq.int(from, length.out = n)
    },
    stop("Unknown synthetic column type: ", type)
  )
}

#' Null-Coalescing Operator
#'
#' Returns `a` unless it is `NULL`, in which case it returns `b`.
#'
#' @param a Left-hand value.
#' @param b Fallback used when `a` is `NULL`.
#' @return `a` if it is not `NULL`, otherwise `b`.
#' @keywords internal
#' @noRd
`%||%` <- function(a, b) if (is.null(a)) b else a

## ----- Main generator -----
## `schema` is the synthetic_recipe sub-block of provenance.
## `out_path` is where to write the CSV.

#' Generate a Synthetic CSV From a Schema Recipe
#'
#' Generates a reproducible synthetic data set from the
#' `schema$synthetic_recipe` block of a provenance object and writes it to
#' a CSV. Columns are produced in declaration order so later columns can
#' reference earlier ones, a shared per-row latent propensity drives any
#' Bernoulli columns, and an optional row-replication block expands
#' per-person rows.
#'
#' @param schema The synthetic recipe (a list with `columns`, and optional
#'   `n_rows`, `seed`, and `row_replication`).
#' @param out_path Path where the CSV is written.
#' @param n_rows Number of rows (persons, if replicating) to generate.
#'   Defaults to `schema$n_rows`, then 50000.
#' @param seed Random seed for reproducibility. Defaults to `schema$seed`,
#'   then 91735246.
#' @return Invisibly, a list with `path`, `rows` (rows written), and
#'   `seed` used.
#' @export
make_synthetic_csv <- function(schema, out_path,
                                n_rows = NULL, seed = NULL) {
  if (is.null(seed)) seed <- schema$seed %||% 91735246L
  if (is.null(n_rows)) n_rows <- schema$n_rows %||% 50000L
  set.seed(seed)

  ## Optional: replicate rows per "person" if a multiplier is specified
  reps_spec <- schema$row_replication
  if (!is.null(reps_spec)) {
    n_persons <- n_rows
    rows_per  <- sample(unlist(reps_spec$values),
                        n_persons, replace = TRUE,
                        prob = unlist(reps_spec$weights))
    expand <- function(x) rep(x, rows_per)
  } else {
    expand <- identity
  }

  ## Latent per-row "baseline propensity" — shared across bernoulli cols
  base_p <- stats::runif(n_rows, 0, 1)

  ## Generate columns in declaration order; later columns can see ctx
  out <- list()
  ctx <- list()
  for (col_name in names(schema$columns)) {
    spec <- schema$columns[[col_name]]
    vals <- make_synthetic_column(spec, n_rows, ctx, base_p)
    if (!is.null(reps_spec)) {
      ## Expand non-id columns; ids handled inside id_pattern
      if ((spec$type %||% "sample") != "id_pattern") vals <- expand(vals)
    }
    ctx[[col_name]] <- vals
    out[[col_name]] <- vals
  }
  out_df <- as.data.frame(out, stringsAsFactors = FALSE)
  utils::write.csv(out_df, out_path, row.names = FALSE)
  invisible(list(path = out_path, rows = nrow(out_df), seed = seed))
}
