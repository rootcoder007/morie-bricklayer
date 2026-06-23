## =====================================================================
## lib_manifest.R — cross-check accounting + SUMMARY.txt + manifest.json
##
## Part of morie-bricklayer. Provides the `record()` machinery and the
## end-of-run summary writers.
##
## Provides:
##   make_manifest(meta)                Construct a manifest object
##   record(manifest, name, observed,   Append a cross-check entry; returns
##          expected, tol, group,         the mutated manifest
##          synthetic)
##   write_manifest_json(manifest, path)
##   write_summary_txt(manifest, output_dir, paths, what_was_done)
##
## Licence: AGPL-3.0-or-later
## =====================================================================

`%||%` <- function(a, b) if (is.null(a)) b else a

make_manifest <- function(meta) {
  list(meta = meta, results = list())
}

record <- function(manifest, name, observed, expected,
                   tol = 0.0001, group = "general",
                   synthetic = FALSE) {
  diff <- if (is.numeric(observed) && is.numeric(expected))
    abs(observed - expected) else NA_real_
  status <- if (isTRUE(synthetic)) "INFO"
            else if (!is.na(diff) && diff <= tol) "PASS"
            else if (!is.na(diff)) "DIFFER"
            else "INFO"
  manifest$results[[name]] <- list(
    group    = group,
    observed = observed,
    expected = expected,
    diff     = diff,
    status   = status,
    tol      = tol,
    note     = if (isTRUE(synthetic))
                  "synthetic data — comparison not meaningful" else NULL
  )
  cat(sprintf("  %-44s observed = %-12s expected = %-12s [%s]\n",
              name,
              if (is.numeric(observed)) sprintf("%.4f", observed) else as.character(observed),
              if (is.numeric(expected)) sprintf("%.4f", expected) else as.character(expected),
              status))
  manifest
}

write_manifest_json <- function(manifest, path) {
  if (!requireNamespace("jsonlite", quietly = TRUE))
    stop("The 'jsonlite' package is required.")
  jsonlite::write_json(manifest, path, auto_unbox = TRUE, pretty = TRUE)
  invisible(path)
}

summarise_counts <- function(manifest) {
  statuses <- vapply(manifest$results, function(x) x$status, character(1))
  list(
    total  = length(statuses),
    pass   = sum(statuses == "PASS"),
    differ = sum(statuses == "DIFFER"),
    info   = sum(statuses == "INFO")
  )
}

## ----- SUMMARY.txt -----
## `paths` is a named list: bundle, input, results, script, provenance
## `what_was_done` is an optional character vector of bullet points
write_summary_txt <- function(manifest, output_dir, paths,
                              what_was_done = NULL,
                              contact = NULL,
                              licence = NULL) {
  counts <- summarise_counts(manifest)
  files <- sort(list.files(output_dir))
  is_synth <- isTRUE(manifest$meta$synthetic)

  lines <- c(
    "##########################################################",
    "#                                                        #",
    "#   REPRODUCIBILITY RUN — SUMMARY                        #",
    "#                                                        #",
    "##########################################################",
    "",
    paste0("Project:   ", manifest$meta$project %||% "(unnamed)"),
    paste0("Author:    ", manifest$meta$author  %||% "(unknown)"),
    paste0("When:      ", manifest$meta$run_at %||%
                          format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    paste0("OS:        ", manifest$meta$os %||% Sys.info()[["sysname"]]),
    paste0("R:         ", manifest$meta$r_version %||% R.version.string),
    paste0("Mode:      ", if (is_synth)
                            "SYNTHETIC (not real data — pipeline check only)"
                          else "real data"),
    "",
    "----------------------------------------------------------",
    "  PATHS — exact absolute locations used in this run",
    "----------------------------------------------------------"
  )
  for (nm in names(paths)) {
    lines <- c(lines, sprintf("%-15s %s",
                              paste0(toupper(substr(nm, 1, 1)),
                                     substr(nm, 2, nchar(nm)), ":"),
                              paths[[nm]]))
  }
  lines <- c(lines, "",
    "----------------------------------------------------------",
    "  RESULT COUNTS",
    "----------------------------------------------------------",
    sprintf("Total checks: %d", counts$total),
    sprintf("PASS:         %d", counts$pass),
    sprintf("DIFFER:       %d", counts$differ),
    sprintf("INFO:         %d", counts$info),
    "",
    "----------------------------------------------------------",
    "  FILES IN THIS RESULTS FOLDER",
    "----------------------------------------------------------",
    paste0("  ", files)
  )
  if (!is.null(what_was_done)) {
    lines <- c(lines, "",
      "----------------------------------------------------------",
      "  WHAT WAS DONE",
      "----------------------------------------------------------",
      what_was_done)
  }
  if (!is.null(contact)) lines <- c(lines, "", paste0("Contact: ", contact))
  if (!is.null(licence)) lines <- c(lines, paste0("Licence: ", licence))

  writeLines(lines, file.path(output_dir, "SUMMARY.txt"))
  invisible(file.path(output_dir, "SUMMARY.txt"))
}
