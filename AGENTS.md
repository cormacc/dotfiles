# Dotfiles / NixOS Configuration

Nix flake managing NixOS, Home Manager, and nix-darwin configs across multiple
hosts (x86_64-linux + aarch64-darwin). Primary dev platform is Arch Linux + nix
+ home-manager. See [README.org](README.org) for end-user setup, shell
aliases, provisioning, and required submodule bootstraps.

## Build conventions

- `--impure` is required on every build: `home-core.nix` reads `NAME`,
  `EMAIL`, `EMAIL_OSS`, `USER`, `HOME`, `GITLAB` from the environment at
  apply time. `EMAIL` is the default git identity; `EMAIL_OSS` overrides
  it inside `~/dev/` via an `includeIf` and falls back to `$EMAIL` when
  unset.
- `allowUnfree = true` globally.
- `home.nix` is the full-Linux-workstation entry point — read it to see which
  modules a workstation pulls in. NixOS host modules live in
  `hosts/<hostname>/`; the shared profile `nixos-workstation.nix` imports
  `nixos-base.nix`, with optional mixins (`nixos-nvidia*.nix`,
  `nixos-gaming.nix`).
- The homelab infrastructure hosts (including `nas`) live in the private
  repository `cormacc/homelab`, which imports this flake's
  `nixosModules.base` and `nixosModules.boot-default`. A change to
  `nixos-base.nix` or `nixos-boot-default.nix` therefore also affects those
  hosts. Keep credentials, private addresses and inventory out of this public
  repository.

## Nix-specific gotchas

- **Linux and Darwin both track `nixos-unstable`, through separate inputs.**
  Darwin uses `nixpkgs-darwin`, and `nix-darwin` and `home-manager-darwin`
  follow it. The separate input lets you pin Darwin when a macOS regression
  occurs, without a change to the Linux package set. The earlier
  `release-25.11` pin (for
  [nixpkgs#507531](https://github.com/NixOS/nixpkgs/issues/507531)) was
  removed at `e7a2fe2`.
- **`strix` host (Framework Desktop / Ryzen AI Max+ 395)** pulls in
  `inputs.nix-amd-ai.nixosModules.default` for XRT/XDNA/Lemonade/ROCm/
  Vulkan. **Do not** add `nix-amd-ai.inputs.nixpkgs.follows` — closure
  hashes must match nix-amd-ai's Cachix.

## Local packages (`pkgs/`)

`pkgs/overlay.nix` auto-exposes each `pkgs/<name>/default.nix` as `pkgs.<name>`
and flake output `packages.x86_64-linux.<name>` (`nix build .#<name> --impure`) —
no flake edits to add one. See [pkgs/README.md](pkgs/README.md) for the
auto-discovery mechanism and how to add a package.

- **`pkgs/` holds no packages right now** — only `overlay.nix` and `README.md`.

## `agents.nix` — the dotagents bridge

`agents/` is a git submodule pointing at
[`cormacc/dotagents`](https://github.com/cormacc/dotagents) — source of truth
for every reusable skill, pi extension, prompt template, the pi-side
`AGENTS.md`, and user-local `pi/settings.json`. `agents.nix` symlinks the
live submodule tree into:

- `~/.agents/skills` (including packaged Herdr personas at
  `skills/herdr-orch/subagents/`)
- `~/.agents/subagents` (the home override layer, from the submodule's own
  `subagents/`, which carries the claude/codex approval-relaxing override).
  Definition resolution order and `config.edn` merge semantics are the
  `herdr-orch` skill's contract rather than wiring, and are documented once
  in [agents/skills/herdr-orch/scripts/docs/contract.md#Model resolution](agents/skills/herdr-orch/scripts/docs/contract.md#model-resolution) and
  [agents/skills/herdr-orch/scripts/docs/contract.md#Harness `:extra-args`](agents/skills/herdr-orch/scripts/docs/contract.md#harness-extra-args)
- `~/.pi/agent/{AGENTS.md, prompts, extensions, skills, settings.json, mcp.json}`
- `~/.config/herdr/config.toml` → `agents/herdr/config.toml` (the file only; the directory also holds Herdr's sockets and session state)
- `~/.config/herdr-app/settings.json` → `agents/herdr-app/settings.json` (the file only; Herdr desktop app settings, including `option_as_alt`)
- `~/.local/bin/ot` → org-tasks CLI shim
- `~/.local/share/herdr-plugins/org-tasks` → `agents/herdr-plugin/org-tasks` (Herdr org-tasks plugin leaf; activation rejects a foreign occupant)

Out-of-store symlinks, so edits in `agents/` take effect immediately via
`/reload` — no Home Manager switch needed.

On activation, `agents.nix`:
1. Fails fast with an actionable error if the submodule is uninitialised.
2. Runs `npm install --omit=dev --ignore-scripts` for local-only pi extensions (`chromium`, `pi-clojure`, `dataspex`) when their `package.json` hash changes. It does not install root npm dependencies. Herdr subscription reporting uses the owned Babashka collector; root `npm ci --ignore-scripts` is an explicit development step.
3. Registers the submodule-local `pi-settings` git clean filter by running
   `agents/install-git-filter.sh` on every activation; the script exits early
   when the filter is current (the filter definition lives in `.git/config`,
   so it cannot be tracked). The filter strips pi's volatile runtime keys
   (`lastChangelogVersion`, `deviceId`) from `agents/pi/settings.json` at
   stage time; `defaultProvider` and `defaultModel` are tracked (pi saves them
   only on Ctrl+S in `/model`). `jq` is in `home.packages` because the filter
   is `required = true`.
   Failure warns instead of aborting activation. See
   [README.org#The pi-settings clean filter](README.org#the-pi-settings-clean-filter).
4. Runs `herdr plugin link` on the org-tasks plugin leaf when `herdr plugin list` does not show `cormacc.org-tasks`. Failure warns instead of aborting activation. The tracked `agents/herdr/config.toml` binds its actions to keys.
