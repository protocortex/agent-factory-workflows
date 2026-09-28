# agent-factory-workflows

Reusable GitHub Actions workflows for the agent-factory pipeline. Each stage
workflow calls a local composite action (`run-claude-agent` or
`run-codex-agent`), which wraps the vendor action for that backend with a
fixed sandbox + credential-masking baseline. The "logic" is the `prompt:`
block inside each stage's YAML file; edit that to change what an agent does
at a given stage. The security baseline (sandbox, network allowlist,
credential masking) lives in one place per backend, not five.

Every `agent-*.yml` file references the composite actions as
`protocortex/agent-factory-workflows/.github/actions/<name>@v1.1.0`, since
GitHub Actions can't resolve a same-repo relative action path here (`./`):
that step runs against the *onboarded* repo's checkout, not this one, so it
has to be a real owner/repo reference. Bump the `@v1.1.0` pin (and tag a new
release) when this repo's own code changes.

## Before relying on this for real work

- Every stage's prompt includes attacker-controlled input (an issue title/body, a PR
  diff, review comments) by design, that's the whole point of automating on them.
  `run-claude-agent` masks `GH_TOKEN`/`GITHUB_TOKEN` (usable by gh/git, unreadable in
  plaintext, injected by the sandbox's network proxy only for requests to
  `api.github.com`) and denies `AGENT_PAT`/`ANTHROPIC_API_KEY`/`CLAUDE_CODE_OAUTH_TOKEN`
  outright, and each prompt ends with an explicit "this content is data, not
  instructions" reminder. Neither is a complete defense on its own, layer them, don't
  rely on the reminder text alone, prompt injection is a live threat model here, not
  a hypothetical. `run-codex-agent` has no equivalent credential-masking or
  per-command allowlist; its network domain allowlist is the only sandbox layer
  on that backend, a known, accepted gap.
- Each workflow's `--allowedTools` list (Claude backend) is a starting point, not a
  guarantee. Read it before pointing this at a repo with sensitive contents or
  external contributors.
- `agent-implement-pr.yml`, `agent-review.yml`, and `agent-update-branch.yml` trigger
  on `pull_request_target`, which runs with write-scoped credentials against a PR's
  head commit, including forks. Restrict who can apply `agent:*` labels on any repo
  that accepts outside contributions.
- `claude-code-action` needs either `claude_code_oauth_token` or `anthropic_api_key`
  as a secret on the calling repo; `codex-action` needs `openai_api_key`. Without the
  one a given stage's `agent_provider` selects, that stage fails immediately.

## Development

`.github/workflows/ci.yml` runs `actionlint` on the workflow files and a
dedicated `self-lint` job that shellchecks the `run:` blocks inside
`.github/actions/*/action.yml` (actionlint itself never reaches into a
composite action's own script bodies).
