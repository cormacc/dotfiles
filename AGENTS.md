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

The flake (`flake.nix`) defines two output types:

- **`nixosConfigurations`**: Full system configs per host (xps15, t470p, t580, t470-nas, nas)
- **`homeConfigurations`**: User environment configs (`default` = full workstation, `minimal` = server/WSL)
- **`nix-darwin/flake.nix`**: Separate flake for macOS (aarch64-darwin), imports `../home-darwin.nix`

### NixOS module layering

`nixos.nix` imports `nixos-core.nix` and adds workstation concerns (audio, display, sway, hyprland).
Host-specific configs live in `hosts/<hostname>/`. Optional mixins:
- `nixos-nvidia.nix` / `nixos-nvidia-legacy.nix` — GPU drivers
- `nixos-extra.nix` — additional system packages
- `nixos-llm.nix` — ollama/LLM setup
- `nixos-server.nix` — server-only config

### Home Manager module layering

```
home-core.nix  →  shell/shell.nix
      ↑
home-linux.nix  (adds: llm-linux.nix)
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
| `nix-darwin/` | Separate flake for macOS/darwin-rebuild (aarch64-darwin) |
| `agents/` | AI/coding agent config: pi extensions, prompts, skills |
| `microchip/` | Microchip embedded dev tooling (see microchip/README.org) |
| `legacy/` | Deprecated configs (ruby, matlab, cdrip) |

## Nix-Specific Notes

- Uses nixpkgs unstable channel (`nixos-unstable`)
- `allowUnfree = true` globally; `--impure` flag required on all builds (env var reads)
- Overlays applied: nixGL, nix-microchip, rust-overlay, NUR, llm-agents, claude-desktop
- The `rebuild` script in repo root is hardcoded for xps15 NixOS rebuild only
- `agents.nix` symlinks `agents/pi/` contents into `~/.pi/agent/` (settings, extensions, prompts, skills)
- `nix-darwin/` is a standalone flake — run `drs` alias or `darwin-rebuild switch --flake ./nix-darwin` from repo root
