---
name: review
description: Run a code review sub-agent
---
Run the harness-agnostic wrapper script:

`./scripts/review-subagent "$@"`

Behavior requirements:
- Wrapper chooses a compatible runner via `REVIEW_AGENT_CMD` or auto-detects (`pi`, `claude`, `codex`).
- If user requested model/provider, pass via env vars before running wrapper:
  - `REVIEW_MODEL=<model>`
  - `REVIEW_PROVIDER=<provider>`
- Ask the sub-agent to review for:
  - Bugs and logic errors
  - Security issues
  - Error handling gaps
  - Severity and precise `file:line` locations

Do not do a full duplicate review yourself.
You may only sanity-check obviously suspicious findings.

Return:
- Concise summary
- Structured findings
- Or “No issues found.”
