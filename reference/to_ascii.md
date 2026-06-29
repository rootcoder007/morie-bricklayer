# Transliterate Text to Plain ASCII

Converts a character vector to plain 7-bit ASCII, transliterating
accented or non-Latin characters to their nearest ASCII equivalent (for
example, an accented capital A becomes a plain "A"). Falls back to
dropping any character that has no transliteration. This is the
deterministic "fallback" used by
[`ascii_fallback()`](https://rootcoder007.github.io/rmorie-bricklayer/reference/ascii_fallback.md).

## Usage

``` r
to_ascii(x)
```

## Arguments

- x:

  A character vector.

## Value

A character vector containing only ASCII characters.

## Examples

``` r
to_ascii("Prof. \u00c1ngela Zorro Medina")  # "Prof. Angela Zorro Medina"
#> [1] "Prof. Angela Zorro Medina"
```
