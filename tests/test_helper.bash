#!/usr/bin/env bash
# Shared scaffolding for the bats suite.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

# Read a make variable from the repo at [dir] (default: this one) through the
# print-% target.
mk() {
    run make -C "${2:-$REPO_ROOT}" --no-print-directory "print-$1"
    output="${output#"$1"=}"
}
