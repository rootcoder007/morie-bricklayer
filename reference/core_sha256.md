# SHA-256 hex digest (C backend)

Hashes character or raw input with the self-contained SHA-256 in the
`rmoriebricklayer` core. For a character vector each element is hashed
as its UTF-8/native bytes; for a raw vector the raw bytes are hashed.
This is the same routine sibling packages use for provenance via
`LinkingTo: rmoriebricklayer`.

## Usage

``` r
core_sha256(x)
```

## Arguments

- x:

  A character vector or a raw vector.

## Value

A character vector of 64-character lowercase hex digests (one per
element for character input; length-1 for raw input).

## Examples

``` r
core_sha256("abc")
#> [1] "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
# ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
```
