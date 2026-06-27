#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# check-morie-core-sync.sh -- verify the vendored src/morie_core.h matches
# morie's canonical libmorie/morie_core.hpp (the single source of truth for
# the numeric kernels this package's C core delegates to).
#
# Resolution of the canonical file:
#   1. $MORIE_REPO/libmorie/morie_core.hpp if MORIE_REPO is set, else
#   2. walk up from this script looking for a sibling morie/ checkout.
#
# If the canonical file is not reachable the check SKIPS (exit 0) so CI
# without a morie checkout is not blocked. Run it locally (all repos as
# siblings under one parent) or in a combined-checkout CI to gate drift.
#
# Resync after an upstream change:
#   cp "$canon" src/morie_core.h
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
vendored="$here/../src/morie_core.h"

if [ -n "${MORIE_REPO:-}" ]; then
    canon="$MORIE_REPO/libmorie/morie_core.hpp"
else
    canon=""
    d="$here"
    while [ "$d" != "/" ]; do
        if [ -f "$d/morie/libmorie/morie_core.hpp" ]; then
            canon="$d/morie/libmorie/morie_core.hpp"
            break
        fi
        d=$(dirname -- "$d")
    done
fi

if [ -z "$canon" ] || [ ! -f "$canon" ]; then
    echo "skip: canonical morie_core.hpp not found (set MORIE_REPO to a morie checkout)"
    exit 0
fi

if diff -u "$canon" "$vendored"; then
    echo "in sync: $vendored matches $canon"
    exit 0
else
    echo "DRIFT: vendored morie_core.h differs from canonical. Resync with:"
    echo "  cp \"$canon\" \"$vendored\""
    exit 1
fi
