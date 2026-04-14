# General

- CRITICAL: Always verify symbols, function names, config options, module
  paths, variable names, CLI flags, and API fields against actual source code or
  documentation before using them.

- When I ask a question, don't start coding, don't write files, just answer the question.
  You can use tools and write scripts, but only if you need additional information to answer.


# Running commands

- CRITICAL: DON'T prefix the command with `cd`, NEVER change directory when running
  commands in the current directory, the current directory is ALWAYS correct
  and safe to run commands in. Use relative paths within the current directory when
  the command needs to run in a different directory.

- Use ripgrep (`rg`) instead of `grep`. It's faster, respects gitignore and
  allows regular expressions.

- CRITICAL: Never run `find` command from bash, use the builtin Find TOOL instead.
  It's faster, safer and better.

- CRITICAL: NEVER run find on big directories like `/` or `/nix` or `~`!
  It would never complete and might even crash the terminal you are running in.

- When running commands, NEVER prefix it with a sleep. If you expect something
  to take long, write a script which polls the result.


# Coding style

- Don't worry about linting, formatting or type checking at all, they will be run
  automatically and you will be notified every error. Don't run them manually.

- CRITICAL: Only use APIs, class names, variables or objects which you already read or
  made sure they exist, NEVER guess symbols which you have not seen or read before.

# Temporary files

Use `$PROJECT_ROOT/.agents/tmp/` for scripts, data or temporary files for experiments,
exploration, testing, answering questions, or other ad-hoc tasks, to write and run them.
Never delete anything from there.


# File operations and paths
- When you want to write the exact same file to a different place with the exact same content,
  DON'T USE the write tool, use the mv command instead. This makes the move faster and more precise.

- CRITICAL: When moving files controlled by git, use `git mv` rather than `mv` -- this is essential to preserve file history.

- IMPORTANT: When you want to write a new file, ALWAYS USE THE Write TOOL. Never use cat << 'EOF' or something strange.

- When you want to revert file changes you made, use git operations instead of editing the file again.
