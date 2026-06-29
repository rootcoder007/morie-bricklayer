## =====================================================================
##  otis_MRP.R
##
##  Canonical reproducibility script for the Major Research Paper:
##
##    "Alert Complexity and Placement Volatility in
##     Ontario Restrictive Confinement Data"
##
##    Vansh Singh Ruhela
##    MA, Centre for Criminology and Sociolegal Studies, U of T
##    vsruhela@proton.me
##    ORCID: 0009-0004-1750-3592
##    Submission target: August 17, 2026
##
##  Reproduces every numerical claim in CRIM_MRP_v2.{md,docx,tex}.
##  Runs end-to-end in a single Rscript invocation. All random
##  procedures are seeded; output is deterministic given the input
##  data and the seed value below.
##
##  USAGE:
##    Rscript otis_MRP.R [path-to-input] [output-dir]
##
##  INPUT (auto-detected by extension):
##    .RData  — author-prepared workspace with df + res_pool + res_by_year
##              Reproduces all 36 cross-checks.
##    .csv    — raw public OTIS A01RCDD dataset from
##              https://data.ontario.ca/dataset/data-on-inmates-in-ontario
##              (file: "Restrictive Confinement – Detailed Dataset English")
##              Reproduces 28 cross-checks; DML estimates record as INFO
##              because they're pre-computed in the .RData (see paper §5).
##
##  DEFAULTS:
##    Input:   /Volumes/VSR/rootcoderfiles/OTIS-RC/correctional_stats_report_environment1b.RData
##    Output:  ./otis_MRP_results/  (CSVs + manifest.json)
##
##  Dependencies (CRAN):
##    data.table, MatchIt, glmmTMB, lme4, DHARMa, Hmisc, jsonlite
##
##  Version: 2.1 (2026-06-23) — added CSV-direct mode (reads public OGL-Ontario
##                              dataset directly from data.ontario.ca format)
##  Version: 2.0 (2026-06-22) — switched to glmmTMB nbinom2 canonical model,
##                              added CSV outputs and manifest.json
##  License: AGPL-3.0-or-later (same as morie)
## =====================================================================

## --- 1. Setup and dependencies ----------------------------------------

suppressPackageStartupMessages({
  library(data.table)
  library(MatchIt)
  library(glmmTMB)
  library(lme4)
  library(Hmisc)
  library(jsonlite)
})

## Seed for ALL stochastic procedures. Do not change unless you intend
## to break the reproducibility guarantee.
CANONICAL_SEED <- 5824769L
set.seed(CANONICAL_SEED)

## CLI: input path + output dir
args <- commandArgs(trailingOnly = TRUE)
INPUT_PATH <- if (length(args) >= 1) args[1] else
  "/Volumes/VSR/rootcoderfiles/OTIS-RC/correctional_stats_report_environment1b.RData"
OUTPUT_DIR  <- if (length(args) >= 2) args[2] else
  file.path(getwd(), "otis_MRP_results")

dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)

## Detect input mode by file extension
INPUT_MODE <- if (grepl("\\.csv$", INPUT_PATH, ignore.case = TRUE)) "csv" else
              if (grepl("\\.RData$", INPUT_PATH, ignore.case = TRUE)) "rdata" else
              stop("Input must be .csv or .RData — got: ", INPUT_PATH)

## Synthetic-data mode is signalled by setup_and_run.R via env var.
## In this mode, all cross-checks are recorded as INFO (not PASS/DIFFER)
## because the data is randomly generated and not expected to match
## published values.
SYNTHETIC_MODE <- isTRUE(nzchar(Sys.getenv("BRICKLAYER_SYNTHETIC", "")) || nzchar(Sys.getenv("OTIS_SYNTHETIC", "")))
if (SYNTHETIC_MODE) {
  INPUT_MODE <- "synthetic"
}

cat("==========================================================\n")
cat("OTIS A01RCDD MRP Reproducibility Script (v2.2)\n")
cat("Input:  ", INPUT_PATH, "\n")
cat("Mode:   ", INPUT_MODE,
    if (INPUT_MODE == "csv")
      "  (public OGL-Ontario CSV — DML checks will be INFO)\n"
    else if (INPUT_MODE == "synthetic")
      "  (SYNTHETIC random data — ALL checks will be INFO, not authoritative)\n"
    else
      "  (author workspace — full 36 checks)\n", sep = "")
if (SYNTHETIC_MODE) {
  cat("\n")
  cat("  ********************************************************\n")
  cat("  *  WARNING: SYNTHETIC MODE. The numbers produced below  *\n")
  cat("  *  are computed on random data and do NOT reproduce the *\n")
  cat("  *  paper. Cross-checks are marked INFO, never PASS.     *\n")
  cat("  ********************************************************\n")
}
cat("Output: ", OUTPUT_DIR, "\n")
cat("Seed:   ", CANONICAL_SEED, "\n")
cat("Date:   ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), "\n")
cat("R:      ", R.version.string, "\n")
cat("==========================================================\n\n")

stopifnot(file.exists(INPUT_PATH))

if (INPUT_MODE == "rdata") {
  load(INPUT_PATH)
  stopifnot(exists("df"), is.data.frame(df))
  setDT(df)
} else {
  ## CSV-direct mode: load the public OTIS dataset, validate schema
  ## against pinned data_provenance.json (if present next to script),
  ## and map column names to the snake_case schema the pipeline expects.
  df_raw <- fread(INPUT_PATH, encoding = "UTF-8")

  ## --- Locate data_provenance.json next to this script (if present) ---
  ## R doesn't have a direct __file__; reconstruct via commandArgs(FALSE).
  script_path <- tryCatch({
    fa <- commandArgs(trailingOnly = FALSE)
    fp <- sub("^--file=", "", fa[grep("^--file=", fa)])
    if (length(fp) > 0L) normalizePath(fp[1]) else NA_character_
  }, error = function(e) NA_character_)
  script_dir <- if (!is.na(script_path)) dirname(script_path) else getwd()
  provenance_path <- file.path(script_dir, "data_provenance.json")

  ## Defaults if provenance file not bundled (back-compat for older runs)
  expected_cols <- c("EndFiscalYear", "UniqueIndividual_ID",
                     "Region_AtTimeOfPlacement", "Region_MostRecentPlacement",
                     "Gender", "Age_Category", "MentalHealth_Alert",
                     "SuicideRisk_Alert", "SuicideWatch_Alert",
                     "Number_Of_Placements")
  expected_value_sets <- list(
    Region_AtTimeOfPlacement   = c("Central","Eastern","Northern","Toronto","Western"),
    Region_MostRecentPlacement = c("Central","Eastern","Northern","Toronto","Western"),
    Gender                     = c("Male","Female"),
    Age_Category               = c("18 to 24","25 to 49","50+"),
    MentalHealth_Alert         = c("Yes","No"),
    SuicideRisk_Alert          = c("Yes","No"),
    SuicideWatch_Alert         = c("Yes","No")
  )
  min_rows <- 70000L; max_rows <- 90000L

  if (file.exists(provenance_path)) {
    cat("      Using schema from: ", provenance_path, "\n")
    prov <- jsonlite::fromJSON(provenance_path)
    if (!is.null(prov$schema$expected_columns))
      expected_cols <- prov$schema$expected_columns
    if (!is.null(prov$schema$expected_value_sets))
      expected_value_sets <- prov$schema$expected_value_sets
    if (!is.null(prov$schema$structural_invariants$min_data_rows))
      min_rows <- prov$schema$structural_invariants$min_data_rows
    if (!is.null(prov$schema$structural_invariants$max_data_rows))
      max_rows <- prov$schema$structural_invariants$max_data_rows
  } else {
    cat("      (data_provenance.json not found; using built-in schema)\n")
  }

  ## --- Schema validation: hard fail on missing required cols ---
  missing_cols <- setdiff(expected_cols, colnames(df_raw))
  if (length(missing_cols) > 0L) {
    stop("CSV missing expected columns: ",
         paste(missing_cols, collapse = ", "),
         "\nThis script expects the OTIS A01RCDD CSV from ",
         "https://data.ontario.ca/dataset/data-on-inmates-in-ontario ",
         "with the schema documented in data_provenance.json. ",
         "If Ontario has changed the column names, update ",
         "data_provenance.json's expected_columns to match.")
  }

  ## --- Schema validation: warn on row count out of expected range ---
  if (nrow(df_raw) < min_rows || nrow(df_raw) > max_rows) {
    warning("Row count ", nrow(df_raw), " is outside expected range [",
            min_rows, ", ", max_rows, "]. Data may have been substantially ",
            "expanded or trimmed since the pipeline was validated.")
  }

  ## --- Schema validation: warn on unexpected categorical values ---
  for (col in names(expected_value_sets)) {
    if (col %in% colnames(df_raw)) {
      actual_vals <- unique(df_raw[[col]])
      expected_vals <- expected_value_sets[[col]]
      unexpected <- setdiff(actual_vals, expected_vals)
      if (length(unexpected) > 0L) {
        warning("Column '", col, "' has unexpected values: ",
                paste(unexpected, collapse = ", "),
                ". Expected only: ", paste(expected_vals, collapse = ", "),
                ". Pipeline may not handle these correctly.")
      }
    }
  }

  csv_to_snake <- c(
    "EndFiscalYear"               = "end_fiscal_year",
    "UniqueIndividual_ID"         = "unique_individual_id",
    "Region_AtTimeOfPlacement"    = "region_at_time_of_placement",
    "Region_MostRecentPlacement"  = "region_most_recent_placement",
    "Gender"                      = "gender",
    "Age_Category"                = "age_category",
    "MentalHealth_Alert"          = "mental_health_alert",
    "SuicideRisk_Alert"           = "suicide_risk_alert",
    "SuicideWatch_Alert"          = "suicide_watch_alert",
    "Number_Of_Placements"        = "number_of_placements"
  )
  setnames(df_raw, old = names(csv_to_snake), new = unname(csv_to_snake))
  df <- df_raw[, unname(csv_to_snake), with = FALSE]
  setDT(df)
}

cat("[1/8] Raw data loaded.\n")
cat("      Rows in df:  ", nrow(df), "\n")
cat("      Cols:        ", paste(colnames(df), collapse = ", "), "\n\n")

## A manifest object that accumulates every claim+observation.
manifest <- list(
  meta = list(
    script        = "otis_MRP.R",
    version       = "2.2",
    seed          = CANONICAL_SEED,
    run_at        = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    r_version     = R.version.string,
    input_path    = INPUT_PATH,
    input_mode    = INPUT_MODE,
    synthetic     = SYNTHETIC_MODE,
    output_dir    = OUTPUT_DIR
  ),
  results = list()
)

record <- function(name, observed, expected, tol = 0.0001, group = "general") {
  diff <- if (is.numeric(observed) && is.numeric(expected))
    abs(observed - expected) else NA_real_
  ## In synthetic mode, never report PASS/DIFFER — the comparison is
  ## meaningless because the data is random. Always INFO.
  status <- if (SYNTHETIC_MODE) "INFO" else
            if (!is.na(diff) && diff <= tol) "PASS" else
            if (!is.na(diff)) "DIFFER" else "INFO"
  manifest$results[[name]] <<- list(
    group    = group,
    observed = observed,
    expected = expected,
    diff     = diff,
    status   = status,
    tol      = tol,
    note     = if (SYNTHETIC_MODE) "synthetic data — comparison not meaningful" else NULL
  )
  cat(sprintf("  %-44s observed = %-12s expected = %-12s [%s]\n",
              name,
              if (is.numeric(observed)) sprintf("%.4f", observed) else as.character(observed),
              if (is.numeric(expected)) sprintf("%.4f", expected) else as.character(expected),
              status))
}


## --- 2. Construct combo, ac, vm per canonical morie-oss formula -------

df[, mh := mental_health_alert == "Yes"]
df[, sr := suicide_risk_alert == "Yes"]
df[, sw := suicide_watch_alert == "Yes"]

df[, combo := fcase(
   mh & !sr & !sw, "a1",
  !mh &  sr & !sw, "a2",
   mh &  sr & !sw, "a4",
  !mh &  sr &  sw, "a5",
   mh &  sr &  sw, "a7",
  !mh & !sr & !sw, "a8",
  default = "other"
)]

setorder(df, unique_individual_id, end_fiscal_year, region_at_time_of_placement)
df[, vm_within := as.integer(region_at_time_of_placement != region_most_recent_placement)]
df[, regA_prev := shift(region_at_time_of_placement, type = "lag"),
   by = .(unique_individual_id, end_fiscal_year)]
df[, vm_across := as.integer(!is.na(regA_prev) &
                              region_at_time_of_placement != regA_prev)]
df[, vm_row := vm_within + vm_across]

cat("[2/8] vm and combo constructed.\n\n")


## --- 3. Person-year aggregation (orc) ---------------------------------

orc <- df[, .(
  vm = sum(vm_row),
  ac = uniqueN(intersect(combo, c("a1","a2","a4","a5","a7","a8"))),
  np = sum(number_of_placements),
  gender = first(gender),
  age = first(age_category),
  yr = first(end_fiscal_year),
  rc = paste(sort(unique(c(region_at_time_of_placement,
                           region_most_recent_placement))),
             collapse = " + ")
), by = .(unique_individual_id, end_fiscal_year)]
orc[, treat := as.integer(ac >= 2)]

## Encoding to match the OTIS Statistical Report exactly:
orc[, sg := ifelse(gender == "Male", 1L, 2L)]
orc[, sg := factor(sg, levels = c(1L, 2L), labels = c("M", "F"))]
orc[, ag := fcase(age == "18 to 24", 21,
                  age == "25 to 49", 42,
                  age == "50+",      57.5,
                  default = NA_real_)]
orc[, ag := factor(ag, levels = c("21", "42", "57.5"), ordered = TRUE)]
orc[, yr := factor(yr, levels = sort(unique(yr)), ordered = TRUE)]
orc[, rc := as.factor(rc)]

cat("[3/8] Person-year orc table built.\n\n")

cat("=== Cross-check: structural counts ===\n")
record("person_year_n",            nrow(orc),             65467, tol = 0, group = "structural")
record("total_placements_sum",     sum(orc$np),           1933327, tol = 0, group = "structural")

## Write orc summary CSV
fwrite(orc[, .(unique_individual_id, end_fiscal_year, vm, ac, np,
               gender, age, yr, rc, treat, sg, ag)],
       file.path(OUTPUT_DIR, "01_orc_person_year.csv"))


## --- 4. Full-sample descriptives --------------------------------------

cat("\n[4/8] Full-sample descriptives\n")

vm_mean   <- mean(orc$vm)
vm_sd     <- sd(orc$vm)
vm_min    <- min(orc$vm)
vm_max    <- max(orc$vm)
vm_wmean  <- wtd.mean(orc$vm, weights = orc$np)
vm_wsd    <- sqrt(wtd.var(orc$vm, weights = orc$np))

cat("\n=== Cross-check: vm full sample ===\n")
record("vm_full_unweighted_mean",     vm_mean,  0.089,  tol = 0.01, group = "descriptive_full")
record("vm_full_unweighted_sd",       vm_sd,    0.4627, tol = 0.01, group = "descriptive_full")
record("vm_full_unweighted_max",      vm_max,   9,      tol = 0.5,  group = "descriptive_full")
record("vm_full_np_weighted_mean",    vm_wmean, 0.1938, tol = 0.01, group = "descriptive_full")
record("vm_full_np_weighted_sd",      vm_wsd,   0.6852, tol = 0.01, group = "descriptive_full")
record("D1_proportion_full",          mean(orc$treat), 0.1109, tol = 0.01, group = "descriptive_full")

biv_D1_unw <- mean(orc$vm[orc$treat == 1])
biv_D0_unw <- mean(orc$vm[orc$treat == 0])
biv_D1_wgt <- wtd.mean(orc$vm[orc$treat == 1], weights = orc$np[orc$treat == 1])
biv_D0_wgt <- wtd.mean(orc$vm[orc$treat == 0], weights = orc$np[orc$treat == 0])

record("vm_full_unweighted_D1_mean", biv_D1_unw, 0.2709, tol = 0.01, group = "bivariate_full")
record("vm_full_unweighted_D0_mean", biv_D0_unw, 0.0663, tol = 0.01, group = "bivariate_full")
record("vm_full_npweighted_D1_mean", biv_D1_wgt, 0.3887, tol = 0.01, group = "bivariate_full")
record("vm_full_npweighted_D0_mean", biv_D0_wgt, 0.1500, tol = 0.01, group = "bivariate_full")

## Descriptive CSV
desc_full <- data.table(
  scope = "full_sample",
  weighting = c("unweighted", "unweighted", "unweighted", "unweighted",
                "np_weighted", "np_weighted", "np_weighted", "np_weighted"),
  statistic = c("mean", "sd", "min", "max", "mean", "sd",
                "D1_mean", "D0_mean"),
  value = c(vm_mean, vm_sd, vm_min, vm_max,
            vm_wmean, vm_wsd, biv_D1_wgt, biv_D0_wgt)
)
fwrite(desc_full, file.path(OUTPUT_DIR, "02_descriptive_full_sample.csv"))


## --- 5. Matching ------------------------------------------------------

set.seed(CANONICAL_SEED)
m.out <- matchit(treat ~ ag + sg + yr,
                 data = as.data.frame(orc),
                 method = "nearest",
                 distance = "glm",
                 weights = orc$np,
                 replace = FALSE)
orc_matched <- match.data(m.out)
setDT(orc_matched)

cat("\n[5/8] Matching complete.\n\n")
cat("=== Cross-check: matched sample ===\n")
record("matched_sample_n",        nrow(orc_matched),                14520, tol = 0, group = "matched")
record("matched_D1_count",        sum(orc_matched$treat == 1),      7260,  tol = 0, group = "matched")
record("matched_D0_count",        sum(orc_matched$treat == 0),      7260,  tol = 0, group = "matched")

m_mean   <- mean(orc_matched$vm)
m_sd     <- sd(orc_matched$vm)
m_max    <- max(orc_matched$vm)
m_wmean  <- wtd.mean(orc_matched$vm, weights = orc_matched$np)
m_wsd    <- sqrt(wtd.var(orc_matched$vm, weights = orc_matched$np))
m_D1_unw <- mean(orc_matched$vm[orc_matched$treat == 1])
m_D0_unw <- mean(orc_matched$vm[orc_matched$treat == 0])
m_D1_wgt <- wtd.mean(orc_matched$vm[orc_matched$treat == 1],
                     weights = orc_matched$np[orc_matched$treat == 1])
m_D0_wgt <- wtd.mean(orc_matched$vm[orc_matched$treat == 0],
                     weights = orc_matched$np[orc_matched$treat == 0])

record("vm_matched_unweighted_mean",    m_mean, 0.1729, tol = 0.01, group = "descriptive_matched")
record("vm_matched_unweighted_sd",      m_sd,   0.6881, tol = 0.01, group = "descriptive_matched")
record("vm_matched_unweighted_max",     m_max,  9,      tol = 0.5,  group = "descriptive_matched")
record("vm_matched_npweighted_mean",    m_wmean, 0.3019, tol = 0.01, group = "descriptive_matched")
record("vm_matched_npweighted_sd",      m_wsd,   0.9133, tol = 0.01, group = "descriptive_matched")
record("vm_matched_unweighted_D1_mean", m_D1_unw, 0.2709, tol = 0.01, group = "bivariate_matched")
record("vm_matched_unweighted_D0_mean", m_D0_unw, 0.0748, tol = 0.01, group = "bivariate_matched")
record("vm_matched_npweighted_D1_mean", m_D1_wgt, 0.3887, tol = 0.01, group = "bivariate_matched")
record("vm_matched_npweighted_D0_mean", m_D0_wgt, 0.1540, tol = 0.01, group = "bivariate_matched")

desc_matched <- data.table(
  scope = "matched_sample",
  weighting = c("unweighted","unweighted","unweighted","unweighted",
                "np_weighted","np_weighted","np_weighted","np_weighted",
                "unweighted","unweighted"),
  statistic = c("mean","sd","min","max","mean","sd","D1_mean","D0_mean",
                "D1_mean_unw","D0_mean_unw"),
  value = c(m_mean,m_sd,min(orc_matched$vm),m_max,m_wmean,m_wsd,
            m_D1_wgt,m_D0_wgt,m_D1_unw,m_D0_unw)
)
fwrite(desc_matched, file.path(OUTPUT_DIR, "03_descriptive_matched_sample.csv"))
fwrite(orc_matched[, .(unique_individual_id, end_fiscal_year, vm, ac, treat, weights, np, rc, yr, sg, ag)],
       file.path(OUTPUT_DIR, "04_matched_sample.csv"))


## --- 6. Negative-binomial GLMM via glmmTMB (the canonical published model)

cat("\n[6/8] glmmTMB nbinom2 (canonical published model_final_thesis)\n")
set.seed(CANONICAL_SEED)
fit_nb <- glmmTMB(
  vm ~ treat + ag + sg + yr + (1 | rc),
  data = orc_matched,
  family = nbinom2,
  weights = weights,
  control = glmmTMBControl(optimizer = optim,
                           optArgs = list(method = "BFGS"))
)
s_nb <- summary(fit_nb)
fix_nb <- s_nb$coefficients$cond
nb_coef <- fix_nb["treat", "Estimate"]
nb_se   <- fix_nb["treat", "Std. Error"]
nb_irr  <- exp(nb_coef)
nb_z    <- fix_nb["treat", "z value"]
nb_p    <- fix_nb["treat", "Pr(>|z|)"]
nb_aic  <- AIC(fit_nb)
nb_bic  <- BIC(fit_nb)

cat("\n=== Cross-check: negative-binomial GLMM ===\n")
record("nb_treat_coef",       nb_coef, 0.291, tol = 0.07, group = "model")
record("nb_treat_se",         nb_se,   0.052, tol = 0.02, group = "model")
record("nb_IRR",              nb_irr,  1.337, tol = 0.10, group = "model")
record("nb_AIC",              nb_aic,  3041.7, tol = 10, group = "model")

nb_table <- data.table(
  model = "glmmTMB_nbinom2",
  term = rownames(fix_nb),
  estimate = fix_nb[, "Estimate"],
  std_error = fix_nb[, "Std. Error"],
  z_value = fix_nb[, "z value"],
  p_value = fix_nb[, "Pr(>|z|)"],
  irr = exp(fix_nb[, "Estimate"])
)
fwrite(nb_table, file.path(OUTPUT_DIR, "05_nb_glmm_coefficients.csv"))


## --- 7. Pre-computed DML estimates (res_pool / res_by_year) ------------

## Reference DML values = the EXACT numbers reported in the MRP. Never change
## these; the recompute only compares against them.
.dml_refs <- list(
  DML_pooled_ATE_unclustered  = 0.1605, DML_pooled_ATTE_unclustered = 0.1557,
  DML_2023_ATE  = 0.1342, DML_2023_ATTE = 0.1272,
  DML_2024_ATE  = 0.1591, DML_2024_ATTE = 0.1550,
  DML_2025_ATE  = 0.1737, DML_2025_ATTE = 0.1704
)

## Optional recompute of the IRM DML from the PUBLIC data, mirroring the
## canonical OTIS-RC/explority.R spec: DoubleMLIRM with DETERMINISTIC learners
## (regr.lm + classif.log_reg), n_folds = 3, n_rep = 1, seed 1111111111,
## clustered on individual, data expanded by number_of_placements, Y = suicide-
## risk alert, D = mental-health alert. Deterministic learners + fixed seed mean
## a fresh run reproduces the published estimates up to small cross-platform RNG
## drift, hence the +/-0.02 tolerance.
recompute_dml_irm <- function(d) {
  for (pkg in c("DoubleML", "mlr3", "mlr3learners"))
    if (!requireNamespace(pkg, quietly = TRUE))
      stop("DML recompute needs package '", pkg, "'. Install it, or decline ",
           "the recompute (the checks then record as INFO).")
  if (requireNamespace("lgr", quietly = TRUE))
    lgr::get_logger("mlr3")$set_threshold("warn")
  lrn <- mlr3::lrn

  d <- data.table::copy(d)
  d[, number_of_placements := as.integer(number_of_placements)]
  d <- d[!is.na(number_of_placements) & number_of_placements > 0L]
  d <- d[rep.int(seq_len(.N), number_of_placements)]   # expand by placements
  d[, Y := as.integer(suicide_risk_alert == "Yes")]
  d[, D := as.integer(mental_health_alert == "Yes")]
  d[, cluster_id := as.factor(unique_individual_id)]

  ml_g <- lrn("regr.lm")
  ml_m <- lrn("classif.log_reg", predict_type = "prob")

  fit_irm <- function(dsub, x_cols, tag) {
    for (cc in x_cols) dsub[[cc]] <- as.factor(dsub[[cc]])
    dml_data <- DoubleML::DoubleMLClusterData$new(
      data = dsub, y_col = "Y", d_cols = "D",
      x_cols = x_cols, cluster_cols = "cluster_id")
    set.seed(1111111111)
    a <- DoubleML::DoubleMLIRM$new(dml_data, ml_g = ml_g, ml_m = ml_m,
                                   n_folds = 3, n_rep = 1, score = "ATE"); a$fit()
    set.seed(1111111111)
    b <- DoubleML::DoubleMLIRM$new(dml_data, ml_g = ml_g, ml_m = ml_m,
                                   n_folds = 3, n_rep = 1, score = "ATTE"); b$fit()
    data.table(group = tag, estimand = c("ATE", "ATTE"),
               effect = c(as.numeric(a$coef), as.numeric(b$coef)))
  }
  x_pool <- c("gender", "age_category", "region_at_time_of_placement",
              "region_most_recent_placement", "end_fiscal_year")
  x_year <- setdiff(x_pool, "end_fiscal_year")
  kp <- stats::complete.cases(d[, c("Y", "D", "cluster_id", x_pool), with = FALSE])
  rp <- fit_irm(d[kp, c("Y", "D", "cluster_id", x_pool), with = FALSE], x_pool, "Pooled 2023-25")
  rby <- data.table::rbindlist(lapply(sort(unique(d$end_fiscal_year)), function(yy) {
    s  <- d[end_fiscal_year == yy]
    ky <- stats::complete.cases(s[, c("Y", "D", "cluster_id", x_year), with = FALSE])
    fit_irm(s[ky, c("Y", "D", "cluster_id", x_year), with = FALSE], x_year, as.character(yy))
  }))
  list(res_pool = rp, res_by_year = rby)
}

## OPTIONAL canonical engine: if the author's own 'rmorie' package is installed,
## use its rmorie::morie_otis_irm_dml() (ols outcome + logit propensity -- the
## SAME learners as the published spec) instead of the self-contained DoubleML
## port. It is ~300x faster (reference ~10 s vs ~24 min) and reproduces the
## published effects to <=0.001. cluster_cols=NULL: we cross-check the EFFECT
## estimates only (clustering changes the SE, not the point estimate; rmorie's
## by-year cluster-SE path is separately buggy and unrelated to this check).
recompute_dml_via_rmorie <- function(d) {
  d <- data.table::copy(d)
  d[, number_of_placements := as.integer(number_of_placements)]
  d <- d[!is.na(number_of_placements) & number_of_placements > 0L]
  d <- d[rep.int(seq_len(.N), number_of_placements)]
  d[, Y := as.integer(suicide_risk_alert == "Yes")]
  d[, D := as.integer(mental_health_alert == "Yes")]
  d[, cluster_id := as.factor(unique_individual_id)]
  one <- function(dat, xcov) {
    for (cc in xcov) dat[[cc]] <- droplevels(as.factor(dat[[cc]]))
    r <- rmorie::morie_otis_irm_dml(as.data.frame(dat), treatment = "D",
           outcome = "Y", covariates = xcov, cluster_cols = NULL,
           n_folds = 3L, seed = 1111111111L)
    c(as.numeric(r$ate), as.numeric(r$atte))
  }
  x_pool <- c("gender", "age_category", "region_at_time_of_placement",
              "region_most_recent_placement", "end_fiscal_year")
  x_year <- setdiff(x_pool, "end_fiscal_year")
  p   <- one(data.table::copy(d), x_pool)
  yrs <- sort(unique(d$end_fiscal_year))
  by  <- unlist(lapply(yrs, function(yy) one(d[end_fiscal_year == yy], x_year)))
  list(
    res_pool    = data.table(group = "Pooled 2023-25",
                             estimand = c("ATE", "ATTE"), effect = p),
    res_by_year = data.table(group = rep(as.character(yrs), each = 2L),
                             estimand = rep(c("ATE", "ATTE"), length(yrs)),
                             effect = by)
  )
}

if (INPUT_MODE == "rdata" && exists("res_pool") && exists("res_by_year")) {
  cat("\n[7/8] Pre-computed DML estimates from RData\n")
  setDT(res_pool); setDT(res_by_year)
  fwrite(res_pool,    file.path(OUTPUT_DIR, "06_DML_res_pool.csv"))
  fwrite(res_by_year, file.path(OUTPUT_DIR, "07_DML_res_by_year.csv"))

  record("DML_pooled_ATE_unclustered",   res_pool$effect[1], 0.1605, tol = 0.001, group = "DML")
  record("DML_pooled_ATTE_unclustered",  res_pool$effect[2], 0.1557, tol = 0.001, group = "DML")
  record("DML_2023_ATE",                 res_by_year$effect[1], 0.1342, tol = 0.001, group = "DML")
  record("DML_2023_ATTE",                res_by_year$effect[2], 0.1272, tol = 0.001, group = "DML")
  record("DML_2024_ATE",                 res_by_year$effect[3], 0.1591, tol = 0.001, group = "DML")
  record("DML_2024_ATTE",                res_by_year$effect[4], 0.1550, tol = 0.001, group = "DML")
  record("DML_2025_ATE",                 res_by_year$effect[5], 0.1737, tol = 0.001, group = "DML")
  record("DML_2025_ATTE",                res_by_year$effect[6], 0.1704, tol = 0.001, group = "DML")

} else if (tolower(Sys.getenv("OTIS_DML_RECOMPUTE", "")) %in% c("1", "yes", "true", "y")) {
  if (requireNamespace("rmorie", quietly = TRUE)) {
    cat("\n[7/8] Recomputing DML via canonical rmorie::morie_otis_irm_dml ...\n")
    cat("      Using your installed 'rmorie' package (ols outcome + logit\n")
    cat("      propensity -- the published learners). FAST: reference run ~10 s.\n")
    cat("      Comparing to the published MRP estimates at tolerance +/- 0.02.\n")
    dml <- recompute_dml_via_rmorie(df)
  } else {
    cat("\n[7/8] Recomputing DML from PUBLIC data (self-contained DoubleML) ...\n")
    cat("      ****************************************************************\n")
    cat("      *  HEAVY + SLOW fallback (no 'rmorie' installed). DoubleML +    *\n")
    cat("      *  mlr3; expands to ~1.9M rows; reference ~24 min + ~1.2 GB RAM.*\n")
    cat("      *  TIP: install 'rmorie' for the fast ~10 s canonical path.     *\n")
    cat("      *  Checks a FRESH IRM run vs published MRP estimates +/- 0.02.   *\n")
    cat("      ****************************************************************\n")
    dml <- recompute_dml_irm(df)
  }
  fwrite(dml$res_pool,    file.path(OUTPUT_DIR, "06_DML_res_pool.csv"))
  fwrite(dml$res_by_year, file.path(OUTPUT_DIR, "07_DML_res_by_year.csv"))

  record("DML_pooled_ATE_unclustered",   dml$res_pool$effect[1],    0.1605, tol = 0.02, group = "DML")
  record("DML_pooled_ATTE_unclustered",  dml$res_pool$effect[2],    0.1557, tol = 0.02, group = "DML")
  record("DML_2023_ATE",                 dml$res_by_year$effect[1], 0.1342, tol = 0.02, group = "DML")
  record("DML_2023_ATTE",                dml$res_by_year$effect[2], 0.1272, tol = 0.02, group = "DML")
  record("DML_2024_ATE",                 dml$res_by_year$effect[3], 0.1591, tol = 0.02, group = "DML")
  record("DML_2024_ATTE",                dml$res_by_year$effect[4], 0.1550, tol = 0.02, group = "DML")
  record("DML_2025_ATE",                 dml$res_by_year$effect[5], 0.1737, tol = 0.02, group = "DML")
  record("DML_2025_ATTE",                dml$res_by_year$effect[6], 0.1704, tol = 0.02, group = "DML")

  ## 37th check: overall confirmation that the FRESH public-data recompute
  ## matches ALL 8 published MRP estimates within tolerance -> 37/37 when the
  ## heavy path is run (36 deterministic+DML + this aggregate).
  all_within <- all(abs(c(dml$res_pool$effect, dml$res_by_year$effect) -
                        unlist(.dml_refs, use.names = FALSE)) <= 0.02)
  record("DML_recompute_matches_published", as.integer(all_within), 1L,
         tol = 0, group = "DML")

} else {
  cat("\n[7/8] Skipping DML recompute (CSV mode; default) -- recording as INFO\n")
  cat("      The 8 DML estimates are pre-computed in the authors' .RData.\n")
  cat("      The 28 deterministic checks above already reproduce from THIS\n")
  cat("      public data. As a FINAL, optional deep-verification you can also\n")
  cat("      recompute the 8 DML estimates from this public data and confirm\n")
  cat("      they match the authors' published MRP values (+/- 0.02) -> 37/37:\n")
  cat("          OTIS_DML_RECOMPUTE=1\n")
  cat("      Do this LAST and only if you want full self-verification.\n")
  cat("      FAST (~10 s) if 'rmorie' is installed (canonical morie_otis_irm_dml);\n")
  cat("      otherwise a HEAVY ~24 min self-contained DoubleML fallback runs.\n")
  cat("      Most reviewers can skip it.\n")
  for (nm in names(.dml_refs))
    record(nm, "not-computed", .dml_refs[[nm]], tol = 0, group = "DML")
}


## --- 8. Manifest output -----------------------------------------------

cat("\n[8/8] Writing manifest.json\n")
write_json(manifest, file.path(OUTPUT_DIR, "manifest.json"),
           auto_unbox = TRUE, pretty = TRUE)

## Synthetic-mode watermark file in the results folder
if (SYNTHETIC_MODE) {
  warning_lines <- c(
    "##########################################################",
    "#                                                        #",
    "#  WARNING: THIS RESULTS FOLDER IS FROM SYNTHETIC DATA   #",
    "#                                                        #",
    "##########################################################",
    "",
    "The CSV and manifest.json files in this folder were",
    "produced from a randomly-generated synthetic dataset that",
    "MATCHES THE OTIS A01RCDD SCHEMA but contains NO REAL",
    "INFORMATION about anyone.",
    "",
    "The numbers in these files DO NOT REPRODUCE the paper",
    "'Alert Complexity and Placement Volatility in Ontario",
    "Restrictive Confinement Data' and CANNOT be used to",
    "verify any of its claims.",
    "",
    "This mode exists so that reviewers without internet or",
    "without access to the public OTIS dataset can confirm",
    "that the analysis pipeline works correctly on their",
    "machine. To actually reproduce the paper, please obtain",
    "the real public CSV from:",
    "",
    "  https://data.ontario.ca/dataset/data-on-inmates-in-ontario",
    "",
    "Run time:    ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    "Synthetic CSV: ", INPUT_PATH,
    "Pipeline seed: ", CANONICAL_SEED
  )
  writeLines(warning_lines, file.path(OUTPUT_DIR, "SYNTHETIC.txt"))
}

## Summary count
all_results <- manifest$results
pass_n <- sum(sapply(all_results, function(x) x$status == "PASS"))
diff_n <- sum(sapply(all_results, function(x) x$status == "DIFFER"))
info_n <- sum(sapply(all_results, function(x) x$status == "INFO"))

cat("\n==========================================================\n")
cat("REPRODUCIBILITY SUMMARY\n")
cat("==========================================================\n")
cat(sprintf("  Total checks:  %d\n", length(all_results)))
cat(sprintf("  PASS:          %d\n", pass_n))
cat(sprintf("  DIFFER:        %d\n", diff_n))
cat(sprintf("  INFO:          %d\n", info_n))
cat("\nAll CSV outputs in: ", OUTPUT_DIR, "\n")
cat("Files written:\n")
for (f in list.files(OUTPUT_DIR)) {
  cat("  -", f, "\n")
}
cat("\n==========================================================\n")
cat("END OF SCRIPT\n")
cat("==========================================================\n")
