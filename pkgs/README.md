# Local packages

Drop-in local Nix packages for this flake. `overlay.nix` auto-discovers every
`pkgs/<name>/default.nix` and wires it up — no edits to `overlay.nix` or
`flake.nix` are needed to add one.

> This directory is currently **empty** (only the overlay remains). The `dirge`
> packages that used to live here now come from the upstream flake
> (`github:cormacc/dirge`, applied via `dirge.overlays.default` in `flake.nix`).
> The overlay is retained for the next local package.

## How it works

`overlay.nix` reads this directory and, for each subdirectory containing a
`default.nix`, exposes it two ways against the fully-overlaid package set:

- **`pkgs.<name>`** — available to every Home Manager / NixOS / nix-darwin
  module (the overlay is in each config's `nixpkgs.overlays`).
- **`packages.x86_64-linux.<name>`** — a flake output, buildable directly with
  `nix build .#<name> --impure`.

Both are the same `callPackage`-wired derivation, so there's no duplication.

## Adding a package

1. **Create `pkgs/<name>/default.nix`.** Write it as a `callPackage` function:
   its arguments are filled automatically from the overlaid `pkgs` set (so list
   `lib`, `stdenv`, `fetchFromGitHub`, other packages, etc. as formal args).

   ```nix
   { lib, stdenv, fetchFromGitHub }:

   stdenv.mkDerivation (finalAttrs: {
     pname = "my-tool";
     version = "1.2.3";

     src = fetchFromGitHub {
       owner = "someone";
       repo = "my-tool";
       rev = "v${finalAttrs.version}";
       hash = lib.fakeHash; # replace with the hash from the first build error
     };

     meta = {
       description = "Short one-line description";
       homepage = "https://github.com/someone/my-tool";
       license = lib.licenses.mit;
       mainProgram = "my-tool";
       platforms = [ "x86_64-linux" "aarch64-darwin" ];
     };
   })
   ```

2. **`git add pkgs/<name>/`.** Flakes only see git-tracked files — an untracked
   `default.nix` is invisible to `nix build` and won't appear in `pkgs`.

3. **Build it** (every build in this repo needs `--impure`):

   ```nix
   nix build .#<name> --impure
   ```

   On the first run, replace any `lib.fakeHash` placeholders with the real
   hashes reported in the build error.

## Conventions

- **Always `--impure`** — `home-core.nix` reads identity from the environment at
  eval time, so it's required for every build/eval in this flake.
- **`meta` matters**: set `description`, `homepage`, `license`,
  `mainProgram`, and `platforms`. `mainProgram` lets `lib.getExe pkgs.<name>`
  resolve the binary.
- **Pin and hash everything** for reproducibility. To track a moving target
  (latest release / branch / a local worktree) you can use an impure
  `builtins.fetchGit`, but prefer a pinned source plus
  `passthru.updateScript = nix-update-script { }` so bumps are a single
  `nix-update --flake <name>`.
- **Builders**: `rustPlatform.buildRustPackage` (Rust, with
  `cargoLock.lockFile = "${src}/Cargo.lock"`), `buildGoModule` (Go),
  `stdenv.mkDerivation` (generic / prebuilt). Prebuilt Linux binaries usually
  need `autoPatchelfHook`.
