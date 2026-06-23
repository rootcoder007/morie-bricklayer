## =====================================================================
## lib_helpers.R — interactive prompts, OS detection, path helpers
##
## Part of morie-bricklayer. Project-agnostic — no domain knowledge here.
##
## Provides:
##   say(...)                                Console writer
##   hr()                                    Horizontal rule
##   ask_yn(prompt, default, quick)          Y/N prompt
##   ask_path(prompt, default, quick)        Free-text path prompt
##   ask_menu(prompt, options, default, q)   Numbered menu
##   ask_save_location(prompt, default_key,  Constrained save-location menu
##                     script_dir, project,    (bundle / Downloads / Documents /
##                     quick)                   R-policy / custom)
##   detect_os()                             "macos", "windows", "linux-dnf",
##                                             "linux-apt", "linux-other"
##   sha256_file(path)                       SHA256 via the `digest` package
##
## Licence: AGPL-3.0-or-later
## =====================================================================

say <- function(...) cat(..., "\n", sep = "")
hr  <- function()    cat(strrep("-", 58), "\n", sep = "")

## ----------------- Y/N prompt -----------------
ask_yn <- function(prompt, default = "Y", quick = FALSE) {
  if (isTRUE(quick)) return(default == "Y")
  hint <- if (default == "Y") "[Y/n]" else "[y/N]"
  repeat {
    cat(sprintf("%s %s ", prompt, hint))
    ans <- readLines(con = "stdin", n = 1, warn = FALSE)
    if (length(ans) == 0L || nchar(ans) == 0L) ans <- default
    ans <- toupper(substr(ans, 1L, 1L))
    if (ans %in% c("Y", "N")) return(ans == "Y")
    cat("Please answer y or n.\n")
  }
}

## ----------------- Path prompt -----------------
ask_path <- function(prompt, default, quick = FALSE) {
  if (isTRUE(quick)) return(default)
  cat(sprintf("%s [%s] ", prompt, default))
  ans <- readLines(con = "stdin", n = 1, warn = FALSE)
  if (length(ans) == 0L || nchar(ans) == 0L) return(default)
  ans
}

## ----------------- Numbered menu -----------------
ask_menu <- function(prompt, options, default_index = 1L, quick = FALSE) {
  if (isTRUE(quick)) return(default_index)
  cat(prompt, "\n", sep = "")
  for (i in seq_along(options)) {
    marker <- if (i == default_index) " *" else "  "
    cat(sprintf("    %d.%s %s\n", i, marker, options[i]))
  }
  cat("  (* = default; press Enter to accept default)\n")
  cat(sprintf("  Your choice [%d]: ", default_index))
  ans <- readLines(con = "stdin", n = 1, warn = FALSE)
  if (length(ans) == 0L || !nzchar(ans)) return(default_index)
  n <- suppressWarnings(as.integer(ans))
  if (is.na(n) || n < 1L || n > length(options)) {
    cat("  Invalid choice; using default.\n")
    return(default_index)
  }
  n
}

## ----------------- Constrained save-location menu -----------------
## Allow-listed save locations only. Deliberately avoids:
##   - /tmp and /var/folders/.../T (transient, OS-managed, confusing)
##   - System directories (require admin rights)
##   - iCloud-synced locations (can fail unpredictably when offline)
##   - Anything outside the user's home directory
## All four core options are user-owned, never require sudo, and work
## identically on macOS, Windows, and Linux.
##
## `project_name` is used for the R-canonical option, which maps to
## tools::R_user_dir(project_name, "data").
ask_save_location <- function(prompt, default_key = "bundle",
                              script_dir,
                              project_name = "bricklayer-project",
                              quick = FALSE) {
  home <- Sys.getenv("HOME", path.expand("~"))
  r_user_dir <- tryCatch(tools::R_user_dir(project_name, which = "data"),
                         error = function(e) NA_character_)
  locs <- list(
    bundle    = list(label = paste0("This bundle folder  (",
                                    script_dir,
                                    ", self-contained — recommended)"),
                     path  = script_dir),
    downloads = list(label = paste0("Downloads folder    (",
                                    file.path(home, "Downloads"),
                                    ", browser default)"),
                     path  = file.path(home, "Downloads")),
    documents = list(label = paste0("Documents folder    (",
                                    file.path(home, "Documents"),
                                    ", organized storage)"),
                     path  = file.path(home, "Documents")),
    r_canon   = list(label = paste0("R-policy data folder (",
                                    if (is.na(r_user_dir)) "(R 4.0+ only)" else r_user_dir,
                                    ", what R itself recommends)"),
                     path  = if (is.na(r_user_dir)) NA_character_ else r_user_dir),
    custom    = list(label = "Other location (I'll type the folder path)",
                     path  = NA_character_)
  )
  keys <- names(locs)
  default_idx <- match(default_key, keys)
  labels <- vapply(locs, function(x) x$label, character(1))
  idx <- ask_menu(prompt, labels, default_idx, quick)
  chosen_key <- keys[idx]
  chosen <- locs[[chosen_key]]
  if (chosen_key == "custom" || is.na(chosen$path)) {
    if (chosen_key == "r_canon" && is.na(chosen$path)) {
      cat("  R 4.0+ is required for that option; using bundle folder.\n")
      return(script_dir)
    }
    custom <- ask_path("  Enter the folder path:",
                       file.path(home, "Downloads"), quick)
    custom <- path.expand(custom)
    if (!dir.exists(custom)) {
      cat("  ! That folder does not exist; using bundle folder instead.\n")
      return(script_dir)
    }
    return(normalizePath(custom, mustWork = FALSE))
  }
  if (!dir.exists(chosen$path)) {
    dir.create(chosen$path, recursive = TRUE, showWarnings = FALSE)
  }
  cat("  -> Folder selected: ", chosen$path, "\n", sep = "")
  normalizePath(chosen$path, mustWork = FALSE)
}

## ----------------- OS detection -----------------
detect_os <- function() {
  if (.Platform$OS.type == "windows") return("windows")
  if (Sys.info()[["sysname"]] == "Darwin") return("macos")
  if (Sys.which("dnf") != "") return("linux-dnf")
  if (Sys.which("apt") != "") return("linux-apt")
  "linux-other"
}

## ----------------- SHA256 (uses digest pkg) -----------------
sha256_file <- function(path) {
  if (!requireNamespace("digest", quietly = TRUE))
    stop("The 'digest' package is required for SHA256 verification.")
  digest::digest(file = path, algo = "sha256")
}
