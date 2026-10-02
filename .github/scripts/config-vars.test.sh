#!/usr/bin/env bash
# Checks that every stage workflow lets a repo variable override the stub's model, effort, timeout
# and extra allowed domains. A bare `inputs.*` in a step or job setting would ignore the variable.
set -euo pipefail
cd "$(dirname "$0")/../workflows"

FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

declare -A STAGE=(
  [agent-triage.yml]=TRIAGE
  [agent-implement.yml]=IMPLEMENT
  [agent-implement-pr.yml]=IMPLEMENT_PR
  [agent-review.yml]=REVIEW
  [agent-update-branch.yml]=UPDATE_BRANCH
)

for file in "${!STAGE[@]}"; do
  s=${STAGE[$file]}
  # Step settings sit at 10 spaces of indent. The chained review job in implement passes inputs
  # through at 6 spaces and resolves its own variables, so it is left alone.
  if grep -nE '^ {10}(model|effort|extra_allowed_domains): \$\{\{ inputs\.' "$file"; then
    fail "$file: a step setting reads an input directly, so a repo variable cannot override it"
  fi
  if grep -nE '^ {4}timeout-minutes: \$\{\{ inputs\.' "$file"; then
    fail "$file: timeout-minutes reads the input directly"
  fi
  grep -q "vars.AGENT_${s}_MODEL || vars.AGENT_MODEL || inputs.model" "$file" || fail "$file: missing the AGENT_${s}_MODEL override"
  grep -q "vars.AGENT_${s}_EFFORT || vars.AGENT_EFFORT || inputs.effort" "$file" || fail "$file: missing the AGENT_${s}_EFFORT override"
  grep -q 'vars.AGENT_EXTRA_ALLOWED_DOMAINS || inputs.extra_allowed_domains' "$file" || fail "$file: missing the AGENT_EXTRA_ALLOWED_DOMAINS override"
  grep -q 'fromJSON(vars.AGENT_TIMEOUT_MINUTES || inputs.timeout_minutes)' "$file" || fail "$file: missing the AGENT_TIMEOUT_MINUTES override"
done

if [ "$FAILED" -ne 0 ]; then exit 1; fi
echo "all config variable checks passed"
