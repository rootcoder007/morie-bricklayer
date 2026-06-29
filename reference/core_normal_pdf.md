# Normal density (C backend)

Vectorised over `x`; `mean` and `sd` are length-1.

## Usage

``` r
core_normal_pdf(x, mean = 0, sd = 1)
```

## Arguments

- x:

  Numeric vector of quantiles.

- mean:

  Distribution mean (length-1, default 0).

- sd:

  Distribution standard deviation (length-1, default 1, \> 0).

## Value

A numeric vector the length of `x`. Equivalent to
`stats::dnorm(x, mean, sd)`.

## Examples

``` r
core_normal_pdf(c(-1, 0, 1))
#> [1] 0.2419707 0.3989423 0.2419707
```
