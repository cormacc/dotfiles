# review skill

Harness-agnostic code-review skill wrapper for `pi`, `claude`, `codex`, or a custom runner.

## Files

- `SKILL.md` — skill instructions used by the agent
- `scripts/review-subagent` — runner wrapper script

## Usage

From the skill directory:

```bash
./scripts/review-subagent "$@"
```

`$@` should describe review scope (files, directories, diff/range, etc).

## Runner selection

The wrapper selects a sub-agent runner in this order:

1. `REVIEW_AGENT_CMD` (if set)
2. `pi`
3. `claude`
4. `codex`

If none are available, it exits with an error.

## Environment variables

- `REVIEW_AGENT_CMD`
  - Optional explicit command to run (can include args), e.g.:
    - `REVIEW_AGENT_CMD="pi --print"`
    - `REVIEW_AGENT_CMD="claude -p"`
    - `REVIEW_AGENT_CMD="codex exec"`

- `REVIEW_MODEL`
  - Optional model name passed to runners that support model flags.

- `REVIEW_PROVIDER`
  - Optional provider value (currently applied for `pi`; ignored by others with a warning).

## Examples

```bash
# Auto-detect runner, review staged changes text
./scripts/review-subagent "git diff --staged"

# Force Claude with specific model
REVIEW_AGENT_CMD="claude -p" REVIEW_MODEL="sonnet" \
  ./scripts/review-subagent "src/"

# Force pi with provider/model
REVIEW_AGENT_CMD="pi --print" REVIEW_PROVIDER="openrouter" REVIEW_MODEL="gpt-4.1" \
  ./scripts/review-subagent "foo.clj:1-200"
```

## Expected output

- Concise review findings with:
  - severity
  - `file:line` location
  - rationale
  - fix suggestion
- Or exactly: `No issues found.`
