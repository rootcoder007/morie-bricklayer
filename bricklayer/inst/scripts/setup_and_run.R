## =====================================================================
## setup_and_run.R
##
## Brick-proof, cross-platform (macOS / Windows / Linux) entrypoint for
## any morie-bricklayer bundle. Driven entirely by config.json and
## data_provenance.json — knows nothing about specific datasets.
##
## What it does:
##   1. Detects OS, loads project config + provenance, sources libs.
##   2. Auto-installs missing R packages (from config$r_packages).
##   3. Locates the input data file (probe defaults → menu of options:
##      already have it / manual download / auto-download / synthetic).
##   4. Runs the project's analysis script as a subprocess.
##   5. Writes manifest.json + SUMMARY.txt with full provenance.
##
## Only external requirement: R 4.0+. No bash, zsh, python, curl, jq,
## brew, apt, dnf, or winget required.
##
## USAGE:
##   Rscript setup_and_run.R              # interactive
##   Rscript setup_and_run.R --quick      # non-interactive (defaults)
##   Rscript setup_and_run.R --data PATH  # explicit data path
##   Rscript setup_and_run.R --help
##
## Licence: AGPL-3.0-or-later
## Part of morie-bricklayer.
## =====================================================================

## ---------- Locate script directory + parse CLI ----------
script_dir <- (function() {
  fa <- commandArgs(trailingOnly = FALSE)
  fp <- sub("^--file=", "", fa[grep("^--file=", fa)])
  if (length(fp) > 0L) normalizePath(dirname(fp[1])) else getwd()
})()
setwd(script_dir)

args <- commandArgs(trailingOnly = TRUE)
QUICK_MODE <- any(args %in% c("-q", "--quick"))
HELP_MODE  <- any(args %in% c("-h", "--help"))
DATA_ARG   <- NULL
if (any(args == "--data")) {
  i <- which(args == "--data")[1]
  if (length(args) >= i + 1) DATA_ARG <- args[i + 1]
}

if (HELP_MODE) {
  cat(readLines("setup_and_run.R")[
      grep("^## USAGE", readLines("setup_and_run.R"))[1] + 0:5],
      sep = "\n")
  quit(status = 0)
}

## ---------- Source libraries ----------
LIB_DIR <- script_dir  # libs may be next to setup_and_run.R after bundle build
for (lib in c("lib_helpers.R", "lib_data_loader.R",
              "lib_synthetic.R", "lib_manifest.R")) {
  lib_path <- file.path(LIB_DIR, lib)
  if (!file.exists(lib_path))
    stop("Required library not found: ", lib_path)
  source(lib_path)
}

## ---------- Load project config + provenance ----------
CONFIG_PATH     <- file.path(script_dir, "config.json")
PROVENANCE_PATH <- file.path(script_dir, "data_provenance.json")
if (!file.exists(CONFIG_PATH))
  stop("config.json not found at ", CONFIG_PATH)
if (!requireNamespace("jsonlite", quietly = TRUE)) {
  install.packages("jsonlite", repos = "https://cloud.r-project.org",
                   quiet = TRUE)
}
cfg <- jsonlite::fromJSON(CONFIG_PATH, simplifyVector = FALSE)
prov <- load_provenance(PROVENANCE_PATH)

PROJECT_NAME    <- cfg$project$name         %||% "bricklayer-project"
PROJECT_AUTHOR  <- cfg$project$author       %||% "(unknown author)"
PROJECT_CONTACT <- cfg$project$contact      %||% ""
PROJECT_LICENCE <- cfg$project$licence      %||% "AGPL-3.0-or-later"
ANALYSIS_R      <- file.path(script_dir,
                             cfg$analysis$r_script %||% "analysis.R")
REQ_PKGS        <- unlist(cfg$r_packages) %||% c()

## ---------- Banner + OS detection ----------
OS_KIND <- detect_os()

cat("==========================================================\n")
cat("  morie-bricklayer Reproducibility Runner\n")
cat("  Project: ", PROJECT_NAME, "\n", sep = "")
cat("  Author:  ", PROJECT_AUTHOR, "\n", sep = "")
cat("==========================================================\n")
say("OS detected:    ", OS_KIND)
say("R version:      ", R.version.string)
say("Mode:           ", if (QUICK_MODE) "quick (non-interactive)" else "interactive")
cat("\n")

## ---------- WHERE EVERYTHING WILL GO panel ----------
home_dir       <- normalizePath(Sys.getenv("HOME", path.expand("~")),
                                winslash = "/", mustWork = FALSE)
default_result <- file.path(script_dir,
                            paste0("results_",
                                   format(Sys.time(), "%Y%m%d-%H%M%S")))
r_user_data    <- tryCatch(tools::R_user_dir(PROJECT_NAME, which = "data"),
                           error = function(e) "(R 4.0+ required)")

cat("----------------------------------------------------------\n")
cat("  WHERE EVERYTHING WILL GO\n")
cat("----------------------------------------------------------\n")
cat("  This script writes ONLY to the locations below. It never\n")
cat("  touches system files and never requires admin/sudo rights.\n\n")
cat("  Bundle folder (where setup_and_run.R lives — DEFAULT):\n")
cat("    ", script_dir, "\n", sep = "")
cat("  Results subfolder (created fresh on each run):\n")
cat("    ", default_result, "\n", sep = "")
cat("  Your home directory:\n")
cat("    ", home_dir, "\n", sep = "")
cat("  R's OS-canonical data folder (R-policy location):\n")
cat("    ", r_user_data, "\n", sep = "")
cat("\n  Internet endpoints the script may contact:\n")
for (url in unlist(cfg$network$endpoints %||% c())) {
  cat("    - ", url, "\n", sep = "")
}
cat("    - https://cloud.r-project.org           (CRAN R packages)\n")
cat("    - https://web.archive.org/web/...       (Wayback fallback, if needed)\n")
cat("  No telemetry. No third-party services. No personal data leaves your machine.\n")
cat("----------------------------------------------------------\n\n")

## ---------- 1. Sanity-check companion files ----------
if (!file.exists(ANALYSIS_R)) {
  say("ERROR: analysis script not found: ", ANALYSIS_R)
  say("  Set cfg$analysis$r_script in config.json correctly.")
  quit(status = 2)
}

## ---------- 2. Auto-install R packages ----------
say("Step 1/5: Checking R packages...")
if (length(REQ_PKGS) > 0L) {
  installed <- rownames(installed.packages())
  missing_pkgs <- setdiff(REQ_PKGS, installed)
  if (length(missing_pkgs) > 0L) {
    say("  Missing: ", paste(missing_pkgs, collapse = ", "))
    if (ask_yn("  Install missing packages now?", "Y", QUICK_MODE)) {
      say("  Installing (this can take 2-5 minutes on first run)...")
      install.packages(missing_pkgs,
                       repos = "https://cloud.r-project.org",
                       quiet = TRUE)
      still <- setdiff(REQ_PKGS, rownames(installed.packages()))
      if (length(still) > 0L) {
        say("ERROR: failed to install: ", paste(still, collapse = ", "))
        quit(status = 3)
      }
      say("  ✓ All packages installed.")
    } else {
      say("  Skipping — analysis may fail if anything is missing.")
    }
  } else {
    say("  ✓ All required packages present.")
  }
} else {
  say("  (No packages declared in config$r_packages.)")
}
hr()

## ---------- 3. Locate input data ----------
say("Step 2/5: Locating the input data...")
input_path <- NULL
SYNTHETIC_MODE <- FALSE

dataset_url     <- prov$dataset$catalogue_page %||% "(no catalogue page in provenance)"
resource_name   <- prov$resource$name          %||% "(no resource name in provenance)"
licence_label   <- prov$dataset$licence_short  %||% prov$dataset$licence_name %||% ""

## Default candidates (probe before asking)
default_candidates <- function() {
  home <- Sys.getenv("HOME", path.expand("~"))
  fn   <- prov$resource$filename %||% "input.csv"
  cands <- c(
    file.path(script_dir, fn),
    file.path(home, "Desktop", fn),
    file.path(home, "Downloads", fn),
    file.path(home, "Documents", fn),
    file.path(script_dir, "input.csv"),
    file.path(script_dir, "data.csv")
  )
  unlist(c(cands, cfg$data$default_candidates %||% c()))
}

if (!is.null(DATA_ARG)) {
  if (!file.exists(DATA_ARG)) {
    say("ERROR: --data path does not exist: ", DATA_ARG)
    quit(status = 4)
  }
  input_path <- DATA_ARG
  say("  Using --data: ", input_path)
} else {
  cands <- default_candidates()
  hits  <- cands[file.exists(cands)]
  if (length(hits) > 0L) {
    say("  Found a candidate file at:")
    say("    ", hits[1])
    if (ask_yn("  Use this file?", "Y", QUICK_MODE)) input_path <- hits[1]
  }

  if (is.null(input_path)) {
    say("")
    say("  This project uses the following dataset:")
    say("    Resource: ", resource_name)
    say("    Source:   ", dataset_url)
    if (nzchar(licence_label)) say("    Licence:  ", licence_label)
    say("")
    menu_options <- c(
      "I already have the file on this computer — I'll tell you where",
      "Open the link and download it myself in a browser",
      "Have this script download it for me (needs internet)",
      "Run on SYNTHETIC fake data (no internet, no real data — testing only)",
      "Cancel and exit"
    )
    choice <- ask_menu("  How would you like to proceed?",
                       menu_options, 3L, QUICK_MODE)

    if (choice == 1L) {
      hint_dir <- ask_save_location(
        "  Pick the folder it's in:",
        default_key  = "downloads",
        script_dir   = script_dir,
        project_name = PROJECT_NAME,
        quick        = QUICK_MODE)
      default_name <- prov$resource$filename %||% "input.csv"
      typed <- ask_path("  Enter the file name (just the name, not full path):",
                        default_name, QUICK_MODE)
      candidate <- file.path(hint_dir, typed)
      if (!file.exists(candidate))
        candidate <- ask_path("  Enter the FULL path to the file:",
                              candidate, QUICK_MODE)
      if (!file.exists(candidate)) {
        say("ERROR: file does not exist: ", candidate); quit(status = 4)
      }
      input_path <- normalizePath(candidate)
    }

    else if (choice == 2L) {
      say("")
      say("  Open this URL in any browser:")
      say("    ", dataset_url)
      say("  Find the resource: '", resource_name, "' and download it.")
      save_dir <- ask_save_location(
        "  Where will the file end up after you download it?",
        default_key  = "downloads",
        script_dir   = script_dir,
        project_name = PROJECT_NAME,
        quick        = QUICK_MODE)
      say("  Press Enter when the download is complete.")
      if (!QUICK_MODE) invisible(readLines(con = "stdin", n = 1, warn = FALSE))
      default_name <- prov$resource$filename %||% "input.csv"
      typed <- ask_path("  What is the downloaded file's name?",
                        default_name, QUICK_MODE)
      candidate <- file.path(save_dir, typed)
      if (!file.exists(candidate))
        candidate <- ask_path("  Enter the FULL path to the file:",
                              candidate, QUICK_MODE)
      if (!file.exists(candidate)) {
        say("ERROR: file does not exist: ", candidate); quit(status = 4)
      }
      input_path <- normalizePath(candidate)
      if (!is.null(prov$resource$sha256)) {
        v <- verify_sha256(input_path, prov$resource$sha256)
        if (v$match) say("  ✓ SHA256 matches pinned provenance.")
        else say("  ! SHA256 differs — the file may be a newer release.")
      }
    }

    else if (choice == 3L) {
      save_dir <- ask_save_location(
        "  Where should I save the downloaded file?",
        default_key  = "bundle",
        script_dir   = script_dir,
        project_name = PROJECT_NAME,
        quick        = QUICK_MODE)
      url <- resolve_via_ckan(prov)
      if (is.null(url)) url <- resolve_via_ckan_search(prov)
      if (is.null(url)) url <- prov$resource$direct_url
      if (is.null(url)) {
        say("ERROR: no download URL available — provenance missing.")
        quit(status = 5)
      }
      fn <- prov$resource$filename %||% basename(url)
      target <- file.path(save_dir, fn)
      say("  Downloading: ", url)
      say("  → ", target)
      wb_url <- prov$wayback$csv_snapshot %||% ""
      if (!friendly_download(url, target,
                              attempt_wayback = if (nzchar(wb_url)) wb_url else NULL)) {
        say("  All download paths exhausted. Options:")
        say("    1) Re-run after disabling your VPN")
        say("    2) Download manually from: ", prov$dataset$catalogue_page)
        say("    3) Try synthetic mode (no internet required)")
        quit(status = 5)
      }
      input_path <- target
      if (!is.null(prov$resource$sha256)) {
        v <- verify_sha256(target, prov$resource$sha256)
        if (v$match) say("  ✓ SHA256 byte-for-byte match.")
        else say("  ! SHA256 differs — Ontario may have updated the data.")
      }
    }

    else if (choice == 4L) {
      say("")
      say("  *** SYNTHETIC DATA MODE ***")
      say("  Generates random fake data that matches the schema.")
      say("  Pipeline will run end-to-end but results are NOT real and")
      say("  CANNOT verify any claim in the paper.")
      say("")
      if (!ask_yn("  Confirm — generate synthetic data and run on it?",
                  "N", QUICK_MODE)) {
        say("  Cancelled."); quit(status = 0)
      }
      save_dir <- ask_save_location(
        "  Where should I save the synthetic CSV?",
        default_key  = "bundle",
        script_dir   = script_dir,
        project_name = PROJECT_NAME,
        quick        = QUICK_MODE)
      synth_schema <- prov$schema$synthetic_recipe
      if (is.null(synth_schema)) {
        say("ERROR: data_provenance.json has no schema.synthetic_recipe block.")
        say("  Synthetic mode requires the project author to define a recipe.")
        quit(status = 6)
      }
      target <- file.path(save_dir, "SYNTHETIC_data.csv")
      say("  Generating synthetic dataset...")
      info <- make_synthetic_csv(synth_schema, target)
      say("  Wrote ", info$rows, " rows (seed = ", info$seed, ") to: ", target)
      input_path <- target
      SYNTHETIC_MODE <- TRUE
    }

    else {
      say("  Exiting at user request."); quit(status = 0)
    }
  }
}
hr()

## ---------- 4. Run the project's analysis script ----------
say("Step 3/5: Running ", basename(ANALYSIS_R), "...")
output_dir <- default_result
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
say("  Input:   ", input_path)
say("  Output:  ", output_dir)
say("")
if (!ask_yn("  Start the analysis now?", "Y", QUICK_MODE)) {
  say("OK — exiting without running."); quit(status = 0)
}
hr()

log_path <- file.path(output_dir, "run.log")
rscript_bin <- file.path(R.home("bin"),
                         if (OS_KIND == "windows") "Rscript.exe" else "Rscript")

if (isTRUE(SYNTHETIC_MODE)) {
  cat("\n##########################################################\n")
  cat("#   ⚠  SYNTHETIC DATA MODE — RESULTS ARE NOT REAL  ⚠     #\n")
  cat("##########################################################\n\n")
}

run_args <- c(ANALYSIS_R, shQuote(input_path), shQuote(output_dir))
env_vec <- if (isTRUE(SYNTHETIC_MODE)) "BRICKLAYER_SYNTHETIC=1" else character(0)
exit_code <- system2(rscript_bin, run_args,
                     stdout = log_path, stderr = log_path,
                     env = env_vec)
cat(readLines(log_path, warn = FALSE), sep = "\n")
hr()

## ---------- 5. Results summary + SUMMARY.txt ----------
say("Step 4/5: Results summary")
manifest_path <- file.path(output_dir, "manifest.json")
if (file.exists(manifest_path)) {
  m <- jsonlite::fromJSON(manifest_path, simplifyVector = FALSE)
  counts <- summarise_counts(m)
  say(sprintf("  Total:  %d", counts$total))
  say(sprintf("  PASS:   %d", counts$pass))
  say(sprintf("  DIFFER: %d", counts$differ))
  say(sprintf("  INFO:   %d", counts$info))
  ## Drop a SUMMARY.txt
  m$meta$project   <- PROJECT_NAME
  m$meta$author    <- PROJECT_AUTHOR
  m$meta$os        <- OS_KIND
  m$meta$synthetic <- SYNTHETIC_MODE
  write_summary_txt(
    m, output_dir,
    paths = list(
      bundle         = script_dir,
      input          = input_path,
      results        = output_dir,
      analysis_script = ANALYSIS_R,
      provenance     = PROVENANCE_PATH
    ),
    what_was_done = unlist(cfg$summary$what_was_done %||%
                            list("Ran the project's analysis script.",
                                 "Wrote CSV outputs and manifest.json.")),
    contact = PROJECT_CONTACT,
    licence = paste0(PROJECT_LICENCE,
                     if (!is.null(prov$dataset$licence_short))
                       paste0(" (scripts); ",
                              prov$dataset$licence_short, " (data)")
                     else "")
  )
} else {
  say("  WARNING: manifest.json not produced. Check run.log.")
}
hr()

say("Step 5/5: Done.")
say("  Results folder: ", output_dir)
say("  Plain-language summary: SUMMARY.txt in that folder.")

if (ask_yn("  Open the results folder now?", "Y", QUICK_MODE)) {
  if (OS_KIND == "macos") system2("open", shQuote(output_dir))
  else if (OS_KIND == "windows") shell.exec(output_dir)
  else tryCatch(system2("xdg-open", shQuote(output_dir)),
                error = function(e) invisible(NULL))
}

quit(status = exit_code)
