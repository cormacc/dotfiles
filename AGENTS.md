# Dotfiles / NixOS Configuration

Nix flake managing NixOS system configurations, Home Manager user environments,
and nix-darwin system configs across multiple hosts. Targets x86_64-linux and
aarch64-darwin. Primary dev platform is Arch Linux + nix + home-manager, with
NixOS used on some machines and nix-darwin on macOS.

## Key Commands

```shell
# NixOS rebuild for current host (requires sudo)
sudo nixos-rebuild switch --flake .#<hostname> --impure

# Home Manager switch (two configurations available)
home-manager switch --flake './dotfiles#default' --impure -b backup   # full workstation
home-manager switch --flake './dotfiles#minimal' --impure -b backup   # server/WSL

# Update flake inputs
nix flake update

# Shell aliases defined after first apply:
#   hms  - home-manager switch (default config)
#   nos  - nixos-rebuild switch (auto-detects hostname)
#   drs  - darwin-rebuild switch (macOS, requires sudo)

# Validate flake
nix flake check --impure
```

## Architecture

The flake (`flake.nix`) defines three output types:

- **`nixosConfigurations`**: Full system configs per host (xps15, t470p, t580, t470-nas, nas)
- **`homeConfigurations`**: User environment configs (`default` = full workstation, `minimal` = server/WSL)
- **`darwinConfigurations`**: macOS system configs via nix-darwin (`Cormacs-MacBook-Air`)

### NixOS module layering

`nixos-workstation.nix` imports `nixos-base.nix` and adds workstation concerns (audio, display, sway, hyprland).
Host-specific configs live in `hosts/<hostname>/`. Optional mixins:
- `nixos-nvidia.nix` / `nixos-nvidia-legacy.nix` — GPU drivers
- `nixos-gaming.nix` — Steam and gaming packages
- `nixos-llm.nix` — ollama/LLM setup
- `nixos-server.nix` — server-only config

### Home Manager module layering

```
home-core.nix  →  shell/shell.nix
      ↑
home-linux.nix
      ↑
home.nix (full Linux workstation, adds:)
      ├── editors/editors.nix    (emacs configs: corgi, doom, spacemacs)
      ├── dev/dev.nix            (dev tooling, clojure)
      ├── dev/dev-linux.nix
      ├── desktop/{web,audio,office}.nix
      ├── wayland/wayland.nix    (foot, rofi, fontconfig)
      ├── wayland/sway/sway.nix
      ├── wayland/hypr/hypr.nix
      ├── nmd/nmd.nix            (OneDrive/work tooling)
      └── agents.nix             (pi + claude-code)

home-darwin.nix  →  home-core.nix  (macOS, adds: editors, dev, agents)
```

`home-core.nix` owns: shell config, direnv, git, ssh, vim, fonts, XDG, and defines
the `hms`/`nos`/`drs` shell aliases.

### Environment variables consumed at initial apply

`NAME`, `EMAIL`, `USER`, `HOME` — identity and paths.
`GITLAB` — self-hosted gitlab TLD for SSH config.
`OPENAI_API_KEY`, `ANTHROPIC_API_KEY` — persisted to shell env after first apply.

## Key Directories

| Path | Purpose |
|------|---------|
| `hosts/` | Per-host hardware-configuration.nix and NixOS overrides |
| `shell/` | Shell config (fish, zsh, bash), direnv, babashka scripts |
| `editors/` | Editor configs (emacs: corgi/doom/spacemacs) |
| `dev/` | Development tooling (clojure, linux-specific dev) |
| `desktop/` | Desktop app modules (web, audio, office, entertainment) |
| `wayland/` | Wayland compositor configs (sway, hyprland, foot, rofi) |
| `nmd/` | Work-specific tooling (OneDrive etc.) |
| `darwin-configuration.nix` | macOS system config (nix-darwin) |
| `agents-src/` | Git submodule pointing at [`cormacc/dotagents`](https://github.com/cormacc/dotagents) — every reusable skill, pi extension, prompt template, the pi-side `AGENTS.md`, and the `agent-org-memory` pi package. Edited in place; `agents.nix` symlinks the working tree into `~/.agents/skills` and `~/.pi/agent/{extensions,skills,prompts,AGENTS.md}`. |
| `agents-config/pi/settings.json` | User-local pi configuration (default provider/model, package list, secrets toggles). Stays in dotfiles, *outside* the dotagents submodule. Symlinked to `~/.pi/agent/settings.json`. |
| `microchip/` | Microchip embedded dev tooling (see microchip/README.org) |
| `legacy/` | Deprecated configs (ruby, matlab, cdrip) |

## Nix-Specific Notes

- Uses nixpkgs unstable channel (`nixos-unstable`)
- `allowUnfree = true` globally; `--impure` flag required on all builds (env var reads)
- Overlays applied: nix-microchip, rust-overlay, NUR, llm-agents, claude-desktop
- The `rebuild` script in repo root is hardcoded for xps15 NixOS rebuild only
- `agents.nix` is a Home Manager module that symlinks the dotagents submodule working tree (`agents-src/`) into `~/.agents/skills` and `~/.pi/agent/{AGENTS.md,prompts,extensions,skills}`, plus `agents-config/pi/settings.json` into `~/.pi/agent/settings.json`. Edits in `agents-src/` reload in place via `/reload` without a Home Manager switch. The module fails fast with an actionable error if the submodule is uninitialised.
- Darwin config lives in the root flake — run `drs` alias or `darwin-rebuild switch --flake '/Users/cormacc/dotfiles#Cormacs-MacBook-Air' --impure`
