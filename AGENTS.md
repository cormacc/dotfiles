# Dotfiles / NixOS Configuration

Nix flake managing NixOS, Home Manager, and nix-darwin configs across multiple
hosts (x86_64-linux + aarch64-darwin). Primary dev platform is Arch Linux + nix
+ home-manager. See [README.org](README.org) for end-user setup, shell
aliases, provisioning, and the dotagents submodule bootstrap.

## Build conventions

- `--impure` is required on every build: `home-core.nix` reads `NAME`,
  `EMAIL`, `EMAIL_OSS`, `USER`, `HOME`, `GITLAB` from the environment at
  apply time. `EMAIL` is the default git identity; `EMAIL_OSS` overrides
  it inside `~/dev/` via an `includeIf` and falls back to `$EMAIL` when
  unset.
- `allowUnfree = true` globally.
- `home.nix` is the full-Linux-workstation entry point — read it to see which
  modules a workstation pulls in. NixOS host modules live in
  `hosts/<hostname>/`; shared profiles `nixos-workstation.nix` and
  `nixos-server.nix` both import `nixos-base.nix`, with optional mixins
  (`nixos-nvidia*.nix`, `nixos-gaming.nix`, `nixos-llm.nix`).

## Nix-specific gotchas

- **Linux tracks nixpkgs unstable; Darwin is pinned** to a bisect-verified
  commit on `release-25.11` (see flake comment) to dodge
  [nixpkgs#507531](https://github.com/NixOS/nixpkgs/issues/507531). Bump
  together with the `nix-darwin` + `home-manager-darwin` pins.
- **Overlays differ by platform.** Linux (`pkgs`): nix-microchip,
  rust-overlay, NUR, llm-agents, claude-desktop. Darwin: llm-agents,
  claude-desktop, + a tiny babashka overlay sourcing unstable (drop once
  the darwin pin advances past bb 1.12.211).
- **`strix` host (Framework Desktop / Ryzen AI Max+ 395)** pulls in
  `inputs.nix-amd-ai.nixosModules.default` for XRT/XDNA/Lemonade/ROCm/
  Vulkan. **Do not** add `nix-amd-ai.inputs.nixpkgs.follows` — closure
  hashes must match nix-amd-ai's Cachix.

## Local packages (`pkgs/`)

`pkgs/overlay.nix` auto-exposes every `pkgs/<name>/default.nix` as `pkgs.<name>`
**and** as a flake output `packages.x86_64-linux.<name>` (so `nix build .#<name>
--impure` works) — drop a new dir in, no flake edits needed.

- **limux** (terminal multiplexer, embeds Ghostty's OpenGL renderer):
  - `pkgs.limux` is the **prebuilt** release tarball — the default, what
    `dev/dev-linux.nix` installs, cheap to bump (1 hash). `pkgs.limux-src`
    is an opt-in from-source Rust+Zig build (`.#limux-src`, depends on
    `pkgs.limux-ghostty`); kept only for provenance, ~4 hashes per bump.
  - Both bake `--set-default GDK_BACKEND x11` plus `libglvnd` +
    `addDriverRunpath.driverLink` on `LD_LIBRARY_PATH`. On NVIDIA + Wayland
    (this host: Sway, RTX 4070) the embedded Ghostty GLArea renders but
    **takes no keyboard input** on the native-Wayland EGL path; XWayland/GLX
    fixes it. Building from a coherent nixpkgs closure did **not** fix it —
    it's a genuine NVIDIA/GTK4-embedded-GLArea/Wayland bug, not a Nix
    library-mismatch seam. Don't retry the "build it coherently and it'll
    work" theory. See `design/log/2026-06-16-build-limux-from-source-*.org`.

- **Verifying GUI fixes:** a window that *launches* and reports a *realized*
  surface is not a working app. Control-socket / IPC text injection (e.g.
  `limux send`) and health-probe state (`surface-health`) bypass the
  compositor and will report success even when real input is dead. Verify
  GUI render+input via the **compositor** (actual keystrokes, a screenshot
  you inspect) — not via the app's own control plane.

## `agents.nix` — the dotagents bridge

`agents/` is a git submodule pointing at
[`cormacc/dotagents`](https://github.com/cormacc/dotagents) — source of truth
for every reusable skill, pi extension, prompt template, the pi-side
`AGENTS.md`, and user-local `pi/settings.json`. `agents.nix` symlinks the
live submodule tree into:

- `~/.agents/skills`
- `~/.pi/agent/{AGENTS.md, prompts, extensions, skills, agents, settings.json}`
- `~/.config/mcp/mcp.json`
- `~/.local/bin/ot` → org-tasks CLI shim

The `agents/` slot under `~/.pi/agent/` overrides `pi-interactive-subagents`'
bundled subagent definitions.

Out-of-store symlinks, so edits in `agents/` take effect immediately via
`/reload` — no Home Manager switch needed.

On activation, `agents.nix`:
1. Fails fast with an actionable error if the submodule is uninitialised.
2. Runs `npm install --omit=dev` for local-only pi extensions
   (`chromium`, `pi-clojure`, `dataspex`) when their `package.json` hash
   changes.
