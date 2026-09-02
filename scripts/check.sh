#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

plutil -lint Resources/*.plist Resources/*.entitlements
zsh -n build.sh scripts/check.sh

pl_keys="$(sed -n '/    "pl": \[/,/^    \],/p' Sources/App/AppMain.swift | tail -n +2 | rg -o '"[A-Za-z0-9]+"[[:space:]]*:' | tr -d ' ":' | sort -u)"
en_keys="$(sed -n '/    "en": \[/,/^    \]/p' Sources/App/AppMain.swift | tail -n +2 | rg -o '"[A-Za-z0-9]+"[[:space:]]*:' | tr -d ' ":' | sort -u)"
if [[ "$pl_keys" != "$en_keys" ]]; then
  echo "Polish and English translation keys differ" >&2
  diff <(print -r -- "$pl_keys") <(print -r -- "$en_keys") || true
  exit 1
fi

if rg -n --glob '!build/**' '(10\.55\.|192\.168\.|/Users/|/home/)' Sources Resources README.md PRIVACY.md SECURITY.md CONTRIBUTING.md; then
  echo "Environment-specific path or address detected" >&2
  exit 1
fi

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -s bash build.sh scripts/check.sh
else
  echo "shellcheck: not installed (skipped)"
fi

if rg -n --hidden \
  --glob '!build/**' \
  --glob '!.git/**' \
  '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]{20,}|api[_-]?key[[:space:]]*[:=][[:space:]]*[^[:space:]]+|password[[:space:]]*[:=][[:space:]]*[^[:space:]]+)' .; then
  echo "Potential secret detected" >&2
  exit 1
fi

./build.sh
codesign --verify --deep --strict "build/Local LLM Usage.app"

echo "All checks passed."
