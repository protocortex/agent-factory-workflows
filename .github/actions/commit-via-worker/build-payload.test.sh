#!/usr/bin/env bash
# Tests build-payload.sh against throwaway git repos.
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/build-payload.sh"
fail=0
check() { # name, result of the condition (0 = pass)
  if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}

expect_code() { # name, expected exit code, actual exit code
  local result=0
  [ "$3" -eq "$2" ] || result=1
  check "$1" "$result"
}

new_repo() {
  dir="$(mktemp -d)"
  cd "$dir"
  git init -q -b main
  git config user.email t@example.com
  git config user.name t
  printf 'one\n' > keep.txt
  printf 'gone\n' > remove.txt
  mkdir -p ".github/workflows"
  printf 'name: x\n' > .github/workflows/ci.yml
  git add -A
  git commit -qm base
  base=$(git rev-parse HEAD)
}

run() { BRANCH=agent/x MESSAGE="fix: x" BASE_SHA="$base" OUT="$dir/out.json" bash "$script" > /dev/null 2>&1; }

# 1. nothing changed
new_repo
code=0; run || code=$?
expect_code "exit 10 when nothing changed" 10 "$code"

# 2. modify, delete, add, and a path with a space
new_repo
printf 'two\n' > keep.txt
git rm -q remove.txt
printf 'new\n' > "with space.txt"
code=0; run || code=$?
expect_code "exit 0 for a normal change" 0 "$code"
check "branch and message are set" "$(jq -e '.branch == "agent/x" and .message == "fix: x"' "$dir/out.json" > /dev/null; echo $?)"
check "modified file carries base64 content" "$(jq -e --arg c "$(printf 'two\n' | base64 | tr -d '\n')" '.changes[] | select(.path == "keep.txt") | .content_base64 == $c' "$dir/out.json" > /dev/null; echo $?)"
check "deleted file is marked delete" "$(jq -e '.changes[] | select(.path == "remove.txt") | .delete == true' "$dir/out.json" > /dev/null; echo $?)"
check "path with a space survives" "$(jq -e '.changes[] | select(.path == "with space.txt") | has("content_base64")' "$dir/out.json" > /dev/null; echo $?)"
check "three changes" "$(jq -e '.changes | length == 3' "$dir/out.json" > /dev/null; echo $?)"

# 3. an untracked file in a new directory
new_repo
mkdir -p deep/dir
printf 'x\n' > deep/dir/file.txt
code=0; run || code=$?
check "untracked nested file is included" "$(jq -e '.changes[0].path == "deep/dir/file.txt"' "$dir/out.json" > /dev/null; echo $?)"

# 4. workflow files are refused
new_repo
printf 'on: push\n' > .github/workflows/evil.yml
code=0; run || code=$?
expect_code "exit 12 for a workflow file" 12 "$code"

# 5. too many changes
new_repo
printf 'a\n' > a.txt
printf 'b\n' > b.txt
printf 'c\n' > c.txt
code=0; MAX_CHANGES=2 run || code=$?
expect_code "exit 11 over the change limit" 11 "$code"

# 6. too large
new_repo
head -c 3000 /dev/zero | tr '\0' 'a' > big.txt
code=0; MAX_BASE64_CHARS=100 run || code=$?
expect_code "exit 11 over the size limit" 11 "$code"

# 7. a new executable file cannot be written by the Worker
new_repo
printf '#!/bin/sh\n' > run.sh
chmod +x run.sh
code=0; run || code=$?
expect_code "exit 11 for a new executable" 11 "$code"

exit "$fail"
