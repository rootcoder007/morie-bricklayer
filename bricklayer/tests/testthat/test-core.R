# SPDX-License-Identifier: AGPL-3.0-or-later

test_that("core_sha256 matches the FIPS 180-4 standard vectors", {
  # Canonical test vectors -- if these break, the C SHA-256 is wrong.
  expect_equal(core_sha256(""),
               "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  expect_equal(core_sha256("abc"),
               "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  expect_equal(
    core_sha256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
})

test_that("core_sha256 hashes raw the same as the equivalent string", {
  expect_equal(core_sha256(charToRaw("abc")), core_sha256("abc"))
})

test_that("core_sha256 is vectorised over character and cross-checks digest", {
  expect_equal(core_sha256(c("abc", "")),
               c(core_sha256("abc"), core_sha256("")))
  skip_if_not_installed("digest")
  expect_equal(core_sha256("provenance"),
               digest::digest("provenance", algo = "sha256", serialize = FALSE))
})

test_that("core stats match base R", {
  x <- c(2, 4, 4, 4, 5, 5, 7, 9)
  y <- (seq_along(x))^2
  expect_equal(core_mean(x), mean(x))
  expect_equal(core_var(x), var(x))
  expect_equal(core_cor(x, y), cor(x, y))
  expect_equal(core_normal_pdf(c(-1, 0, 1, 2.5), mean = 0.3, sd = 1.7),
               dnorm(c(-1, 0, 1, 2.5), mean = 0.3, sd = 1.7))
})

test_that("core stats handle degenerate input the way R's contract implies", {
  expect_true(is.nan(core_var(1)))             # sample variance needs n >= 2
  expect_true(is.nan(core_cor(c(1, 1, 1), c(2, 3, 4))))  # zero variance
  expect_true(is.nan(core_normal_pdf(0, sd = 0)))        # sd must be > 0
})
