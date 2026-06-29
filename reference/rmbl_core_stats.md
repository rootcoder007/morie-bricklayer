# Fast summary statistics (C backend)

Thin R wrappers over the `rmoriebricklayer` compiled core – the same
kernels that sibling packages reach through
`LinkingTo: rmoriebricklayer`. NA/NaN values propagate (there is no
`na.rm`); call
[`stats::na.omit()`](https://rdrr.io/r/stats/na.fail.html) first if you
need NA handling.

## Usage

``` r
core_mean(x)

core_var(x)

core_cor(x, y)
```

## Arguments

- x, y:

  Numeric vectors (coerced with
  [`as.numeric()`](https://rdrr.io/r/base/numeric.html)).

## Value

`core_mean()`, `core_var()` and `core_cor()` return a length-1 numeric.
`core_var()` uses the `n - 1` (sample) denominator, matching
[`stats::var()`](https://rdrr.io/r/stats/cor.html).

## Examples

``` r
core_mean(1:10)
#> [1] 5.5
core_var(c(2, 4, 4, 4, 5, 5, 7, 9))
#> [1] 4.571429
core_cor(1:10, (1:10)^2)
#> [1] 0.9745586
```
