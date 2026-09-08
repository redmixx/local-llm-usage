#!/bin/zsh
# Runs the parser unit tests (Swift Testing via SPM).
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

/usr/bin/swift test
