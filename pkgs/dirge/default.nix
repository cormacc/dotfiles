{
  lib,
  rustPlatform,
  fetchFromGitHub,
  cmake,
  mold,
  nix-update-script,
  # Build an arbitrary source instead of the pinned release. The `dirge-dev`
  # package sets these to track the latest commit on `main`. When left at
  # their defaults this is the ordinary release build.
  srcOverride ? null,
  versionOverride ? null,
}:

let
  # nix-update bumps `version` + the src `hash` below on `nix-update --flake dirge`.
  version = "0.7.7";

  releaseSrc = fetchFromGitHub {
    owner = "dirge-code";
    repo = "dirge";
    rev = "v${version}";
    hash = "sha256-H82uiruToka8Itu99d1Pc1srcLYgO0TNLA52gIcWWbA=";
  };

  src = if srcOverride != null then srcOverride else releaseSrc;
in
rustPlatform.buildRustPackage {
  pname = "dirge";
  version = if versionOverride != null then versionOverride else version;

  inherit src;

  cargoLock.lockFile = "${src}/Cargo.lock";

  nativeBuildInputs = [
    cmake
    # Upstream passes -fuse-ld=mold in release builds.
    mold
    # evil-janet generates bindings during the build.
    rustPlatform.bindgenHook
  ];

  # Tests reach network/LLM providers.
  doCheck = false;

  # Release builds carry a nix-update updateScript; the main-tracking
  # `dirge-dev` build (srcOverride set) needs no version bumping.
  passthru = lib.optionalAttrs (srcOverride == null) {
    # Bump to the latest upstream release with `nix-update --flake dirge`
    # (rewrites version + src hash in place; cargoLock follows the new src).
    updateScript = nix-update-script { };
  };

  meta = {
    description = "Minimal, fast pure-Rust coding agent with persistent memory";
    homepage = "https://github.com/dirge-code/dirge";
    license = lib.licenses.gpl3Only;
    mainProgram = "dirge";
    platforms = [ "x86_64-linux" "aarch64-darwin" ];
  };
}
