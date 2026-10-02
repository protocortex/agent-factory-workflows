#!/usr/bin/env bash
# Builds the JSON body for the Worker's POST /commit from the working tree.
#
# Env: BRANCH, MESSAGE, BASE_SHA, OUT (payload file).
# Optional env: MAX_CHANGES (100), MAX_BASE64_CHARS (7000000).
#
# Exit codes:
#   0   payload written
#   10  nothing changed
#   11  too big or not representable, so the caller falls back to git push
#   12  touches .github/workflows/, which the Worker and the workflow token both refuse
set -euo pipefail

: "${BRANCH:?}" "${MESSAGE:?}" "${BASE_SHA:?}" "${OUT:?}"
max_changes="${MAX_CHANGES:-100}"
max_base64="${MAX_BASE64_CHARS:-7000000}"

git add -A
if git diff --cached --quiet "$BASE_SHA"; then
  exit 10
fi

entries="$(mktemp)"
count=0
total=0
while IFS= read -r -d '' status && IFS= read -r -d '' path; do
  case "$path" in
    .github/workflows/*)
      echo "::error::The agent changed $path. Workflow files cannot be committed by the agent."
      exit 12
      ;;
  esac
  count=$((count + 1))
  if [ "$count" -gt "$max_changes" ]; then
    echo "::notice::More than $max_changes changed files, using git push."
    exit 11
  fi
  case "$status" in
    D)
      jq -cn --arg path "$path" '{path: $path, delete: true}' >> "$entries"
      ;;
    A | M | T)
      mode=$(git ls-files -s -- "$path" | cut -d' ' -f1)
      if [ "$mode" != "100644" ] && { [ "$status" = "A" ] || [ "$mode" = "120000" ] || [ "$mode" = "160000" ]; }; then
        echo "::notice::$path has mode $mode, which the Worker cannot write. Using git push."
        exit 11
      fi
      encoded=$(base64 < "$path" | tr -d '\n')
      total=$((total + ${#encoded}))
      if [ "$total" -gt "$max_base64" ]; then
        echo "::notice::Changes are too large for the Worker, using git push."
        exit 11
      fi
      jq -cn --arg path "$path" --arg content "$encoded" '{path: $path, content_base64: $content}' >> "$entries"
      ;;
    *)
      echo "::notice::Unsupported change type $status for $path. Using git push."
      exit 11
      ;;
  esac
done < <(git diff --cached --no-renames --name-status -z "$BASE_SHA")

jq -s --arg branch "$BRANCH" --arg message "$MESSAGE" '{branch: $branch, message: $message, changes: .}' "$entries" > "$OUT"
