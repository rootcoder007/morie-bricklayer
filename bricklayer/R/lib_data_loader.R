# SPDX-License-Identifier: AGPL-3.0-or-later
## =====================================================================
## lib_data_loader.R — open-data discovery, download, schema validation
##
## Part of morie-bricklayer. Project-agnostic; project specifics live in
## data_provenance.json and config.json.
##
## Provides:
##   load_provenance(path)                Read pinned URL + SHA256 + schema
##   resolve_via_ckan(provenance)         Try CKAN package_show + name match
##   resolve_via_ckan_search(provenance)  Fall back to CKAN package_search
##   download_data(url, target_path)      utils::download.file() wrapper
##   verify_sha256(path, expected)        Compare to provenance
##   validate_schema(df_raw, provenance)  Hard fail / warn on schema drift
##
## Licence: AGPL-3.0-or-later
## =====================================================================

#' Load a Pinned Data-Provenance Record
#'
#' Reads a `data_provenance.json` file describing a project's pinned data
#' source: the CKAN endpoint, resource name pattern, expected SHA256,
#' Wayback snapshot, schema, and synthetic-data recipe.
#'
#' @param path Path to the provenance JSON file.
#' @return The parsed provenance as a nested list (via
#'   [jsonlite::fromJSON()] with `simplifyVector = FALSE`), or `NULL` if
#'   the file does not exist.
#' @export
load_provenance <- function(path) {
  if (!file.exists(path)) return(NULL)
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

## ----- CKAN package_show by slug + name match -----
## CKAN is the API used by data.ontario.ca, data.gov.uk, data.gov, and
## most government open-data portals. Resolves the current download URL
## for a known package even if the resource UUID has been replaced.

#' Resolve a Download URL via CKAN package_show
#'
#' Queries the CKAN `package_show` endpoint recorded in a provenance
#' object and returns the URL of the first resource whose name matches the
#' provenance's name-match pattern. CKAN powers data.ontario.ca,
#' data.gov.uk, data.gov, and most government open-data portals, so this
#' recovers the current download URL even if the underlying resource UUID
#' has been replaced.
#'
#' @param provenance A provenance list as returned by [load_provenance()].
#'   Must contain `dataset$ckan_api_endpoint` and
#'   `resource$name_match_pattern`.
#' @return The matched resource URL as a character string, or `NULL` if
#'   the endpoint is missing, the request fails, CKAN reports failure, or
#'   no resource name matches.
#' @export
resolve_via_ckan <- function(provenance) {
  if (is.null(provenance)) return(NULL)
  ds   <- provenance$dataset
  res  <- provenance$resource
  if (is.null(ds$ckan_api_endpoint) || is.null(res$name_match_pattern))
    return(NULL)
  api_url <- ds$ckan_api_endpoint
  if (is.null(api_url) || !nzchar(api_url)) return(NULL)
  resp <- tryCatch(jsonlite::fromJSON(api_url, simplifyVector = FALSE),
                   error = function(e) NULL)
  if (is.null(resp) || !isTRUE(resp$success)) return(NULL)
  pat <- res$name_match_pattern
  for (r in resp$result$resources) {
    name <- if (is.null(r$name)) "" else r$name
    if (grepl(pat, name, ignore.case = TRUE)) return(r$url)
  }
  NULL
}

## ----- CKAN package_search (fallback if slug changes) -----

#' Resolve a Download URL via CKAN package_search
#'
#' Fallback for [resolve_via_ckan()] when the dataset slug has changed.
#' Derives the CKAN portal base URL from the provenance's `package_show`
#' endpoint, runs a `package_search` query (from `resource$search_query`,
#' or derived from the name-match pattern), and returns the URL of the
#' first matching resource, preferring CSV format when specified.
#'
#' @param provenance A provenance list as returned by [load_provenance()].
#'   Uses `resource$search_query`, `resource$name_match_pattern`,
#'   `resource$format`, and `dataset$ckan_api_endpoint`.
#' @return The matched resource URL as a character string, or `NULL` if no
#'   query or base URL can be derived, the request fails, or nothing
#'   matches.
#' @export
resolve_via_ckan_search <- function(provenance) {
  if (is.null(provenance)) return(NULL)
  res <- provenance$resource
  q   <- res$search_query
  if (is.null(q) || !nzchar(q)) {
    ## Derive a search query from the resource name pattern
    q <- gsub("[^A-Za-z0-9 ]", " ", res$name_match_pattern %||% "")
    if (!nzchar(q)) return(NULL)
  }
  ## CKAN portal base URL inferred from package_show endpoint
  base <- sub("/api/3/.*$", "",
              provenance$dataset$ckan_api_endpoint %||% "")
  if (!nzchar(base)) return(NULL)
  api_url <- sprintf("%s/api/3/action/package_search?q=%s",
                     base, URLencode(q, reserved = TRUE))
  resp <- tryCatch(jsonlite::fromJSON(api_url, simplifyVector = FALSE),
                   error = function(e) NULL)
  if (is.null(resp)) return(NULL)
  pat <- res$name_match_pattern
  for (pkg in resp$result$results) {
    for (r in pkg$resources) {
      name <- if (is.null(r$name)) "" else r$name
      fmt  <- toupper(r$format %||% "")
      if (grepl(pat, name, ignore.case = TRUE) &&
          (fmt == "CSV" || is.null(res$format) || toupper(res$format) == fmt))
        return(r$url)
    }
  }
  NULL
}

## ----- Tiny `%||%` operator (R 4.4+ has it natively) -----

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

## ----- Download -----

#' Download a File
#'
#' Thin wrapper around [utils::download.file()] that returns the target
#' path invisibly so it composes in pipelines.
#'
#' @param url URL to download.
#' @param target_path Destination path on disk.
#' @param mode Write mode passed to [utils::download.file()]; defaults to
#'   `"wb"` (binary) for cross-platform safety.
#' @param quiet Logical; suppress progress output. Defaults to `FALSE`.
#' @return The `target_path`, returned invisibly.
#' @export
download_data <- function(url, target_path, mode = "wb", quiet = FALSE) {
  utils::download.file(url, target_path, mode = mode, quiet = quiet)
  invisible(target_path)
}

## ----- friendly_download: wraps utils::download.file with diagnostic
## error messages for common academic/corporate network failures.
## Returns TRUE on success, FALSE on failure.

#' Download a File With Diagnostic Error Messages
#'
#' Wraps [utils::download.file()] and, on failure, prints plain-language
#' guidance for the most common academic and corporate network problems
#' (rate limiting, TLS-inspection VPNs, DNS failures, timeouts, HTTP 403).
#' Optionally retries from a Wayback Machine snapshot URL.
#'
#' @param url URL to download.
#' @param target_path Destination path on disk.
#' @param attempt_wayback Optional Wayback Machine snapshot URL tried as a
#'   fallback if the primary download fails. `NULL` (default) or an empty
#'   string disables the fallback.
#' @return `TRUE` if either the primary download or the Wayback fallback
#'   succeeds, otherwise `FALSE`.
#' @export
friendly_download <- function(url, target_path, attempt_wayback = NULL) {
  result <- tryCatch({
    utils::download.file(url, target_path, mode = "wb", quiet = FALSE)
    TRUE
  }, error = function(e) {
    msg <- conditionMessage(e)
    cat("\n  ! Download failed.\n")
    cat("    URL:   ", url, "\n", sep = "")
    cat("    Error: ", msg, "\n\n", sep = "")
    cat("  Common causes (in rough order of likelihood):\n")
    if (grepl("429|too many|rate", msg, ignore.case = TRUE)) {
      cat("    • Rate-limited (HTTP 429). VPNs share IPs across users\n")
      cat("      and often trip rate limits. Try disabling your VPN.\n")
    }
    if (grepl("SSL|TLS|certificate|handshake|UNEXPECTED_EOF",
              msg, ignore.case = TRUE)) {
      cat("    • SSL/TLS handshake failed.\n")
      cat("      VPNs with TLS inspection (Cisco AnyConnect, GlobalProtect,\n")
      cat("      Zscaler, NetSkope) break R's HTTPS. Try disabling.\n")
    }
    if (grepl("could not|unable to resolve|name not|getaddrinfo",
              msg, ignore.case = TRUE))
      cat("    • DNS lookup failed; check network connectivity.\n")
    if (grepl("timeout|timed out|connection (refused|reset)",
              msg, ignore.case = TRUE))
      cat("    • Connection timed out / refused (firewall, often institutional).\n")
    if (grepl("403|forbidden", msg, ignore.case = TRUE))
      cat("    • HTTP 403 Forbidden (geo-restriction; try a different VPN region).\n")
    cat("\n")
    if (!is.null(attempt_wayback) && nzchar(attempt_wayback)) {
      cat("  Trying Wayback Machine fallback snapshot...\n")
      tryCatch({
        utils::download.file(attempt_wayback, target_path, mode = "wb", quiet = FALSE)
        cat("  ✓ Wayback snapshot retrieved.\n")
        return(TRUE)
      }, error = function(e2) {
        cat("  ! Wayback fallback also failed: ", conditionMessage(e2), "\n")
        return(FALSE)
      })
    }
    FALSE
  })
  result
}

## ----- SHA256 check -----

#' Verify a File's SHA256 Against an Expected Digest
#'
#' Computes the SHA256 digest of a file (via the digest package) and
#' compares it to the expected value pinned in provenance.
#'
#' @param path Path to the file to hash.
#' @param expected_sha The expected SHA256 digest, as a lowercase hex
#'   string.
#' @return A list with `actual` (computed digest), `expected` (the value
#'   passed in), and `match` (logical; `TRUE` if they are identical).
#' @export
verify_sha256 <- function(path, expected_sha) {
  if (!requireNamespace("digest", quietly = TRUE))
    stop("The 'digest' package is required.")
  actual <- digest::digest(file = path, algo = "sha256")
  list(actual = actual, expected = expected_sha,
       match  = identical(actual, expected_sha))
}

## ----- Schema validation -----
## `provenance$schema` should contain:
##   expected_columns       character vector
##   expected_value_sets    named list of allowed values per column
##   structural_invariants  list with min_data_rows / max_data_rows (optional)
##
## Returns a list of issues (length 0 = clean). The caller decides whether
## to stop() or warning() based on severity.

#' Validate a Data Frame Against a Provenance Schema
#'
#' Checks a raw data frame against the `schema` block of a provenance
#' object: required columns, row-count bounds, and allowed categorical
#' value sets. Returns the issues found rather than raising, so the caller
#' decides how to react.
#'
#' @param df_raw The data frame to validate.
#' @param provenance A provenance list as returned by [load_provenance()].
#'   The `schema` block may contain `expected_columns`,
#'   `structural_invariants` (`min_data_rows`, `max_data_rows`), and
#'   `expected_value_sets` (a named list of allowed values per column).
#' @return A named list of issues; each issue is a list with `severity`
#'   (`"fatal"` or `"warning"`) and a human-readable `message`. A
#'   zero-length list means the data frame is clean.
#' @export
validate_schema <- function(df_raw, provenance) {
  issues <- list()
  if (is.null(provenance) || is.null(provenance$schema)) return(issues)
  sch <- provenance$schema

  ## --- Required columns ---
  if (!is.null(sch$expected_columns)) {
    missing_cols <- setdiff(sch$expected_columns, colnames(df_raw))
    if (length(missing_cols) > 0L) {
      issues$missing_columns <- list(
        severity = "fatal",
        message  = paste0("Missing required columns: ",
                          paste(missing_cols, collapse = ", "))
      )
    }
  }

  ## --- Row count bounds ---
  inv <- sch$structural_invariants
  if (!is.null(inv$min_data_rows) && nrow(df_raw) < inv$min_data_rows)
    issues$row_count_low <- list(
      severity = "warning",
      message  = sprintf("Row count %d below expected minimum %d",
                        nrow(df_raw), inv$min_data_rows)
    )
  if (!is.null(inv$max_data_rows) && nrow(df_raw) > inv$max_data_rows)
    issues$row_count_high <- list(
      severity = "warning",
      message  = sprintf("Row count %d above expected maximum %d",
                        nrow(df_raw), inv$max_data_rows)
    )

  ## --- Categorical value sets ---
  if (!is.null(sch$expected_value_sets)) {
    for (col in names(sch$expected_value_sets)) {
      if (!col %in% colnames(df_raw)) next
      actual_vals  <- unique(df_raw[[col]])
      expected_vals <- sch$expected_value_sets[[col]]
      unexpected   <- setdiff(actual_vals, expected_vals)
      if (length(unexpected) > 0L) {
        issues[[paste0("unexpected_", col)]] <- list(
          severity = "warning",
          message  = sprintf("Column '%s' has unexpected values: %s",
                             col, paste(unexpected, collapse = ", "))
        )
      }
    }
  }
  issues
}

## ----- Apply schema validation; stop on fatal, warn otherwise -----

#' Apply Schema Validation, Stopping on Fatal Issues
#'
#' Runs [validate_schema()] and acts on the result: fatal issues raise an
#' error via [stop()], warning-severity issues emit a [warning()].
#'
#' @param df_raw The data frame to validate.
#' @param provenance A provenance list as returned by [load_provenance()].
#' @return Invisibly, `TRUE` if no issues were found and `FALSE`
#'   otherwise. Errors if any fatal issue is present.
#' @export
apply_schema_validation <- function(df_raw, provenance) {
  issues <- validate_schema(df_raw, provenance)
  for (nm in names(issues)) {
    iss <- issues[[nm]]
    if (iss$severity == "fatal") stop(iss$message, call. = FALSE)
    if (iss$severity == "warning") warning(iss$message, call. = FALSE)
  }
  invisible(length(issues) == 0L)
}
