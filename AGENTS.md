# Dotfiles / NixOS Configuration

Nix flake managing NixOS, Home Manager, and nix-darwin configs across multiple
hosts (x86_64-linux + aarch64-darwin). Primary dev platform is Arch Linux + nix
+ home-manager; NixOS on some machines; nix-darwin on macOS.

## Key Commands

```shell
# Aliases (defined in home-core.nix, available after first apply):
hms   # home-manager switch --flake .#default --impure
nos   # nixos-rebuild switch (auto-detects hostname, sudo)
drs   # darwin-rebuild switch (macOS, sudo -E)

# Cold-start equivalents (before aliases exist):
home-manager switch --flake './dotfiles#default' --impure -b backup   # full workstation
home-manager switch --flake './dotfiles#minimal' --impure -b backup   # server/WSL
sudo nixos-rebuild switch --flake .#<hostname> --impure
```

`--impure` is required everywhere because `home-core.nix` reads `NAME`,
`EMAIL`, `USER`, `HOME`, `GITLAB` from the environment at apply time.

## Architecture

`flake.nix` defines:

- **`nixosConfigurations`**: `xps15`, `strix`, `t470p`, `t580`, `t470-nas`, `nas`
- **`homeConfigurations`**: `default` (full workstation → `home.nix`) and `minimal` (server/WSL → `home-linux.nix`)
- **`darwinConfigurations."Cormacs-MacBook-Air"`** → `home-darwin.nix`

`home.nix` is the entry point — read it to see which modules a full Linux
workstation pulls in. NixOS host modules live in `hosts/<hostname>/`; the
shared workstation/server profiles are `nixos-workstation.nix` and
`nixos-server.nix` (both import `nixos-base.nix`), with optional mixins
(`nixos-nvidia*.nix`, `nixos-gaming.nix`, `nixos-llm.nix`).

## Nix-Specific Notes

- nixpkgs tracks **unstable** for Linux. Darwin is pinned to a specific
  bisect-verified commit on `release-25.11` (see flake comment) to dodge
  [nixpkgs#507531](https://github.com/NixOS/nixpkgs/issues/507531); bump
  together with the `nix-darwin` + `home-manager-darwin` pins.
- `allowUnfree = true` globally; `--impure` always.
- **Overlays — Linux** (`pkgs`): nix-microchip, rust-overlay, NUR, llm-agents,
  claude-desktop. **Darwin**: llm-agents, claude-desktop, + a tiny babashka
  overlay sourcing unstable (drop once darwin pin advances past bb 1.12.211).
- The `strix` host (Framework Desktop / AMD Ryzen AI Max+ 395) additionally
  pulls in `inputs.nix-amd-ai.nixosModules.default` for XRT/XDNA/Lemonade/
  ROCm/Vulkan. **Do not** add `nix-amd-ai.inputs.nixpkgs.follows` — closure
  hashes must match nix-amd-ai's Cachix.
- `darwin-rebuild switch --flake '/Users/cormacc/dotfiles#Cormacs-MacBook-Air' --impure`
  (or just `drs`).

## `agents.nix` — the dotagents bridge

`agents/` is a git submodule pointing at
[`cormacc/dotagents`](https://github.com/cormacc/dotagents). It is the source
of truth for every reusable skill, pi extension, prompt template, the pi-side
`AGENTS.md`, and user-local `pi/settings.json`.

`agents.nix` symlinks the live submodule tree into:

- `~/.agents/skills` (generic Agent Skills spec)
- `~/.pi/agent/{AGENTS.md, prompts, extensions, skills, settings.json}`
- `~/.config/mcp/mcp.json`
- `~/.local/bin/ot` → org-tasks CLI shim (also added to `home.sessionPath`)

Because these are out-of-store symlinks, edits in `agents/` take effect
immediately via `/reload`; no Home Manager switch needed.

On activation, `agents.nix`:
1. Fails fast with an actionable error if the submodule is uninitialised.
2. Runs `npm install --omit=dev` for the local-only pi extensions
   (`chromium`, `pi-clojure`, `dataspex`) when their `package.json` hash
   changes.

## Per-clone bootstrap

1. **Initialise the dotagents submodule** — `home-manager switch` refuses
   without it:

   ```shell
   git clone --recurse-submodules <dotfiles-url>
   # or, post-clone:
   git -C ~/dotfiles submodule update --init --recursive
   ```

2. **Register the pi-settings clean filter** so volatile fields in
   `agents/pi/settings.json` aren't restaged on every `/model` swap. Run from
   inside the submodule (filter binds to its git config):

   ```shell
   ~/dotfiles/agents/install-git-filter.sh
   ```

   Idempotent; needs `jq`. See README.org § *The pi-settings clean filter*.
