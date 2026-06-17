{
  lib,
  rustPlatform,
  fetchFromGitHub,
  cmake,
  mold,
  nix-update-script,
}:

rustPlatform.buildRustPackage rec {
  pname = "dirge";
  version = "0.7.6";

  src = fetchFromGitHub {
    owner = "dirge-code";
    repo = "dirge";
    rev = "v${version}";
    hash = "sha256-7gA7Gqhc44/ntqQi9demL7dI/e6/cfXAAacpnrKsEVk=";
  };

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

  # Bump to the latest upstream release with `nix-update --flake dirge`
  # (rewrites version + src hash in place; cargoLock follows the new src).
  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Minimal, fast pure-Rust coding agent with persistent memory";
    homepage = "https://github.com/dirge-code/dirge";
    license = lib.licenses.gpl3Only;
    mainProgram = "dirge";
    platforms = [ "x86_64-linux" "aarch64-darwin" ];
  };
}
