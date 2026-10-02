#!/usr/bin/env bash
# Tests for next-version.sh. Each case builds a throwaway repo with a tag and conventional commits.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/next-version.sh"
FAILED=0

# new_repo <tag-or-empty>: makes a repo with one base commit, optionally tagged.
new_repo() {
  dir=$(mktemp -d)
  cd "$dir"
  git init -q
  git config user.email t@example.com
  git config user.name t
  git config commit.gpgsign false
  git config tag.gpgsign false
  git commit -q --allow-empty -m "chore: base"
  if [ -n "${1:-}" ]; then git tag "$1"; fi
}

# check <name> <expected output lines, newline separated>: runs the script and compares.
check() {
  name=$1
  expected=$2
  actual=$(bash "$SCRIPT")
  if [ "$actual" = "$expected" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    echo "  expected: $(echo "$expected" | tr '\n' ' ')"
    echo "  actual:   $(echo "$actual" | tr '\n' ' ')"
    FAILED=1
  fi
}

new_repo v1.2.3
git commit -q --allow-empty -m "fix(triage): handle empty body (#1)"
check "fix bumps patch" "release=true
bump=patch
previous=v1.2.3
version=1.2.4
major=1"

new_repo v1.2.3
git commit -q --allow-empty -m "fix: a bug"
git commit -q --allow-empty -m "feat(implement): new thing"
check "feat beats fix and bumps minor" "release=true
bump=minor
previous=v1.2.3
version=1.3.0
major=1"

new_repo v1.2.3
git commit -q --allow-empty -m "feat!: drop an input"
check "bang bumps major" "release=true
bump=major
previous=v1.2.3
version=2.0.0
major=2"

new_repo v1.2.3
git commit -q --allow-empty -m "refactor: tidy" -m "BREAKING CHANGE: inputs renamed"
check "BREAKING CHANGE footer bumps major" "release=true
bump=major
previous=v1.2.3
version=2.0.0
major=2"

new_repo v1.2.3
git commit -q --allow-empty -m "chore: bump"
git commit -q --allow-empty -m "docs: readme"
git commit -q --allow-empty -m "ci: lint"
git commit -q --allow-empty -m "test: more"
git commit -q --allow-empty -m "refactor: tidy"
check "non-releasing types make no release" "release=false
previous=v1.2.3"

new_repo v1.2.3
check "no commits since the tag makes no release" "release=false
previous=v1.2.3"

new_repo v1.2.3
git tag v1
git tag v1.10.0
git commit -q --allow-empty -m "fix: x"
check "floating tag is ignored and versions sort numerically" "release=true
bump=patch
previous=v1.10.0
version=1.10.1
major=1"

new_repo ""
git commit -q --allow-empty -m "feat: first feature"
check "no tag starts from v0.0.0" "release=true
bump=minor
previous=v0.0.0
version=0.1.0
major=0"

new_repo v1.2.3
git commit -q --allow-empty -m "feat(scope): a thing (#9)" -m "Squashed body mentioning breaking change in prose"
check "prose mention of breaking is not a major" "release=true
bump=minor
previous=v1.2.3
version=1.3.0
major=1"

exit "$FAILED"
