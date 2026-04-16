# General

- CRITICAL: Always verify symbols, function names, config options, module
  paths, variable names, CLI flags, and API fields against actual source code or
  documentation before use.

- When asked a question, just answer the question -- don't start coding.
  Use tools and write scripts only to obtain additional required information.


# Running commands

- Use ripgrep (`rg`) instead of `grep`. It's faster, respects gitignore and
  allows regular expressions.

- CRITICAL: Never run `find` command from bash, use the builtin Find TOOL instead.
  It's faster, safer and better.


# Temporary files

Use `$PROJECT_ROOT/.agents/tmp/` for scripts, data or temporary files for experiments,
exploration, testing, answering questions, or other ad-hoc tasks, to write and run them.


# File operations and paths
- CRITICAL: When moving files controlled by git, use `git mv` rather than `mv` -- this is essential to preserve file history.

- IMPORTANT: When you want to write a new file, ALWAYS USE THE Write TOOL. Never use cat << 'EOF' or something strange.

- When you want to revert file changes you made, use git operations instead of editing the file again.
