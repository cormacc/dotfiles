{
  lib,
  rustPlatform,
  fetchFromGitHub,
  cmake,
  mold,
}:

rustPlatform.buildRustPackage rec {
  pname = "dirge";
  version = "0.7.5";

  src = fetchFromGitHub {
    owner = "dirge-code";
    repo = "dirge";
    rev = "v${version}";
    hash = "sha256-qRaqcyh7OTX8xGi4YAjR1axTPcjG45m6bv1jIluUk+E=";
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

  meta = {
    description = "Minimal, fast pure-Rust coding agent with persistent memory";
    homepage = "https://github.com/dirge-code/dirge";
    license = lib.licenses.gpl3Only;
    mainProgram = "dirge";
    platforms = [ "x86_64-linux" "aarch64-darwin" ];
  };
}
