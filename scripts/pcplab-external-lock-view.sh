#!/usr/bin/env bash

set -euo pipefail

if [[ $# -gt 1 ]]; then
  printf 'Usage: %s [Cargo.lock]\n' "$(basename "$0")" >&2
  exit 2
fi

if [[ $# -eq 1 ]]; then
  exec <"$1"
fi

# Remove source-less workspace package records while preserving every other
# byte represented as a line. Registry/git package blocks remain whole so a
# version, source, checksum, dependency-array, or future lockfile field change
# triggers the Rust dependency security scan.
awk '
  function flush(  i) {
    if (in_package && external) {
      emitted_external = 1
      for (i = 0; i < line_count; i++) {
        print block[i]
      }
    }
    delete block
    in_package = 0
    line_count = 0
    external = 0
  }

  /^\[\[package\]\]$/ {
    flush()
    saw_package = 1
    in_package = 1
    block[line_count++] = $0
    next
  }

  in_package && /^\[/ {
    flush()
  }

  in_package {
    if ($0 ~ /^source = /) {
      external = 1
    }
    block[line_count++] = $0
    next
  }

  { print }

  END {
    flush()
    if (saw_package && !emitted_external) {
      exit 3
    }
  }
'
