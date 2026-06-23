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

load_provenance <- function(path) {
  if (!file.exists(path)) return(NULL)
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

## ----- CKAN package_show by slug + name match -----
## CKAN is the API used by data.ontario.ca, data.gov.uk, data.gov, and
## most government open-data portals. Resolves the current download URL
## for a known package even if the resource UUID has been replaced.
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
`%||%` <- function(a, b) if (is.null(a)) b else a

## ----- Download -----
download_data <- function(url, target_path, mode = "wb", quiet = FALSE) {
  utils::download.file(url, target_path, mode = mode, quiet = quiet)
  invisible(target_path)
}

## ----- friendly_download: wraps utils::download.file with diagnostic
## error messages for common academic/corporate network failures.
## Returns TRUE on success, FALSE on failure.
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
apply_schema_validation <- function(df_raw, provenance) {
  issues <- validate_schema(df_raw, provenance)
  for (nm in names(issues)) {
    iss <- issues[[nm]]
    if (iss$severity == "fatal") stop(iss$message, call. = FALSE)
    if (iss$severity == "warning") warning(iss$message, call. = FALSE)
  }
  invisible(length(issues) == 0L)
}
