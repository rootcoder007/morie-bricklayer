# Write Text as UTF-8, Falling Back to ASCII on an Encoding Error

Writes `text` to `path` as UTF-8. If the write raises an encoding error
(for example a destination or locale that cannot represent the
characters), it retries with an ASCII transliteration produced by
[`to_ascii()`](https://rootcoder007.github.io/rmorie-bricklayer/reference/to_ascii.md)
so bundle generation never fails on a non-ASCII name.

## Usage

``` r
write_text_fallback(text, path)
```

## Arguments

- text:

  A character vector of lines to write.

- path:

  Destination file path.

## Value

Invisibly, `path`.
