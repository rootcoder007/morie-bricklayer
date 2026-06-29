# Use Text As-Is, Falling Back to ASCII When It Cannot Be Represented

Returns `x` unchanged when it is valid, well-formed text (so legitimate
UTF-8 such as an accented name is preserved), and only transliterates to
plain ASCII via
[`to_ascii()`](https://rootcoder007.github.io/rmorie-bricklayer/reference/to_ascii.md)
when the text is not valid UTF-8 (an encoding error) or when
`force = TRUE` (for ASCII-only destinations such as a package
`DESCRIPTION`). This lets author and supervisor names keep their accents
wherever UTF-8 is supported while degrading gracefully instead of
erroring where it is not.

## Usage

``` r
ascii_fallback(x, force = FALSE)
```

## Arguments

- x:

  A character vector.

- force:

  Logical; always transliterate to ASCII (default `FALSE`).

## Value

A character vector: `x` where it can be represented, ASCII otherwise.

## Examples

``` r
ascii_fallback("\u00c1ngela")            # accented name kept (UTF-8)
#> [1] "Ángela"
ascii_fallback("\u00c1ngela", force = TRUE) # "Angela"
#> [1] "Angela"
```
