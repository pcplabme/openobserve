#!/usr/bin/env bash

set -euo pipefail

printf 'canary-intentional-failure: expected failure for Issue #3 CI evidence\n' >&2
exit 42
